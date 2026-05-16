import QtQuick
import QtQuick.Layouts
import Quickshell
import Quickshell.Wayland
import Quickshell.Io

// Omarchy top bar. Layout and typography are Kanagawa Dragon's — kanji
// workspaces, smoked sumi surface, autumn seal accents. Colours are
// reactive: they read ~/.config/omarchy/current/theme/colors.toml so the
// bar follows whatever omarchy theme is active.
ShellRoot {
    id: root

    // ---------- Theme path ----------
    readonly property string colorsPath: Quickshell.env("HOME") + "/.config/omarchy/current/theme/colors.toml"
    readonly property string themeNamePath: Quickshell.env("HOME") + "/.config/omarchy/current/theme.name"

    // ---------- Semantic palette (resolved from colors.toml) ----------
    // Names match the original Kanagawa Dragon mapping so the visual
    // hierarchy carries over to any palette:
    //   paper    = background          (bar surface base)
    //   ink      = foreground          (primary text)
    //   inkDeep  = color7              (secondary bright text)
    //   sumi     = color8              (muted/decorative)
    //   indigo   = accent              (info accent, e.g. low-battery warn)
    //   seal     = color1              (alert / active marker)
    property color paper:   "#181616"
    property color ink:     "#c5c9c5"
    property color inkDeep: "#c8c093"
    property color sumi:    "#a6a69c"
    property color indigo:  "#658594"
    property color seal:    "#c4746e"

    // Derived bar colours. bg is paper at 0.94; sep is ink at 0.18.
    readonly property color bg:     Qt.rgba(paper.r, paper.g, paper.b, 0.94)
    readonly property color fg:     ink
    readonly property color muted:  sumi
    readonly property color accent: seal
    readonly property color warn:   seal
    readonly property color sep:    Qt.rgba(ink.r, ink.g, ink.b, 0.18)

    readonly property string serif: "serif"
    readonly property string mono:  "JetBrainsMono Nerd Font"

    // Kanji numerals 〇 一 二 ... 十.
    readonly property var kanjiNum: ["〇","一","二","三","四","五","六","七","八","九","十"]
    function indexKanji(n) { return n >= 0 && n <= 10 ? kanjiNum[n] : String(n); }

    // BMP Private Use Area icons; written via fromCodePoint so the source
    // stays ASCII-safe.
    readonly property string icoOmarchy: String.fromCodePoint(0xe900)
    readonly property string icoBtOn:    String.fromCodePoint(0xf294)
    readonly property string icoVol1:    String.fromCodePoint(0xf026)
    readonly property string icoVol2:    String.fromCodePoint(0xf027)
    readonly property string icoVol3:    String.fromCodePoint(0xf028)
    readonly property string icoMute:    String.fromCodePoint(0xeee8)

    readonly property int barHeight: 26

    // ---------- State ----------
    property int activeWs: 1
    property var existingWs: [1, 2, 3, 4, 5]
    // +1 = user navigated to a higher-numbered workspace (rightward along
    // the bar), -1 = lower-numbered (leftward), 0 = no recent travel. The
    // active Workspace cell reads this to bias its kanji's entry offset.
    property int lastDirection: 0

    property int cpuVal: 0
    property int memVal: 0
    property int batVal: 0
    property string batState: "Unknown"

    property string netIcon: "󰤯"
    property string btIcon:  "󰂲"
    property string audioIcon: ""

    property string hh: "--"
    property string mm: "--"
    property string dd: "--"
    property string mon: "---"

    // ---------- Calendar popup state ----------
    property bool calendarVisible: false
    property int calendarMonthOffset: 0
    // Bumped on each open so the cells/title bindings below re-evaluate
    // (new Date() is opaque to QML's dependency tracker — touching this
    // int forces a recompute even when calendarMonthOffset is unchanged).
    property int calendarTick: 0

    readonly property var calendarCells: {
        root.calendarTick;
        const now = new Date();
        const m = now.getMonth() + root.calendarMonthOffset;
        const first = new Date(now.getFullYear(), m, 1);
        const lastDay = new Date(first.getFullYear(), first.getMonth() + 1, 0).getDate();
        // Monday-first week: shift Sunday (0) to slot 6.
        const startDay = (first.getDay() + 6) % 7;
        const today = new Date();
        const isCurrentMonth = first.getFullYear() === today.getFullYear()
                            && first.getMonth() === today.getMonth();
        const cells = [];
        for (let i = 0; i < startDay; i++) cells.push({day: 0, today: false});
        for (let d = 1; d <= lastDay; d++) {
            cells.push({day: d, today: isCurrentMonth && d === today.getDate()});
        }
        while (cells.length < 42) cells.push({day: 0, today: false});
        return cells;
    }

    readonly property string calendarTitle: {
        root.calendarTick;
        const months = ["JAN","FEB","MAR","APR","MAY","JUN","JUL","AUG","SEP","OCT","NOV","DEC"];
        const now = new Date();
        const d = new Date(now.getFullYear(), now.getMonth() + root.calendarMonthOffset, 1);
        return months[d.getMonth()] + " " + d.getFullYear();
    }

    function openCalendar() {
        root.calendarMonthOffset = 0;
        root.calendarTick++;
        root.calendarVisible = true;
    }

    // ---------- Palette loader ----------
    // Reads omarchy's colors.toml and re-applies the palette on any change.
    // The file is rewritten in place when `omarchy theme set` runs, so
    // FileView's inode watcher catches it without extra hooks.
    function parseColors(text) {
        const want = {
            background: null, foreground: null, accent: null,
            color1: null, color7: null, color8: null
        };
        const re = /^\s*([A-Za-z_][A-Za-z0-9_]*)\s*=\s*"([^"]+)"/;
        const lines = text.split("\n");
        for (let i = 0; i < lines.length; i++) {
            const m = lines[i].match(re);
            if (m && (m[1] in want)) want[m[1]] = m[2];
        }
        if (want.background) root.paper   = want.background;
        if (want.foreground) root.ink     = want.foreground;
        if (want.color7)     root.inkDeep = want.color7;
        if (want.color8)     root.sumi    = want.color8;
        if (want.accent)     root.indigo  = want.accent;
        if (want.color1)     root.seal    = want.color1;
    }

    FileView {
        id: paletteFile
        path: root.colorsPath
        watchChanges: true
        onFileChanged: reload()
        onLoaded: root.parseColors(paletteFile.text())
    }

    // omarchy-theme-set rm -rf's current/theme/ and mv's a fresh dir in, so
    // colors.toml gets a new inode each swap and paletteFile's inotify watch
    // dies with it. theme.name, by contrast, is rewritten in place (echo > )
    // so its inode is stable. Use it as a swap-detection beacon.
    FileView {
        id: themeMarker
        path: root.themeNamePath
        watchChanges: true
        onFileChanged: { reload(); paletteFile.reload(); }
    }

    // ---------- Generic launcher ----------
    Process { id: runner; running: false }
    function run(cmd) {
        runner.command = ["bash", "-lc", cmd];
        runner.running = false;
        runner.running = true;
    }

    // ---------- Telemetry (1 Hz) ----------
    Process {
        id: tel
        running: false
        command: ["bash", "-lc",
            "read _ a b c d _ < <(grep '^cpu ' /proc/stat); "
            + "sleep 0.15; "
            + "read _ e f g h _ < <(grep '^cpu ' /proc/stat); "
            + "du=$(( (e+f+g) - (a+b+c) )); dt=$(( (e+f+g+h) - (a+b+c+d) )); "
            + "cpu=$(( dt>0 ? du*100/dt : 0 )); "
            + "mem=$(awk '/MemTotal/{t=$2}/MemAvailable/{m=$2}END{printf \"%d\",(t-m)*100/t}' /proc/meminfo); "
            + "bat=0; bst=Unknown; "
            + "if [ -d /sys/class/power_supply/BAT0 ]; then "
            + "  bat=$(cat /sys/class/power_supply/BAT0/capacity 2>/dev/null || echo 0); "
            + "  bst=$(cat /sys/class/power_supply/BAT0/status 2>/dev/null || echo Unknown); "
            + "elif [ -d /sys/class/power_supply/BAT1 ]; then "
            + "  bat=$(cat /sys/class/power_supply/BAT1/capacity 2>/dev/null || echo 0); "
            + "  bst=$(cat /sys/class/power_supply/BAT1/status 2>/dev/null || echo Unknown); "
            + "fi; "
            + "printf '%d|%d|%d|%s|%s|%s|%s|%s' "
            + "  \"$cpu\" \"$mem\" \"$bat\" \"$bst\" "
            + "  \"$(date +%H)\" \"$(date +%M)\" \"$(date +%d)\" \"$(date +%b | tr a-z A-Z)\""]
        stdout: StdioCollector {
            onStreamFinished: {
                const p = this.text.split("|");
                if (p.length === 8) {
                    root.cpuVal = parseInt(p[0]) || 0;
                    root.memVal = parseInt(p[1]) || 0;
                    root.batVal = parseInt(p[2]) || 0;
                    root.batState = p[3] || "Unknown";
                    root.hh = p[4]; root.mm = p[5];
                    root.dd = p[6]; root.mon = p[7];
                }
            }
        }
    }
    Timer { interval: 1000; running: true; repeat: true; triggeredOnStart: true
        onTriggered: { tel.running = false; tel.running = true; } }

    // ---------- Workspaces (2 Hz) ----------
    Process {
        id: wsProbe
        running: false
        command: ["bash", "-lc",
            "act=$(hyprctl activeworkspace -j 2>/dev/null | sed -n 's/.*\"id\": *\\([0-9]*\\).*/\\1/p' | head -1); "
            + "ids=$(hyprctl workspaces -j 2>/dev/null | tr ',' '\\n' | sed -n 's/.*\"id\": *\\([0-9]*\\).*/\\1/p' | sort -nu | paste -sd,); "
            + "printf '%s|%s' \"${act:-1}\" \"${ids:-1}\""]
        stdout: StdioCollector {
            onStreamFinished: {
                const p = this.text.split("|");
                if (p.length === 2) {
                    const next = parseInt(p[0]) || 1;
                    // Set direction first; the Workspace delegates read it
                    // inside their onActiveChanged handlers, which fire as
                    // soon as we write activeWs below.
                    if (next > root.activeWs) root.lastDirection = 1;
                    else if (next < root.activeWs) root.lastDirection = -1;
                    root.activeWs = next;
                    const have = p[1].split(",").map(s => parseInt(s)).filter(n => !isNaN(n));
                    root.existingWs = [...new Set([...have, 1, 2, 3, 4, 5])].sort((a,b) => a-b).slice(0, 9);
                }
            }
        }
    }
    Timer { interval: 500; running: true; repeat: true; triggeredOnStart: true
        onTriggered: { wsProbe.running = false; wsProbe.running = true; } }

    // ---------- Network status ----------
    Process {
        id: netProbe
        running: false
        command: ["bash", "-lc",
            "type=none; "
            + "if ip -o addr show | grep -qE '^[0-9]+: (en|eth)[^ ]*.*inet '; then type=eth; fi; "
            + "if [ \"$type\" = none ]; then "
            + "  for w in $(iw dev 2>/dev/null | awk '/Interface/{print $2}'); do "
            + "    dbm=$(iw dev \"$w\" link 2>/dev/null | awk '/signal:/{print $2}'); "
            + "    if [ -n \"$dbm\" ]; then "
            + "      pct=$((2 * (dbm + 100))); "
            + "      [ $pct -lt 0 ] && pct=0; "
            + "      [ $pct -gt 100 ] && pct=100; "
            + "      type=wifi:$pct; break; "
            + "    fi; "
            + "  done; "
            + "fi; printf '%s' \"$type\""]
        stdout: StdioCollector {
            onStreamFinished: {
                const t = this.text.trim();
                if (t === "eth") root.netIcon = "󰀂";
                else if (t.startsWith("wifi:")) {
                    const sig = parseInt(t.split(":")[1]) || 0;
                    const ramp = ["󰤯","󰤟","󰤢","󰤥","󰤨"];
                    const idx = sig >= 80 ? 4 : sig >= 60 ? 3 : sig >= 40 ? 2 : sig >= 20 ? 1 : 0;
                    root.netIcon = ramp[idx];
                } else root.netIcon = "󰤮";
            }
        }
    }
    Timer { interval: 3000; running: true; repeat: true; triggeredOnStart: true
        onTriggered: { netProbe.running = false; netProbe.running = true; } }

    // ---------- Bluetooth status ----------
    Process {
        id: btProbe
        running: false
        command: ["bash", "-lc",
            "p=$(bluetoothctl show 2>/dev/null | grep -c 'Powered: yes' || echo 0); "
            + "c=$(bluetoothctl devices Connected 2>/dev/null | wc -l); "
            + "if [ \"$p\" = 0 ]; then echo off; "
            + "elif [ \"$c\" -gt 0 ]; then echo on-conn; "
            + "else echo on; fi"]
        stdout: StdioCollector {
            onStreamFinished: {
                const s = this.text.trim();
                if (s === "off") root.btIcon = "󰂲";
                else if (s === "on-conn") root.btIcon = "󰂱";
                else root.btIcon = root.icoBtOn;
            }
        }
    }
    Timer { interval: 5000; running: true; repeat: true; triggeredOnStart: true
        onTriggered: { btProbe.running = false; btProbe.running = true; } }

    // ---------- Audio status ----------
    // Icon ramps with volume: muted → icoMute, 0 → off, <50 → low, ≥50 → high.
    Process {
        id: audioProbe
        running: false
        command: ["bash", "-lc",
            "v=$(pamixer --get-volume 2>/dev/null || echo 0); "
            + "m=$(pamixer --get-mute 2>/dev/null || echo false); "
            + "printf '%s|%s' \"$v\" \"$m\""]
        stdout: StdioCollector {
            onStreamFinished: {
                const p = this.text.split("|");
                if (p.length !== 2) return;
                const v = parseInt(p[0]);
                const m = p[1].trim() === "true";
                if (m) {
                    root.audioIcon = root.icoMute;
                } else if (isNaN(v) || v <= 0) {
                    root.audioIcon = root.icoVol1;
                } else if (v < 50) {
                    root.audioIcon = root.icoVol2;
                } else {
                    root.audioIcon = root.icoVol3;
                }
            }
        }
    }
    Timer { interval: 2000; running: true; repeat: true; triggeredOnStart: true
        onTriggered: { audioProbe.running = false; audioProbe.running = true; } }

    // ---------- Battery icon helper ----------
    function batteryIcon() {
        const charging = root.batState === "Charging" || root.batState === "Full";
        const c = root.batVal;
        if (charging) {
            const r = ["󰢜","󰂆","󰂇","󰂈","󰢝","󰂉","󰢞","󰂊","󰂋","󰂅"];
            return r[Math.min(9, Math.floor(c / 10))];
        }
        const r = ["󰁺","󰁻","󰁼","󰁽","󰁾","󰁿","󰂀","󰂁","󰂂","󰁹"];
        return r[Math.min(9, Math.floor(c / 10))];
    }

    // ---------- Panel ----------
    PanelWindow {
        id: bar
        color: "transparent"
        anchors { top: true; left: true; right: true }
        implicitHeight: root.barHeight
        exclusiveZone: root.barHeight

        WlrLayershell.layer: WlrLayer.Top
        WlrLayershell.namespace: "omarchy-menu"

        Rectangle {
            anchors.fill: parent
            color: root.bg

            // Faint 静 (stillness) mark. Pure decoration.
            Text {
                anchors.right: parent.right
                anchors.rightMargin: 8
                anchors.verticalCenter: parent.verticalCenter
                text: "静"
                color: Qt.rgba(root.ink.r, root.ink.g, root.ink.b, 0.07)
                font.family: root.serif
                font.pixelSize: root.barHeight + 6
                font.weight: Font.Light
                z: 0
            }

            // Bottom hairline.
            Rectangle {
                anchors.left: parent.left
                anchors.right: parent.right
                anchors.bottom: parent.bottom
                height: 1
                color: root.sep
            }

            // Centre cluster: clock + date. z is bumped above the RowLayout
            // so the date's MouseArea isn't shadowed by the layout's
            // fill-width spacer occupying the same screen region.
            Row {
                anchors.horizontalCenter: parent.horizontalCenter
                anchors.verticalCenter: parent.verticalCenter
                spacing: 8
                z: 10

                Text {
                    anchors.verticalCenter: parent.verticalCenter
                    text: root.hh + ":" + root.mm
                    color: root.ink
                    font.family: root.mono
                    font.pixelSize: 12
                    font.letterSpacing: 2
                    font.weight: Font.Light
                }
                Rectangle {
                    anchors.verticalCenter: parent.verticalCenter
                    width: 1; height: 10
                    color: root.sumi
                    opacity: 0.4
                }
                Item {
                    id: dateItem
                    anchors.verticalCenter: parent.verticalCenter
                    // Pad outwards so the bloom (clipped to this item) has
                    // room around the glyph instead of just halo-ing inside
                    // the tight letterbox.
                    implicitWidth: dateText.implicitWidth + 12
                    implicitHeight: dateText.implicitHeight + 6

                    Bloom { id: dateBloom }

                    Text {
                        id: dateText
                        anchors.centerIn: parent
                        text: root.dd + " " + root.mon
                        color: dateMouse.containsMouse ? root.ink : root.sumi
                        font.family: root.mono
                        font.pixelSize: 10
                        font.letterSpacing: 2
                        font.italic: true
                        Behavior on color { ColorAnimation { duration: 180 } }
                    }

                    MouseArea {
                        id: dateMouse
                        anchors.fill: parent
                        hoverEnabled: true
                        cursorShape: Qt.PointingHandCursor
                        onEntered: dateBloom.fire(mouseX, mouseY)
                        onClicked: {
                            if (root.calendarVisible) root.calendarVisible = false;
                            else root.openCalendar();
                        }
                    }
                }
            }

            RowLayout {
                anchors.fill: parent
                anchors.leftMargin: 10
                anchors.rightMargin: 10
                spacing: 4

                Module {
                    glyph: root.icoOmarchy
                    color: root.seal
                    fontFamily: "omarchy"
                    fontSize: 14
                    onActivated: root.run("omarchy-menu")
                    onRightActivated: root.run("xdg-terminal-exec")
                }

                Separator {}

                Repeater {
                    model: 10
                    delegate: Workspace {
                        required property int index
                        wsId: index + 1
                        label: root.indexKanji(index + 1)
                        active: root.activeWs === (index + 1)
                        present: root.existingWs.indexOf(index + 1) !== -1
                        onActivated: root.run("hyprctl dispatch workspace " + (index + 1))
                    }
                }

                Item { Layout.fillWidth: true }

                Separator {}

                Module {
                    glyph: "󰍛"
                    color: root.cpuVal > 80 ? root.seal : root.ink
                    onActivated: root.run("omarchy-launch-or-focus-tui btop")
                }

                Module {
                    glyph: root.netIcon
                    onActivated: root.run("omarchy-launch-wifi")
                }

                Module {
                    glyph: root.btIcon
                    onActivated: root.run("omarchy-launch-bluetooth")
                }

                Module {
                    glyph: root.audioIcon
                    onActivated: root.run("omarchy-launch-audio")
                    onRightActivated: root.run("pamixer -t")
                }

                Module {
                    glyph: root.batteryIcon()
                    color: root.batVal <= 10 ? root.seal : root.batVal <= 20 ? root.indigo : root.ink
                    onActivated: root.run("omarchy-menu power")
                }
            }
        }
    }

    // ---------- Calendar popup ----------
    // Overlay layer that floats below the bar. ExclusionMode.Ignore so it
    // doesn't reserve space (it would shift the bar otherwise). The card
    // descends from the date on a thin seal-coloured thread — thread leads,
    // card trails — so the popup reads as something dropped from the bar.
    PanelWindow {
        id: calendarPopup
        // Stay alive while the close animation plays; once reveal decays
        // below the threshold the layer surface tears down.
        visible: root.calendarVisible || reveal > 0.001
        color: "transparent"
        anchors { top: true; left: true; right: true }
        implicitHeight: root.barHeight + 260
        exclusionMode: ExclusionMode.Ignore
        WlrLayershell.layer: WlrLayer.Overlay
        WlrLayershell.namespace: "omarchy-calendar"

        property real reveal: root.calendarVisible ? 1 : 0
        Behavior on reveal { NumberAnimation { duration: 260; easing.type: Easing.OutCubic } }

        // Thread leads (full extension by ~55% of the reveal), card trails
        // (starts emerging around 40%). Symmetrical on the way out.
        readonly property real threadProgress: Math.min(1, reveal / 0.55)
        readonly property real cardProgress:   Math.max(0, (reveal - 0.4) / 0.6)

        MouseArea {
            anchors.fill: parent
            onClicked: root.calendarVisible = false
        }

        // The "thread" — a 1px seal line that drops from just below the
        // bar, marking where the popup originated from.
        Rectangle {
            id: thread
            anchors.horizontalCenter: parent.horizontalCenter
            y: root.barHeight - 1
            width: 1
            height: 14 * calendarPopup.threadProgress
            color: root.seal
            opacity: calendarPopup.threadProgress
            antialiasing: true
        }

        // Tiny seal seed where the thread meets the card — a stitch.
        Rectangle {
            anchors.horizontalCenter: parent.horizontalCenter
            y: thread.y + thread.height - 1
            width: 3
            height: 3
            radius: 1.5
            color: root.seal
            opacity: calendarPopup.threadProgress
            antialiasing: true
        }

        Rectangle {
            id: card
            anchors.top: thread.bottom
            anchors.topMargin: 2
            anchors.horizontalCenter: parent.horizontalCenter
            width: 232
            height: cardCol.implicitHeight + 24
            color: root.bg
            border.color: root.sep
            border.width: 1
            radius: 0
            opacity: calendarPopup.cardProgress
            transformOrigin: Item.Top
            scale: 0.94 + 0.06 * calendarPopup.cardProgress

            // Swallow clicks on the card so they don't bubble to the outer
            // dismiss area.
            MouseArea { anchors.fill: parent }

            Column {
                id: cardCol
                anchors.fill: parent
                anchors.margins: 12
                spacing: 8

                // Header: month + year, with prev/next.
                Item {
                    width: parent.width
                    height: 22

                    Text {
                        id: monthLabel
                        anchors.left: parent.left
                        anchors.verticalCenter: parent.verticalCenter
                        text: root.calendarTitle
                        color: root.seal
                        font.family: root.serif
                        font.pixelSize: 14
                        font.letterSpacing: 2
                    }

                    Row {
                        anchors.right: parent.right
                        anchors.verticalCenter: parent.verticalCenter
                        spacing: 6

                        Text {
                            id: prevBtn
                            text: "‹"
                            color: prevMouse.containsMouse ? root.seal : root.ink
                            font.family: root.mono
                            font.pixelSize: 16
                            Behavior on color { ColorAnimation { duration: 120 } }
                            MouseArea {
                                id: prevMouse
                                anchors.fill: parent
                                anchors.margins: -4
                                hoverEnabled: true
                                cursorShape: Qt.PointingHandCursor
                                onClicked: { root.calendarMonthOffset--; root.calendarTick++; }
                            }
                        }

                        Text {
                            text: "•"
                            color: root.sumi
                            font.family: root.mono
                            font.pixelSize: 10
                            opacity: 0.5
                            MouseArea {
                                anchors.fill: parent
                                anchors.margins: -4
                                cursorShape: Qt.PointingHandCursor
                                onClicked: { root.calendarMonthOffset = 0; root.calendarTick++; }
                            }
                        }

                        Text {
                            id: nextBtn
                            text: "›"
                            color: nextMouse.containsMouse ? root.seal : root.ink
                            font.family: root.mono
                            font.pixelSize: 16
                            Behavior on color { ColorAnimation { duration: 120 } }
                            MouseArea {
                                id: nextMouse
                                anchors.fill: parent
                                anchors.margins: -4
                                hoverEnabled: true
                                cursorShape: Qt.PointingHandCursor
                                onClicked: { root.calendarMonthOffset++; root.calendarTick++; }
                            }
                        }
                    }
                }

                // Hairline under header.
                Rectangle {
                    width: parent.width
                    height: 1
                    color: root.sep
                }

                // Weekday row (Monday first).
                Grid {
                    columns: 7
                    rowSpacing: 0
                    columnSpacing: 0
                    width: parent.width

                    Repeater {
                        model: ["MO","TU","WE","TH","FR","SA","SU"]
                        delegate: Item {
                            required property string modelData
                            width: 28
                            height: 18
                            Text {
                                anchors.centerIn: parent
                                text: modelData
                                color: root.sumi
                                font.family: root.mono
                                font.pixelSize: 9
                                font.letterSpacing: 1
                            }
                        }
                    }
                }

                // Day grid: 6 rows of 7 cells.
                Grid {
                    columns: 7
                    rowSpacing: 0
                    columnSpacing: 0
                    width: parent.width

                    Repeater {
                        model: root.calendarCells
                        delegate: Item {
                            required property var modelData
                            width: 28
                            height: 24

                            Rectangle {
                                anchors.centerIn: parent
                                width: 22
                                height: 22
                                color: modelData.today ? root.seal : "transparent"
                                opacity: modelData.today ? 0.18 : 0
                                radius: 0
                            }
                            Text {
                                anchors.centerIn: parent
                                text: modelData.day === 0 ? "" : modelData.day
                                color: modelData.today ? root.seal : root.ink
                                opacity: modelData.day === 0 ? 0 : 1
                                font.family: root.mono
                                font.pixelSize: 11
                                font.weight: modelData.today ? Font.Medium : Font.Light
                            }
                        }
                    }
                }
            }
        }
    }

    // ---------- Components ----------
    component Separator: Rectangle {
        Layout.alignment: Qt.AlignVCenter
        Layout.preferredWidth: 1
        Layout.preferredHeight: 12
        Layout.leftMargin: 4
        Layout.rightMargin: 4
        color: root.sep
    }

    // Hover bloom: a soft accent-tinted halo that radiates from the cursor's
    // entry point and fades inside the item rect. Single-beat sibling of
    // clipboard-ripple — same halo/ox/oy/haloR/haloO vocabulary, just
    // scaled down for the bar (~250 ms, no inner core pulse) and clipped to
    // the host bounds so neighbours don't get splashed.
    component Bloom: Item {
        id: bloomRoot
        anchors.fill: parent
        clip: true

        property real ox: 0
        property real oy: 0
        property real haloR: 0
        property real haloO: 0

        function fire(x, y) {
            bloomRoot.ox = x;
            bloomRoot.oy = y;
            bloomAnim.restart();
        }

        Rectangle {
            width: bloomRoot.haloR * 2
            height: bloomRoot.haloR * 2
            radius: bloomRoot.haloR
            x: bloomRoot.ox - bloomRoot.haloR
            y: bloomRoot.oy - bloomRoot.haloR
            color: Qt.lighter(root.accent, 1.35)
            opacity: bloomRoot.haloO
            antialiasing: true
        }

        SequentialAnimation {
            id: bloomAnim
            ScriptAction { script: { bloomRoot.haloR = 0; bloomRoot.haloO = 0; } }
            ParallelAnimation {
                NumberAnimation {
                    target: bloomRoot; property: "haloR"
                    from: 2; to: Math.max(bloomRoot.width, bloomRoot.height) * 0.9
                    duration: 250
                    easing.type: Easing.OutCubic
                }
                SequentialAnimation {
                    NumberAnimation { target: bloomRoot; property: "haloO"; from: 0; to: 0.22; duration: 80; easing.type: Easing.OutQuad }
                    NumberAnimation { target: bloomRoot; property: "haloO"; to: 0; duration: 170; easing.type: Easing.InCubic }
                }
            }
        }
    }

    component Module: Item {
        property string glyph: ""
        property color color: root.ink
        property string fontFamily: root.mono
        property int fontSize: 12

        signal activated()
        signal rightActivated()

        Layout.alignment: Qt.AlignVCenter
        Layout.preferredWidth: 24
        Layout.preferredHeight: root.barHeight

        Rectangle {
            anchors.fill: parent
            anchors.topMargin: 3
            anchors.bottomMargin: 3
            radius: 0
            color: mouse.containsMouse ? Qt.rgba(root.ink.r, root.ink.g, root.ink.b, 0.08) : "transparent"
            Behavior on color { ColorAnimation { duration: 180 } }
        }

        Bloom { id: bloom }

        Text {
            anchors.centerIn: parent
            text: glyph
            color: parent.color
            font.family: parent.fontFamily
            font.pixelSize: parent.fontSize
        }

        MouseArea {
            id: mouse
            anchors.fill: parent
            hoverEnabled: true
            acceptedButtons: Qt.LeftButton | Qt.RightButton
            cursorShape: Qt.PointingHandCursor
            onEntered: bloom.fire(mouseX, mouseY)
            onClicked: (e) => {
                if (e.button === Qt.RightButton) parent.rightActivated();
                else parent.activated();
            }
        }
    }

    // Workspace cell.
    component Workspace: Item {
        id: wsCell
        property int wsId: 0
        property string label: ""
        property bool active: false
        property bool present: false
        signal activated()

        Layout.alignment: Qt.AlignVCenter
        Layout.preferredWidth: 20
        Layout.preferredHeight: root.barHeight

        // On becoming active, snap the kanji 2px in the direction of travel
        // (carousel-style: going right enters from the right, eases left),
        // then ease back to centre. The snap bypasses the Behavior by going
        // through an explicit NumberAnimation.
        onActiveChanged: {
            if (active && root.lastDirection !== 0) {
                slideHome.stop();
                kanji.slideX = root.lastDirection * 2;
                slideHome.start();
            }
        }

        NumberAnimation {
            id: slideHome
            target: kanji
            property: "slideX"
            to: 0
            duration: 180
            easing.type: Easing.OutCubic
        }

        Bloom { id: bloom }

        Text {
            id: kanji
            property real slideX: 0
            anchors.horizontalCenter: parent.horizontalCenter
            anchors.horizontalCenterOffset: slideX
            anchors.verticalCenter: parent.verticalCenter
            text: label
            color: active ? root.seal : (present ? root.ink : root.sumi)
            opacity: active ? 1.0 : (present ? 0.75 : 0.35)
            font.family: root.serif
            font.pixelSize: active ? 14 : 12
            font.weight: Font.Light
            Behavior on color { ColorAnimation { duration: 120 } }
            Behavior on opacity { NumberAnimation { duration: 120 } }
            Behavior on font.pixelSize { NumberAnimation { duration: 120 } }
        }

        MouseArea {
            anchors.fill: parent
            hoverEnabled: true
            cursorShape: Qt.PointingHandCursor
            onEntered: bloom.fire(mouseX, mouseY)
            onClicked: parent.activated()
        }
    }
}
