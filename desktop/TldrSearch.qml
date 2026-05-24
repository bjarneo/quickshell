import QtQuick
import Quickshell.Io

// tldr-backed inline CLI help. Triggered by a `$` query prefix in the
// omni-menu. The single "result" row is synthetic; OmniMenu.activate()
// special-cases `isTldr` and launches a floating terminal with the
// command pre-typed at the readline prompt. The preview pane shows the
// tldr markdown for the first word (the tool name).
Item {
    id: tldrSearch

    required property string query
    required property bool active

    property var items: []
    property string previewText: ""
    property string toolName: ""
    property string preFill: ""
    readonly property bool running: tldrProc.running

    // Monotonic per-fetch token. Bumped on every dispatch; the stdout
    // collector ignores any result whose token doesn't match the
    // current one, so a slow process completing after the user typed
    // ahead can't backwrite stale text into previewText.
    property int _gen: 0

    function clear() {
        tldrSearch.items = [];
        tldrSearch.previewText = "";
        tldrSearch.toolName = "";
        tldrSearch.preFill = "";
        tldrDebounce.stop();
        // Kill the in-flight subprocess so its StdioCollector can't
        // backwrite previewText after a deactivation.
        tldrSearch._gen += 1;
        tldrProc.running = false;
    }

    // Strip the leading "$" + whitespace. Return both the first word
    // (the tldr lookup key) and the entire post-`$` text (what the
    // user wants pre-typed at the terminal prompt). `parseQuery`
    // returns null when the query isn't a tldr trigger.
    function parseQuery(q) {
        if (q.charAt(0) !== "$") return null;
        const rest = q.substring(1).trim();
        if (rest.length === 0) return { name: "", preFill: "" };
        const space = rest.indexOf(" ");
        const name = space >= 0 ? rest.substring(0, space) : rest;
        return { name: name, preFill: rest };
    }

    onQueryChanged: { if (tldrSearch.active) tldrDebounce.restart(); }
    onActiveChanged: { if (!tldrSearch.active) tldrSearch.clear(); }

    Process {
        id: tldrProc
        running: false
        command: ["true"]
        property int gen: 0
        stdout: StdioCollector {
            onStreamFinished: {
                // Drop results from a prior dispatch — the user has
                // already moved on, and we don't want this text to
                // overwrite whatever the current dispatch is loading.
                if (tldrProc.gen !== tldrSearch._gen) return;
                tldrSearch.previewText = this.text;
            }
        }
    }

    Timer {
        id: tldrDebounce
        interval: 120
        repeat: false
        onTriggered: {
            const parsed = tldrSearch.parseQuery(tldrSearch.query);
            if (!tldrSearch.active || !parsed || parsed.name.length === 0) {
                tldrSearch.items = [];
                tldrSearch.previewText = "";
                tldrSearch.toolName = "";
                tldrSearch.preFill = "";
                return;
            }
            tldrSearch.toolName = parsed.name;
            tldrSearch.preFill = parsed.preFill;
            // Synthetic single-row result. `isTldr` routes activate()
            // to a special branch that bypasses the shell-quoting
            // path and launches a floating terminal with the user's
            // typed text pre-filled at the prompt via argv-positional.
            tldrSearch.items = [{
                title: "tldr " + parsed.name,
                comment: "open terminal with `" + parsed.preFill + "` ready",
                keywords: "",
                category: "tldr",
                icon: "󰂺",
                rawCategory: true,
                isTldr: true,
                tldrName: parsed.name,
                tldrPreFill: parsed.preFill
            }];
            // Bump the generation token, snapshot it onto the
            // Process, then restart. The collector compares against
            // tldrSearch._gen — a delayed result from a previous
            // dispatch will mismatch and be dropped.
            tldrSearch._gen += 1;
            tldrProc.gen = tldrSearch._gen;
            // `-m` emits raw markdown so OmniMenu can style it against
            // the live palette. 2>&1 folds the "documentation is not
            // available" message into the preview body. Positional $1
            // keeps the tool name argv-safe.
            tldrProc.command = ["sh", "-c",
                "tldr -m -- \"$1\" 2>&1",
                "sh", parsed.name];
            tldrProc.running = false;
            tldrProc.running = true;
        }
    }
}
