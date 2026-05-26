import QtQuick
import Quickshell.Io
import "omni/AssistantTools.js" as AssistantTools

// Local-LLM chat backend for the omni-menu, triggered by a `?` query
// prefix. Mirrors TldrSearch's shape: a synthetic single-row item plus
// a streamed preview body. The HTTP API at localhost:11434 streams
// NDJSON token chunks which a SplitParser appends to previewText.
//
// State machine (status property):
//   ""           probe still running (transient)
//   "no-ollama"  binary missing — user must install themselves
//   "no-daemon"  binary OK, daemon not responding — Enter starts it
//   "no-model"   daemon OK, model not pulled — Enter pulls it
//   "ok"         everything in place — Enter submits the prompt
//
// Within "ok", `submitted` flips true on Enter and `running` tracks the
// local tool, fixed action, or curl subprocess; once running flips
// back to false the answer is done.
//
// RAM: clear() invokes unloadIfUsed() to release the resident model
// weights (~1 GB for qwen3.5:0.8b) right after the user leaves
// chat mode. The `_usedThisSession` flag guards against unloading a
// model the user warmed via some other tool before opening the
// palette. The ollama daemon itself stays running - we manage only
// our use of it.
Item {
    id: ollamaChat

    required property string query
    required property bool active

    property var items: []
    property string previewText: ""
    property string prompt: ""
    property string status: ""
    property bool submitted: false
    readonly property bool running: chatProc.running || toolProc.running || actionProc.running

    property int _gen: 0
    readonly property string model_: "qwen3.5:0.8b"
    property var _pendingTool: null
    property string actionLabel: ""
    property string actionCommand: ""

    // Tracks whether THIS session actually invoked inference (vs. just
    // probed the daemon). Without it, leaving the palette while ollama
    // ps already had the model warm from another tool would unload it
    // and surprise the user. Set in submit(), cleared after the unload
    // fires from clear().
    property bool _usedThisSession: false

    // Emitted from submit() so callers can scroll to top / reset
    // state on each *new* submission specifically — not on every
    // prompt edit (which also flips `submitted` false→true→false).
    signal promptSubmitted()
    readonly property int assistantIntentCount: AssistantTools.intents.length

    // Steers the model toward Omarchy-native answers. Small local
    // models follow concrete operational boundaries better than broad
    // personality notes, so the bridge and safety model are spelled out.
    readonly property string systemPrompt:
          "You are Omni, a lightweight on-machine assistant built specifically for Omarchy on Arch, Hyprland, Quickshell, Wayland, and Aether. "
        + "You are not a generic chatbot: answer as a desktop helper that understands Omarchy commands, Omni palette state, Quickshell IPC, Hyprland windows/workspaces/monitors, themes, screenshots, recordings, packages, logs, and local files. "
        + "Omni may provide output from a fixed read-only local tool bridge for Omarchy and local machine inspection. "
        + "When tool output is provided, treat it as authoritative and answer from it; do not say you ran the command yourself. "
        + "Never invent local facts, files, windows, services, or packages that are not in tool output. "
        + "You cannot execute arbitrary tools and cannot request arbitrary shell execution; when no tool output is provided and a command would verify or inspect the system, include it under a Check: heading. "
        + "Read-only inspection may be automatic, but mutating actions require explicit user intent and must run only through Omni's fixed reviewed action flow. "
        + "For organize, clean, tidy, dedupe, or sort requests, default to a non-destructive review plan; if Omni offers a fixed reviewed action, tell the user Enter runs that fixed action. "
        + "Use $HOME for home-relative shell paths, never /home/$USER. "
        + "Reply in devrel style: short, scannable, no preamble, no apologies. "
        + "Lead with the answer or the exact command. "
        + "Wrap every shell snippet in a fenced ```code``` block. "
        + "Use plain hyphens (-), never em dashes. "
        + "If you don't know, say so in one line. "
        + "Skip restating the question."

    function clear() {
        ollamaChat.items = [];
        ollamaChat.previewText = "";
        ollamaChat.prompt = "";
        ollamaChat.submitted = false;
        ollamaChat._gen += 1;
        chatProc.running = false;
        toolProc.running = false;
        actionProc.running = false;
        probeProc.running = false;
        ollamaChat.status = "";
        ollamaChat._pendingTool = null;
        ollamaChat.actionLabel = "";
        ollamaChat.actionCommand = "";
        ollamaChat.refreshItems();
        // If this session actually loaded the model (vs. just probed),
        // ping ollama with keep_alive:0 so the ~2GB of weights are
        // released right away instead of waiting for the daemon's
        // default 5-minute idle timeout. Gated on _usedThisSession so
        // we never unload a model the user warmed up via some other
        // tool before opening the palette.
        ollamaChat.unloadIfUsed();
    }

    // Posts a no-prompt generate with keep_alive:0, which ollama
    // interprets as "unload this model immediately". Fire-and-forget,
    // short timeout so a wedged daemon can't slow the palette close.
    function unloadIfUsed() {
        if (!ollamaChat._usedThisSession) return;
        ollamaChat._usedThisSession = false;
        const body = JSON.stringify({
            model: ollamaChat.model_,
            keep_alive: 0
        });
        unloadProc.command = ["curl", "-s", "--max-time", "2", "-X", "POST",
            "http://localhost:11434/api/generate",
            "-d", body];
        unloadProc.running = false;
        unloadProc.running = true;
    }

    function parseQuery(q) {
        if (q.charAt(0) !== "?") return null;
        return { prompt: q.substring(1).trim() };
    }

    function isUnsafePrompt(p) {
        return /\b(delete|remove|rm|wipe|clear|move|mv|copy|cp|write|edit|modify|change|install|update|upgrade|pull|fetch|download|restart|start|stop|kill|shutdown|reboot|sudo|chmod|chown)\b/.test(p);
    }

    function blocksReviewAction(p) {
        return /\b(delete|remove|rm|wipe|clear|write|edit|modify|change|install|update|upgrade|pull|fetch|download|restart|start|stop|kill|shutdown|reboot|sudo|chmod|chown)\b/.test(p);
    }

    function isOrganizePrompt(p) {
        return /\b(organize|organise|sort|clean|tidy|dedupe|declutter)\b/.test(p);
    }

    readonly property string downloadsOrganizerCommand:
          "set -euo pipefail\n"
        + "dir=\"$HOME/Downloads\"\n"
        + "move_unique() {\n"
        + "  src=\"$1\"; dest=\"$2\"; mkdir -p \"$dest\"\n"
        + "  base=\"$(basename \"$src\")\"; target=\"$dest/$base\"\n"
        + "  if [ -e \"$target\" ]; then\n"
        + "    stem=\"${base%.*}\"; ext=\"${base##*.}\"\n"
        + "    if [ \"$stem\" = \"$base\" ]; then ext=\"\"; else ext=\".$ext\"; fi\n"
        + "    i=1\n"
        + "    while [ -e \"$dest/$stem-$i$ext\" ]; do i=$((i+1)); done\n"
        + "    target=\"$dest/$stem-$i$ext\"\n"
        + "  fi\n"
        + "  mv -- \"$src\" \"$target\"\n"
        + "  printf 'moved %s -> %s\\n' \"$base\" \"${target#$dir/}\"\n"
        + "}\n"
        + "for f in \"$dir\"/*; do\n"
        + "  [ -f \"$f\" ] || continue\n"
        + "  name=\"${f##*/}\"\n"
        + "  lower=\"$(printf '%s' \"$name\" | tr '[:upper:]' '[:lower:]')\"\n"
        + "  case \"$lower\" in\n"
        + "    *.crdownload|*.part) move_unique \"$f\" \"$dir/Partials\" ;;\n"
        + "    *.zip|*.7z|*.rar|*.tar|*.tar.gz|*.tgz|*.tar.xz|*.txz|*.gz|*.xz|*.bz2|*.zst|*.iso) move_unique \"$f\" \"$dir/Archives\" ;;\n"
        + "    *.png|*.jpg|*.jpeg|*.gif|*.webp|*.bmp|*.svg|*.avif) move_unique \"$f\" \"$dir/Images\" ;;\n"
        + "    *.mp4|*.mkv|*.mov|*.webm|*.avi|*.flv|*.wmv|*.m4v) move_unique \"$f\" \"$dir/Videos\" ;;\n"
        + "    *.pdf|*.doc|*.docx|*.odt|*.xls|*.xlsx|*.ods|*.ppt|*.pptx|*.txt|*.md|*.csv) move_unique \"$f\" \"$dir/Docs\" ;;\n"
        + "    *.apk|*.apks|*.xapk) move_unique \"$f\" \"$dir/APKs\" ;;\n"
        + "    *.mp3|*.flac|*.wav|*.ogg|*.m4a|*.opus) move_unique \"$f\" \"$dir/Audio\" ;;\n"
        + "  esac\n"
        + "done\n"
        + "printf '\\nDone. Top-level Downloads now:\\n'\n"
        + "ls -lh --group-directories-first \"$dir\" | sed -n '1,80p'\n"

    function toolForKey(key) {
        switch (key) {
        case "downloads":
            return { key: key, label: "Downloads", command: "ls -lh --group-directories-first \"$HOME/Downloads\" | sed -n '1,80p'" };
        case "date":
            return { key: key, label: "Date/time", command: "date" };
        case "storage":
            return { key: key, label: "Storage", command: "df -h / \"$HOME\" \"$HOME/Downloads\" 2>/dev/null | awk '!seen[$6]++'" };
        case "large-files":
            return { key: key, label: "Large home files", command: "find \"$HOME\" -xdev \\( -path \"$HOME/.cache\" -o -path \"$HOME/.local/share/Trash\" \\) -prune -o -type f -size +100M -printf '%s %p\\n' 2>/dev/null | sort -nr | head -40 | awk '{ size=$1; $1=\"\"; printf \"%.1f MB %s\\n\", size/1048576, substr($0,2) }'" };
        case "processes":
            return { key: key, label: "Top processes", command: "ps -eo pid,comm,%cpu,%mem --sort=-%cpu | head -20" };
        case "system-overview":
            return { key: key, label: "System overview", command: "printf 'Uptime:\\n'; uptime; printf '\\nMemory:\\n'; free -h; printf '\\nHome disk:\\n'; df -h \"$HOME\" 2>/dev/null" };
        case "network":
            return { key: key, label: "Network", command: "printf 'Addresses:\\n'; ip -brief addr; printf '\\nRoutes:\\n'; ip route | sed -n '1,12p'; printf '\\nDNS:\\n'; resolvectl status 2>/dev/null | sed -n '1,40p'" };
        case "user-services":
            return { key: key, label: "User services", command: "systemctl --user --failed --no-pager; printf '\\nRecent user units:\\n'; systemctl --user list-units --type=service --state=running --no-pager --plain | sed -n '1,25p'" };
        case "logs":
            return { key: key, label: "Recent user log warnings", command: "journalctl --user -p warning..alert -n 80 --no-pager" };
        case "troubleshoot":
            return { key: key, label: "Troubleshooting snapshot", command: "printf 'Failed user units:\\n'; systemctl --user --failed --no-pager; printf '\\nHyprland config errors:\\n'; hyprctl configerrors 2>/dev/null || true; printf '\\nRecent warnings:\\n'; journalctl --user -p warning..alert -n 40 --no-pager" };
        case "quickshell-ipc":
            return { key: key, label: "Quickshell IPC", command: "qs -c desktop ipc show" };
        case "quickshell-processes":
            return { key: key, label: "Quickshell processes", command: "ps -eo pid,comm,args | grep -E 'qs .*desktop|qs -n -d -c desktop|quickshell' | grep -v grep" };
        case "waybar-status":
            return { key: key, label: "Waybar status", command: "systemctl --user is-active waybar 2>/dev/null || pgrep -a waybar || true" };
        case "active-window":
            return { key: key, label: "Active Hyprland window", command: "hyprctl activewindow" };
        case "hypr-workspaces":
            return { key: key, label: "Hyprland workspaces", command: "hyprctl workspaces" };
        case "hypr-monitors":
            return { key: key, label: "Hyprland monitors", command: "hyprctl monitors" };
        case "hypr-clients":
            return { key: key, label: "Hyprland clients", command: "hyprctl clients | sed -n '1,220p'" };
        case "hypr-errors":
            return { key: key, label: "Hyprland config errors", command: "hyprctl configerrors" };
        case "omarchy-commands":
            return { key: key, label: "Omarchy commands", command: "omarchy commands 2>/dev/null || omarchy --help" };
        case "omarchy-theme":
            return { key: key, label: "Omarchy theme", command: "printf 'Current theme:\\n'; cat \"$HOME/.config/omarchy/current/theme.name\" 2>/dev/null || true; printf '\\nTheme commands:\\n'; omarchy theme --help 2>/dev/null || true; printf '\\nCustom themes:\\n'; find \"$HOME/.config/omarchy/themes\" -mindepth 1 -maxdepth 1 -type d -printf '%f\\n' 2>/dev/null | sort | sed -n '1,80p'" };
        case "aether":
            return { key: key, label: "Aether", command: "aether --help 2>&1 | sed -n '1,100p'; printf '\\nBlueprints:\\n'; aether --list-blueprints --json 2>/dev/null | sed -n '1,80p' || true" };
        case "screenshots":
            return { key: key, label: "Recent screenshots", command: "find \"$HOME/Pictures/Screenshots\" \"$HOME/Pictures\" -maxdepth 2 -type f \\( -iname '*.png' -o -iname '*.jpg' -o -iname '*.jpeg' -o -iname '*.webp' \\) -printf '%TY-%Tm-%Td %TH:%TM %p\\n' 2>/dev/null | sort -r | head -40" };
        case "recordings":
            return { key: key, label: "Recent recordings", command: "find \"$HOME/Videos\" -maxdepth 2 -type f \\( -iname '*.mp4' -o -iname '*.mkv' -o -iname '*.webm' -o -iname '*.mov' \\) -printf '%TY-%Tm-%Td %TH:%TM %p\\n' 2>/dev/null | sort -r | head -40" };
        case "packages":
            return { key: key, label: "Installed packages", command: "printf 'Package counts:\\n'; pacman -Q | wc -l | awk '{print \"total \" $1}'; pacman -Qe | wc -l | awk '{print \"explicit \" $1}'; printf '\\nExplicit packages:\\n'; pacman -Qe | sed -n '1,90p'" };
        case "updates":
            return { key: key, label: "Package updates", command: "if command -v checkupdates >/dev/null 2>&1; then checkupdates | sed -n '1,120p'; else echo 'checkupdates is not installed; use omarchy update when you want to update.'; fi" };
        case "recent-files":
            return { key: key, label: "Recent home files", command: "find \"$HOME\" \\( -path \"$HOME/.cache\" -o -path \"$HOME/.local/share/Trash\" -o -path \"$HOME/.ollama\" \\) -prune -o -type f -printf '%T@ %p\\n' 2>/dev/null | sort -nr | head -50 | cut -d' ' -f2-" };
        case "desktop-files":
            return { key: key, label: "Desktop files", command: "ls -lh --group-directories-first \"$HOME/Desktop\" 2>/dev/null | sed -n '1,80p'" };
        case "documents":
            return { key: key, label: "Recent documents", command: "find \"$HOME/Documents\" -maxdepth 3 -type f -printf '%TY-%Tm-%Td %TH:%TM %p\\n' 2>/dev/null | sort -r | head -50" };
        case "trash":
            return { key: key, label: "Trash status", command: "du -sh \"$HOME/.local/share/Trash\" 2>/dev/null || true; find \"$HOME/.local/share/Trash/files\" -maxdepth 1 -mindepth 1 -printf '%f\\n' 2>/dev/null | sed -n '1,80p'" };
        case "session":
            return { key: key, label: "Session", command: "printf 'Desktop: %s\\nSession: %s\\nWayland: %s\\nHyprland instance: %s\\n' \"$XDG_CURRENT_DESKTOP\" \"$XDG_SESSION_TYPE\" \"$WAYLAND_DISPLAY\" \"$HYPRLAND_INSTANCE_SIGNATURE\"" };
        default:
            return null;
        }
    }

    function detectTool(text) {
        const p = AssistantTools.normalize(text);
        const intent = AssistantTools.findIntent(p);
        if (!intent) return null;
        const tool = ollamaChat.toolForKey(intent.tool);
        if (!tool) return null;
        if (intent.action === "downloads-organizer"
            && ollamaChat.isOrganizePrompt(p)
            && !ollamaChat.blocksReviewAction(p)) {
            tool.actionLabel = "Review Downloads organizer";
            tool.actionCommand = ollamaChat.downloadsOrganizerCommand;
        }
        return tool;
    }

    function cappedToolScript(command) {
        const inner = JSON.stringify(command);
        return "set -o pipefail; "
            + "timeout 5s bash -lc " + inner + " 2>&1 | head -c 12000; "
            + "rc=${PIPESTATUS[0]}; printf '\\n__OMNI_RC:%s\\n' \"$rc\"";
    }

    function cappedActionScript() {
        return "set -o pipefail; "
            + "timeout 30s bash -lc \"$1\" 2>&1 | head -c 12000; "
            + "rc=${PIPESTATUS[0]}; printf '\\n__OMNI_RC:%s\\n' \"$rc\"";
    }

    function parseToolResult(raw) {
        const marker = "\n__OMNI_RC:";
        const idx = raw.lastIndexOf(marker);
        if (idx < 0) return { output: raw.trim(), rc: "unknown", truncated: raw.length >= 12000 };
        const output = raw.substring(0, idx).trim();
        const rc = raw.substring(idx + marker.length).trim().split(/\s+/)[0] || "unknown";
        return { output: output, rc: rc, truncated: output.length >= 11950 };
    }

    function startGenerate(promptText) {
        ollamaChat._usedThisSession = true;
        chatProc.gen = ollamaChat._gen;
        const body = JSON.stringify({
            model: ollamaChat.model_,
            prompt: promptText,
            system: ollamaChat.systemPrompt,
            stream: true,
            think: false
        });
        chatProc.command = ["curl", "-sN",
            "http://localhost:11434/api/generate",
            "-d", body];
        chatProc.running = false;
        chatProc.running = true;
    }

    function runTool(tool) {
        ollamaChat._pendingTool = tool;
        ollamaChat.previewText = "Running local check: " + tool.label + "...\n\nCheck:\n```bash\n" + tool.command + "\n```";
        toolProc.gen = ollamaChat._gen;
        toolProc.command = ["bash", "-lc", ollamaChat.cappedToolScript(tool.command)];
        toolProc.running = false;
        toolProc.running = true;
    }

    function runAction() {
        if (ollamaChat.actionCommand === "" || actionProc.running) return false;
        const label = ollamaChat.actionLabel || "Fixed action";
        const command = ollamaChat.actionCommand;
        ollamaChat._gen += 1;
        chatProc.running = false;
        toolProc.running = false;
        ollamaChat._pendingTool = null;
        ollamaChat.actionLabel = "";
        ollamaChat.actionCommand = "";
        ollamaChat.previewText = "Running fixed action: " + label + "...\n\n```bash\n" + command + "\n```";
        ollamaChat.refreshItems();
        actionProc.gen = ollamaChat._gen;
        actionProc.label = label;
        actionProc.command = ["bash", "-lc", ollamaChat.cappedActionScript(), "_", command];
        actionProc.running = false;
        actionProc.running = true;
        return true;
    }

    function refreshItems() {
        if (!ollamaChat.active) { ollamaChat.items = []; return; }
        const empty = ollamaChat.prompt.length === 0;
        const rows = [{
            title: "ollama " + ollamaChat.model_,
            comment: empty ? "type a question after ?" : ollamaChat.prompt,
            keywords: "",
            category: "ollama",
            icon: "󱚤",
            rawCategory: true,
            isOllama: true
        }];
        if (ollamaChat.submitted && ollamaChat.actionCommand !== "") {
            rows.push({
                title: "run fixed action",
                comment: ollamaChat.actionLabel,
                keywords: "",
                category: "action",
                icon: "󰆍",
                rawCategory: true,
                isOllamaAction: true
            });
        }
        ollamaChat.items = rows;
    }

    function submit() {
        if (ollamaChat.status !== "ok") return;
        if (ollamaChat.prompt.length === 0) return;
        ollamaChat.submitted = true;
        ollamaChat.previewText = "";
        ollamaChat._gen += 1;
        ollamaChat.actionLabel = "";
        ollamaChat.actionCommand = "";
        ollamaChat.promptSubmitted();

        const tool = ollamaChat.detectTool(ollamaChat.prompt);
        if (tool) {
            ollamaChat.runTool(tool);
            return;
        }

        // argv-style — the prompt rides inside JSON.stringify'd body so
        // no shell parsing touches its contents.
        //
        // think:false disables Qwen3-family thinking mode. With it on,
        // tokens stream into a separate `thinking` field while
        // `response` stays empty until the model finishes planning,
        // which looks like a frozen panel for the first few seconds.
        // Our devrel-style system prompt already rules out chain-of-
        // thought output anyway. Ignored by non-thinking models.
        ollamaChat.startGenerate(ollamaChat.prompt);
    }

    onActiveChanged: {
        if (ollamaChat.active) {
            // Re-probe on every entry: install / pull / daemon-start
            // performed in a previous activation should be picked up
            // without a menu reload.
            ollamaChat.status = "";
            probeProc.running = false;
            probeProc.running = true;
            ollamaChat.refreshItems();
        } else {
            // User backspaced the leading `?` while the menu stayed
            // open. Cancel any in-flight stream so curl + ollama
            // don't keep spending CPU/tokens on an answer no-one is
            // looking at, and bump _gen so late chunks can't backwrite
            // previewText. Keep prompt/items/submitted for the case
            // where they re-type `?` with the same content — clear()
            // is called from close()/category-pivot, not here.
            ollamaChat._gen += 1;
            chatProc.running = false;
            toolProc.running = false;
            ollamaChat._pendingTool = null;
            ollamaChat.actionLabel = "";
            ollamaChat.actionCommand = "";
        }
    }

    onQueryChanged: {
        if (!ollamaChat.active) return;
        const parsed = ollamaChat.parseQuery(ollamaChat.query);
        const next = parsed ? parsed.prompt : "";
        if (next !== ollamaChat.prompt) {
            ollamaChat.prompt = next;
            ollamaChat.submitted = false;
            ollamaChat.previewText = "";
            // Editing the prompt invalidates any in-flight stream.
            ollamaChat._gen += 1;
            chatProc.running = false;
            toolProc.running = false;
            ollamaChat._pendingTool = null;
            ollamaChat.actionLabel = "";
            ollamaChat.actionCommand = "";
            ollamaChat.refreshItems();
        }
    }

    // Readiness probe — runs once per chatMode activation. Cheap
    // (<100ms locally). Output is one of the four status strings.
    Process {
        id: probeProc
        running: false
        // Model name is passed positionally as $1 so shell
        // metacharacters / regex characters in it can never
        // re-interpret the command. grep -F treats the pattern as a
        // fixed string (so `.` and `:` in `qwen3.5:0.8b` aren't
        // regex metachars), and `--` separates the flag block from
        // the pattern. Substring match against /api/tags is still
        // technically loose but the model id is distinctive enough
        // that a JSON false-positive is implausible.
        command: ["sh", "-c",
            "if ! command -v ollama >/dev/null 2>&1; then echo no-ollama; exit; fi; "
            + "if ! curl -s --max-time 1 http://localhost:11434/api/tags >/dev/null 2>&1; then echo no-daemon; exit; fi; "
            + "if ! curl -s http://localhost:11434/api/tags | grep -Fq -- \"$1\"; then echo no-model; exit; fi; "
            + "echo ok",
            "sh", ollamaChat.model_]
        stdout: StdioCollector {
            onStreamFinished: { ollamaChat.status = this.text.trim(); }
        }
    }

    // Fire-and-forget keep_alive:0 unload. No stdout handler because
    // we don't care what ollama says — the goal is just to free the
    // RAM. max-time 2 keeps a stuck daemon from blocking palette
    // close.
    Process {
        id: unloadProc
        running: false
        command: ["true"]
    }

    Process {
        id: toolProc
        running: false
        command: ["true"]
        property int gen: 0
        stdout: StdioCollector {
            onStreamFinished: {
                if (toolProc.gen !== ollamaChat._gen) return;
                const tool = ollamaChat._pendingTool;
                if (!tool) return;
                const result = ollamaChat.parseToolResult(this.text || "");
                const output = result.output.length > 0 ? result.output : "(no output)";
                ollamaChat.actionLabel = tool.actionLabel || "";
                ollamaChat.actionCommand = tool.actionCommand || "";
                ollamaChat.refreshItems();
                const toolPrompt =
                      "Original question: " + ollamaChat.prompt + "\n\n"
                    + "A fixed read-only local tool was run on this Omarchy machine.\n"
                    + "Tool: " + tool.label + "\n"
                    + "Command: " + tool.command + "\n"
                    + "Exit code: " + result.rc + "\n"
                    + "Output" + (result.truncated ? " (truncated)" : "") + ":\n"
                    + "```text\n" + output + "\n```\n\n"
                    + "Answer from this output like a local machine assistant. Be concise and practical. "
                    + "If this is an organization request, only group the listed names into suggested categories and mention obvious review targets. "
                    + (ollamaChat.actionCommand !== "" ? "Tell the user they can press Enter again to run the fixed organizer action. " : "")
                    + "Do not output rm, mv, cp, mkdir, or other mutating commands unless the user explicitly asks for commands or asks you to apply a plan. "
                    + "Do not invent files that are not in the output. If the command failed, say what failed and show the Check command.";
                ollamaChat.previewText = "";
                ollamaChat._pendingTool = null;
                ollamaChat.startGenerate(toolPrompt);
            }
        }
    }

    Process {
        id: actionProc
        running: false
        command: ["true"]
        property int gen: 0
        property string label: ""
        stdout: StdioCollector {
            onStreamFinished: {
                if (actionProc.gen !== ollamaChat._gen) return;
                const result = ollamaChat.parseToolResult(this.text || "");
                const output = result.output.length > 0 ? result.output : "(no output)";
                ollamaChat.previewText =
                      "Fixed action finished: " + actionProc.label + "\n"
                    + "Exit code: " + result.rc + "\n"
                    + "Output" + (result.truncated ? " (truncated)" : "") + ":\n"
                    + "```text\n" + output + "\n```";
                ollamaChat.refreshItems();
            }
        }
    }

    // Streaming inference via Ollama's HTTP API. SplitParser fires on
    // each NDJSON line; we accumulate `response` fields into
    // previewText. Generation token drops stale chunks from a prior
    // dispatch when the user edits the prompt mid-stream.
    Process {
        id: chatProc
        running: false
        command: ["true"]
        property int gen: 0
        stdout: SplitParser {
            splitMarker: "\n"
            onRead: function (data) {
                if (chatProc.gen !== ollamaChat._gen) return;
                if (!data || data.length === 0) return;
                try {
                    const obj = JSON.parse(data);
                    if (typeof obj.response === "string" && obj.response.length > 0) {
                        ollamaChat.previewText += obj.response;
                    }
                } catch (e) {
                    // Non-JSON chunk (rare — curl status messages, empty
                    // lines on stream boundary). Silently skip.
                }
            }
        }
    }

}
