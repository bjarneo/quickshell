import QtQuick
import Quickshell
import Quickshell.Wayland
import Quickshell.Io
import Quickshell.Hyprland
import "Data.js" as Data
import "omni" as Omni
import "omni/Tiles.js" as Tiles

// Omni-menu palette. Fuses installed apps (.desktop scan) with every
// `omarchy-menu` action, scored against title, category, and per-entry
// synonyms (so "wallpaper" finds Background, "reboot" finds Restart).
// Drill-down rows pivot the list to a category, fd file search, gh repo
// search, processes, or themes. Toggle via:
//   qs -c desktop ipc call palette toggle
//
// Source layout: this file is the entry and keeps all state (search
// index, scoring, mode flags, IPC, shortcuts, the keyboard handler,
// and the panel chrome). Visual subtrees live alongside in `omni/`:
//   omni/HeaderBar.qml       title + count + hint
//   omni/SearchInput.qml     prompt glyph + query text + caret
//   omni/QuickContainer.qml  quick-mode tile grid + detail panel
//   omni/ResultList.qml      ListView + row delegate
//   omni/PreviewPane.qml     preview header + body for all modes
//   omni/Footer.qml          exec line for the selected item
//   omni/Format.js           markdown formatters (tldr, chat)
//   omni/Tiles.js            quick-tile static data + dyn builder
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
    // Sibling query-shape mode: `? <question>` pivots to a local
    // Ollama chat preview against qwen3.5:0.8b.
    readonly property bool chatMode: root.query.charAt(0) === "?"
    // Live font multiplier — every `font.pixelSize` binding in this
    // file multiplies its base by this value. Ctrl++ / Ctrl+- nudge
    // it in 0.1 steps; Ctrl+= resets to 1.0. Clamped to keep the
    // panel usable at extremes.
    property real fontScale: 1.0
    function bumpFontScale(delta) {
        const next = Math.max(0.7, Math.min(2.0, root.fontScale + delta));
        // Snap to one decimal so successive bumps don't drift on
        // floating-point round-off.
        root.fontScale = Math.round(next * 10) / 10;
    }
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
    readonly property var quickTilesBase: Tiles.base

    // Dynamic per-tile data — keyed by tile.key. Gated on `visible_`
    // so navbar ticks don't wake the rebuild while the palette is
    // closed (the previous snapshot keeps the Repeater happy when the
    // user re-opens, before this binding re-evaluates).
    property var _quickTilesDynCache: ({})
    readonly property var quickTilesDyn: {
        if (!root.visible_) return root._quickTilesDynCache;
        // No navbar yet (shell reload, hot-swap, or a tick before the
        // sibling Navbar wires up): return an empty snapshot but do NOT
        // store it, so the cached previous-good values survive the gap
        // and the close-fade never flashes blank tiles.
        if (!root.navbar) return ({});
        const dyn = Tiles.buildDyn(root.navbar);
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
        active: root.ghMode && !root.tldrMode && !root.chatMode
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
        active: root.fileMode && !root.tldrMode && !root.chatMode
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
        active: root.procMode && !root.chatMode
        selectedItem: root.filteredItems[root.selectedIndex] || null
    }
    readonly property alias procItems:    processes.items
    readonly property alias procRunning:  processes.running
    readonly property alias procPreviewText: processes.previewText
    readonly property alias procPreviewPid:  processes.previewPid

    Themes {
        id: themes
        active: root.themeMode && !root.chatMode
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

    // Local-LLM chat preview. Triggered by `? <question>` in the query.
    OllamaChat {
        id: ollamaChat
        query: root.query
        active: root.chatMode
    }
    readonly property alias chatItems:     ollamaChat.items
    readonly property alias chatRunning:   ollamaChat.running
    readonly property alias chatPreview:   ollamaChat.previewText
    readonly property alias chatStatus:    ollamaChat.status
    readonly property alias chatPrompt:    ollamaChat.prompt
    readonly property alias chatSubmitted: ollamaChat.submitted
    readonly property alias chatModel:     ollamaChat.model_

    readonly property bool previewActive: root.tldrMode || root.chatMode || root.fileMode || root.ghMode || root.procMode || root.themeMode
    readonly property bool previewHasContent: {
        if (root.tldrMode) return root.tldrPreview !== "";
        if (root.chatMode) {
            // Probing: no content yet. Status != "ok": show the
            // install/start/pull hint as content. OK + not submitted:
            // empty (the placeholder hint shows). OK + submitted:
            // there's a streaming or completed answer.
            if (root.chatStatus === "") return false;
            if (root.chatStatus !== "ok") return true;
            if (!root.chatSubmitted) return false;
            return root.chatPreview !== "";
        }
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
    function close() {
        root.visible_ = false;
        // Cancel any in-flight stream and zero chat state so the next
        // session starts fresh. The ollama daemon itself is left
        // running — we don't manage its lifecycle, only our use of it.
        ollamaChat.clear();
    }
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
        ollamaChat.clear();
        // Processes/Themes own their own clear()-on-deactivate via their
        // `active` binding, so the shell doesn't have to nudge them when
        // the filter changes — they react automatically.
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
        // ollama chat → Enter behaviour depends on the readiness state:
        //   no-ollama  no-op (user installs themselves; we don't run a
        //              package manager unprompted)
        //   no-daemon  start the daemon in a floating terminal
        //   no-model   pull qwen3.5:0.8b in a floating terminal
        //   ok+!sub    submit the prompt; preview streams inline,
        //              panel stays open
        //   ok+sub     no-op; user can edit and resubmit, or Esc out
        if (item.isOllama) {
            const status = ollamaChat.status;
            if (status === "no-ollama") {
                // Don't auto-install. The preview body has already
                // told the user what to do.
                return;
            }
            if (status === "no-daemon") {
                runner.command = ["setsid", "-f", "uwsm-app", "--",
                    "xdg-terminal-exec",
                    "--app-id=org.omarchy.terminal",
                    "--title=Omarchy",
                    "-e", "bash", "-c",
                    "echo 'Starting ollama daemon...'; "
                    + "systemctl --user start ollama 2>/dev/null "
                    + "|| sudo systemctl start ollama 2>/dev/null "
                    + "|| ollama serve; "
                    + "echo; echo '[done — close to return]'; exec bash"];
                runner.running = false;
                runner.running = true;
                root.close();
                return;
            }
            if (status === "no-model") {
                // Pull the model in a held-open terminal. The model id
                // is passed positionally as $1 so shell metacharacters
                // in it can never re-interpret the script (same
                // hardening as the probe in OllamaChat.qml). `exec bash`
                // at the end keeps the window up so the user can read
                // the pull output (and any errors) before closing.
                runner.command = ["setsid", "-f", "uwsm-app", "--",
                    "xdg-terminal-exec",
                    "--app-id=org.omarchy.terminal",
                    "--title=Omarchy",
                    "-e", "bash", "-c",
                    "ollama pull \"$1\"; "
                    + "echo; echo '[done — close to return]'; exec bash",
                    "--", ollamaChat.model_];
                runner.running = false;
                runner.running = true;
                root.close();
                return;
            }
            if (status === "ok" && !ollamaChat.submitted) {
                ollamaChat.submit();
                // Keep the panel open so the response streams in.
                return;
            }
            // status === "ok" && submitted: stay open, no-op. User
            // can edit the prompt and the new submit fires on Enter.
            return;
        }
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
        // chat mode is the other query-shape mode; same one-row pivot.
        if (root.chatMode) return root.chatItems;
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
        resultListInstance.list.positionViewAtIndex(next, ListView.Contain);
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
                const bodyItem = quickContainer.bodyLoaderItem.item;
                if (root.quickExpanded
                    && bodyItem
                    && typeof bodyItem.kbdHandle === "function"
                    && bodyItem.kbdHandle(e2)) {
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
                } else if (root.chatMode && root.previewHasContent
                           && (e2.key === Qt.Key_Up || e2.key === Qt.Key_Down
                               || e2.key === Qt.Key_PageUp || e2.key === Qt.Key_PageDown
                               || e2.key === Qt.Key_Home || e2.key === Qt.Key_End
                               || e2.key === Qt.Key_Tab || e2.key === Qt.Key_Backtab)) {
                    // chat mode: same scroll routing as tldr mode below.
                    // List nav is a no-op here (single synthetic row).
                    const f = previewPaneInstance.chatFlickable;
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
                } else if (root.tldrMode && root.tldrPreview !== ""
                           && (e2.key === Qt.Key_Up || e2.key === Qt.Key_Down
                               || e2.key === Qt.Key_PageUp || e2.key === Qt.Key_PageDown
                               || e2.key === Qt.Key_Home || e2.key === Qt.Key_End
                               || e2.key === Qt.Key_Tab || e2.key === Qt.Key_Backtab)) {
                    // tldr mode has a single synthetic row, so list nav is
                    // a no-op. Route arrow/page/home/end (and Tab/Shift+Tab,
                    // which would otherwise wrap the same row to itself) to
                    // the preview Flickable instead.
                    const f = previewPaneInstance.tldrFlickable;
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
                    resultListInstance.list.positionViewAtIndex(0, ListView.Beginning);
                    event.accepted = true;
                } else if (e2.key === Qt.Key_End) {
                    root.selectedIndex = Math.max(0, root.filteredItems.length - 1);
                    resultListInstance.list.positionViewAtIndex(root.selectedIndex, ListView.End);
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
                    if (it && !it.isCategory && !it.isTldr && !it.isOllama) bookmarks.toggleFavourite(it);
                    event.accepted = true;
                } else if ((e2.modifiers & Qt.ControlModifier)
                           && (e2.key === Qt.Key_Plus || e2.key === Qt.Key_Equal
                               || e2.key === Qt.Key_Minus)) {
                    // Ctrl++ / Ctrl+- nudge the omni-menu font scale;
                    // Ctrl+= resets to default. Plus is reached via
                    // Shift+= on US layouts (Qt delivers Qt.Key_Plus),
                    // and via a dedicated key on numpads / EU layouts.
                    if (e2.key === Qt.Key_Plus) root.bumpFontScale(+0.1);
                    else if (e2.key === Qt.Key_Minus) root.bumpFontScale(-0.1);
                    else /* Key_Equal without Shift */ root.fontScale = 1.0;
                    event.accepted = true;
                } else if (e2.key === Qt.Key_C && (e2.modifiers & Qt.ControlModifier)
                           && root.chatMode && root.chatPreview !== "") {
                    // Ctrl+C: if the user dragged a selection in the
                    // rendered RichText edit, copy that (lossy — Qt
                    // strips inline `code` backticks during conversion,
                    // but it's what they asked for). With no selection,
                    // copy the full raw markdown from the hidden plain-
                    // text shadow so pasted commands keep their syntax.
                    if (previewPaneInstance.chatEdit.selectedText.length > 0) {
                        previewPaneInstance.chatEdit.copy();
                    } else {
                        previewPaneInstance.chatPlain.selectAll();
                        previewPaneInstance.chatPlain.copy();
                        previewPaneInstance.chatPlain.deselect();
                    }
                    event.accepted = true;
                } else if (e2.key === Qt.Key_C && (e2.modifiers & Qt.ControlModifier)
                           && root.tldrMode && root.tldrPreview !== "") {
                    // Ctrl+C in tldr mode: copy the active selection if
                    // there is one, otherwise copy the whole rendered
                    // preview. The TextEdit's `copy()` works without
                    // active focus, so the search input keeps keystrokes.
                    if (previewPaneInstance.tldrEdit.selectedText.length > 0) {
                        previewPaneInstance.tldrEdit.copy();
                    } else {
                        previewPaneInstance.tldrEdit.selectAll();
                        previewPaneInstance.tldrEdit.copy();
                        previewPaneInstance.tldrEdit.deselect();
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

                Omni.HeaderBar {
                    omni: root
                    processes: processes
                    themes: themes
                    bookmarks: bookmarks
                }

                Rectangle { width: parent.width; height: 1; color: root.sep }

                Omni.QuickContainer {
                    id: quickContainer
                    omni: root
                    panel: panel
                }

                Omni.SearchInput { omni: root }

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

                    Omni.ResultList {
                        id: resultListInstance
                        anchors.top: parent.top
                        anchors.bottom: parent.bottom
                        anchors.left: parent.left
                        // Follows card.width's Behavior animation — adding a
                        // second Behavior here would animate to a moving
                        // target and produce staggered motion.
                        width: parent.width * listArea.listFraction
                        omni: root
                        bookmarks: bookmarks
                        processes: processes
                        themes: themes
                        ollamaChat: ollamaChat
                    }

                    Rectangle {
                        visible: root.previewActive
                        anchors.top: parent.top
                        anchors.bottom: parent.bottom
                        anchors.left: resultListInstance.right
                        width: 1
                        color: root.sep
                    }

                    Omni.PreviewPane {
                        id: previewPaneInstance
                        visible: root.previewActive
                        anchors.top: parent.top
                        anchors.bottom: parent.bottom
                        anchors.left: resultListInstance.right
                        anchors.leftMargin: 13
                        anchors.right: parent.right
                        omni: root
                        ollamaChat: ollamaChat
                    }
                }

                Rectangle { width: parent.width; height: 1; color: root.sep }

                Omni.Footer { omni: root }
            }
        }
    }
}
