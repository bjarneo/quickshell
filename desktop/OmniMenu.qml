import QtQuick
import QtQuick.Layouts
import QtQuick.Effects
import Quickshell
import Quickshell.Wayland
import Quickshell.Io
import Quickshell.Hyprland
import "Data.js" as Data

// Omni-menu palette. Fuses installed apps (.desktop scan) with every
// `omarchy-menu` action, scored against title, category, and per-entry
// synonyms (so "wallpaper" finds Background, "reboot" finds Restart).
// Drill-down rows pivot the list to a category, fd file search, gh repo
// search, processes, or themes. Toggle via:
//   qs -c desktop ipc call palette toggle
Item {
    id: root

    required property var theme
    // Navbar instance handed in from shell.qml. Used by Quick mode to
    // bind live telemetry (battery, audio, network, bluetooth, weather,
    // …) into the tile grid. Optional so OmniMenu can still load without
    // a navbar (e.g. headless config); Quick tiles fall back to "—" then.
    // Named `navbar` to avoid colliding with the existing `nav: []`
    // category-row array further down.
    property var navbar: null

    readonly property color paper:   theme.paper
    readonly property color ink:     theme.ink
    readonly property color inkDeep: theme.inkDeep
    readonly property color sumi:    theme.inkDeep
    readonly property color indigo:  theme.indigo
    readonly property color seal:    theme.seal
    readonly property color bg:      theme.bg
    readonly property color fg:      theme.fg
    readonly property color muted:   theme.muted
    readonly property color sep:     theme.sep
    readonly property color rowHi:   theme.rowHi
    readonly property color rowSel:  theme.rowSel

    // Scoring weights and result cap. omarchy-menu has ~125 entries plus the
    // 12 nav rows plus ~80-200 .desktop apps, so the cap lets a quick
    // page-down still reach near-matches without overdrawing.
    readonly property int scPrefix: 100
    readonly property int scTitle:  60
    readonly property int scKw:     20
    readonly property int scCat:    10
    readonly property int maxResults: 250

    readonly property string mono:  theme.mono
    readonly property string serif: theme.serif

    readonly property int cornerRadius: theme.cornerRadius

    // Sources that feed `allItems`. AppScan reads .desktop files;
    // NavbarApps probes the navbar shell for its IpcHandler widgets and
    // surfaces only the ones it actually exposes (so users on a
    // navbar-less setup see nothing instead of broken rows).
    AppScan { id: appScan }
    NavbarApps { id: navbarApps }
    Tuis { id: tuis }
    readonly property alias appsLoaded: appScan.loaded

    // ---------- Visibility / state ----------
    // Trailing underscore avoids shadowing Item.visible — read by the
    // PanelWindow's visibility binding below.
    property bool visible_: false
    property string query: ""
    property int selectedIndex: 0
    // Active drill-down. "" means root (category navigators + everything
    // searchable); any other value pins the list to that category. Set by
    // activating a category nav row; cleared by Esc / Backspace-on-empty.
    property string categoryFilter: ""

    // File and GitHub search drills reuse the category machinery: the
    // Files/GitHub nav rows set categoryFilter to one of Data's sentinels,
    // filteredItems pivots to the matching results array, and goUp/Esc
    // unwind via the same path as any other category.
    readonly property bool fileMode: root.categoryFilter === Data.fileCategory
    readonly property bool ghMode:   root.categoryFilter === Data.ghCategory
    readonly property bool favMode:  root.categoryFilter === Data.favCategory
    readonly property bool histMode: root.categoryFilter === Data.histCategory
    readonly property bool procMode:  root.categoryFilter === Data.procCategory
    readonly property bool themeMode: root.categoryFilter === Data.themeCategory
    // Quick mode swaps the result list for a live-tile grid. Tiles bind
    // to nav telemetry for instantaneous state; clicking one drops an
    // expanded detail panel below the grid with that tile's adjustments.
    readonly property bool quickMode: root.categoryFilter === "Quick"
    // Query-shape mode: `$ rg` pivots to an inline tldr preview. Lives
    // alongside the category drills but triggers off the query itself,
    // so the user can pivot in from any drill without going to root.
    readonly property bool tldrMode: root.query.charAt(0) === "$"
    // null = no expansion; otherwise the tile object whose detail panel
    // is currently revealed under the grid.
    property var expandedTile: null
    // Single source of truth for "in Quick mode with a tile open" — the
    // grid column count, the compressed-tile flag, and the side-panel
    // visibility all key off it.
    readonly property bool quickExpanded: quickMode && expandedTile !== null
    readonly property int  quickGridCols: quickExpanded ? 1 : 4
    function expandTile(t) {
        if (!t) { root.expandedTile = null; return; }
        // Click same tile to collapse; click a different tile to swap.
        root.expandedTile = (root.expandedTile && root.expandedTile.key === t.key)
                            ? null : t;
    }
    function collapseTile() { root.expandedTile = null; }

    Bookmarks { id: bookmarks }

    // ---------- Quick tiles ----------
    // Split into a *static* base array (the Repeater's model) and a
    // *dynamic* dict of per-tile live data, indexed by tile.key. The
    // base never changes, so the Repeater's 12 delegates are built once
    // and never torn down — clicks and hover state survive across
    // navbar ticks. Dynamic fields (glyph/label/sub/tone) read out of
    // `quickTilesDyn` via the `tileDyn()` helper; when the dict swaps,
    // only the delegate's text/color bindings re-evaluate. Order
    // matches the Samsung-style quick panel — most glanced
    // (battery/audio/wifi/bt) first.
    readonly property var quickTilesBase: [
        { key: "battery",     keywords: "battery power charge plugged ac percent watt",
          action: "omarchy-menu power" },
        { key: "audio",       keywords: "audio sound speaker volume mute pulse pipewire",
          action: "omarchy-launch-audio", longAction: "pamixer -t" },
        { key: "network",     keywords: "wifi wireless network internet ssid signal ethernet eth",
          action: "omarchy-launch-wifi" },
        { key: "bluetooth",   keywords: "bluetooth bt pair device headset speaker keyboard",
          action: "omarchy-launch-bluetooth" },
        { key: "weather",     keywords: "weather forecast temperature wttr rain sun wind",
          action: "qs -c desktop ipc call weather toggle",
          longAction: "qs -c desktop ipc call weather refresh" },
        { key: "display",     keywords: "display monitor brightness warmth gamma night light blue temperature dim",
          action: "qs -c desktop ipc call display toggle",
          longAction: "qs -c desktop ipc call display reset" },
        { key: "aether",      keywords: "aether theme blueprint palette swatch picker wallpaper",
          action: "qs -c desktop ipc call aether toggle",
          longAction: "sh -c 'aether --generate \"$(aether --random-wallpaper)\"'" },
        { key: "cpu",         keywords: "cpu processor memory monitor btop top htop performance load",
          action: "omarchy-launch-or-focus-tui btop" },
        { key: "calendar",    keywords: "calendar date month day today schedule planner",
          action: "qs -c desktop ipc call calendar toggle" },
        { key: "screenshots", keywords: "screenshots shots browse pictures captures images gallery",
          action: "qs -c desktop ipc call screenshots toggle",
          longAction: "omarchy-capture-screenshot" },
        { key: "videos",      keywords: "videos films clips recordings browse gallery library",
          action: "qs -c desktop ipc call videos toggle" },
        { key: "power",       keywords: "power menu suspend hibernate logout restart shutdown lock",
          action: "omarchy-menu power" }
    ]

    // Dynamic per-tile data — keyed by tile.key. Gated on `visible_`
    // so navbar ticks don't wake the rebuild while the palette is
    // closed (the previous snapshot keeps the Repeater happy when the
    // user re-opens, before this binding re-evaluates).
    property var _quickTilesDynCache: ({})
    readonly property var quickTilesDyn: {
        if (!root.visible_) return root._quickTilesDynCache;
        const n = root.navbar;
        if (!n) return ({});
        const chargingTag = n.batState === "Charging"    ? " · CHARGING"
                          : n.batState === "Full"        ? " · FULL"
                          : n.batState === "Not charging" ? " · PLUGGED"
                          : "";
        const dyn = {
            battery: {
                glyph: n.batteryIcon(),
                label: "BATTERY",
                sub: n.batVal + "%" + chargingTag
                     + (n.batPower >= 0.05
                        ? "  " + n.batPower.toFixed(1) + "W"
                        : ""),
                tone: n.batVal <= 10 ? n.seal
                                     : n.batVal <= 20 ? n.indigo
                                                      : n.ink
            },
            audio: {
                glyph: n.audioIcon,
                label: "AUDIO",
                sub: n.audioMuted ? "MUTED" : (n.audioVol + "%"),
                tone: n.audioMuted ? n.seal : n.ink
            },
            network: {
                glyph: n.netIcon,
                label: n.netKind === "wifi" ? "WI-FI"
                       : n.netKind === "eth"  ? "ETHERNET"
                                              : "OFFLINE",
                sub: n.netKind === "wifi"
                     ? ((n.wifiSsid || "(hidden)") + " · " + n.wifiSignal + "%")
                     : n.netKind === "eth" ? "CONNECTED" : "—",
                tone: n.netKind === "none" ? n.inkDeep : n.ink
            },
            bluetooth: {
                glyph: n.btIcon,
                label: "BLUETOOTH",
                sub: !n.btPowered ? "OFF"
                                  : (n.btCount > 0 ? n.btCount + " CONN" : "ON"),
                tone: !n.btPowered ? n.inkDeep : n.ink
            },
            weather: {
                glyph: n.weatherUnavailable ? "?"
                     : (n.weatherLoaded ? n.weatherIcon : "·"),
                label: "WEATHER",
                sub: n.weatherUnavailable ? "OFFLINE"
                     : (n.weatherLoaded ? Math.round(n.weatherTempC) + "°C" : "…"),
                tone: n.weatherUnavailable ? n.inkDeep : n.ink
            },
            display: {
                glyph: n.icoDisplay,
                label: "DISPLAY",
                sub: n.brightnessPct + "%"
                     + (n.warmthK < 6500 ? "  " + n.warmthK + "K" : ""),
                tone: (n.warmthK < 6500 || n.gammaPct !== 100 || n.brightnessPct < 100)
                      ? n.seal : n.ink
            },
            aether:      { glyph: n.icoAether, label: "AETHER", sub: "THEMES", tone: n.ink },
            cpu: {
                glyph: "󰍛",
                label: "CPU",
                sub: Math.round(n.cpuVal) + "%",
                tone: n.cpuVal > 80 ? n.seal : n.ink
            },
            calendar:    { glyph: "󰃭",          label: "CALENDAR",    sub: n.dd + " " + n.mon, tone: n.ink },
            screenshots: { glyph: n.icoCamera,  label: "SHOTS",       sub: "BROWSE",           tone: n.ink },
            videos:      { glyph: n.icoFilm,    label: "VIDEOS",      sub: "BROWSE",           tone: n.ink },
            power:       { glyph: n.icoPower,   label: "POWER",       sub: "MENU",             tone: n.ink }
        };
        root._quickTilesDynCache = dyn;
        return dyn;
    }

    // Resolve the dynamic side of a base tile. Returns an empty object
    // (not undefined) so delegate bindings can chain `.glyph` / `.sub`
    // without an `?.` chain on every read.
    function tileDyn(t) { return (t && root.quickTilesDyn[t.key]) || ({}); }

    // No search field in quickMode — tiles are always the full set so
    // grid arithmetic (gridCols * row) stays predictable. Kept as a
    // separate property so non-quick code paths don't need to branch.
    readonly property var filteredQuickTiles: root.quickTilesBase

    // Same launch envelope as activate() so popup IPCs (qs ipc call …)
    // get fired off-process and quickshell can close immediately.
    function activateQuickTile(t) {
        if (!t || !t.action) return;
        runner.command = ["sh", "-c",
                          "setsid -f uwsm-app -- bash -c "
                          + JSON.stringify(t.action)
                          + " >/dev/null 2>&1"];
        runner.running = false;
        runner.running = true;
        root.close();
    }

    // Long-press / right-click hook. Stays open so a "refresh weather"
    // or "reset display" doesn't dismiss the panel mid-glance.
    function longQuickTile(t) {
        if (!t || !t.longAction) return;
        runner.command = ["sh", "-c",
                          "setsid -f uwsm-app -- bash -c "
                          + JSON.stringify(t.longAction)
                          + " >/dev/null 2>&1"];
        runner.running = false;
        runner.running = true;
    }

    // gh CLI-backed repo search + README preview.
    GhSearch {
        id: ghSearch
        query: root.query
        active: root.ghMode && !root.tldrMode
        selectedItem: root.filteredItems[root.selectedIndex] || null
    }
    readonly property alias ghReady:        ghSearch.ready
    readonly property alias ghItems:        ghSearch.items
    readonly property alias ghRunning:      ghSearch.running
    readonly property alias previewRepo:    ghSearch.previewRepo
    readonly property alias previewRepoUrl: ghSearch.previewRepoUrl
    readonly property alias previewReadme:  ghSearch.previewReadme

    readonly property string sectionIcon: {
        if (root.categoryFilter === "") return "";
        for (let i = 0; i < Data.categoryNav.length; i++) {
            if (Data.categoryNav[i].target === root.categoryFilter)
                return Data.categoryNav[i].icon;
        }
        return "";
    }

    // fd-backed file search + file preview. Aliases mirror the prior root
    // properties so the panel UI doesn't have to change wholesale.
    FileSearch {
        id: fileSearch
        query: root.query
        queryTokens: root.queryTokens
        active: root.fileMode && !root.tldrMode
        selectedItem: root.filteredItems[root.selectedIndex] || null
    }
    readonly property alias fileItems:    fileSearch.items
    readonly property alias fdRunning:    fileSearch.running
    readonly property alias previewPath:  fileSearch.previewPath
    readonly property alias previewText:  fileSearch.previewText
    readonly property alias previewMeta:  fileSearch.previewMeta
    readonly property alias previewKind:  fileSearch.previewKind

    Processes {
        id: processes
        active: root.procMode
        selectedItem: root.filteredItems[root.selectedIndex] || null
    }
    readonly property alias procItems:    processes.items
    readonly property alias procRunning:  processes.running
    readonly property alias procPreviewText: processes.previewText
    readonly property alias procPreviewPid:  processes.previewPid

    Themes {
        id: themes
        active: root.themeMode
    }
    readonly property alias themeItems:   themes.items
    readonly property alias themeLoaded:  themes.loaded

    // tldr-backed CLI help preview. Triggered by `$ <name>` in the query.
    TldrSearch {
        id: tldrSearch
        query: root.query
        active: root.tldrMode
    }
    readonly property alias tldrItems:    tldrSearch.items
    readonly property alias tldrRunning:  tldrSearch.running
    readonly property alias tldrPreview:  tldrSearch.previewText
    readonly property alias tldrTool:     tldrSearch.toolName

    readonly property bool previewActive: root.tldrMode || root.fileMode || root.ghMode || root.procMode || root.themeMode
    readonly property bool previewHasContent: {
        if (root.tldrMode) return root.tldrPreview !== "";
        if (root.fileMode || root.ghMode)
            return root.previewPath !== "" || root.previewRepoUrl !== "";
        if (root.procMode) return processes.previewPid !== "";
        if (root.themeMode) {
            const it = root.filteredItems[root.selectedIndex];
            return !!(it && it.swatches && it.swatches.length > 0);
        }
        return false;
    }

    readonly property string homeDir: Quickshell.env("HOME")

    function open() {
        root.query = "";
        root.selectedIndex = 0;
        root.categoryFilter = "";
        root.visible_ = true;
        navbarApps.probe();
    }
    function close() { root.visible_ = false; }
    function toggle() { if (root.visible_) close(); else open(); }
    function goUp() {
        // Step back one level. At root this is a no-op so the caller can
        // chain "goUp or close" without a branch.
        if (root.categoryFilter !== "") {
            root.categoryFilter = "";
            root.query = "";
            root.selectedIndex = 0;
            return true;
        }
        return false;
    }

    // Entering or leaving file mode resets fd state. Other category drills
    // share the same handler — clearing both is a free no-op for other drills.
    onCategoryFilterChanged: {
        fileSearch.clear();
        ghSearch.clear();
        tldrSearch.clear();
        // Processes/Themes own their own clear()-on-deactivate via their
        // `active` binding, so the shell doesn't have to nudge them when
        // the filter changes — they react automatically.
    }


    // ---------- tldr markdown styling ----------
    // Parses the small markdown dialect tldr emits with `-m` and
    // returns RichText HTML coloured against the live palette. Bound
    // (not memoised) so a theme swap repaints automatically. Patterns:
    //   `# name`      title — skipped (header shows the tool name)
    //   `> text`      description (ink), inline `code` in indigo
    //   `- text:`     example label (inkDeep), inline `code` in indigo
    //   `` `cmd` ``   example command (indigo); {{placeholders}} seal
    //   other        fallthrough (e.g. "documentation not available")
    function formatTldrHtml(raw) {
        if (!raw) return "";
        // Qt color.toString() returns `#AARRGGBB` for non-opaque
        // colors (alpha first), which Qt's RichText parser
        // misinterprets as `#RRGGBB` for the first six digits. Trim
        // to `#RRGGBB` so translucent palette entries still render
        // their nominal hue, even if alpha is dropped.
        function hex(c) {
            const s = c.toString();
            return s.length === 9 ? "#" + s.substring(3) : s;
        }
        const ink = hex(root.ink);
        const inkDeep = hex(root.inkDeep);
        const indigo = hex(root.indigo);
        const seal = hex(root.seal);

        function esc(s) {
            return s.replace(/&/g, "&amp;")
                    .replace(/</g, "&lt;")
                    .replace(/>/g, "&gt;");
        }
        function wrap(color, text) {
            return '<span style="color:' + color + '">' + esc(text) + '</span>';
        }
        // Inline `code` spans inside prose: split on backticks so the
        // intervening code segments switch to indigo without changing
        // the surrounding base colour.
        function styleProse(s, base) {
            let out = "", i = 0;
            while (i < s.length) {
                const j = s.indexOf("`", i);
                if (j < 0) { out += wrap(base, s.substring(i)); break; }
                if (j > i) out += wrap(base, s.substring(i, j));
                const k = s.indexOf("`", j + 1);
                if (k < 0) { out += wrap(base, s.substring(j)); break; }
                out += wrap(indigo, s.substring(j + 1, k));
                i = k + 1;
            }
            return out;
        }
        // Code lines: most of the string is indigo, {{placeholders}}
        // pop in seal so the user sees what they need to fill in.
        function styleCode(s) {
            let out = "", i = 0;
            while (i < s.length) {
                const j = s.indexOf("{{", i);
                if (j < 0) { out += wrap(indigo, s.substring(i)); break; }
                if (j > i) out += wrap(indigo, s.substring(i, j));
                const k = s.indexOf("}}", j + 2);
                if (k < 0) { out += wrap(indigo, s.substring(j)); break; }
                out += wrap(seal, s.substring(j + 2, k));
                i = k + 2;
            }
            return out;
        }

        const lines = raw.split("\n");
        const out = [];
        for (let i = 0; i < lines.length; i++) {
            const line = lines[i];
            if (line.length === 0) { out.push(""); continue; }
            const c = line.charAt(0);
            if (c === "#") continue;
            if (c === ">") { out.push(styleProse(line.substring(1).trim(), ink)); continue; }
            // Require a space after `-` so markdown rules (`---`) and
            // any future hyphen-led prose don't get parsed as a tldr
            // example label (which is always `- text:`).
            if (c === "-" && line.charAt(1) === " ") { out.push(styleProse(line.substring(1).trim(), inkDeep)); continue; }
            if (c === "`") {
                let body = line;
                if (body.charAt(0) === "`") body = body.substring(1);
                if (body.charAt(body.length - 1) === "`") body = body.substring(0, body.length - 1);
                out.push(styleCode(body));
                continue;
            }
            out.push(styleProse(line, inkDeep));
        }
        return out.join("<br>");
    }

    // ---------- Icon resolution ----------
    // `.desktop` Icon field is either an absolute path or an icon-theme
    // name. Qt's QQmlEngine doesn't know about XDG themes, so theme names
    // get pushed through Quickshell.iconPath for resolution; absolute paths
    // just need a file:// prefix. Returns "" when nothing resolves so the
    // delegate can fall back to its nerd-font glyph.
    function resolveIconUrl(raw) {
        if (!raw) return "";
        if (raw.charAt(0) === "/") return "file://" + raw;
        return Quickshell.iconPath(raw, "");
    }

    // ---------- Search index annotation ----------
    // Annotated indexes. Assigned in Component.onCompleted and in the
    // appScan handler so they stay plain `var` assignments rather than
    // re-evaluating bindings whose dependency graph would re-allocate the
    // 200+ entry array on unrelated property touches.
    property var omarchy: []
    property var nav: []
    readonly property var allItems: root.omarchy.concat(appScan.apps).concat(navbarApps.items).concat(tuis.items).concat(themes.items)

    // ---------- Launcher ----------
    // Matches omarchy's launch convention (see omarchy-launch-or-focus):
    //   setsid -f          fork into a new session, returning immediately
    //                      so quickshell's Process completes; the spawned
    //                      app fully detaches from quickshell's lifetime
    //   uwsm-app -- <cmd>  registers the spawn under a systemd-user scope
    //                      (omarchy convention; gives the app a managed
    //                      unit, proper cgroup, clean logout teardown)
    //   bash -c "<exec>"   lets exec lines with shell syntax (pipes,
    //                      ||, &&, redirects) work alongside plain
    //                      argv-style commands without a special case
    Process { id: runner; running: false }
    function activate(item) {
        if (!item) return;
        if (item.isCategory) {
            root.categoryFilter = item.target;
            root.query = "";
            root.selectedIndex = 0;
            return;
        }
        // Process kill — refresh stays in-mode so you can chain kills.
        if (item.isProcess) {
            processes.killPid(item.pid, false);
            return;
        }
        // Theme apply — fire and forget; omarchy-theme-set rebuilds
        // configs and reloads all the live apps that listen for it.
        if (item.isTheme) {
            runner.command = ["sh", "-c",
                "setsid -f uwsm-app -- omarchy-theme-set \"$1\" >/dev/null 2>&1",
                "sh", item.themeName];
            runner.running = false;
            runner.running = true;
            root.close();
            return;
        }
        // tldr → open a floating terminal with the user's typed text
        // pre-filled at the readline prompt, ready to edit and run.
        // Builds runner.command as argv (no shell-quoting layer) so
        // backticks / $vars / metachars in the query land as literal
        // text in $1 inside the inner bash, never as code. Bypasses
        // bookmarks.record() — tldr lookups aren't apps and shouldn't
        // pollute history or favourites.
        if (item.isTldr) {
            runner.command = ["setsid", "-f", "uwsm-app", "--",
                "xdg-terminal-exec",
                "--app-id=org.omarchy.terminal",
                "--title=Omarchy",
                "-e", "bash", "-c",
                "read -e -i \"$1 \" line; eval \"$line\"; exec bash",
                "_", item.tldrPreFill || item.tldrName || ""];
            runner.running = false;
            runner.running = true;
            root.close();
            return;
        }
        bookmarks.record(item);
        // TUI commands need a real terminal — fzf, sudo prompts, and bash
        // `read` fail when launched detached. `item.tui` holds the wrapper
        // command name (omarchy-launch-tui or omarchy-launch-floating-…).
        const cmd = item.tui ? item.tui + " " + item.exec : item.exec;
        runner.command = ["sh", "-c",
                          "setsid -f uwsm-app -- bash -c "
                          + JSON.stringify(cmd)
                          + " >/dev/null 2>&1"];
        runner.running = false;
        runner.running = true;
        root.close();
    }

    // ---------- Search ----------
    // Each query token must match somewhere in the item for the item to
    // qualify; scores stack so "thm dark" finds Theme even though neither
    // token is a prefix on its own. Uses precomputed lowercased fields
    // (`_t`/`_k`/`_c`) so a 200+ item × N-token scoring pass doesn't
    // re-lowercase the same strings on every keystroke.
    function scoreItem(item, tokens) {
        const title = item._t;
        const kw = item._k;
        const cat = item._c;
        let total = 0;
        for (let i = 0; i < tokens.length; i++) {
            const t = tokens[i];
            let sub = 0;
            if (title.indexOf(t) === 0) sub += root.scPrefix;
            else if (title.indexOf(t) >= 0) sub += root.scTitle;
            if (kw.indexOf(t) >= 0) sub += root.scKw;
            if (cat.indexOf(t) >= 0) sub += root.scCat;
            if (sub === 0) return 0; // any token miss disqualifies
            total += sub;
        }
        return total;
    }

    readonly property var queryTokens: {
        const q = root.query.trim().toLowerCase();
        return q.length === 0 ? [] : q.split(/\s+/);
    }

    // Cached at root-level so it isn't reallocated on every keystroke.
    // Only depends on `nav` and `ghReady`, so re-evaluates once when the
    // auth probe finishes.
    readonly property var navRows: root.ghReady
        ? root.nav
        : root.nav.filter(it => it.target !== Data.ghCategory)

    readonly property var filteredItems: {
        // tldr mode owns the query entirely — its synthetic row is the
        // only thing the list should show, scoring doesn't apply.
        if (root.tldrMode) return root.tldrItems;
        // File and GitHub modes are their own worlds: fd and gh already
        // did the filtering, so we just pass their results through.
        if (root.fileMode) return root.fileItems;
        if (root.ghMode)   return root.ghItems;

        const tokens = root.queryTokens;
        const filter = root.categoryFilter;
        const cap = root.maxResults;

        // Favourites/history/proc/theme drill-ins draw from their
        // owning component; scoring still applies so typing inside the
        // drill filters live.
        let pool;
        if (root.favMode)        pool = bookmarks.favouriteItems;
        else if (root.histMode)  pool = bookmarks.historyItems;
        else if (root.procMode)  pool = root.procItems;
        else if (root.themeMode) pool = root.themeItems;
        else if (filter !== "")  pool = root.allItems.filter(it => it.category === filter);
        else                     pool = root.navRows.concat(root.allItems);

        // Empty query: preserve insertion order (nav rows first, then
        // omarchy actions, then apps). No scoring, no allocation overhead.
        if (tokens.length === 0) {
            return pool.length <= cap ? pool : pool.slice(0, cap);
        }

        const scored = [];
        for (let i = 0; i < pool.length; i++) {
            const it = pool[i];
            const s = root.scoreItem(it, tokens);
            if (s > 0) scored.push({ s: s, item: it });
        }
        scored.sort((a, b) => {
            if (b.s !== a.s) return b.s - a.s;
            // Tie-break: nav rows come first so a typed "setup" surfaces
            // the Setup drill-in row above any Setup-category leaf.
            const aCat = a.item.isCategory ? 0 : 1;
            const bCat = b.item.isCategory ? 0 : 1;
            if (aCat !== bCat) return aCat - bCat;
            return a.item.title.localeCompare(b.item.title);
        });
        const lim = Math.min(scored.length, cap);
        const out = new Array(lim);
        for (let j = 0; j < lim; j++) out[j] = scored[j].item;
        return out;
    }

    onFilteredItemsChanged: {
        root.selectedIndex = Math.max(0, Math.min(root.selectedIndex,
                                                  root.filteredItems.length - 1));
    }

    // ---------- Selection movement ----------
    // Single entry point for keyboard nav so arrow/Tab/Page bindings stay
    // one-liners. `wrap` toggles modulo behaviour vs. clamp — arrow + Tab
    // wrap, paging clamps (matches list-widget convention everywhere else).
    function moveSelection(delta, wrap) {
        const n = root.filteredItems.length;
        if (n === 0) return;
        let next = root.selectedIndex + delta;
        next = wrap ? ((next % n) + n) % n
                    : Math.max(0, Math.min(n - 1, next));
        root.selectedIndex = next;
        resultList.positionViewAtIndex(next, ListView.Contain);
    }

    // Grid-aware step for Quick mode. `delta` may exceed ±1 (arrow Up/Down
    // moves by gridCols). Clamps rather than wraps so Up from the top row
    // doesn't jump to the last row of a partial bottom row.
    function moveQuickSelection(delta) {
        const n = root.filteredQuickTiles.length;
        if (n === 0) return;
        const next = Math.max(0, Math.min(n - 1, root.selectedIndex + delta));
        root.selectedIndex = next;
    }

    Component.onCompleted: {
        root.omarchy = Data.annotate(Data.omarchyItems);
        root.nav     = Data.annotate(Data.categoryNav);
    }

    // ---------- IPC ----------
    IpcHandler {
        target: "palette"
        function toggle(): void { root.toggle() }
        function open(): void { root.open() }
        function close(): void { root.close() }
        function refresh(): void { appScan.refresh(); }
        // Open OmniMenu pre-pivoted to a drill-down category (e.g. "Quick").
        // Lets Hyprland bind a shortcut straight into a category without
        // exposing the visual grid as a separate surface.
        function openCategory(cat: string): void {
            root.open();
            root.categoryFilter = cat;
        }
    }

    // ---------- Global shortcuts ----------
    // Direct wlroots global-shortcut binding. Hyprland delivers the
    // keypress over its socket straight to this running shell, so
    // SUPER+SPACE no longer pays for a fresh `qs` client process (the
    // dominant ~50-150ms of perceived "boot" before any pixel changes).
    // Bind in Hyprland with:
    //   bind = SUPER, SPACE, global, quickshell:palette-toggle
    //   bind = ALT,   SPACE, global, quickshell:palette-quick
    GlobalShortcut {
        appid: "quickshell"
        name: "palette-toggle"
        description: "Toggle omni-menu palette"
        onPressed: root.toggle()
    }
    GlobalShortcut {
        appid: "quickshell"
        name: "palette-quick"
        description: "Open omni-menu pivoted to Quick"
        onPressed: { root.open(); root.categoryFilter = "Quick"; }
    }

    // ---------- Panel ----------
    PanelWindow {
        id: panel
        visible: root.visible_ || reveal > 0.001
        color: "transparent"
        anchors { top: true; bottom: true; left: true; right: true }
        exclusionMode: ExclusionMode.Ignore
        WlrLayershell.layer: WlrLayer.Overlay
        WlrLayershell.namespace: "omni-menu"
        WlrLayershell.keyboardFocus: root.visible_ ? WlrKeyboardFocus.Exclusive : WlrKeyboardFocus.None

        property real reveal: root.visible_ ? 1 : 0
        // Open is instant (no fade-in) so SUPER+SPACE paints the palette
        // on the very next frame. Close keeps a short eased fade so the
        // dismissal still reads as a deliberate motion instead of a pop.
        Behavior on reveal {
            NumberAnimation {
                duration: root.visible_ ? 0 : 70
                easing.type: Easing.InQuad
            }
        }

        // Backdrop dim — fades the desktop behind the palette along the
        // same reveal curve as the card scale, so open/close stays one
        // motion. Drawn before the dismiss MouseArea so clicks still
        // reach the close handler.
        Rectangle {
            anchors.fill: parent
            color: Qt.rgba(0, 0, 0, 0.5 * panel.reveal)
        }

        // Outside-click dismiss.
        MouseArea {
            anchors.fill: parent
            onClicked: root.close()
        }

        Rectangle {
            id: card
            anchors.horizontalCenter: parent.horizontalCenter
            // Card sits slightly above visual centre so the result list grows
            // downward without dragging the search field out of the eyeline.
            y: parent.height * 0.18
            // Wide in any preview-bearing mode (file, github, processes,
            // themes) so a ~520px preview pane fits next to the result
            // list; narrow 640 elsewhere — including Quick mode whether
            // collapsed or expanded — so opening a tile doesn't cause any
            // horizontal jump. The tile column compresses to 64px on the
            // left of the same 640 card, leaving ~509px for the detail
            // panel.
            width: root.previewActive ? 1000 : 640
            Behavior on width {
                NumberAnimation { duration: 60; easing.type: Easing.OutCubic }
            }
            // Cap the card so it never exceeds the screen even on small
            // displays; cardCol implicitHeight covers the search + list +
            // footer block.
            height: Math.min(cardCol.implicitHeight + 34, parent.height * 0.72)
            color: root.bg
            border.color: root.sep
            border.width: 1
            radius: root.cornerRadius
            transformOrigin: Item.Center
            scale: panel.reveal

            // Swallow clicks so the underlying dismiss MouseArea doesn't fire.
            MouseArea { anchors.fill: parent }

            focus: root.visible_
            Keys.onPressed: function(event) {
                // hjkl → arrow translation (Vim-style nav). Only active
                // in quickMode, where there is no typing buffer and the
                // tile grid is the sole input surface. In the main omni
                // search h/j/k/l are letters first; remapping them — even
                // conditionally on empty query — surprised users who
                // expected to start typing immediately.
                const _hjklMap = {};
                _hjklMap[Qt.Key_H] = Qt.Key_Left;
                _hjklMap[Qt.Key_J] = Qt.Key_Down;
                _hjklMap[Qt.Key_K] = Qt.Key_Up;
                _hjklMap[Qt.Key_L] = Qt.Key_Right;
                const _wrap = (e) => {
                    if (_hjklMap[e.key] === undefined) return e;
                    if (!root.quickMode) return e;
                    return { key: _hjklMap[e.key], modifiers: e.modifiers, text: e.text };
                };
                const e2 = _wrap(event);

                // When a quick tile is expanded, give its body first crack
                // at the key so arrow/Tab/Enter drive the body's own focus
                // chain (volume slider, wi-fi list, bluetooth list, …)
                // instead of the tile grid. Bodies return true from
                // kbdHandle() to swallow the event; anything they leave
                // unhandled (e.g. Esc) bubbles to the cascade below.
                if (root.quickExpanded
                    && bodyLoader.item
                    && typeof bodyLoader.item.kbdHandle === "function"
                    && bodyLoader.item.kbdHandle(e2)) {
                    event.accepted = true;
                    return;
                }
                if (e2.key === Qt.Key_Escape) {
                    // Esc cascade: collapse the quick-tile detail panel
                    // first (if open), then clear the typed query, then
                    // unwind drill-down, then close. Each Esc undoes
                    // exactly one layer of state so the palette never
                    // exits with a half-typed query on screen.
                    if (root.quickExpanded) {
                        root.expandedTile = null;
                    } else if (root.query.length > 0) {
                        root.query = "";
                        root.selectedIndex = 0;
                    } else if (!root.goUp()) {
                        root.close();
                    }
                    event.accepted = true;
                } else if (root.quickMode && e2.key === Qt.Key_Left) {
                    root.moveQuickSelection(-1);
                    event.accepted = true;
                } else if (root.quickMode && e2.key === Qt.Key_Right) {
                    root.moveQuickSelection(1);
                    event.accepted = true;
                } else if (root.quickMode && e2.key === Qt.Key_Up) {
                    root.moveQuickSelection(-root.quickGridCols);
                    event.accepted = true;
                } else if (root.quickMode && e2.key === Qt.Key_Down) {
                    root.moveQuickSelection(root.quickGridCols);
                    event.accepted = true;
                } else if (root.quickMode
                           && (e2.key === Qt.Key_Tab && !(e2.modifiers & Qt.ShiftModifier))) {
                    root.moveQuickSelection(1);
                    event.accepted = true;
                } else if (root.quickMode
                           && (e2.key === Qt.Key_Backtab
                               || (e2.key === Qt.Key_Tab && (e2.modifiers & Qt.ShiftModifier)))) {
                    root.moveQuickSelection(-1);
                    event.accepted = true;
                } else if (root.tldrMode && root.tldrPreview !== ""
                           && (e2.key === Qt.Key_Up || e2.key === Qt.Key_Down
                               || e2.key === Qt.Key_PageUp || e2.key === Qt.Key_PageDown
                               || e2.key === Qt.Key_Home || e2.key === Qt.Key_End
                               || e2.key === Qt.Key_Tab || e2.key === Qt.Key_Backtab)) {
                    // tldr mode has a single synthetic row, so list nav is
                    // a no-op. Route arrow/page/home/end (and Tab/Shift+Tab,
                    // which would otherwise wrap the same row to itself) to
                    // the preview Flickable instead.
                    const f = tldrPreviewScroll;
                    const max = Math.max(0, f.contentHeight - f.height);
                    const line = 18;
                    const page = Math.max(line, f.height * 0.9);
                    let dy = 0;
                    if (e2.key === Qt.Key_Up
                        || (e2.key === Qt.Key_Tab && (e2.modifiers & Qt.ShiftModifier))
                        || e2.key === Qt.Key_Backtab) dy = -line;
                    else if (e2.key === Qt.Key_Down
                             || (e2.key === Qt.Key_Tab && !(e2.modifiers & Qt.ShiftModifier))) dy = line;
                    else if (e2.key === Qt.Key_PageUp)   dy = -page;
                    else if (e2.key === Qt.Key_PageDown) dy = page;
                    else if (e2.key === Qt.Key_Home) { f.contentY = 0; event.accepted = true; return; }
                    else if (e2.key === Qt.Key_End)  { f.contentY = max; event.accepted = true; return; }
                    f.contentY = Math.max(0, Math.min(max, f.contentY + dy));
                    event.accepted = true;
                } else if (e2.key === Qt.Key_Down
                           || (e2.key === Qt.Key_Tab && !(e2.modifiers & Qt.ShiftModifier))) {
                    // Tab + Down step forward, Shift+Tab + Up step backward,
                    // both wrap. Paging clamps (see Key_PageDown). Matches
                    // launcher convention everywhere else.
                    root.moveSelection(1, true);
                    event.accepted = true;
                } else if (e2.key === Qt.Key_Up
                           || e2.key === Qt.Key_Backtab
                           || (e2.key === Qt.Key_Tab && (e2.modifiers & Qt.ShiftModifier))) {
                    root.moveSelection(-1, true);
                    event.accepted = true;
                } else if (e2.key === Qt.Key_PageDown) {
                    root.moveSelection(8, false);
                    event.accepted = true;
                } else if (e2.key === Qt.Key_PageUp) {
                    root.moveSelection(-8, false);
                    event.accepted = true;
                } else if (e2.key === Qt.Key_Home) {
                    root.selectedIndex = 0;
                    resultList.positionViewAtIndex(0, ListView.Beginning);
                    event.accepted = true;
                } else if (e2.key === Qt.Key_End) {
                    root.selectedIndex = Math.max(0, root.filteredItems.length - 1);
                    resultList.positionViewAtIndex(root.selectedIndex, ListView.End);
                    event.accepted = true;
                } else if (e2.key === Qt.Key_Return || e2.key === Qt.Key_Enter) {
                    if (root.quickMode) {
                        const t = root.filteredQuickTiles[root.selectedIndex];
                        if (t) root.expandTile(t);
                    } else {
                        const it = root.filteredItems[root.selectedIndex];
                        if (it) root.activate(it);
                    }
                    event.accepted = true;
                } else if (e2.key === Qt.Key_Backspace) {
                    // Backspace deletes a char first; once the query is
                    // empty it walks back up one level so the same key
                    // unwinds both the typed query and the breadcrumb.
                    if (root.query.length > 0) root.query = root.query.slice(0, -1);
                    else root.goUp();
                    event.accepted = true;
                } else if (e2.key === Qt.Key_S && (e2.modifiers & Qt.ControlModifier)) {
                    const it = root.filteredItems[root.selectedIndex];
                    if (it && !it.isCategory && !it.isTldr) bookmarks.toggleFavourite(it);
                    event.accepted = true;
                } else if (e2.key === Qt.Key_C && (e2.modifiers & Qt.ControlModifier)
                           && root.tldrMode && root.tldrPreview !== "") {
                    // Ctrl+C in tldr mode: copy the active selection if
                    // there is one, otherwise copy the whole rendered
                    // preview. The TextEdit's `copy()` works without
                    // active focus, so the search input keeps keystrokes.
                    if (tldrPreviewEdit.selectedText.length > 0) {
                        tldrPreviewEdit.copy();
                    } else {
                        tldrPreviewEdit.selectAll();
                        tldrPreviewEdit.copy();
                        tldrPreviewEdit.deselect();
                    }
                    event.accepted = true;
                } else if (!root.quickMode && event.text && event.text.length === 1) {
                    const ch = event.text;
                    // Printable range; lets letters, digits, and spaces in,
                    // keeps modifier-driven control codes out. Skipped in
                    // quickMode — there's no search field to feed.
                    if (ch.charCodeAt(0) >= 32 && ch.charCodeAt(0) !== 127) {
                        root.query += ch;
                        root.selectedIndex = 0;
                        event.accepted = true;
                    }
                }
            }

            Column {
                id: cardCol
                anchors.fill: parent
                anchors.margins: 17
                spacing: 12

                Item {
                    width: parent.width
                    height: 43

                    Column {
                        anchors.left: parent.left
                        anchors.verticalCenter: parent.verticalCenter
                        spacing: 2

                        Text {
                            text: root.categoryFilter === ""
                                  ? "OMNI"
                                  : "OMNI › " + root.sectionIcon + "  " + root.categoryFilter.toUpperCase()
                            color: root.ink
                            font.family: root.mono
                            font.pixelSize: 19
                            font.letterSpacing: 4
                            font.weight: Font.Medium
                        }
                        Text {
                            text: {
                                if (!root.appsLoaded) return "LOADING APPS…";
                                if (root.fileMode) {
                                    if (root.query.length === 0) return "TYPE TO SEARCH ~";
                                    if (root.fdRunning) return "SEARCHING…";
                                    const total = root.filteredItems.length;
                                    return total === 0
                                        ? "NO FILES MATCH"
                                        : total + " FILE" + (total === 1 ? "" : "S");
                                }
                                if (root.ghMode) {
                                    const total = root.filteredItems.length;
                                    if (root.query.length === 0) {
                                        if (root.ghRunning && total === 0) return "LOADING PRS…";
                                        return total === 0
                                            ? "NO OPEN PRS"
                                            : total + " OPEN PR" + (total === 1 ? "" : "S");
                                    }
                                    if (root.ghRunning) return "SEARCHING GITHUB…";
                                    return total === 0
                                        ? "NO REPOS MATCH"
                                        : total + " REPO" + (total === 1 ? "" : "S");
                                }
                                if (root.favMode) {
                                    const total = root.filteredItems.length;
                                    return total === 0
                                        ? "NO FAVOURITES YET  ·  CTRL+S TO STAR"
                                        : total + " FAVOURITE" + (total === 1 ? "" : "S");
                                }
                                if (root.histMode) {
                                    const total = root.filteredItems.length;
                                    return total === 0
                                        ? "NO HISTORY YET"
                                        : total + " RECENT" + (total === 1 ? "" : "S");
                                }
                                if (root.procMode) {
                                    const total = root.filteredItems.length;
                                    if (processes.running && total === 0) return "LOADING PROCESSES…";
                                    return total === 0
                                        ? "NO PROCESSES"
                                        : total + " PROCESS" + (total === 1 ? "" : "ES");
                                }
                                if (root.themeMode) {
                                    const total = root.filteredItems.length;
                                    if (!themes.loaded && total === 0) return "LOADING THEMES…";
                                    return total === 0
                                        ? "NO THEMES FOUND"
                                        : total + " THEME" + (total === 1 ? "" : "S");
                                }
                                const total = root.filteredItems.length;
                                if (root.query.length === 0) {
                                    return total + " ENTRIES  ·  " + root.allItems.length + " TOTAL";
                                }
                                return total === 0
                                    ? "NO MATCHES"
                                    : total + " MATCH" + (total === 1 ? "" : "ES");
                            }
                            color: root.inkDeep
                            font.family: root.mono
                            font.pixelSize: 11
                            font.letterSpacing: 2
                        }
                    }

                    Text {
                        anchors.right: parent.right
                        anchors.verticalCenter: parent.verticalCenter
                        text: {
                            if (root.quickMode) {
                                return root.quickExpanded
                                    ? "HJKL / ↑↓←→  ·  TAB SECT  ·  ↵ APPLY  ·  ESC BACK"
                                    : "HJKL / ↑↓←→  ·  ↵ OPEN  ·  ESC BACK";
                            }
                            if (root.categoryFilter === "")
                                return "↑↓ / TAB  ·  ↵ OPEN  ·  ^S STAR  ·  ESC CLOSE";
                            let verb = "RUN";
                            if (root.fileMode)       verb = "OPEN FILE";
                            else if (root.ghMode)    verb = "OPEN";
                            else if (root.procMode)  verb = "KILL";
                            else if (root.themeMode) verb = "APPLY";
                            return "↑↓ / TAB  ·  ↵ " + verb + "  ·  ^S STAR  ·  ESC BACK";
                        }
                        color: root.inkDeep
                        font.family: root.mono
                        font.pixelSize: 10
                        font.letterSpacing: 2
                        opacity: 0.6
                    }
                }

                Rectangle { width: parent.width; height: 1; color: root.sep }

                // ---------- Quick container (quickMode only) ----------
                // Lays the tile grid on the left and the optional detail
                // panel on the right when a tile is expanded, so the panel
                // doesn't push the grid down or shove rows off the card.
                Item {
                    id: quickContainer
                    visible: root.quickMode
                    width: parent.width
                    height: visible
                        ? Math.max(quickGrid.height,
                                   detailPanel.visible ? detailPanel.height : 0)
                        : 0

                Item {
                    id: quickGrid
                    visible: root.quickMode
                    // Expanded: compress to a narrow column on the left
                    // edge so the detail panel gets the wider right half.
                    readonly property bool colMode: root.quickExpanded
                    anchors.top: parent.top
                    anchors.left: parent.left
                    width: colMode ? 64 : parent.width
                    readonly property int tileH: colMode ? 42 : 86
                    readonly property int spacing: colMode ? 4 : 10
                    readonly property int rows: visible
                        ? Math.ceil(root.filteredQuickTiles.length / root.quickGridCols)
                        : 0
                    height: visible
                        ? (rows * tileH + Math.max(0, rows - 1) * spacing)
                        : 0

                    Grid {
                        anchors.fill: parent
                        columns: root.quickGridCols
                        rowSpacing: quickGrid.spacing
                        columnSpacing: quickGrid.spacing

                        Repeater {
                            model: root.filteredQuickTiles
                            delegate: Item {
                                id: tileSlot
                                required property var modelData
                                required property int index
                                readonly property bool selected: root.selectedIndex === index
                                width: (quickGrid.width - (root.quickGridCols - 1) * quickGrid.spacing)
                                       / root.quickGridCols
                                height: quickGrid.tileH

                                Rectangle {
                                    anchors.fill: parent
                                    radius: root.cornerRadius
                                    color: tileSlot.selected
                                           ? Qt.rgba(root.ink.r, root.ink.g, root.ink.b, 0.08)
                                           : tileMouse.containsMouse
                                                ? Qt.rgba(root.ink.r, root.ink.g, root.ink.b, 0.05)
                                                : Qt.rgba(root.ink.r, root.ink.g, root.ink.b, 0.03)
                                    border.color: tileSlot.selected ? root.seal : root.sep
                                    border.width: tileSlot.selected ? 2 : 1
                                    Behavior on color        { ColorAnimation  { duration: 50 } }
                                    Behavior on border.color { ColorAnimation  { duration: 50 } }
                                    Behavior on border.width { NumberAnimation { duration: 50 } }
                                }

                                Column {
                                    anchors.fill: parent
                                    anchors.margins: quickGrid.colMode ? 3 : 8
                                    spacing: quickGrid.colMode ? 0 : 3

                                    Text {
                                        readonly property var dyn: root.tileDyn(tileSlot.modelData)
                                        anchors.horizontalCenter: parent.horizontalCenter
                                        text: dyn.glyph || ""
                                        color: dyn.tone || root.ink
                                        font.family: root.mono
                                        font.pixelSize: quickGrid.colMode ? 14 : 20
                                    }
                                    Text {
                                        anchors.horizontalCenter: parent.horizontalCenter
                                        width: parent.width
                                        horizontalAlignment: Text.AlignHCenter
                                        elide: Text.ElideRight
                                        text: root.tileDyn(tileSlot.modelData).label || ""
                                        color: root.ink
                                        font.family: root.mono
                                        font.pixelSize: quickGrid.colMode ? 7 : 9
                                        font.letterSpacing: quickGrid.colMode ? 0.8 : 1.4
                                        font.weight: Font.Medium
                                    }
                                    // Sub-label is redundant in colMode —
                                    // the detail panel header above shows
                                    // the same live value. Hiding it lets
                                    // the column fit all 12 tiles inside
                                    // the card's vertical budget.
                                    Text {
                                        visible: !quickGrid.colMode
                                        anchors.horizontalCenter: parent.horizontalCenter
                                        width: parent.width
                                        horizontalAlignment: Text.AlignHCenter
                                        elide: Text.ElideRight
                                        text: root.tileDyn(tileSlot.modelData).sub || ""
                                        color: root.inkDeep
                                        font.family: root.mono
                                        font.pixelSize: 8
                                        font.letterSpacing: 1
                                        opacity: 0.85
                                    }
                                }

                                MouseArea {
                                    id: tileMouse
                                    anchors.fill: parent
                                    hoverEnabled: true
                                    cursorShape: Qt.PointingHandCursor
                                    acceptedButtons: Qt.LeftButton | Qt.RightButton
                                    onPositionChanged: root.selectedIndex = tileSlot.index
                                    onClicked: (e) => {
                                        root.selectedIndex = tileSlot.index;
                                        if (e.button === Qt.RightButton) {
                                            // Right-click still runs the long action
                                            // (mute toggle, refresh, reset) without
                                            // opening the detail panel.
                                            root.longQuickTile(tileSlot.modelData);
                                        } else {
                                            root.expandTile(tileSlot.modelData);
                                        }
                                    }
                                }
                            }
                        }
                    }
                }

                // Vertical separator between the compressed tile column
                // (left) and the detail panel (right). Anchored to the
                // grid's right edge so it tracks the column's width.
                Rectangle {
                    id: quickMidSep
                    visible: root.quickExpanded
                    anchors.left: quickGrid.right
                    anchors.leftMargin: 16
                    anchors.top: parent.top
                    anchors.bottom: parent.bottom
                    width: 1
                    color: root.sep
                }

                // ---------- Quick tile detail panel ----------
                // Drops below the tile grid when a tile is clicked. Each
                // tile gets a small adjustment surface here — sliders for
                // audio + display, action buttons for everything else.
                // The whole panel collapses to height 0 when no tile is
                // expanded so the card auto-shrinks back to its grid-only
                // footprint.
                Item {
                    id: detailPanel
                    visible: root.quickExpanded
                    anchors.left: quickMidSep.right
                    anchors.leftMargin: 16
                    anchors.right: parent.right
                    anchors.top: parent.top
                    // Cap the panel so the card never extends past its
                    // budget. Body content beyond this height scrolls
                    // inside `bodyScroll` below instead of pushing the
                    // card off-screen.
                    readonly property real _maxHeight: panel.height * 0.55
                    readonly property real _wantHeight: detailHeader.implicitHeight + bodyLoader.implicitContentHeight + 18
                    height: visible ? Math.min(_wantHeight, _maxHeight) : 0
                    clip: true
                    Behavior on height {
                        NumberAnimation { duration: 60; easing.type: Easing.OutCubic }
                    }

                    readonly property var t: root.expandedTile
                    readonly property string tKey: t ? t.key : ""
                    // Capture the OmniMenu root under a non-conflicting
                    // name. Inside the Component children below, an
                    // expression like `root: root` would self-bind to the
                    // body's own `root` property (still undefined at the
                    // moment of evaluation) rather than reach the outer
                    // id. `omni` lets us reference the OmniMenu root
                    // unambiguously from within those Component templates.
                    readonly property var omni: root

                    // Per-tile body Components — instantiated by the
                    // Loader below based on `tKey`. Each body owns its
                    // own controls (sliders, lists) and may emit `close`
                    // to dismiss OmniMenu after an action that takes
                    // focus away.
                    Component { id: batteryBodyComp;     QuickBatteryBody     { root: detailPanel.omni; nav: detailPanel.omni.navbar } }
                    Component { id: audioBodyComp;       QuickAudioBody       { root: detailPanel.omni; nav: detailPanel.omni.navbar } }
                    Component { id: wifiBodyComp;        QuickWifiBody        { root: detailPanel.omni; nav: detailPanel.omni.navbar } }
                    Component { id: btBodyComp;          QuickBluetoothBody   { root: detailPanel.omni; nav: detailPanel.omni.navbar } }
                    Component { id: weatherBodyComp;     QuickWeatherBody     { root: detailPanel.omni; nav: detailPanel.omni.navbar } }
                    Component { id: displayBodyComp;     QuickDisplayBody     { root: detailPanel.omni; nav: detailPanel.omni.navbar } }
                    Component { id: aetherBodyComp;      QuickAetherBody      { root: detailPanel.omni; nav: detailPanel.omni.navbar } }
                    Component { id: cpuBodyComp;         QuickCpuBody         { root: detailPanel.omni; nav: detailPanel.omni.navbar } }
                    Component { id: calendarBodyComp;    QuickCalendarBody    { root: detailPanel.omni; nav: detailPanel.omni.navbar } }
                    Component { id: screenshotsBodyComp; QuickScreenshotsBody { root: detailPanel.omni; nav: detailPanel.omni.navbar } }
                    Component { id: videosBodyComp;      QuickVideosBody      { root: detailPanel.omni; nav: detailPanel.omni.navbar } }
                    Component { id: powerBodyComp;       QuickPowerBody       { root: detailPanel.omni; nav: detailPanel.omni.navbar } }

                    // Header (always visible at the top of the panel)
                    RowLayout {
                        id: detailHeader
                        anchors.left: parent.left
                        anchors.right: parent.right
                        anchors.top: parent.top
                        anchors.topMargin: 6
                        spacing: 12
                        Text {
                            readonly property var dyn: root.tileDyn(detailPanel.t)
                            text: dyn.glyph || ""
                            color: dyn.tone || root.ink
                            font.family: root.mono
                            font.pixelSize: 26
                            Layout.alignment: Qt.AlignVCenter
                        }
                        Column {
                            Layout.fillWidth: true
                            Layout.alignment: Qt.AlignVCenter
                            spacing: 2
                            Text {
                                text: root.tileDyn(detailPanel.t).label || ""
                                color: root.ink
                                font.family: root.mono
                                font.pixelSize: 13
                                font.letterSpacing: 2
                                font.weight: Font.Medium
                            }
                            Text {
                                text: root.tileDyn(detailPanel.t).sub || ""
                                color: root.inkDeep
                                font.family: root.mono
                                font.pixelSize: 10
                                font.letterSpacing: 1
                                opacity: 0.85
                            }
                        }
                        Rectangle {
                            Layout.alignment: Qt.AlignVCenter
                            width: 22; height: 22; radius: 11
                            color: closeMouse.containsMouse
                                   ? Qt.rgba(root.ink.r, root.ink.g, root.ink.b, 0.08)
                                   : "transparent"
                            border.color: root.sep
                            border.width: 1
                            Text {
                                anchors.centerIn: parent
                                text: "×"
                                color: root.inkDeep
                                font.family: root.mono
                                font.pixelSize: 14
                            }
                            MouseArea {
                                id: closeMouse
                                anchors.fill: parent
                                hoverEnabled: true
                                cursorShape: Qt.PointingHandCursor
                                onClicked: root.collapseTile()
                            }
                        }
                    }

                    // Scrollable body region: takes whatever vertical
                    // space is left after the header. When the body
                    // content exceeds the available space the user can
                    // flick / scroll inside this clipped region instead
                    // of having content fall off the card.
                    Flickable {
                        id: bodyScroll
                        anchors.left: parent.left
                        anchors.right: parent.right
                        anchors.top: detailHeader.bottom
                        anchors.bottom: parent.bottom
                        anchors.topMargin: 10
                        contentWidth: width
                        contentHeight: bodyLoader.implicitContentHeight
                        clip: true
                        boundsBehavior: Flickable.StopAtBounds
                        interactive: contentHeight > height

                        Loader {
                            id: bodyLoader
                            width: bodyScroll.width
                            active: detailPanel.visible
                            // Exposed so detailPanel.height can clamp to
                            // panel-budget while still picking the
                            // shorter of "content" / "available".
                            readonly property real implicitContentHeight: item ? item.implicitHeight : 0
                            sourceComponent: {
                                switch (detailPanel.tKey) {
                                    case "battery":     return batteryBodyComp;
                                    case "audio":       return audioBodyComp;
                                    case "network":     return wifiBodyComp;
                                    case "bluetooth":   return btBodyComp;
                                    case "weather":     return weatherBodyComp;
                                    case "display":     return displayBodyComp;
                                    case "aether":      return aetherBodyComp;
                                    case "cpu":         return cpuBodyComp;
                                    case "calendar":    return calendarBodyComp;
                                    case "screenshots": return screenshotsBodyComp;
                                    case "videos":      return videosBodyComp;
                                    case "power":       return powerBodyComp;
                                }
                                return null;
                            }
                            onLoaded: {
                                if (item && item.close)
                                    item.close.connect(function() { root.close(); });
                                bodyScroll.contentY = 0;
                            }
                        }

                        // Slim scroll indicator on the right edge — only
                        // visible while overflow exists. Tracks the
                        // viewport position so the user has a hint that
                        // more content is below.
                        Rectangle {
                            visible: bodyScroll.contentHeight > bodyScroll.height
                            anchors.right: parent.right
                            anchors.rightMargin: 2
                            width: 3
                            radius: 1.5
                            color: root.seal
                            opacity: 0.55
                            y: bodyScroll.contentHeight > 0
                               ? (bodyScroll.contentY / bodyScroll.contentHeight) * bodyScroll.height
                               : 0
                            height: bodyScroll.contentHeight > 0
                                    ? Math.max(20, (bodyScroll.height / bodyScroll.contentHeight) * bodyScroll.height)
                                    : 0
                        }
                    }
                }

                } // end of quickContainer

                // No focus indicator on TextInput — the caret and the
                // live count above act as the focus tell. Hidden entirely
                // in quickMode where the tile grid is the only surface
                // the user interacts with (filtering removed per UX call).
                Item {
                    visible: !root.quickMode
                    width: parent.width
                    height: visible ? 34 : 0

                    Text {
                        id: searchPrompt
                        anchors.left: parent.left
                        anchors.verticalCenter: parent.verticalCenter
                        text: root.fileMode ? "󰉖"
                              : root.ghMode ? "󰊤"
                              : root.procMode ? "󰍛"
                              : root.themeMode ? "󰸌"
                              : "󰍉"
                        color: root.seal
                        font.family: root.mono
                        font.pixelSize: 16
                    }

                    Text {
                        id: queryText
                        anchors.left: searchPrompt.right
                        anchors.leftMargin: 10
                        anchors.verticalCenter: parent.verticalCenter
                        text: {
                            if (root.query.length > 0) return root.query;
                            if (root.fileMode)  return "Type to search files in ~ …";
                            if (root.ghMode)    return "Your PRs · type to search GitHub repos";
                            if (root.procMode)  return "Type to filter processes by name, user, pid…";
                            if (root.themeMode) return "Type to filter themes…";
                            return "Type to search apps, themes, settings…";
                        }
                        color: root.query.length === 0 ? root.inkDeep : root.ink
                        opacity: root.query.length === 0 ? 0.5 : 1.0
                        font.family: root.mono
                        font.pixelSize: 14
                        font.letterSpacing: 1
                    }

                    // Blinking caret riding the end of the query.
                    Rectangle {
                        id: caret
                        width: 2
                        height: 16
                        color: root.seal
                        anchors.verticalCenter: parent.verticalCenter
                        x: root.query.length === 0
                           ? searchPrompt.x + searchPrompt.width + 10
                           : queryText.x + queryText.contentWidth + 2
                        visible: root.visible_
                        SequentialAnimation on opacity {
                            running: root.visible_
                            loops: Animation.Infinite
                            NumberAnimation { from: 1; to: 0.2; duration: 600; easing.type: Easing.InOutSine }
                            NumberAnimation { from: 0.2; to: 1; duration: 600; easing.type: Easing.InOutSine }
                        }
                    }
                }

                Rectangle {
                    visible: !root.quickMode
                    width: parent.width
                    height: 1
                    color: root.sep
                }

                // Fixed row height in the delegate keeps positionViewAtIndex
                // honest under fast keyboard navigation; the wrapping Item's
                // clip prevents the bottom row bleeding into the footer
                // hairline mid-scroll.
                Item {
                    id: listArea
                    visible: !root.quickMode
                    width: parent.width
                    height: visible
                        ? Math.max(60, card.height - 34 - 43 - 34 - 22 - 12 * 5)
                        : 0
                    clip: true

                    // In file mode the list shrinks to ~44% of the card so
                    // a 520px-ish preview pane fits alongside it. The 1px
                    // hairline + 1px inverse hairline divider sits between
                    // them. animated alongside card.width for a single
                    // smooth widen-and-split motion.
                    readonly property real listFraction: root.previewActive ? 0.44 : 1.0

                    ListView {
                        id: resultList
                        anchors.top: parent.top
                        anchors.bottom: parent.bottom
                        anchors.left: parent.left
                        // Follows card.width's Behavior animation — adding a
                        // second Behavior here would animate to a moving
                        // target and produce staggered motion.
                        width: parent.width * listArea.listFraction
                        model: root.filteredItems
                        currentIndex: root.selectedIndex
                        highlightFollowsCurrentItem: false
                        boundsBehavior: Flickable.StopAtBounds
                        cacheBuffer: 200
                        // Snap pixel-perfect so the row outline doesn't
                        // shimmer during arrow-key scroll.
                        pixelAligned: true

                        delegate: Item {
                            id: row
                            required property var modelData
                            required property int index
                            width: ListView.view.width
                            height: 38
                            readonly property bool isSelected: root.selectedIndex === index

                            Rectangle {
                                anchors.fill: parent
                                color: row.isSelected ? root.rowSel
                                                       : rowMouse.containsMouse ? root.rowHi
                                                                                : "transparent"
                                Behavior on color { ColorAnimation { duration: 40 } }
                            }
                            Rectangle {
                                anchors.left: parent.left
                                anchors.top: parent.top
                                anchors.bottom: parent.bottom
                                width: 2
                                color: root.seal
                                visible: row.isSelected
                            }

                            // Icon slot: tinted .desktop image when one
                            // resolves, nerd-font glyph fallback otherwise.
                            // hasImageIcon flips on Image.Ready so the swap
                            // happens in one frame, no broken-icon flash.
                            Item {
                                id: iconText
                                anchors.left: parent.left
                                anchors.leftMargin: 14
                                anchors.verticalCenter: parent.verticalCenter
                                width: 22
                                height: 22

                                readonly property string iconUrl: root.resolveIconUrl(row.modelData.rawIcon)
                                readonly property bool hasImageIcon: appImg.status === Image.Ready && iconUrl !== ""
                                readonly property color tint: row.isSelected ? root.seal : root.inkDeep

                                Text {
                                    anchors.centerIn: parent
                                    visible: !iconText.hasImageIcon
                                    text: row.modelData.icon || "·"
                                    color: iconText.tint
                                    font.family: root.mono
                                    font.pixelSize: 16
                                }

                                // Hidden because MultiEffect draws the
                                // recoloured copy; layer.enabled hands it
                                // a texture to sample without committing a
                                // full FBO until an icon actually resolves.
                                Image {
                                    id: appImg
                                    anchors.centerIn: parent
                                    width: 18
                                    height: 18
                                    visible: false
                                    source: iconText.iconUrl
                                    sourceSize.width: 36
                                    sourceSize.height: 36
                                    fillMode: Image.PreserveAspectFit
                                    smooth: true
                                    asynchronous: true
                                    cache: true
                                    layer.enabled: iconText.hasImageIcon
                                }
                                // colorization: 1.0 paints solid colour
                                // through the source's alpha — a flat
                                // tinted silhouette in the ink/seal palette.
                                MultiEffect {
                                    anchors.fill: appImg
                                    visible: iconText.hasImageIcon
                                    source: appImg
                                    colorization: 1.0
                                    colorizationColor: iconText.tint
                                    Behavior on colorizationColor { ColorAnimation { duration: 40 } }
                                }
                            }
                            Text {
                                id: titleText
                                anchors.left: iconText.right
                                anchors.leftMargin: 12
                                anchors.verticalCenter: parent.verticalCenter
                                // Trailing chevron flags drill-in rows so
                                // you can tell at a glance which Enters
                                // drill in vs. which Enters execute.
                                text: row.modelData.isCategory
                                      ? row.modelData.title + "  ›"
                                      : row.modelData.title
                                color: row.isSelected ? root.ink : root.fg
                                font.family: root.mono
                                font.pixelSize: 13
                                font.weight: row.isSelected ? Font.Medium : Font.Light
                                font.letterSpacing: 1
                                elide: Text.ElideRight
                                width: row.width - iconText.width - catText.implicitWidth - 60
                            }
                            Text {
                                id: starText
                                anchors.right: catText.left
                                anchors.rightMargin: 8
                                anchors.verticalCenter: parent.verticalCenter
                                visible: bookmarks.isFavourite(row.modelData)
                                text: "󰓎"
                                color: root.seal
                                font.family: root.mono
                                font.pixelSize: 11
                            }
                            Text {
                                id: catText
                                anchors.right: parent.right
                                anchors.rightMargin: 14
                                anchors.verticalCenter: parent.verticalCenter
                                // File rows show the dirname here, which
                                // shouldn't be uppercased or letter-spaced.
                                // Cap the width so a deep path doesn't push
                                // the title text off the row.
                                text: row.modelData.rawCategory
                                      ? (row.modelData.category || "")
                                      : (row.modelData.category || "").toUpperCase()
                                color: row.isSelected ? root.seal : root.inkDeep
                                opacity: row.isSelected ? 0.95 : 0.65
                                font.family: root.mono
                                font.pixelSize: 10
                                font.letterSpacing: row.modelData.rawCategory ? 0 : 2
                                elide: Text.ElideLeft
                                horizontalAlignment: Text.AlignRight
                                width: row.modelData.rawCategory
                                       ? Math.min(implicitWidth, row.width * 0.45)
                                       : implicitWidth
                            }

                            MouseArea {
                                id: rowMouse
                                anchors.fill: parent
                                hoverEnabled: true
                                cursorShape: Qt.PointingHandCursor
                                // onPositionChanged fires only on actual
                                // cursor movement; onEntered would also
                                // fire when rows shift under a stationary
                                // cursor (after a query change, drill-in,
                                // or rescore), stealing keyboard focus.
                                onPositionChanged: root.selectedIndex = row.index
                                onClicked: root.activate(row.modelData)
                            }
                        }

                        Text {
                            anchors.centerIn: parent
                            visible: resultList.count === 0
                            text: {
                                if (root.tldrMode) {
                                    if (root.tldrTool.length === 0) return "$ COMMAND  ·  TLDR PREVIEW";
                                    if (root.tldrRunning) return "FETCHING TLDR…";
                                    return "NO TLDR PAGE";
                                }
                                if (root.fileMode) {
                                    if (root.query.length === 0) return "TYPE TO SEARCH ~";
                                    if (root.fdRunning) return "SEARCHING…";
                                    return "NO FILES MATCH";
                                }
                                if (root.ghMode) {
                                    if (root.query.length === 0) {
                                        return root.ghRunning ? "LOADING PRS…" : "NO OPEN PRS";
                                    }
                                    if (root.ghRunning) return "SEARCHING GITHUB…";
                                    return "NO REPOS MATCH";
                                }
                                if (root.favMode)  return "NO FAVOURITES — CTRL+S TO STAR";
                                if (root.histMode) return "NO HISTORY YET";
                                if (root.procMode)  return processes.running ? "LOADING…" : "NO PROCESSES";
                                if (root.themeMode) return themes.loaded ? "NO THEMES MATCH" : "LOADING THEMES…";
                                return root.appsLoaded ? "NOTHING MATCHES" : "INDEXING APPS…";
                            }
                            color: root.inkDeep
                            font.family: root.mono
                            font.pixelSize: 11
                            font.letterSpacing: 3
                            opacity: 0.6
                        }
                    }

                    // ---------- Preview pane ----------
                    Rectangle {
                        visible: root.previewActive
                        anchors.top: parent.top
                        anchors.bottom: parent.bottom
                        anchors.left: resultList.right
                        width: 1
                        color: root.sep
                    }

                    Item {
                        id: previewPane
                        visible: root.previewActive
                        anchors.top: parent.top
                        anchors.bottom: parent.bottom
                        anchors.left: resultList.right
                        anchors.leftMargin: 13
                        anchors.right: parent.right

                        Text {
                            id: previewName
                            anchors.top: parent.top
                            anchors.left: parent.left
                            anchors.right: parent.right
                            text: {
                                const it = root.filteredItems[root.selectedIndex];
                                if (root.tldrMode) return root.tldrTool;
                                if (root.ghMode) return root.previewRepo;
                                if (root.procMode) return it ? it.title : "";
                                if (root.themeMode) return it ? it.title : "";
                                return root.previewPath ? Data.basename(root.previewPath) : "";
                            }
                            color: root.ink
                            font.family: root.mono
                            font.pixelSize: 13
                            font.weight: Font.Medium
                            font.letterSpacing: 1
                            wrapMode: Text.WrapAnywhere
                            maximumLineCount: 2
                            elide: Text.ElideRight
                        }
                        Text {
                            id: previewDir
                            anchors.top: previewName.bottom
                            anchors.topMargin: 2
                            anchors.left: parent.left
                            anchors.right: parent.right
                            text: {
                                const it = root.filteredItems[root.selectedIndex];
                                if (root.tldrMode) return root.tldrTool.length === 0
                                    ? "type a command name after $"
                                    : "tldr  ·  ↵ opens terminal with command ready";
                                if (root.ghMode) return root.previewRepoUrl;
                                if (root.procMode) return it ? ("pid " + (it.pid || "") + "  ·  ↵ kills (SIGTERM)") : "";
                                if (root.themeMode) return it
                                    ? (it.isActive ? "ACTIVE  ·  ↵ reapplies" : "↵ applies theme")
                                    : "";
                                return root.previewPath ? Data.tildify(Data.dirname(root.previewPath), root.homeDir) : "";
                            }
                            color: root.inkDeep
                            font.family: root.mono
                            font.pixelSize: 10
                            font.letterSpacing: 1
                            elide: Text.ElideLeft
                            opacity: 0.75
                        }
                        Rectangle {
                            id: previewSep
                            anchors.top: previewDir.bottom
                            anchors.topMargin: 8
                            anchors.left: parent.left
                            anchors.right: parent.right
                            height: 1
                            color: root.sep
                            visible: root.previewHasContent
                        }

                        Item {
                            id: previewBody
                            anchors.top: previewSep.bottom
                            anchors.topMargin: 10
                            anchors.left: parent.left
                            anchors.right: parent.right
                            anchors.bottom: parent.bottom
                            clip: true

                            Text {
                                anchors.centerIn: parent
                                visible: !root.previewHasContent
                                text: {
                                    if (root.tldrMode) {
                                        if (root.tldrTool.length === 0) return "TYPE A COMMAND";
                                        return root.tldrRunning ? "FETCHING…" : "NO TLDR PAGE";
                                    }
                                    if (root.ghMode)    return "SELECT A REPO";
                                    if (root.procMode)  return "SELECT A PROCESS";
                                    if (root.themeMode) return "SELECT A THEME";
                                    return root.query.length === 0 ? "PREVIEW APPEARS HERE" : "SELECT A FILE";
                                }
                                color: root.inkDeep
                                font.family: root.mono
                                font.pixelSize: 10
                                font.letterSpacing: 3
                                opacity: 0.5
                            }

                            // sourceSize caps decode memory so a 6000x4000
                            // photo doesn't allocate its full pixel buffer
                            // just to render at ~500px.
                            Image {
                                anchors.fill: parent
                                anchors.margins: 4
                                visible: root.previewKind === "image"
                                source: root.previewKind === "image"
                                        ? "file://" + root.previewPath
                                        : ""
                                sourceSize.width: 1024
                                sourceSize.height: 1024
                                fillMode: Image.PreserveAspectFit
                                asynchronous: true
                                smooth: true
                            }

                            Text {
                                anchors.fill: parent
                                visible: root.previewKind === "text"
                                text: root.previewText
                                color: root.ink
                                font.family: root.mono
                                font.pixelSize: 10
                                lineHeight: 1.3
                                wrapMode: Text.Wrap
                                textFormat: Text.PlainText
                                elide: Text.ElideRight
                                maximumLineCount: Math.max(1, Math.floor(previewBody.height / 13))
                            }

                            Text {
                                anchors.fill: parent
                                visible: root.previewKind === "meta"
                                text: root.previewMeta
                                color: root.inkDeep
                                font.family: root.mono
                                font.pixelSize: 11
                                lineHeight: 1.4
                                wrapMode: Text.WordWrap
                                textFormat: Text.PlainText
                            }

                            // Wheel-scrollable preview. `interactive: false`
                            // disables Flickable's own drag-to-scroll so the
                            // inner TextEdit's drag-to-select wins; wheel
                            // events still scroll via Flickable's separate
                            // wheel handling. contentY resets to 0 whenever
                            // the tldr text changes so a fresh fetch always
                            // starts at the top.
                            Flickable {
                                id: tldrPreviewScroll
                                anchors.fill: parent
                                visible: root.tldrMode && root.tldrPreview !== ""
                                contentWidth: width
                                contentHeight: tldrPreviewEdit.implicitHeight
                                clip: true
                                interactive: false
                                boundsBehavior: Flickable.StopAtBounds

                                Connections {
                                    target: root
                                    function onTldrPreviewChanged() { tldrPreviewScroll.contentY = 0; }
                                }

                                // Mouse wheel scroll. Flickable's built-in
                                // wheel handling is gated by `interactive`,
                                // which we keep false so TextEdit can own
                                // drag-to-select. A WheelHandler bypasses
                                // that gate, scrolling contentY directly.
                                WheelHandler {
                                    onWheel: (event) => {
                                        const f = tldrPreviewScroll;
                                        const max = Math.max(0, f.contentHeight - f.height);
                                        f.contentY = Math.max(0, Math.min(max,
                                            f.contentY - event.angleDelta.y * 0.5));
                                    }
                                }

                                // TextEdit (not Text) so the user can mouse-
                                // drag to select and copy. activeFocusOnPress
                                // false means clicking in the preview doesn't
                                // steal keystrokes from the search input;
                                // selection still tracks the mouse and Ctrl+C
                                // at the root key handler copies via the
                                // edit's copy() method. persistentSelection
                                // keeps the highlight visible while focus
                                // stays on the search input.
                                TextEdit {
                                    id: tldrPreviewEdit
                                    width: tldrPreviewScroll.width
                                    text: root.formatTldrHtml(root.tldrPreview)
                                    color: root.ink
                                    font.family: root.mono
                                    font.pixelSize: 13
                                    wrapMode: TextEdit.Wrap
                                    textFormat: TextEdit.RichText
                                    readOnly: true
                                    selectByMouse: true
                                    persistentSelection: true
                                    activeFocusOnPress: false
                                    selectionColor: root.indigo
                                    selectedTextColor: root.paper
                                }
                            }

                            Text {
                                anchors.fill: parent
                                visible: root.ghMode && root.previewRepoUrl !== ""
                                text: root.previewReadme
                                color: root.ink
                                font.family: root.mono
                                font.pixelSize: 10
                                lineHeight: 1.3
                                wrapMode: Text.Wrap
                                textFormat: Text.PlainText
                                elide: Text.ElideRight
                                maximumLineCount: Math.max(1, Math.floor(previewBody.height / 13))
                            }

                            // Process detail (cmdline + ps stats).
                            Text {
                                anchors.fill: parent
                                visible: root.procMode && root.procPreviewText !== ""
                                text: root.procPreviewText
                                color: root.ink
                                font.family: root.mono
                                font.pixelSize: 10
                                lineHeight: 1.4
                                wrapMode: Text.Wrap
                                textFormat: Text.PlainText
                            }

                            // Theme preview image: themes ship a
                            // preview.png (lock screen sample) or, when
                            // absent, fall back to the first file in the
                            // backgrounds/ subdir. Themes.qml resolves
                            // the path; missing themes get "" and the
                            // image stays invisible so the swatches
                            // below take the whole pane.
                            Image {
                                id: themeImg
                                anchors.top: parent.top
                                anchors.left: parent.left
                                anchors.right: parent.right
                                visible: root.themeMode && status === Image.Ready
                                height: visible ? Math.min(implicitHeight, previewBody.height * 0.6) : 0
                                source: {
                                    if (!root.themeMode) return "";
                                    const it = root.filteredItems[root.selectedIndex];
                                    return (it && it.previewImage) ? "file://" + it.previewImage : "";
                                }
                                fillMode: Image.PreserveAspectFit
                                sourceSize.width: 1024
                                sourceSize.height: 1024
                                asynchronous: true
                                smooth: true
                                cache: true
                            }

                            // Theme swatch grid. Each swatch is a 30x30
                            // tile coloured from the theme's colors.toml;
                            // Flow lets them reflow if the preview pane
                            // is narrowed. Sits under the preview image
                            // when one resolves, otherwise pinned to the
                            // top of the pane.
                            Flow {
                                anchors.top: themeImg.visible ? themeImg.bottom : parent.top
                                anchors.topMargin: themeImg.visible ? 10 : 0
                                anchors.left: parent.left
                                anchors.right: parent.right
                                visible: root.themeMode
                                spacing: 6
                                Repeater {
                                    model: {
                                        const it = root.filteredItems[root.selectedIndex];
                                        return (it && it.swatches) ? it.swatches : [];
                                    }
                                    delegate: Rectangle {
                                        required property string modelData
                                        width: 30
                                        height: 30
                                        radius: 2
                                        color: modelData
                                        border.width: 1
                                        border.color: root.sep
                                    }
                                }
                            }
                        }
                    }
                }

                Rectangle { width: parent.width; height: 1; color: root.sep }

                // Footer surfaces the exec line of the current selection so
                // you can verify what's about to fire before pressing Enter.
                Item {
                    width: parent.width
                    height: 22

                    Text {
                        anchors.left: parent.left
                        anchors.verticalCenter: parent.verticalCenter
                        width: parent.width - 4
                        elide: Text.ElideRight
                        text: {
                            const it = root.filteredItems[root.selectedIndex];
                            if (!it) return "";
                            if (it.isCategory)  return "→ open " + it.target.toLowerCase();
                            if (it.isProcess)   return "↵ kill " + (it.pid || "");
                            if (it.isTheme)     return "↵ omarchy-theme-set " + (it.themeName || "");
                            return "$ " + it.exec;
                        }
                        color: root.inkDeep
                        font.family: root.mono
                        font.pixelSize: 10
                        font.letterSpacing: 1
                        opacity: 0.65
                    }
                }
            }
        }
    }
}
