import QtQuick
import Quickshell.Io
import "Data.js" as Data

// gh CLI-backed repo search + README preview. Owns the auth probe, the
// search debounce/proc, the readme fetch proc, and the preview state.
// Parent shell binds `query`/`active`/`selectedItem` and reads `items`,
// `running`, `ready`, and the preview properties.
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
    readonly property bool running: ghProc.running

    function clear() {
        ghSearch.items = [];
        ghSearch.previewRepo = "";
        ghSearch.previewRepoUrl = "";
        ghSearch.previewReadme = "";
        ghDebounce.stop();
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
            onStreamFinished: { ghSearch.ready = this.text.indexOf("ok") >= 0; }
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
                ghSearch.items = [];
                return;
            }
            ghProc.command = ["gh", "search", "repos", q,
                              "--json", "fullName,description,url,stargazersCount,language",
                              "--limit", "25"];
            ghProc.running = false;
            ghProc.running = true;
        }
    }

    Process {
        id: ghProc
        running: false
        command: ["gh"]
        stdout: StdioCollector {
            onStreamFinished: {
                let arr = [];
                try { arr = JSON.parse(this.text || "[]"); } catch (_) { arr = []; }
                const out = new Array(arr.length);
                for (let i = 0; i < arr.length; i++) {
                    const r = arr[i];
                    const lang = r.language ? "  ·  " + r.language : "";
                    out[i] = {
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
                ghSearch.items = out;
                ghSearch.updatePreview();
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
