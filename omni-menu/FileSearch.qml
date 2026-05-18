import QtQuick
import Quickshell
import Quickshell.Io
import "Data.js" as Data

// fd-backed file search + file preview. Owns the fd Process, its
// debounce, the head/stat preview procs, and the preview state. The
// parent shell binds `query`/`queryTokens`/`active`/`selectedItem` and
// reads `items`, `previewPath`/`Text`/`Meta`/`Kind`, and `running`.
Item {
    id: fileSearch

    required property string query
    required property var queryTokens
    required property bool active
    required property var selectedItem

    readonly property string homeDir: Quickshell.env("HOME")

    property var items: []
    property string previewPath: ""
    property string previewText: ""
    property string previewMeta: ""
    readonly property bool running: fdProc.running

    readonly property string previewKind: {
        if (!fileSearch.previewPath) return "";
        const ext = Data.fileExt(fileSearch.previewPath);
        if (Data.imageExts.indexOf(ext) >= 0) return "image";
        if (Data.textExts.indexOf(ext) >= 0) return "text";
        return "meta";
    }

    function clear() {
        fileSearch.items = [];
        fileSearch.previewPath = "";
        fileSearch.previewText = "";
        fileSearch.previewMeta = "";
        fdDebounce.stop();
    }

    function updatePreview() {
        if (!fileSearch.active) return;
        const it = fileSearch.selectedItem;
        const path = (it && it.path) || "";
        if (path === fileSearch.previewPath) return;
        fileSearch.previewPath = path;
        fileSearch.previewText = "";
        fileSearch.previewMeta = "";
        if (!path) return;
        const kind = fileSearch.previewKind;
        if (kind === "text") {
            fileSearch.previewText = "Loading…";
            textPreviewProc.command = ["head", "-c", "8192", path];
            textPreviewProc.running = false;
            textPreviewProc.running = true;
        } else if (kind === "meta") {
            fileSearch.previewMeta = "Loading…";
            // Positional $1 keeps the path argv-safe; embedding it in the
            // -c script would let `$`/backticks in filenames expand.
            metaPreviewProc.command = ["sh", "-c",
                "stat -c 'SIZE   %s bytes\nMTIME  %y' \"$1\" 2>/dev/null; "
                + "printf 'MIME   '; file -b --mime-type \"$1\" 2>/dev/null",
                "sh", path];
            metaPreviewProc.running = false;
            metaPreviewProc.running = true;
        }
    }

    function buildFdArgs(tokens) {
        const args = ["--type", "f", "--max-results", "200"];
        const excludes = Data.fdExcludes;
        for (let i = 0; i < excludes.length; i++) {
            args.push("--exclude");
            args.push(excludes[i]);
        }
        // Three modes by what the user typed:
        //   "mrrobot/*.txt" -> full-path glob, prefix `**/` so fd crosses
        //                      directory boundaries (a bare `*` doesn't).
        //   "*.png"         -> basename glob, no full-path scoping.
        //   "img wall"      -> fzf-style regex, tokens joined by `.*`.
        const raw = tokens.join(" ");
        const hasSlash = raw.indexOf("/") >= 0;
        const hasGlob = raw.indexOf("*") >= 0 || raw.indexOf("?") >= 0;
        if (hasSlash) {
            args.push("--glob");
            args.push("--full-path");
            const prefix = (raw[0] === "*" || raw[0] === "/") ? "" : "**/";
            args.push(prefix + raw);
        } else if (hasGlob) {
            args.push("--glob");
            args.push(raw);
        } else {
            args.push(tokens.join(".*"));
        }
        args.push(fileSearch.homeDir);
        return args;
    }

    onQueryChanged: { if (fileSearch.active) fdDebounce.restart(); }
    onSelectedItemChanged: { if (fileSearch.active) fileSearch.updatePreview(); }

    Process {
        id: fdProc
        running: false
        command: ["fd"]
        stdout: StdioCollector {
            onStreamFinished: {
                const lines = this.text.split("\n").filter(s => s.length > 0);
                const out = new Array(lines.length);
                const home = fileSearch.homeDir;
                for (let i = 0; i < lines.length; i++) {
                    const path = lines[i];
                    const dirShort = Data.tildify(Data.dirname(path), home);
                    out[i] = {
                        title: Data.basename(path),
                        comment: dirShort,
                        keywords: "",
                        category: dirShort,
                        icon: Data.fileIcon(path),
                        path: path,
                        exec: Data.openUrl(path),
                        rawCategory: true
                    };
                }
                fileSearch.items = out;
                fileSearch.updatePreview();
            }
        }
    }

    Timer {
        id: fdDebounce
        interval: 120
        repeat: false
        onTriggered: {
            const tokens = fileSearch.queryTokens;
            if (!fileSearch.active || tokens.length === 0) {
                fileSearch.items = [];
                fileSearch.updatePreview();
                return;
            }
            fdProc.command = ["fd"].concat(fileSearch.buildFdArgs(tokens));
            fdProc.running = false;
            fdProc.running = true;
        }
    }

    // Two Processes so text and metadata sinks can be staged without
    // racing on a shared body property. Each is restarted via running
    // false→true on selection change.
    Process {
        id: textPreviewProc
        running: false
        command: ["true"]
        stdout: StdioCollector {
            onStreamFinished: { fileSearch.previewText = this.text; }
        }
    }
    Process {
        id: metaPreviewProc
        running: false
        command: ["true"]
        stdout: StdioCollector {
            onStreamFinished: { fileSearch.previewMeta = this.text; }
        }
    }
}
