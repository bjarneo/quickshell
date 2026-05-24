import QtQuick
import QtQuick.Layouts
import Quickshell
import Quickshell.Wayland
import Quickshell.Io

// Game-mode HUD. A small cockpit panel that fades in whenever a focused
// window's class matches one of the configured game regexes (Hyprland's
// `activewindow` events from socket2). Click-through via empty input
// region, so the running game keeps mouse and keyboard focus untouched.
//
// Bind in Hyprland:
//   bind = SUPER SHIFT, G, exec, qs -c gamehud ipc call hud toggle
//
// Override the game regex list at:
//   ~/.config/quickshell/gamehud/games.json   {"classes":["^myGame$", ...]}
ShellRoot {
    id: root

    // ---- detection ----
    property var gameClassRegexes: [
        "^steam_app_\\d+$",
        "^gamescope$",
        "^cs2$",
        "^factorio$",
        "^dota2$",
        "^Minecraft.*",
        "^osu!$",
        "\\.exe$"
    ]
    property string focusedClass: ""
    property string focusedTitle: ""
    property bool inGame: false
    property bool forceShow: false
    readonly property bool shouldShow: forceShow || inGame

    function recompute() {
        const c = root.focusedClass;
        if (!c) { root.inGame = false; return; }
        for (let i = 0; i < gameClassRegexes.length; i++) {
            try {
                if (new RegExp(gameClassRegexes[i]).test(c)) { root.inGame = true; return; }
            } catch (e) { /* malformed entry, ignore */ }
        }
        root.inGame = false;
    }

    // ---- palette (omarchy reactivity) ----
    readonly property string colorsPath: Quickshell.env("HOME") + "/.config/omarchy/current/theme/colors.toml"
    readonly property string themeNamePath: Quickshell.env("HOME") + "/.config/omarchy/current/theme.name"
    property color paper:  "#181616"
    property color ink:    "#c5c9c5"
    property color sumi:   "#a6a69c"
    property color indigo: "#658594"
    property color seal:   "#c4746e"
    readonly property string mono: "JetBrainsMono Nerd Font"

    function parseColors(text) {
        const want = { background:null, foreground:null, accent:null, color1:null, color8:null };
        const re = /^\s*([A-Za-z_][A-Za-z0-9_]*)\s*=\s*"([^"]+)"/;
        const lines = text.split("\n");
        for (let i = 0; i < lines.length; i++) {
            const m = lines[i].match(re);
            if (m && (m[1] in want)) want[m[1]] = m[2];
        }
        if (want.background) root.paper  = want.background;
        if (want.foreground) root.ink    = want.foreground;
        if (want.color8)     root.sumi   = want.color8;
        if (want.accent)     root.indigo = want.accent;
        if (want.color1)     root.seal   = want.color1;
    }

    FileView {
        id: paletteFile
        path: root.colorsPath
        watchChanges: true
        onFileChanged: reload()
        onLoaded: root.parseColors(paletteFile.text())
    }
    // theme.name is rewritten in place when omarchy theme set runs; its
    // stable inode survives the rm+mv on the theme dir and lets us
    // re-prime paletteFile after the atomic swap.
    FileView {
        id: themeMarker
        path: root.themeNamePath
        watchChanges: true
        onFileChanged: { reload(); paletteFile.reload(); }
    }

    // ---- regex list source ----
    Process {
        id: cfgLoad
        running: true
        command: ["bash", "-lc",
              "f=\"$HOME/.config/quickshell/gamehud/games.json\"; "
            + "if [ -f \"$f\" ]; then cat \"$f\"; else echo '{}'; fi"]
        stdout: StdioCollector {
            onStreamFinished: {
                try {
                    const obj = JSON.parse(this.text);
                    if (obj && Array.isArray(obj.classes) && obj.classes.length > 0) {
                        root.gameClassRegexes = obj.classes;
                    }
                } catch (e) { console.warn("gamehud: bad games.json:", e); }
                root.recompute();
            }
        }
    }

    // ---- socket2 event stream ----
    // Python opens Hyprland's event socket and forwards each `event>>data`
    // line to stdout. Auto-revive on death so the HUD survives compositor
    // restarts.
    Process {
        id: hyprEvents
        running: true
        command: ["python3", "-u", "-c",
              "import os,socket,sys\n"
            + "p=os.environ['XDG_RUNTIME_DIR']+'/hypr/'+os.environ['HYPRLAND_INSTANCE_SIGNATURE']+'/.socket2.sock'\n"
            + "s=socket.socket(socket.AF_UNIX); s.connect(p)\n"
            + "f=s.makefile('r')\n"
            + "for ln in f:\n"
            + "    sys.stdout.write(ln); sys.stdout.flush()\n"]
        stdout: SplitParser {
            onRead: function(line) {
                const ix = line.indexOf(">>");
                if (ix < 0) return;
                const name = line.substring(0, ix);
                const data = line.substring(ix + 2);
                if (name === "activewindow") {
                    const c = data.indexOf(",");
                    if (c < 0) { root.focusedClass = data; root.focusedTitle = ""; }
                    else { root.focusedClass = data.substring(0, c); root.focusedTitle = data.substring(c + 1); }
                    root.recompute();
                } else if (name === "activewindowv2" && data === "") {
                    root.focusedClass = ""; root.focusedTitle = ""; root.recompute();
                } else if (name === "closewindow" || name === "movewindow") {
                    // No-op; activewindow will follow.
                }
            }
        }
        onRunningChanged: if (!running) eventsRevive.start()
    }
    Timer { id: eventsRevive; interval: 3000; onTriggered: hyprEvents.running = true }

    // Seed the focused class once at startup so the HUD is correct even
    // before the first activewindow event arrives.
    Process {
        running: true
        command: ["hyprctl", "-j", "activewindow"]
        stdout: StdioCollector {
            onStreamFinished: {
                try {
                    const o = JSON.parse(this.text);
                    if (o && typeof o === "object" && "class" in o) {
                        root.focusedClass = o["class"] || "";
                        root.focusedTitle = o.title || "";
                        root.recompute();
                    }
                } catch (e) { /* probably no focused window */ }
            }
        }
    }

    // ---- IPC ----
    IpcHandler {
        target: "hud"
        function show(): void { root.forceShow = true; }
        function hide(): void { root.forceShow = false; }
        function toggle(): void { root.forceShow = !root.forceShow; }
        function peek(): void { root.forceShow = true; peekTimer.restart(); }
        function reloadConfig(): void { cfgLoad.running = false; cfgLoad.running = true; }
    }
    Timer { id: peekTimer; interval: 4000; onTriggered: root.forceShow = false }

    // ---- metrics (only run while HUD is visible to save battery) ----
    property string cpuPct: "--"
    property string ramPct: "--"
    property string ramUsed: "--"
    property string gpuUtil: "--"
    property string gpuTemp: "--"
    property string gpuPwr: "--"
    property bool hasNvidia: false

    // CPU+RAM, 1s cadence. Reads /proc/stat twice 200ms apart for a usable
    // delta, then prints a single TSV line.
    Process {
        id: sysMetrics
        running: root.shouldShow
        command: ["bash", "-lc",
              "while :; do "
            + "  read _ u1 n1 s1 i1 io1 _ < <(grep -m1 ^cpu /proc/stat); "
            + "  sleep 0.4; "
            + "  read _ u2 n2 s2 i2 io2 _ < <(grep -m1 ^cpu /proc/stat); "
            + "  idle=$(( (i2+io2) - (i1+io1) )); "
            + "  tot=$(( (u2+n2+s2+i2+io2) - (u1+n1+s1+i1+io1) )); "
            + "  if [ $tot -gt 0 ]; then cpu=$(( (100 * (tot - idle)) / tot )); else cpu=0; fi; "
            + "  mem=$(awk '/MemTotal/{t=$2}/MemAvailable/{a=$2}END{printf \"%d %d\", (t-a)/1024, ((t-a)*100/t)}' /proc/meminfo); "
            + "  printf 'CPU=%d\\tMEM=%s\\n' \"$cpu\" \"$mem\"; "
            + "  sleep 0.6; "
            + "done"]
        stdout: SplitParser {
            onRead: function(line) {
                const parts = line.split("\t");
                for (let i = 0; i < parts.length; i++) {
                    const p = parts[i];
                    if (p.indexOf("CPU=") === 0) {
                        root.cpuPct = p.substring(4) + "%";
                    } else if (p.indexOf("MEM=") === 0) {
                        const v = p.substring(4).split(" ");
                        if (v.length >= 2) {
                            root.ramUsed = v[0] >= 1024 ? (Math.round(v[0] / 102.4) / 10) + "G"
                                                        : v[0] + "M";
                            root.ramPct = v[1] + "%";
                        }
                    }
                }
            }
        }
    }

    // Nvidia GPU. Skips silently if nvidia-smi is missing.
    Process {
        id: gpuMetrics
        running: root.shouldShow
        command: ["bash", "-lc",
              "command -v nvidia-smi >/dev/null 2>&1 || { echo NONVIDIA; exit 0; }; "
            + "echo NVIDIA; "
            + "while :; do "
            + "  nvidia-smi --query-gpu=utilization.gpu,temperature.gpu,power.draw "
            + "             --format=csv,noheader,nounits 2>/dev/null; "
            + "  sleep 2; "
            + "done"]
        stdout: SplitParser {
            onRead: function(line) {
                if (line === "NVIDIA")   { root.hasNvidia = true;  return; }
                if (line === "NONVIDIA") { root.hasNvidia = false; return; }
                const p = line.split(",");
                if (p.length >= 3) {
                    root.gpuUtil = p[0].trim() + "%";
                    root.gpuTemp = p[1].trim() + "°";
                    const w = parseFloat(p[2]);
                    root.gpuPwr  = isFinite(w) ? Math.round(w) + "W" : "--";
                }
            }
        }
    }

    // ---- surface ----
    PanelWindow {
        id: panel
        anchors { top: true; right: true }
        margins.top: 32
        margins.right: 32
        implicitWidth: 304
        implicitHeight: 132
        color: "transparent"
        exclusionMode: ExclusionMode.Ignore
        WlrLayershell.layer: WlrLayer.Overlay
        WlrLayershell.keyboardFocus: WlrKeyboardFocus.None
        WlrLayershell.namespace: "qs-gamehud"
        mask: Region {}  // input passes straight through to the game

        Rectangle {
            id: card
            anchors.fill: parent
            color: Qt.rgba(root.paper.r, root.paper.g, root.paper.b, 0.78)
            border.color: Qt.rgba(root.seal.r, root.seal.g, root.seal.b, 0.45)
            border.width: 1
            radius: 4
            opacity: root.shouldShow ? 1 : 0
            scale: root.shouldShow ? 1 : 0.96
            Behavior on opacity { NumberAnimation { duration: 220; easing.type: Easing.OutCubic } }
            Behavior on scale   { NumberAnimation { duration: 220; easing.type: Easing.OutCubic } }

            // Header: blinking dot, "GAME MODE", current class right-aligned.
            Item {
                id: hdr
                anchors.left: parent.left
                anchors.right: parent.right
                anchors.top: parent.top
                anchors.leftMargin: 14
                anchors.rightMargin: 14
                anchors.topMargin: 10
                height: 14

                Rectangle {
                    id: blip
                    width: 5; height: 5; radius: 3
                    color: root.seal
                    anchors.left: parent.left
                    anchors.verticalCenter: parent.verticalCenter
                    SequentialAnimation on opacity {
                        loops: Animation.Infinite
                        NumberAnimation { from: 1.0; to: 0.25; duration: 1100; easing.type: Easing.InOutSine }
                        NumberAnimation { from: 0.25; to: 1.0; duration: 1100; easing.type: Easing.InOutSine }
                    }
                }
                Text {
                    id: hdrLabel
                    anchors.left: blip.right; anchors.leftMargin: 10
                    anchors.verticalCenter: parent.verticalCenter
                    text: "GAME MODE"
                    color: root.ink
                    font.family: root.mono
                    font.pixelSize: 10
                    font.letterSpacing: 2.4
                }
                Rectangle {
                    anchors.left: hdrLabel.right; anchors.leftMargin: 10
                    anchors.right: classLabel.left; anchors.rightMargin: 10
                    anchors.verticalCenter: parent.verticalCenter
                    height: 1
                    color: root.sumi
                    opacity: 0.28
                }
                Text {
                    id: classLabel
                    anchors.right: parent.right
                    anchors.verticalCenter: parent.verticalCenter
                    text: root.focusedClass ? root.focusedClass.toLowerCase().substring(0, 16) : "idle"
                    color: root.sumi
                    font.family: root.mono
                    font.pixelSize: 9
                    font.italic: true
                    font.letterSpacing: 1
                }
            }

            // Metric grid: 3 columns x 2 rows.
            GridLayout {
                anchors.left: parent.left
                anchors.right: parent.right
                anchors.top: hdr.bottom
                anchors.bottom: parent.bottom
                anchors.leftMargin: 14
                anchors.rightMargin: 14
                anchors.topMargin: 10
                anchors.bottomMargin: 10
                columns: 3
                rowSpacing: 4
                columnSpacing: 14

                Repeater {
                    model: [
                        { label: "CPU", val: root.cpuPct, dim: false },
                        { label: "RAM", val: root.ramPct, dim: false },
                        { label: "MEM", val: root.ramUsed, dim: false },
                        { label: "GPU", val: root.gpuUtil, dim: !root.hasNvidia },
                        { label: "TMP", val: root.gpuTemp, dim: !root.hasNvidia },
                        { label: "PWR", val: root.gpuPwr,  dim: !root.hasNvidia }
                    ]
                    delegate: Item {
                        required property var modelData
                        Layout.fillWidth: true
                        Layout.preferredHeight: 36

                        Text {
                            id: lbl
                            anchors.left: parent.left
                            anchors.top: parent.top
                            text: modelData.label
                            color: root.sumi
                            opacity: modelData.dim ? 0.35 : 0.7
                            font.family: root.mono
                            font.pixelSize: 8
                            font.letterSpacing: 1.6
                        }
                        Text {
                            anchors.left: parent.left
                            anchors.top: lbl.bottom
                            anchors.topMargin: 2
                            text: modelData.dim ? "--" : modelData.val
                            color: modelData.dim ? root.sumi : root.ink
                            opacity: modelData.dim ? 0.35 : 1.0
                            font.family: root.mono
                            font.pixelSize: 16
                            font.italic: true
                        }
                    }
                }
            }
        }
    }
}
