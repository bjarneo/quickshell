import QtQuick
import Quickshell
import Quickshell.Wayland
import Quickshell.Io

// Omarchy top bar. Layout and typography are Kanagawa Dragon's — kanji
// workspaces, smoked sumi surface, autumn seal accents. Colours are
// reactive: they read ~/.config/omarchy/current/theme/colors.toml so the
// bar follows whatever omarchy theme is active.
//
// shell.qml owns shared state, probes, helpers, and IPC. The visible
// surface area lives in per-feature files (Bar, *Popup, TooltipOverlay)
// and reusable widgets (Module, Workspace, Bloom, …), all wired through
// a single `root: root` property.
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
    // sealRaw is the palette-sourced value. seal is its drift-modulated
    // view: saturation rides driftAmount*0.05 above resting, which gets
    // pumped right after a theme swap and eases back over ~3s. Every
    // existing root.seal reference inherits the drift via this binding.
    property color sealRaw: "#c4746e"
    property real  driftAmount: 0
    readonly property color seal: Qt.hsva(
        sealRaw.hsvHue,
        Math.min(1, sealRaw.hsvSaturation + driftAmount * 0.05),
        sealRaw.hsvValue,
        sealRaw.a
    )

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
    readonly property string icoCamera:  String.fromCodePoint(0xf0100)
    readonly property string icoRefresh: String.fromCodePoint(0xf0450)
    readonly property string icoDisplay: String.fromCodePoint(0xf0379)
    readonly property string icoPower:   String.fromCodePoint(0xf0425)
    readonly property string icoAether:  String.fromCodePoint(0xf03d8)
    readonly property string icoFilm:    String.fromCodePoint(0xf0231)
    readonly property string icoSearch:  String.fromCodePoint(0xf0349)
    readonly property string icoUpdate:  String.fromCodePoint(0xf021)
    readonly property string icoPlug:    String.fromCodePoint(0xf06a5)

    readonly property int barHeight: 26

    // ---------- Edge ----------
    // Drives bar anchors, internal Row/Column flow, and where the toggle
    // arrow points.
    property string barEdge: "top"
    readonly property bool isHorizontal: barEdge === "top" || barEdge === "bottom"

    function cycleBarEdge() {
        const edges = ["top", "right", "bottom", "left"];
        root.barEdge = edges[(edges.indexOf(root.barEdge) + 1) % 4];
    }

    function edgeArrow() {
        return ({top: "↑", right: "→", bottom: "↓", left: "←"})[root.barEdge] || "?";
    }

    // ---------- Tooltips ----------
    // A single overlay panel reads these and renders the label near the
    // hovered icon. Positions are bar-window-local; the overlay translates
    // them into its own (full-screen) coordinate space based on barEdge.
    property string tooltipText: ""
    property real   tooltipBarX: 0
    property real   tooltipBarY: 0
    property bool   tooltipShown: false

    function showTooltip(text, x, y) {
        if (!text) return;
        root.tooltipText  = text;
        root.tooltipBarX  = x;
        root.tooltipBarY  = y;
        root.tooltipShown = true;
    }

    function hideTooltip(text) {
        // Guard against a late-fired hide from a module the cursor has
        // already left for another tooltip-bearing module.
        if (!text || root.tooltipText === text) root.tooltipShown = false;
    }

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
    // Instantaneous power draw in watts; magnitude only — direction is in batState.
    property real batPower: 0

    property string netIcon: "󰤯"
    property string netKind: "none"   // "eth" | "wifi" | "none"
    property string wifiSsid: ""
    property int    wifiSignal: 0
    property string btIcon:  "󰂲"
    property bool   btPowered: false
    property int    btCount: 0
    property string audioIcon: ""
    property int    audioVol: 0
    property bool   audioMuted: false

    // omarchy-update-available exits 0 when the local omarchy clone is
    // behind the latest tag. The bar surfaces a small refresh glyph next
    // to the battery for as long as that's the case; click → launch the
    // floating update terminal.
    property bool   omarchyUpdateAvailable: false
    property string omarchyLatestTag: ""

    function openOmarchyUpdate() {
        root.run("omarchy-launch-floating-terminal-with-presentation omarchy-update");
    }
    function refreshOmarchyUpdateCheck() {
        omarchyUpdateProbe.running = false;
        omarchyUpdateProbe.running = true;
    }

    property string hh: "--"
    property string mm: "--"
    property string dd: "--"
    property string mon: "---"

    // ---------- Screenshots popup state ----------
    property bool screenshotsVisible: false
    property int screenshotPage: 0
    readonly property int screenshotsPerPage: 12
    property var screenshotFiles: []
    property int selectedScreenshot: -1

    function openScreenshots() {
        root.screenshotPage = 0;
        root.selectedScreenshot = 0;
        screenshotProbe.running = false;
        screenshotProbe.running = true;
        root.screenshotsVisible = true;
    }

    function refreshScreenshots() {
        screenshotProbe.running = false;
        screenshotProbe.running = true;
    }

    // Move selection by `delta` thumbs along the grid's reading order;
    // wraps across pages when stepping off either edge.
    function moveScreenshotSelection(delta) {
        if (root.screenshotFiles.length === 0) return;
        const visible = root.visibleScreenshots;
        const next = root.selectedScreenshot + delta;
        if (next < 0 && root.screenshotPage > 0) {
            root.screenshotPage--;
            root.selectedScreenshot = Math.min(
                root.screenshotsPerPage - 1,
                root.screenshotFiles.length - root.screenshotPage * root.screenshotsPerPage - 1
            );
        } else if (next >= visible.length && root.screenshotPage < root.screenshotPageCount - 1) {
            root.screenshotPage++;
            root.selectedScreenshot = 0;
        } else if (next >= 0 && next < visible.length) {
            root.selectedScreenshot = next;
        }
    }

    // Row step (±4). Stays within the current page.
    function moveScreenshotRow(delta) {
        const visible = root.visibleScreenshots;
        const next = root.selectedScreenshot + delta * 4;
        if (next >= 0 && next < visible.length) root.selectedScreenshot = next;
    }

    function pageScreenshots(delta) {
        const next = root.screenshotPage + delta;
        if (next >= 0 && next < root.screenshotPageCount) {
            root.screenshotPage = next;
            root.selectedScreenshot = 0;
        }
    }

    function formatScreenshotLabel(path) {
        const m = String(path).match(/screenshot-(\d{4}-\d{2}-\d{2})_(\d{2})-(\d{2})-\d{2}\.[A-Za-z0-9]+$/);
        if (m) return m[1] + " " + m[2] + ":" + m[3];
        const parts = String(path).split("/");
        return parts[parts.length - 1];
    }

    // Empty slice while the popup is hidden so the Repeater delegates'
    // Image bindings drop their sources and stop holding decoded thumbs.
    readonly property var visibleScreenshots: {
        if (!root.screenshotsVisible) return [];
        const start = root.screenshotPage * root.screenshotsPerPage;
        return root.screenshotFiles.slice(start, start + root.screenshotsPerPage);
    }

    readonly property var selectedScreenshotEntry:
        root.selectedScreenshot >= 0 ? (root.visibleScreenshots[root.selectedScreenshot] || null) : null

    readonly property int screenshotPageCount: {
        if (root.screenshotFiles.length === 0) return 1;
        return Math.ceil(root.screenshotFiles.length / root.screenshotsPerPage);
    }

    // ---------- Videos popup state ----------
    property bool videosVisible: false
    property int videoPage: 0
    readonly property int videosPerPage: 12
    property var videoFiles: []
    property int selectedVideo: -1

    function openVideos() {
        root.videoPage = 0;
        root.selectedVideo = 0;
        videoProbe.running = false;
        videoProbe.running = true;
        root.videosVisible = true;
    }

    function refreshVideos() {
        videoProbe.running = false;
        videoProbe.running = true;
    }

    function moveVideoSelection(delta) {
        if (root.videoFiles.length === 0) return;
        const visible = root.visibleVideos;
        const next = root.selectedVideo + delta;
        if (next < 0 && root.videoPage > 0) {
            root.videoPage--;
            root.selectedVideo = Math.min(
                root.videosPerPage - 1,
                root.videoFiles.length - root.videoPage * root.videosPerPage - 1
            );
        } else if (next >= visible.length && root.videoPage < root.videoPageCount - 1) {
            root.videoPage++;
            root.selectedVideo = 0;
        } else if (next >= 0 && next < visible.length) {
            root.selectedVideo = next;
        }
    }

    function moveVideoRow(delta) {
        const visible = root.visibleVideos;
        const next = root.selectedVideo + delta * 4;
        if (next >= 0 && next < visible.length) root.selectedVideo = next;
    }

    function pageVideos(delta) {
        const next = root.videoPage + delta;
        if (next >= 0 && next < root.videoPageCount) {
            root.videoPage = next;
            root.selectedVideo = 0;
        }
    }

    function formatVideoLabel(path) {
        const parts = String(path).split("/");
        return parts[parts.length - 1];
    }

    function formatVideoDuration(secs) {
        const s = Math.max(0, Math.floor(Number(secs) || 0));
        if (s <= 0) return "";
        const h = Math.floor(s / 3600);
        const m = Math.floor((s % 3600) / 60);
        const ss = s % 60;
        const pad = (n) => String(n).padStart(2, "0");
        return h > 0 ? (h + ":" + pad(m) + ":" + pad(ss))
                     : (m + ":" + pad(ss));
    }

    function formatVideoSize(bytes) {
        const b = Number(bytes) || 0;
        if (b >= 1073741824) return (b / 1073741824).toFixed(1) + " GB";
        if (b >= 1048576)    return (b / 1048576).toFixed(0) + " MB";
        if (b >= 1024)       return (b / 1024).toFixed(0) + " KB";
        return b + " B";
    }

    function formatVideoMtime(secs) {
        if (!secs) return "";
        return Qt.formatDateTime(new Date(Number(secs) * 1000), "yyyy-MM-dd hh:mm");
    }

    readonly property var visibleVideos: {
        if (!root.videosVisible) return [];
        const start = root.videoPage * root.videosPerPage;
        return root.videoFiles.slice(start, start + root.videosPerPage);
    }

    readonly property var selectedVideoEntry:
        root.selectedVideo >= 0 ? (root.visibleVideos[root.selectedVideo] || null) : null

    readonly property int videoPageCount: {
        if (root.videoFiles.length === 0) return 1;
        return Math.ceil(root.videoFiles.length / root.videosPerPage);
    }

    // ---------- Aether popup state ----------
    // Lightweight quick-handle: a list of saved Aether blueprints with
    // colour-swatch previews. Click applies via `aether --apply-blueprint`,
    // so the heavy GUI only opens when explicitly requested.
    property bool aetherVisible: false
    property var  aetherBlueprints: []
    property int  selectedAether: -1
    property bool aetherLoading: false
    property string aetherQuery: ""

    // Case-insensitive substring filter on blueprint name. With 100+ saved
    // themes a small inline search is the only way to land on one in a
    // single keystroke or two.
    readonly property var aetherFiltered: {
        const q = root.aetherQuery.toLowerCase();
        if (q === "") return root.aetherBlueprints;
        return root.aetherBlueprints.filter(b =>
            String(b.name || "").toLowerCase().indexOf(q) !== -1
        );
    }

    function openAether() {
        root.aetherQuery = "";
        root.selectedAether = 0;
        root.aetherLoading = true;
        aetherProbe.running = false;
        aetherProbe.running = true;
        root.aetherVisible = true;
    }

    function moveAetherSelection(delta, wrap) {
        const n = root.aetherFiltered.length;
        if (n === 0) { root.selectedAether = -1; return; }
        const cur = root.selectedAether < 0 ? 0 : root.selectedAether;
        let next = cur + delta;
        if (wrap) {
            next = ((next % n) + n) % n;
        } else {
            if (next < 0) next = 0;
            else if (next >= n) next = n - 1;
        }
        root.selectedAether = next;
    }

    function applyAetherBlueprint(name) {
        if (!name) return;
        root.run("aether --apply-blueprint " + JSON.stringify(name));
        root.aetherVisible = false;
    }

    // Snap selection back to the top whenever the filter changes, so the
    // first match is always primed for Enter without a fresh j-press.
    onAetherQueryChanged: {
        root.selectedAether = root.aetherFiltered.length > 0 ? 0 : -1;
    }

    // ---------- Calendar popup state ----------
    property bool calendarVisible: false
    property int calendarMonthOffset: 0
    // Bumped on each open so the cells/title bindings below re-evaluate
    // (new Date() is opaque to QML's dependency tracker — touching this
    // int forces a recompute even when calendarMonthOffset is unchanged).
    property int calendarTick: 0

    // Easter Sunday for any Gregorian year via Butcher's anonymous algorithm.
    // Pure arithmetic, no loops; returns a Date in local time.
    function easterDate(year) {
        const a = year % 19;
        const b = Math.floor(year / 100);
        const c = year % 100;
        const d = Math.floor(b / 4);
        const e = b % 4;
        const f = Math.floor((b + 8) / 25);
        const g = Math.floor((b - f + 1) / 3);
        const h = (19 * a + b - d - g + 15) % 30;
        const i = Math.floor(c / 4);
        const k = c % 4;
        const l = (32 + 2 * e + 2 * i - h - k) % 7;
        const mm = Math.floor((a + 11 * h + 22 * l) / 451);
        const month = Math.floor((h + l - 7 * mm + 114) / 31);   // 3=Mar, 4=Apr
        const day = ((h + l - 7 * mm + 114) % 31) + 1;
        return new Date(year, month - 1, day);
    }

    // Norwegian red days. Caller passes precomputed `easter` (Date) so the
    // outer loop in calendarCells doesn't recompute it per day.
    function norwegianHoliday(year, month, day, easter) {
        if (month === 0  && day === 1)  return "Nyttårsdag";
        if (month === 4  && day === 1)  return "Arbeidernes dag";
        if (month === 4  && day === 17) return "Grunnlovsdagen";
        if (month === 11 && day === 25) return "Første juledag";
        if (month === 11 && day === 26) return "Andre juledag";

        const target = new Date(year, month, day);
        const offset = Math.round((target.getTime() - easter.getTime()) / 86400000);

        if (offset === -3) return "Skjærtorsdag";
        if (offset === -2) return "Langfredag";
        if (offset === 0)  return "Første påskedag";
        if (offset === 1)  return "Andre påskedag";
        if (offset === 39) return "Kristi himmelfartsdag";
        if (offset === 49) return "Første pinsedag";
        if (offset === 50) return "Andre pinsedag";

        return "";
    }

    readonly property var calendarCells: {
        root.calendarTick;  // forces recompute on same-month re-open
        const now = new Date();
        const first = new Date(now.getFullYear(), now.getMonth() + root.calendarMonthOffset, 1);
        const year = first.getFullYear();
        const month = first.getMonth();
        const lastDay = new Date(year, month + 1, 0).getDate();
        // Monday-first week: shift Sunday (0) to slot 6.
        const startDay = (first.getDay() + 6) % 7;
        const today = new Date();
        const isCurrentMonth = year === today.getFullYear() && month === today.getMonth();
        const easter = root.easterDate(year);
        const cells = [];
        for (let i = 0; i < startDay; i++) cells.push({day: 0, today: false, holiday: ""});
        for (let d = 1; d <= lastDay; d++) {
            cells.push({
                day: d,
                today: isCurrentMonth && d === today.getDate(),
                holiday: root.norwegianHoliday(year, month, d, easter)
            });
        }
        while (cells.length < 42) cells.push({day: 0, today: false, holiday: ""});
        return cells;
    }

    readonly property string calendarMonthName: {
        const months = ["JANUARY","FEBRUARY","MARCH","APRIL","MAY","JUNE",
                        "JULY","AUGUST","SEPTEMBER","OCTOBER","NOVEMBER","DECEMBER"];
        const now = new Date();
        return months[(now.getMonth() + root.calendarMonthOffset + 12000) % 12];
    }

    readonly property string calendarYear: {
        const now = new Date();
        const d = new Date(now.getFullYear(), now.getMonth() + root.calendarMonthOffset, 1);
        return String(d.getFullYear());
    }

    // Selected day-of-month within the displayed month; 0 = none. Reset
    // on month nav since the selection only makes sense within the
    // visible month.
    property int selectedDay: 0

    readonly property string selectedDayDetail: {
        if (root.selectedDay <= 0) return "";
        const days   = ["SUNDAY","MONDAY","TUESDAY","WEDNESDAY","THURSDAY","FRIDAY","SATURDAY"];
        const months = ["JAN","FEB","MAR","APR","MAY","JUN","JUL","AUG","SEP","OCT","NOV","DEC"];
        const now = new Date();
        const d = new Date(now.getFullYear(), now.getMonth() + root.calendarMonthOffset, root.selectedDay);
        return days[d.getDay()] + " · " + root.selectedDay + " " + months[d.getMonth()] + " " + d.getFullYear();
    }

    readonly property string selectedDayHoliday: {
        if (root.selectedDay <= 0) return "";
        const cells = root.calendarCells;
        for (let i = 0; i < cells.length; i++) {
            if (cells[i].day === root.selectedDay) return cells[i].holiday;
        }
        return "";
    }

    function openCalendar() {
        root.calendarMonthOffset = 0;
        root.calendarTick++;
        root.selectedDay = (new Date()).getDate();
        root.calendarVisible = true;
    }

    // ---------- Display popup state ----------
    // Held locally because hyprsunset has no `get` verb — we mirror values
    // so the slider tracks reflect what was last set, even across daemon
    // restarts.
    property bool  displayVisible: false
    property real  warmthK: 6500
    property int   brightnessPct: 100
    property real  gammaPct: 100
    property string monitorName: "eDP-1"
    property string monitorRes:  "2880x1800"
    property real  monitorRate:  60.0
    property real  monitorScale: 2.0
    readonly property var displayPresets: [
        { label: "DAY",     warmth: 6500, gamma: 100, bright: 100 },
        { label: "READING", warmth: 4500, gamma: 95,  bright: 60  },
        { label: "NIGHT",   warmth: 3000, gamma: 85,  bright: 30  },
        { label: "CANDLE",  warmth: 2000, gamma: 80,  bright: 15  }
    ]
    property int  selectedPreset: 0
    // ↑/↓ moves; ←/→ nudges sliders (0..2) or cycles the preset row (3).
    // Rows 4..6 are EDIT / BLANK / RESET — Enter activates.
    property int  displayRow: 0

    // First hyprsunset call spawns the daemon and waits for its socket; on
    // every later call the prelude collapses to a single pgrep test. Track
    // success so we can skip even that after one confirmed reply.
    property bool sunsetReady: false
    readonly property string ensureSunset:
        "pgrep -x hyprsunset >/dev/null"
        + " || { uwsm app -- hyprsunset --gamma_max 200 >/dev/null 2>&1 &"
        + "      for i in 1 2 3 4 5 6 7 8; do"
        + "        hyprctl hyprsunset identity >/dev/null 2>&1 && break;"
        + "        sleep 0.08;"
        + "      done; }; "

    function openDisplay() {
        displayProbe.running = true;
        root.displayRow = 0;
        root.displayVisible = true;
    }

    function runSunset(verb) {
        const cmd = "hyprctl hyprsunset " + verb;
        if (root.sunsetReady) root.run(cmd);
        else { root.run(root.ensureSunset + cmd); root.sunsetReady = true; }
    }

    function setWarmth(k) {
        k = Math.max(1000, Math.min(6500, Math.round(k / 50) * 50));
        root.warmthK = k;
        // identity skips the GPU matrix entirely at full daylight.
        root.runSunset(k >= 6500 ? "identity" : "temperature " + k);
    }
    function setBrightness(pct) {
        pct = Math.max(1, Math.min(100, Math.round(pct)));
        root.brightnessPct = pct;
        root.run("brightnessctl set " + pct + "%");
    }
    function setGamma(pct) {
        pct = Math.max(50, Math.min(150, Math.round(pct)));
        root.gammaPct = pct;
        root.runSunset("gamma " + pct);
    }
    function applyPreset(p) {
        root.warmthK = p.warmth;
        root.gammaPct = p.gamma;
        root.brightnessPct = p.bright;
        const w = (p.warmth >= 6500) ? "identity" : "temperature " + p.warmth;
        const prelude = root.sunsetReady ? "" : root.ensureSunset;
        root.run(prelude
                 + "hyprctl hyprsunset " + w
                 + " && hyprctl hyprsunset gamma " + p.gamma
                 + " && brightnessctl set " + p.bright + "%");
        root.sunsetReady = true;
    }
    function blankScreen() {
        // Wait out the close animation before the panel blanks, or the
        // reveal-out visibly stutters.
        root.run("sleep 0.25 && hyprctl dispatch dpms off");
        root.displayVisible = false;
    }
    function resetDisplay() {
        root.warmthK = 6500;
        root.gammaPct = 100;
        root.brightnessPct = 100;
        const prelude = root.sunsetReady ? "" : root.ensureSunset;
        root.run(prelude
                 + "hyprctl hyprsunset identity"
                 + " && hyprctl hyprsunset gamma 100"
                 + " && brightnessctl set 100%");
        root.sunsetReady = true;
    }

    // ---------- Display probe ----------
    Process {
        id: displayProbe
        running: false
        command: ["bash", "-lc",
            "m=$(hyprctl monitors -j 2>/dev/null"
            + " | jq -r '.[0] | [.name,(\"\\(.width)x\\(.height)\"),(.refreshRate|tostring),(.scale|tostring)] | join(\"|\")' 2>/dev/null);"
            + " b=$(brightnessctl get 2>/dev/null);"
            + " mb=$(brightnessctl max 2>/dev/null);"
            + " pct=100;"
            + " if [ -n \"$b\" ] && [ -n \"$mb\" ] && [ \"$mb\" -gt 0 ]; then pct=$(( b * 100 / mb )); fi;"
            + " printf '%s|%d' \"$m\" \"$pct\""]
        stdout: StdioCollector {
            onStreamFinished: {
                const p = this.text.trim().split("|");
                if (p.length < 5) return;
                root.monitorName   = p[0] || "eDP-1";
                root.monitorRes    = p[1] || "2880x1800";
                root.monitorRate   = parseFloat(p[2]) || 60.0;
                root.monitorScale  = parseFloat(p[3]) || 1.0;
                root.brightnessPct = parseInt(p[4]) || 100;
            }
        }
    }

    // ---------- Weather state ----------
    // Single curl to wttr.in?format=j1 backs both the bar glyph and the
    // popup. Refreshed every 30 minutes; right-click the bar icon to
    // force-refresh. The location is read from
    //   ~/.config/omarchy/weather/location
    // (a single line, e.g. "Oslo" or "lat,lon"). Empty file / missing
    // file means wttr.in falls back to IP geolocation. Click the place
    // name in the popup to open that file in the editor.
    readonly property string weatherLocationPath: Quickshell.env("HOME") + "/.config/omarchy/weather/location"
    property string weatherLocation: ""
    property bool   weatherVisible: false
    property bool   weatherLoaded: false
    property bool   weatherUnavailable: false
    property string weatherPlace: ""
    property real   weatherTempC: 0
    property real   weatherFeelsC: 0
    property int    weatherWindKmh: 0
    property string weatherWindDir: ""
    property int    weatherHumidity: 0
    property int    weatherUv: 0
    property string weatherDesc: ""
    property int    weatherCode: 0
    property string weatherSunrise: ""
    property string weatherSunset: ""
    property real   weatherHighC: 0
    property real   weatherLowC: 0
    property var    weatherForecast: []
    property string weatherUpdatedAt: ""

    // Mirrors omarchy-weather-icon's case statement so the bar glyph stays
    // honest when a manual location overrides IP geolocation. `night`
    // swaps the variants for codes that have one.
    function weatherGlyph(code, night) {
        const n = parseInt(code) || 0;
        if (n === 113) return String.fromCodePoint(night ? 0xe32b : 0xe30d);
        if (n === 116) return String.fromCodePoint(night ? 0xe32e : 0xe302);
        if (n === 119 || n === 122) return String.fromCodePoint(0xe33d);
        if (n === 143 || n === 248 || n === 260) return String.fromCodePoint(0xe313);
        if (n === 176 || n === 263 || n === 353) return String.fromCodePoint(night ? 0xe333 : 0xe308);
        if ([179,227,230,323,326,368].indexOf(n) !== -1) return String.fromCodePoint(night ? 0xe327 : 0xe30a);
        if ([182,185,281,284,311,314,317,320,350,362,365,374,377].indexOf(n) !== -1) return String.fromCodePoint(0xe3ad);
        if ([200,386,389,392,395].indexOf(n) !== -1) return String.fromCodePoint(0xe31d);
        if ([266,293,296,299,302,305,308,356,359].indexOf(n) !== -1) return String.fromCodePoint(0xe318);
        if ([329,332,335,338,371].indexOf(n) !== -1) return String.fromCodePoint(0xe31a);
        return String.fromCodePoint(0xe33d);
    }

    function parseClock(s) {
        const m = String(s).match(/^(\d{1,2}):(\d{2})\s*(AM|PM)?\s*$/i);
        if (!m) return -1;
        let h = parseInt(m[1]);
        const min = parseInt(m[2]);
        if (m[3]) {
            const pm = m[3].toUpperCase() === "PM";
            if (h === 12) h = pm ? 12 : 0;
            else if (pm) h += 12;
        }
        return h * 60 + min;
    }

    // Touching root.mm — the minute string from the 1Hz telemetry tick —
    // forces this binding to recompute when the clock rolls a minute, so
    // dusk flips the glyph without a fresh wttr fetch.
    readonly property bool weatherIsNight: {
        root.mm;
        const sr = root.parseClock(root.weatherSunrise);
        const ss = root.parseClock(root.weatherSunset);
        if (sr < 0 || ss < 0) return false;
        const now = new Date();
        const cur = now.getHours() * 60 + now.getMinutes();
        return cur < sr || cur >= ss;
    }
    readonly property string weatherIcon: root.weatherLoaded
        ? root.weatherGlyph(root.weatherCode, root.weatherIsNight)
        : ""

    function fmtTemp(c) {
        const v = Math.round(c);
        return (v > 0 ? "+" : "") + v + "°";
    }

    function openWeather() { root.weatherVisible = true; }
    function refreshWeather() { weatherProbe.running = true; }
    function editWeatherLocation() {
        root.run("mkdir -p \"$(dirname " + JSON.stringify(root.weatherLocationPath) + ")\""
                 + " && touch " + JSON.stringify(root.weatherLocationPath)
                 + " && omarchy-launch-editor " + JSON.stringify(root.weatherLocationPath));
        root.weatherVisible = false;
    }

    // ---------- Weather location file ----------
    FileView {
        id: weatherLocFile
        path: root.weatherLocationPath
        watchChanges: true
        onFileChanged: reload()
        onLoaded: {
            root.weatherLocation = weatherLocFile.text().trim();
            // false→true edge so an in-flight probe doesn't swallow the
            // new URL on a runtime location edit.
            weatherProbe.running = false;
            weatherProbe.running = true;
        }
    }

    // ---------- Weather probe ----------
    // wttr.in rate-limits; we cap at one fetch per 30 minutes plus
    // refresh-on-demand. The location segment is empty for auto-geo and
    // a URL-encoded city otherwise. encodeURIComponent keeps spaces and
    // diacritics safe so "São Paulo" or "New York" work without escaping
    // by hand.
    readonly property string weatherUrl: {
        const loc = root.weatherLocation;
        return "https://wttr.in/" + (loc ? encodeURIComponent(loc) : "") + "?format=j1";
    }
    Process {
        id: weatherProbe
        running: false
        command: ["bash", "-lc",
            "URL=" + JSON.stringify(root.weatherUrl) + ";"
            + " j=$(curl -fsS --max-time 5 \"$URL\" 2>/dev/null);"
            + " if [ -z \"$j\" ]; then printf 'ERR'; exit 0; fi;"
            + " data=$(printf '%s' \"$j\" | jq -r '"
            + "  .current_condition[0] as $c"
            + "  | .weather as $w"
            + "  | .nearest_area[0] as $a"
            + "  | [$a.areaName[0].value, $c.temp_C, $c.FeelsLikeC,"
            + "     $c.windspeedKmph, $c.winddir16Point, $c.humidity, $c.uvIndex,"
            + "     $c.weatherDesc[0].value, $c.weatherCode,"
            + "     $w[0].astronomy[0].sunrise, $w[0].astronomy[0].sunset,"
            + "     $w[0].maxtempC, $w[0].mintempC,"
            + "     $w[1].date, $w[1].maxtempC, $w[1].mintempC, $w[1].hourly[4].weatherCode,"
            + "     $w[2].date, $w[2].maxtempC, $w[2].mintempC, $w[2].hourly[4].weatherCode]"
            + "  | map(tostring) | join(\"|\")');"
            + " printf 'OK|%s' \"$data\""]
        stdout: StdioCollector {
            onStreamFinished: {
                const txt = this.text.trim();
                if (!txt.startsWith("OK|")) {
                    root.weatherUnavailable = true;
                    return;
                }
                const p = txt.substring(3).split("|");
                if (p.length < 21) {
                    root.weatherUnavailable = true;
                    return;
                }
                root.weatherPlace    = p[0];
                root.weatherTempC    = parseFloat(p[1]);
                root.weatherFeelsC   = parseFloat(p[2]);
                root.weatherWindKmh  = parseInt(p[3]);
                root.weatherWindDir  = p[4];
                root.weatherHumidity = parseInt(p[5]);
                root.weatherUv       = parseInt(p[6]);
                root.weatherDesc     = p[7];
                root.weatherCode     = parseInt(p[8]);
                root.weatherSunrise  = p[9];
                root.weatherSunset   = p[10];
                root.weatherHighC    = parseFloat(p[11]);
                root.weatherLowC     = parseFloat(p[12]);
                const days = [];
                for (let i = 0; i < 2; i++) {
                    const off = 13 + i * 4;
                    days.push({
                        day:  Qt.formatDate(new Date(p[off]), "ddd").toUpperCase(),
                        high: parseFloat(p[off + 1]),
                        low:  parseFloat(p[off + 2]),
                        code: parseInt(p[off + 3])
                    });
                }
                root.weatherForecast = days;
                const now = new Date();
                root.weatherUpdatedAt = String(now.getHours()).padStart(2,"0")
                                        + ":" + String(now.getMinutes()).padStart(2,"0");
                root.weatherLoaded = true;
                root.weatherUnavailable = false;
            }
        }
    }

    // Initial fetch is driven by weatherLocFile.onLoaded — this timer only
    // handles the half-hourly refresh once the bar is settled.
    Timer {
        interval: 1800000
        running: true
        repeat: true
        onTriggered: { weatherProbe.running = false; weatherProbe.running = true; }
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
        if (want.color1)     root.sealRaw = want.color1;
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
        // Restart the drift delay every swap. onFileChanged only fires on
        // inotify-driven changes (not on the initial load), so this is the
        // right place to detect "user just did `omarchy theme set`."
        onFileChanged: { reload(); paletteFile.reload(); driftDelay.restart(); }
    }

    // theme-wash's animation runs ~1.5s; wait it out so the saturation
    // bump lands as it exits, then rise quick and taper slow over ~3s.
    Timer {
        id: driftDelay
        interval: 1550
        repeat: false
        onTriggered: driftAnim.restart()
    }

    SequentialAnimation {
        id: driftAnim
        NumberAnimation {
            target: root; property: "driftAmount"
            from: 0; to: 1
            duration: 200
            easing.type: Easing.OutQuad
        }
        NumberAnimation {
            target: root; property: "driftAmount"
            to: 0
            duration: 2800
            easing.type: Easing.OutCubic
        }
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
            + "bat=0; bst=Unknown; pwr=0; "
            + "if [ -d /sys/class/power_supply/BAT0 ]; then "
            + "  bat=$(cat /sys/class/power_supply/BAT0/capacity 2>/dev/null || echo 0); "
            + "  bst=$(cat /sys/class/power_supply/BAT0/status 2>/dev/null || echo Unknown); "
            + "  pwr=$(cat /sys/class/power_supply/BAT0/power_now 2>/dev/null || echo 0); "
            + "elif [ -d /sys/class/power_supply/BAT1 ]; then "
            + "  bat=$(cat /sys/class/power_supply/BAT1/capacity 2>/dev/null || echo 0); "
            + "  bst=$(cat /sys/class/power_supply/BAT1/status 2>/dev/null || echo Unknown); "
            + "  pwr=$(cat /sys/class/power_supply/BAT1/power_now 2>/dev/null || echo 0); "
            + "fi; "
            + "pwr=${pwr#-}; "  // some kernels prefix '-' on discharge; magnitude is enough, sign comes from $bst
            + "printf '%d|%d|%d|%s|%s|%s|%s|%s|%d' "
            + "  \"$cpu\" \"$mem\" \"$bat\" \"$bst\" "
            + "  \"$(date +%H)\" \"$(date +%M)\" \"$(date +%d)\" \"$(date +%b | tr a-z A-Z)\" \"$pwr\""]
        stdout: StdioCollector {
            onStreamFinished: {
                const p = this.text.split("|");
                if (p.length === 9) {
                    root.cpuVal = parseInt(p[0]) || 0;
                    root.memVal = parseInt(p[1]) || 0;
                    root.batVal = parseInt(p[2]) || 0;
                    root.batState = p[3] || "Unknown";
                    root.hh = p[4]; root.mm = p[5];
                    root.dd = p[6]; root.mon = p[7];
                    root.batPower = (parseInt(p[8]) || 0) / 1e6;
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
            + "    link=$(iw dev \"$w\" link 2>/dev/null); "
            + "    dbm=$(printf '%s\\n' \"$link\" | awk '/signal:/{print $2}'); "
            + "    if [ -n \"$dbm\" ]; then "
            + "      pct=$((2 * (dbm + 100))); "
            + "      [ $pct -lt 0 ] && pct=0; "
            + "      [ $pct -gt 100 ] && pct=100; "
            + "      ssid=$(printf '%s\\n' \"$link\" | sed -n 's/^[[:space:]]*SSID: //p'); "
            + "      type=\"wifi:$pct:$ssid\"; break; "
            + "    fi; "
            + "  done; "
            + "fi; printf '%s' \"$type\""]
        stdout: StdioCollector {
            onStreamFinished: {
                const t = this.text.trim();
                if (t === "eth") {
                    root.netIcon = "󰀂"; root.netKind = "eth";
                    root.wifiSsid = ""; root.wifiSignal = 0;
                } else if (t.startsWith("wifi:")) {
                    // Split on the first two colons: signal pct, then SSID
                    // (which may itself contain colons, so a naive split
                    // would truncate networks like "Foo:Bar").
                    const rest = t.slice(5);
                    const c = rest.indexOf(":");
                    const sig = parseInt(c < 0 ? rest : rest.slice(0, c)) || 0;
                    const ssid = c < 0 ? "" : rest.slice(c + 1);
                    const ramp = ["󰤯","󰤟","󰤢","󰤥","󰤨"];
                    const idx = sig >= 80 ? 4 : sig >= 60 ? 3 : sig >= 40 ? 2 : sig >= 20 ? 1 : 0;
                    root.netIcon = ramp[idx]; root.netKind = "wifi";
                    root.wifiSignal = sig; root.wifiSsid = ssid;
                } else {
                    root.netIcon = "󰤮"; root.netKind = "none";
                    root.wifiSsid = ""; root.wifiSignal = 0;
                }
            }
        }
    }
    Timer { interval: 3000; running: true; repeat: true; triggeredOnStart: true
        onTriggered: { netProbe.running = false; netProbe.running = true; } }

    // ---------- Network burst detection ----------
    // Samples cumulative rx+tx bytes from /proc/net/dev once per second.
    // When the per-second delta crosses the threshold and the burst is
    // armed, emits netBurst() and disarms for `burstCooldown.interval` ms
    // so a sustained download doesn't keep retriggering — this should read
    // as a rare event, not a continuous activity light.
    signal netBurst()
    property real netPrevBytes: -1
    property bool burstArmed: false
    // First sample after startup seeds netPrevBytes; arm only after a
    // settling beat, otherwise the initial delta (counter vs 0) would
    // always fire.
    Timer { interval: 2500; running: true; repeat: false
        onTriggered: root.burstArmed = true }

    Process {
        id: netBurstProbe
        running: false
        // $2 is rx_bytes, $10 is tx_bytes per /proc/net/dev's column layout.
        // Skip loopback so localhost chatter doesn't count as "network".
        // Direct argv (no shell) — saves the per-poll login-shell startup.
        command: ["awk", "NR>2 && $1!~/^lo:/ {s+=$2+$10} END {print s+0}",
                  "/proc/net/dev"]
        stdout: StdioCollector {
            onStreamFinished: {
                const cur = parseFloat(this.text.trim());
                if (isNaN(cur)) return;
                if (root.netPrevBytes < 0) { root.netPrevBytes = cur; return; }
                const delta = cur - root.netPrevBytes;
                root.netPrevBytes = cur;
                // ~1.5 MB in a 1s sample window. Low enough that an active
                // download or stream paints the arc regularly, high enough
                // that idle browser chatter doesn't.
                if (root.burstArmed && delta > 1.5 * 1024 * 1024) {
                    root.burstArmed = false;
                    root.netBurst();
                    burstCooldown.restart();
                }
            }
        }
    }
    Timer { interval: 1000; running: true; repeat: true; triggeredOnStart: true
        onTriggered: { netBurstProbe.running = false; netBurstProbe.running = true; } }
    Timer { id: burstCooldown; interval: 2000; repeat: false
        onTriggered: root.burstArmed = true }

    // ---------- Idle dim ----------
    // Wayland ext-idle-notify-v1 via Quickshell. The compositor counts
    // pointer AND keyboard activity, so typing keeps the bar bright even
    // when the mouse hasn't moved. Once idle the rectangle eases to 0.7
    // opacity over 6s; the next input snaps it back over 60ms — slow
    // fade reads ambient, fast restore reads responsive.
    IdleMonitor {
        id: idleMonitor
        enabled: true
        timeout: 60
        respectInhibitors: true
    }
    readonly property bool isIdle: idleMonitor.isIdle

    // ---------- Bluetooth status ----------
    Process {
        id: btProbe
        running: false
        command: ["bash", "-lc",
            "p=$(bluetoothctl show 2>/dev/null | grep -c 'Powered: yes' || echo 0); "
            + "c=$(bluetoothctl devices Connected 2>/dev/null | wc -l); "
            + "if [ \"$p\" = 0 ]; then echo off; "
            + "else echo \"on:$c\"; fi"]
        stdout: StdioCollector {
            onStreamFinished: {
                const s = this.text.trim();
                if (s === "off") {
                    root.btIcon = "󰂲"; root.btPowered = false; root.btCount = 0;
                } else if (s.startsWith("on:")) {
                    const n = parseInt(s.slice(3)) || 0;
                    root.btPowered = true; root.btCount = n;
                    root.btIcon = n > 0 ? "󰂱" : root.icoBtOn;
                }
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
                root.audioVol = isNaN(v) ? 0 : v;
                root.audioMuted = m;
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

    // ---------- Omarchy update probe ----------
    // Mirrors waybar's custom/update: omarchy-update-available exits 0 and
    // prints "Omarchy update available (<tag>)" when behind, exits non-zero
    // otherwise. Network-bound (ls-remote), so the cadence matches waybar
    // at 6h; refreshOmarchyUpdateCheck() retriggers on demand.
    Process {
        id: omarchyUpdateProbe
        running: false
        command: ["omarchy-update-available"]
        stdout: StdioCollector { id: omarchyUpdateOut }
        onExited: (code, status) => {
            if (code === 0) {
                const m = omarchyUpdateOut.text.match(/\(([^)]+)\)/);
                root.omarchyLatestTag = m ? m[1] : "";
                root.omarchyUpdateAvailable = true;
            } else {
                root.omarchyUpdateAvailable = false;
                root.omarchyLatestTag = "";
            }
        }
    }
    Timer { interval: 21600000; running: true; repeat: true; triggeredOnStart: true
        onTriggered: root.refreshOmarchyUpdateCheck() }

    // ---------- Screenshots list probe ----------
    // Cap at 60 entries (~5 pages) so a screenshot-heavy ~/Pictures
    // doesn't keep dozens of decoded thumbs hot.
    Process {
        id: screenshotProbe
        running: false
        command: ["sh", "-c",
            "ls -t " + Quickshell.env("HOME") + "/Pictures/screenshot-*.png 2>/dev/null | head -60"]
        stdout: StdioCollector {
            onStreamFinished: {
                const lines = this.text.trim().split("\n").filter(s => s.length > 0);
                root.screenshotFiles = lines.map(p => ({
                    path: p,
                    label: root.formatScreenshotLabel(p)
                }));
                if (root.screenshotPage >= root.screenshotPageCount)
                    root.screenshotPage = 0;
                root.selectedScreenshot = root.visibleScreenshots.length > 0 ? 0 : -1;
            }
        }
    }

    // copiedPath stores the path (not the index) so the ack survives
    // paging or a list refresh that lands mid-flash.
    Process { id: shotCopier; running: false }
    property string copiedPath: ""
    Timer {
        id: copiedReset
        interval: 1400
        repeat: false
        onTriggered: root.copiedPath = ""
    }
    // Hold the popup open long enough for the seal-wash flash to bloom
    // in (~80ms snap + a beat of read time) before dismissing.
    Timer {
        id: copiedDismiss
        interval: 260
        repeat: false
        onTriggered: root.screenshotsVisible = false
    }
    function copyScreenshotToClipboard(path) {
        // -t image/png so GTK/Electron paste it as an image, not a path.
        shotCopier.command = ["sh", "-c", "wl-copy -t image/png < " + JSON.stringify(path)];
        shotCopier.running = false;
        shotCopier.running = true;
        root.copiedPath = path;
        copiedReset.restart();
        if (root.screenshotsVisible) copiedDismiss.restart();
    }

    // ---------- Videos list probe ----------
    // Cache layout: ~/.cache/quickshell-navbar/video-thumbs/<md5-of-path>.{jpg,meta}
    // where .meta holds the integer duration in seconds. Both are
    // re-generated when the source is newer (`-nt`); meta is what lets warm
    // opens skip the ffprobe spawn-storm. ffmpeg/ffprobe absence is tolerated
    // (badge hides at duration 0; cell falls back to the play glyph).
    //
    // Two passes: pass 1 fans out missing thumb/meta generation in parallel
    // via xargs -P; pass 2 emits one tab-separated row per video in mtime
    // order. Cold-open of 60 fresh videos drops from minutes to seconds on
    // any multi-core box; warm-open is just 60 stat+cat round-trips.
    Process {
        id: videoProbe
        running: false
        command: ["bash", "-c",
            "CDIR=\"$HOME/.cache/quickshell-navbar/video-thumbs\"; "
          + "mkdir -p \"$CDIR\" 2>/dev/null; "
          + "PATHS=$(find \"$HOME/Videos\" -maxdepth 3 -type f "
              + "\\( -iname '*.mp4' -o -iname '*.mkv' -o -iname '*.webm' "
              + "  -o -iname '*.mov' -o -iname '*.avi' -o -iname '*.m4v' \\) "
              + "-printf '%T@\\t%p\\n' 2>/dev/null | sort -rn | head -60 | cut -f2-); "
          + "printf '%s\\n' \"$PATHS\" | xargs -r -d '\\n' -P \"$(nproc 2>/dev/null || echo 4)\" -I{} "
              + "sh -c '"
                + "path=\"$1\"; cdir=\"$2\"; "
                + "key=$(printf %s \"$path\" | md5sum | cut -c1-32); "
                + "thumb=\"$cdir/$key.jpg\"; meta=\"$cdir/$key.meta\"; "
                + "if [ ! -f \"$thumb\" ] || [ \"$path\" -nt \"$thumb\" ]; then "
                  + "command -v ffmpeg >/dev/null 2>&1 && "
                  + "ffmpeg -y -ss 1 -i \"$path\" -frames:v 1 -vf scale=320:-1 -q:v 6 \"$thumb\" </dev/null >/dev/null 2>&1 || true; "
                + "fi; "
                + "if [ ! -f \"$meta\" ] || [ \"$path\" -nt \"$meta\" ]; then "
                  + "dur=$(ffprobe -v error -show_entries format=duration -of default=nw=1:nk=1 \"$path\" 2>/dev/null | awk \"{printf \\\"%d\\\",\\$1+0}\"); "
                  + "printf %s \"${dur:-0}\" > \"$meta\"; "
                + "fi"
              + "' _ {} \"$CDIR\"; "
          + "printf '%s\\n' \"$PATHS\" | while IFS= read -r path; do "
              + "[ -z \"$path\" ] && continue; "
              + "key=$(printf %s \"$path\" | md5sum | cut -c1-32); "
              + "thumb=\"$CDIR/$key.jpg\"; "
              + "dur=$(cat \"$CDIR/$key.meta\" 2>/dev/null); "
              + "mtime=$(stat -c %Y \"$path\" 2>/dev/null); "
              + "size=$(stat -c %s \"$path\" 2>/dev/null); "
              + "printf '%s\\t%s\\t%s\\t%s\\t%s\\n' \"$path\" \"$thumb\" \"${dur:-0}\" \"${mtime:-0}\" \"${size:-0}\"; "
          + "done"
        ]
        stdout: StdioCollector {
            onStreamFinished: {
                const lines = this.text.trim().split("\n").filter(s => s.length > 0);
                root.videoFiles = lines.map(line => {
                    const f = line.split("\t");
                    return {
                        path: f[0] || "",
                        thumb: f[1] || "",
                        duration: parseInt(f[2] || "0", 10),
                        mtime: parseInt(f[3] || "0", 10),
                        size: parseInt(f[4] || "0", 10),
                        label: root.formatVideoLabel(f[0] || "")
                    };
                });
                if (root.videoPage >= root.videoPageCount)
                    root.videoPage = 0;
                root.selectedVideo = root.visibleVideos.length > 0 ? 0 : -1;
            }
        }
    }

    Process { id: vidCopier; running: false }

    // Blueprint list for the Aether popup. `aether --list-blueprints --json`
    // emits {blueprints: [{name, colors[16], lightMode, wallpaper, timestamp}]}.
    // Sorted newest-first so freshly-saved themes surface at the top.
    Process {
        id: aetherProbe
        running: false
        command: ["aether", "--list-blueprints", "--json"]
        stdout: StdioCollector {
            onStreamFinished: {
                let arr = [];
                try {
                    const obj = JSON.parse(this.text);
                    arr = (obj.blueprints || []).slice();
                } catch (_) { arr = []; }
                arr.sort((a, b) => (Number(b.timestamp) || 0) - (Number(a.timestamp) || 0));
                root.aetherBlueprints = arr;
                root.aetherLoading = false;
                root.selectedAether = arr.length > 0 ? 0 : -1;
            }
        }
    }
    // copiedVideo = which path is flashing on the grid; copiedVideoMode tells
    // the footer which payload landed (file URI vs raw bytes).
    property string copiedVideo: ""
    property string copiedVideoMode: ""
    Timer {
        id: copiedVideoReset
        interval: 1400
        repeat: false
        onTriggered: { root.copiedVideo = ""; root.copiedVideoMode = ""; }
    }
    Timer {
        id: copiedVideoDismiss
        interval: 260
        repeat: false
        onTriggered: root.videosVisible = false
    }

    // URI-list copy. Targets: Kdenlive (Project Bin paste), file managers,
    // GIMP, OBS, Discord/Slack/Telegram *native* (not web). wl-copy auto-
    // promotes the payload to text/plain alongside text/uri-list, so plain
    // text fields also receive the file URI in one call.
    //
    // Re-trigger vidCopier with `cmd`, then trip the cell-flash / dismiss
    // timers under the given mode. Centralised so a future third copy
    // mode can't forget a timer restart.
    function _runVideoCopy(cmd, path, mode) {
        vidCopier.command = ["sh", "-c", cmd];
        vidCopier.running = false;
        vidCopier.running = true;
        root.copiedVideo = path;
        root.copiedVideoMode = mode;
        copiedVideoReset.restart();
        if (root.videosVisible) copiedVideoDismiss.restart();
    }

    // `-n` is load-bearing: without it, wl-copy appends an LF after our CRLF,
    // and strict text/uri-list parsers (Kdenlive) read the trailing empty
    // line as a phantom second URI and reject the whole payload.
    function copyVideoUri(path) {
        const uri = "file://" + encodeURI(path);
        root._runVideoCopy(
            "printf '%s\\r\\n' " + JSON.stringify(uri) + " | wl-copy -n --type text/uri-list",
            path, "file");
    }

    // Byte copy under the auto-detected MIME (video/mp4, video/webm, …).
    // Targets: web apps that accept clipboard file paste — Discord/Slack/
    // Telegram *web*, GitHub issue editor, Notion. wl-copy holds the file
    // bytes resident until something else replaces the clipboard, so the
    // selection memory cost is the video's file size.
    function copyVideoBytes(path) {
        root._runVideoCopy("wl-copy < " + JSON.stringify(path), path, "bytes");
    }

    // ---------- Battery icon helper ----------
    // "Not charging" covers plugged-in-but-topped-up laptops; "Full" is the
    // briefly-stable Charging→Full edge. Treat all three as AC-powered and
    // swap the battery ramp for a single plug glyph — once AC is in, the
    // % digit in the tooltip is the only number worth glancing at.
    function batteryIcon() {
        if (root.batState === "Charging"
            || root.batState === "Full"
            || root.batState === "Not charging") return root.icoPlug;
        const c = root.batVal;
        const r = ["󰁺","󰁻","󰁼","󰁽","󰁾","󰁿","󰂀","󰂁","󰂂","󰁹"];
        return r[Math.min(9, Math.floor(c / 10))];
    }

    // ---------- Surfaces ----------
    Bar              { root: root }
    TooltipOverlay   { root: root }
    CalendarPopup    { root: root }
    ScreenshotsPopup { root: root }
    VideosPopup      { root: root }
    AetherPopup      { root: root }
    DisplayPopup     { root: root }
    WeatherPopup     { root: root }

    // ---------- IPC ----------
    // Lets external keybinds drive the screenshots popup. Wire up in
    // hyprland with e.g.:
    //   bind = SUPER, P, exec, qs ipc call screenshots toggle
    IpcHandler {
        target: "screenshots"
        function toggle(): void {
            if (root.screenshotsVisible) root.screenshotsVisible = false;
            else root.openScreenshots();
        }
        function open(): void { root.openScreenshots(); }
        function close(): void { root.screenshotsVisible = false; }
    }

    // bind = SUPER, V, exec, qs ipc call videos toggle
    IpcHandler {
        target: "videos"
        function toggle(): void {
            if (root.videosVisible) root.videosVisible = false;
            else root.openVideos();
        }
        function open(): void { root.openVideos(); }
        function close(): void { root.videosVisible = false; }
    }

    // bind = SUPER, W, exec, qs ipc call weather toggle
    IpcHandler {
        target: "weather"
        function toggle(): void {
            if (root.weatherVisible) root.weatherVisible = false;
            else root.openWeather();
        }
        function open(): void    { root.openWeather(); }
        function close(): void   { root.weatherVisible = false; }
        function refresh(): void { root.refreshWeather(); }
    }

    // bind = SUPER, A, exec, qs ipc call aether toggle
    IpcHandler {
        target: "aether"
        function toggle(): void {
            if (root.aetherVisible) root.aetherVisible = false;
            else root.openAether();
        }
        function open(): void  { root.openAether(); }
        function close(): void { root.aetherVisible = false; }
    }

    // bind = SUPER, D, exec, qs ipc call display toggle
    IpcHandler {
        target: "display"
        function toggle(): void {
            if (root.displayVisible) root.displayVisible = false;
            else root.openDisplay();
        }
        function open(): void  { root.openDisplay(); }
        function close(): void { root.displayVisible = false; }
        function reset(): void { root.resetDisplay(); }
        function blank(): void { root.blankScreen(); }
    }
}
