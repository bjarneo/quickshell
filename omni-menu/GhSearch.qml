import QtQuick
import Quickshell.Io
import "Data.js" as Data

// gh CLI-backed search drill. Two surfaces:
//
//   query empty -> your PRs (authored, review-requested, mentioned,
//                  assigned), fetched on mode entry, deduped by URL.
//   query set   -> repo search (scoped: you + your orgs first,
//                  broad: the world after), debounced.
//
// Identity (login + orgs) is probed once at startup so both surfaces
// know who you are. Failures leave the owner filter empty and the
// search falls back to broad-only.
Item {
    id: ghSearch

    required property string query
    required property bool active
    required property var selectedItem

    property bool ready: false
    property string previewRepo: ""
    property string previewRepoUrl: ""
    property string previewReadme: ""
    readonly property bool running: ghScopedProc.running
                                    || ghBroadProc.running
                                    || prAuthorProc.running
                                    || prReviewedProc.running
                                    || prMentionsProc.running
                                    || prAssigneeProc.running

    // Identity, learned once at startup.
    property string userLogin: ""
    property var userOrgs: []
    readonly property string ownerFilter: ghSearch.userLogin
        ? [ghSearch.userLogin].concat(ghSearch.userOrgs).join(",")
        : ""

    // Raw arrays per upstream. items is derived from these.
    property var scopedResults: []
    property var broadResults: []
    property var prAuthorResults: []
    property var prReviewedResults: []
    property var prMentionsResults: []
    property var prAssigneeResults: []

    // Empty query -> PRs; non-empty -> repos. The four PR arrays are
    // merged in priority order (author > review-requested > mentions >
    // assignee) and deduped by URL. Repos merge your own first, then
    // your orgs', then the broad results.
    readonly property var items: {
        if (!ghSearch.active) return [];
        if (ghSearch.query.trim().length === 0) return ghSearch.prItems;
        return ghSearch.repoItems;
    }

    readonly property var prItems: {
        const seen = {};
        const out = [];
        const sources = [
            ghSearch.prAuthorResults,
            ghSearch.prReviewedResults,
            ghSearch.prMentionsResults,
            ghSearch.prAssigneeResults
        ];
        for (let s = 0; s < sources.length; s++) {
            const list = sources[s];
            for (let i = 0; i < list.length; i++) {
                const pr = list[i];
                if (!seen[pr.url]) {
                    seen[pr.url] = true;
                    out.push(ghSearch.toPrItem(pr, s));
                }
            }
        }
        return out;
    }

    readonly property var repoItems: {
        const seen = {};
        const out = [];
        const userPrefix = ghSearch.userLogin ? ghSearch.userLogin + "/" : "";
        for (let i = 0; i < ghSearch.scopedResults.length; i++) {
            const r = ghSearch.scopedResults[i];
            if (userPrefix && r.fullName.indexOf(userPrefix) === 0) {
                seen[r.url] = true;
                out.push(ghSearch.toRepoItem(r));
            }
        }
        for (let i = 0; i < ghSearch.scopedResults.length; i++) {
            const r = ghSearch.scopedResults[i];
            if (!seen[r.url]) {
                seen[r.url] = true;
                out.push(ghSearch.toRepoItem(r));
            }
        }
        for (let i = 0; i < ghSearch.broadResults.length; i++) {
            const r = ghSearch.broadResults[i];
            if (!seen[r.url]) {
                seen[r.url] = true;
                out.push(ghSearch.toRepoItem(r));
            }
        }
        return out;
    }

    function clear() {
        ghSearch.scopedResults = [];
        ghSearch.broadResults = [];
        ghSearch.previewRepo = "";
        ghSearch.previewRepoUrl = "";
        ghSearch.previewReadme = "";
        ghDebounce.stop();
    }

    function toRepoItem(r) {
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

    // sourceIdx 0=author, 1=review-requested, 2=mentions, 3=assignee.
    // The tag shows up in the right column so you can tell at a glance
    // why a PR is in your list.
    readonly property var prTags: ["YOURS", "REVIEW", "MENTIONED", "ASSIGNED"]
    function toPrItem(pr, sourceIdx) {
        const repo = pr.repository ? pr.repository.nameWithOwner : "";
        return {
            title: pr.title,
            comment: repo + "#" + pr.number,
            keywords: "",
            category: repo + "#" + pr.number + "  ·  " + ghSearch.prTags[sourceIdx],
            icon: "󰓂",
            path: pr.url,
            exec: Data.openUrl(pr.url),
            rawCategory: true
        };
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
        // Capture first, only emit on exit success. Works for both repo
        // README endpoints and PR HEAD references.
        readmeProc.command = ["sh", "-c",
            "out=$(gh api repos/\"$1\"/readme -H 'Accept: application/vnd.github.raw' 2>/dev/null) && printf '%s' \"$out\" | head -c 8192 || true",
            "sh", it.title.indexOf("#") >= 0 ? it.title.split("#")[0] : it.title];
        readmeProc.running = false;
        readmeProc.running = true;
    }

    function fetchPRs() {
        if (!ghSearch.ready) return;
        const fields = "title,url,number,repository,createdAt";
        prAuthorProc.command   = ["gh", "search", "prs", "--author=@me",           "--state=open", "--json", fields, "--limit", "25"];
        prReviewedProc.command = ["gh", "search", "prs", "--review-requested=@me", "--state=open", "--json", fields, "--limit", "15"];
        prMentionsProc.command = ["gh", "search", "prs", "--mentions=@me",         "--state=open", "--json", fields, "--limit", "15"];
        prAssigneeProc.command = ["gh", "search", "prs", "--assignee=@me",         "--state=open", "--json", fields, "--limit", "15"];
        prAuthorProc.running   = false; prAuthorProc.running   = true;
        prReviewedProc.running = false; prReviewedProc.running = true;
        prMentionsProc.running = false; prMentionsProc.running = true;
        prAssigneeProc.running = false; prAssigneeProc.running = true;
    }

    onQueryChanged: { if (ghSearch.active) ghDebounce.restart(); }
    onSelectedItemChanged: { if (ghSearch.active) ghSearch.updatePreview(); }
    onItemsChanged: { if (ghSearch.active) ghSearch.updatePreview(); }
    onActiveChanged: { if (ghSearch.active && ghSearch.ready) ghSearch.fetchPRs(); }
    onReadyChanged: { if (ghSearch.active && ghSearch.ready) ghSearch.fetchPRs(); }

    Component.onCompleted: ghAuthProc.running = true

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
                return;
            }
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
            onStreamFinished: { ghSearch.scopedResults = ghSearch.parseResults(this.text); }
        }
    }

    Process {
        id: ghBroadProc
        running: false
        command: ["gh"]
        stdout: StdioCollector {
            onStreamFinished: { ghSearch.broadResults = ghSearch.parseResults(this.text); }
        }
    }

    Process {
        id: prAuthorProc
        running: false
        command: ["gh"]
        stdout: StdioCollector {
            onStreamFinished: { ghSearch.prAuthorResults = ghSearch.parseResults(this.text); }
        }
    }
    Process {
        id: prReviewedProc
        running: false
        command: ["gh"]
        stdout: StdioCollector {
            onStreamFinished: { ghSearch.prReviewedResults = ghSearch.parseResults(this.text); }
        }
    }
    Process {
        id: prMentionsProc
        running: false
        command: ["gh"]
        stdout: StdioCollector {
            onStreamFinished: { ghSearch.prMentionsResults = ghSearch.parseResults(this.text); }
        }
    }
    Process {
        id: prAssigneeProc
        running: false
        command: ["gh"]
        stdout: StdioCollector {
            onStreamFinished: { ghSearch.prAssigneeResults = ghSearch.parseResults(this.text); }
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
