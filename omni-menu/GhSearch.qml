import QtQuick
import Quickshell.Io
import "Data.js" as Data

// gh CLI-backed repo search + README preview. Owns the auth probe, an
// identity probe (your login + your orgs), two parallel search procs
// (scoped to your namespace + broad), the readme fetch proc, and the
// preview state. Parent shell binds `query`/`active`/`selectedItem`
// and reads `items`, `running`, `ready`, and the preview properties.
Item {
    id: ghSearch

    required property string query
    required property bool active
    required property var selectedItem

    property bool ready: false
    property var items: []
    property string previewRepo: ""
    property string previewRepoUrl: ""
    property string previewReadme: ""
    readonly property bool running: ghScopedProc.running || ghBroadProc.running

    // Identity, learned once at startup from `gh api user` / `gh api user/orgs`.
    // Used to bias search results — your repos and your orgs' repos come
    // first, then everything else.
    property string userLogin: ""
    property var userOrgs: []
    readonly property string ownerFilter: ghSearch.userLogin
        ? [ghSearch.userLogin].concat(ghSearch.userOrgs).join(",")
        : ""

    // Raw search results keyed by which proc produced them. mergeItems
    // joins the two with the scope priority (you > your orgs > the world).
    property var scopedResults: []
    property var broadResults: []

    function clear() {
        ghSearch.items = [];
        ghSearch.scopedResults = [];
        ghSearch.broadResults = [];
        ghSearch.previewRepo = "";
        ghSearch.previewRepoUrl = "";
        ghSearch.previewReadme = "";
        ghDebounce.stop();
    }

    function toItem(r) {
        const lang = r.language ? "  ·  " + r.language : "";
        return {
            title: r.fullName,
            comment: r.description || "",
            keywords: "",
            category: "★ " + Data.formatStars(r.stargazersCount || 0) + lang,
            icon: "󰊤",
            path: r.url,
            exec: Data.openUrl(r.url),
            rawCategory: true
        };
    }

    // Within scoped, your own repos rank above your orgs'; broad fills in
    // after with duplicates filtered by URL.
    function mergeItems() {
        const seen = {};
        const out = [];
        const userPrefix = ghSearch.userLogin ? ghSearch.userLogin + "/" : "";
        const scoped = ghSearch.scopedResults;
        for (let i = 0; i < scoped.length; i++) {
            if (userPrefix && scoped[i].fullName.indexOf(userPrefix) === 0) {
                seen[scoped[i].url] = true;
                out.push(ghSearch.toItem(scoped[i]));
            }
        }
        for (let i = 0; i < scoped.length; i++) {
            if (!seen[scoped[i].url]) {
                seen[scoped[i].url] = true;
                out.push(ghSearch.toItem(scoped[i]));
            }
        }
        const broad = ghSearch.broadResults;
        for (let i = 0; i < broad.length; i++) {
            if (!seen[broad[i].url]) {
                seen[broad[i].url] = true;
                out.push(ghSearch.toItem(broad[i]));
            }
        }
        ghSearch.items = out;
        ghSearch.updatePreview();
    }

    function updatePreview() {
        if (!ghSearch.active) return;
        const it = ghSearch.selectedItem;
        const url = (it && it.path) || "";
        if (url === ghSearch.previewRepoUrl) return;
        ghSearch.previewRepoUrl = url;
        ghSearch.previewRepo = (it && it.title) || "";
        ghSearch.previewReadme = "";
        if (!url || !it.title) return;
        ghSearch.previewReadme = "Loading…";
        // gh api prints its 404 error body to stdout, so a naive pipe
        // would leak `{"message":"Not Found"...}` into the preview.
        // Capture first, only emit on exit success.
        readmeProc.command = ["sh", "-c",
            "out=$(gh api repos/\"$1\"/readme -H 'Accept: application/vnd.github.raw' 2>/dev/null) && printf '%s' \"$out\" | head -c 8192 || true",
            "sh", it.title];
        readmeProc.running = false;
        readmeProc.running = true;
    }

    onQueryChanged: { if (ghSearch.active) ghDebounce.restart(); }
    onSelectedItemChanged: { if (ghSearch.active) ghSearch.updatePreview(); }

    Component.onCompleted: ghAuthProc.running = true

    // Shell short-circuit returns "ok" only when gh exists AND has a
    // usable token — drives off exit codes, not stdout parsing, so it
    // survives gh localizing or rephrasing "Logged in".
    Process {
        id: ghAuthProc
        running: false
        command: ["sh", "-c", "command -v gh >/dev/null 2>&1 && gh auth status >/dev/null 2>&1 && echo ok || true"]
        stdout: StdioCollector {
            onStreamFinished: {
                ghSearch.ready = this.text.indexOf("ok") >= 0;
                if (ghSearch.ready) {
                    identityProc.running = false;
                    identityProc.running = true;
                }
            }
        }
    }

    // Fetches login + org list once after auth confirms. Failures leave
    // identity empty and the search falls back to broad-only.
    Process {
        id: identityProc
        running: false
        command: ["sh", "-c",
            "gh api user --jq .login 2>/dev/null; "
            + "gh api user/orgs --jq 'map(.login)|join(\",\")' 2>/dev/null"]
        stdout: StdioCollector {
            onStreamFinished: {
                const lines = this.text.split("\n");
                ghSearch.userLogin = (lines[0] || "").trim();
                const orgsLine = (lines[1] || "").trim();
                ghSearch.userOrgs = orgsLine
                    ? orgsLine.split(",").filter(s => s.length > 0)
                    : [];
            }
        }
    }

    // 350ms debounce — slower than fd's 120ms because each keystroke
    // costs an HTTP round-trip to the GitHub search API, and the
    // rate-limit budget is per-token, not per-process.
    Timer {
        id: ghDebounce
        interval: 350
        repeat: false
        onTriggered: {
            const q = ghSearch.query.trim();
            if (!ghSearch.active || q.length === 0) {
                ghSearch.scopedResults = [];
                ghSearch.broadResults = [];
                ghSearch.items = [];
                return;
            }
            // Scoped: only fires when identity probe filled the owner
            // filter. Empty -> just broad, no API call wasted.
            if (ghSearch.ownerFilter) {
                ghScopedProc.command = ["gh", "search", "repos", q,
                                        "--owner", ghSearch.ownerFilter,
                                        "--json", "fullName,description,url,stargazersCount,language",
                                        "--limit", "10"];
                ghScopedProc.running = false;
                ghScopedProc.running = true;
            } else {
                ghSearch.scopedResults = [];
            }
            ghBroadProc.command = ["gh", "search", "repos", q,
                                   "--json", "fullName,description,url,stargazersCount,language",
                                   "--limit", "20"];
            ghBroadProc.running = false;
            ghBroadProc.running = true;
        }
    }

    function parseResults(text) {
        try { return JSON.parse(text || "[]"); } catch (_) { return []; }
    }

    Process {
        id: ghScopedProc
        running: false
        command: ["gh"]
        stdout: StdioCollector {
            onStreamFinished: {
                ghSearch.scopedResults = ghSearch.parseResults(this.text);
                ghSearch.mergeItems();
            }
        }
    }

    Process {
        id: ghBroadProc
        running: false
        command: ["gh"]
        stdout: StdioCollector {
            onStreamFinished: {
                ghSearch.broadResults = ghSearch.parseResults(this.text);
                ghSearch.mergeItems();
            }
        }
    }

    Process {
        id: readmeProc
        running: false
        command: ["true"]
        stdout: StdioCollector {
            onStreamFinished: { ghSearch.previewReadme = this.text || "NO README"; }
        }
    }
}
