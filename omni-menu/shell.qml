import QtQuick
import QtQuick.Layouts
import QtQuick.Effects
import Quickshell
import Quickshell.Wayland
import Quickshell.Io
import "Data.js" as Data

// Omni-menu. A single command palette that fuses installed apps (.desktop
// scan) with every action exposed by `omarchy-menu` — Style, Setup, Install,
// Remove, Update, System, Toggle, Trigger, Capture, Share, Learn. Search
// indexes title, category, and a curated synonym list per entry, so a query
// like "wallpaper" lands on Background, "dark mode" lands on Theme, "reboot"
// lands on Restart, etc.
//
// Visual language follows navbar/shell.qml: Kanagawa Dragon typography on
// the omarchy live palette (~/.config/omarchy/current/theme/colors.toml),
// mono caps with letter-spacing for headings, a centred card with a
// scale-from-centre reveal, Esc/Q to dismiss.
//
// Toggle from a Hyprland keybind:
//   bind = SUPER, SPACE, exec, qs ipc call palette toggle
ShellRoot {
    id: root

    // Theme.qml owns the live palette (sourced from omarchy's colors.toml)
    // and its derived shades. Aliased at the root so the existing UI
    // bindings (root.paper, root.ink, …) keep working unchanged.
    Theme { id: theme }
    readonly property alias paper:   theme.paper
    readonly property alias ink:     theme.ink
    readonly property alias inkDeep: theme.inkDeep
    readonly property alias sumi:    theme.sumi
    readonly property alias indigo:  theme.indigo
    readonly property alias seal:    theme.seal
    readonly property alias bg:      theme.bg
    readonly property alias fg:      theme.fg
    readonly property alias muted:   theme.muted
    readonly property alias sep:     theme.sep
    readonly property alias rowHi:   theme.rowHi
    readonly property alias rowSel:  theme.rowSel

    // Scoring weights and result cap. omarchy-menu has ~125 entries plus the
    // 12 nav rows plus ~80-200 .desktop apps, so the cap lets a quick
    // page-down still reach near-matches without overdrawing.
    readonly property int scPrefix: 100
    readonly property int scTitle:  60
    readonly property int scKw:     20
    readonly property int scCat:    10
    readonly property int maxResults: 250

    readonly property string mono:  "JetBrainsMono Nerd Font"
    readonly property string serif: "serif"

    // .desktop scanner — one-shot at startup, refreshable via IPC.
    // Annotated apps land on `appScan.apps`; `allItems` rebinds when they
    // arrive so the pool is always omarchy actions + scanned apps.
    AppScan {
        id: appScan
        onScanned: root.allItems = root.omarchy.concat(appScan.apps)
    }
    readonly property alias appsLoaded: appScan.loaded

    // ---------- Visibility / state ----------
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
    readonly property bool ghMode: root.categoryFilter === Data.ghCategory

    // gh CLI-backed repo search + README preview.
    GhSearch {
        id: ghSearch
        query: root.query
        active: root.ghMode
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
        active: root.fileMode
        selectedItem: root.filteredItems[root.selectedIndex] || null
    }
    readonly property alias fileItems:    fileSearch.items
    readonly property alias fdRunning:    fileSearch.running
    readonly property alias previewPath:  fileSearch.previewPath
    readonly property alias previewText:  fileSearch.previewText
    readonly property alias previewMeta:  fileSearch.previewMeta
    readonly property alias previewKind:  fileSearch.previewKind

    readonly property bool previewActive: root.fileMode || root.ghMode
    readonly property bool previewHasContent: root.previewPath !== "" || root.previewRepoUrl !== ""

    readonly property string homeDir: Quickshell.env("HOME")

    function open() {
        root.query = "";
        root.selectedIndex = 0;
        root.categoryFilter = "";
        root.visible_ = true;
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
    property var allItems: []

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



    // FileSearch and GhSearch both react to query/selectedItem changes
    // internally via their `query` and `selectedItem` bindings, so the
    // shell doesn't have to forward anything explicitly anymore.

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
        // File and GitHub modes are their own worlds: fd and gh already
        // did the filtering, so we just pass their results through.
        if (root.fileMode) return root.fileItems;
        if (root.ghMode)   return root.ghItems;

        const tokens = root.queryTokens;
        const filter = root.categoryFilter;
        const cap = root.maxResults;

        const pool = filter !== ""
            ? root.allItems.filter(it => it.category === filter)
            : root.navRows.concat(root.allItems);

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

    Component.onCompleted: {
        root.omarchy = Data.annotate(Data.omarchyItems);
        root.nav     = Data.annotate(Data.categoryNav);
        root.allItems = root.omarchy.slice();
    }

    // ---------- IPC ----------
    IpcHandler {
        target: "palette"
        function toggle(): void { root.toggle() }
        function open(): void { root.open() }
        function close(): void { root.close() }
        function refresh(): void { appScan.refresh(); }
    }

    // ---------- Idle self-exit ----------
    // Daemon exits after the palette has been closed for this long, so it
    // doesn't sit resident overnight. The toggle.sh wrapper cold-starts it
    // again on the next SUPER+SPACE or navbar click. Reset whenever the
    // palette is visible.
    readonly property int idleTimeoutMs: 5 * 60 * 1000
    Timer {
        id: idleTimer
        interval: root.idleTimeoutMs
        running: !root.visible_
        repeat: false
        onTriggered: Qt.quit()
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
        Behavior on reveal {
            NumberAnimation {
                duration: root.visible_ ? 220 : 140
                easing.type: root.visible_ ? Easing.OutCubic : Easing.InCubic
            }
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
            // Wide in search-with-preview modes (file, github) for a
            // ~520px preview pane next to the result list; narrow back to
            // 640 elsewhere so apps/omarchy mode keeps its compact feel.
            width: (root.fileMode || root.ghMode) ? 1000 : 640
            Behavior on width {
                NumberAnimation { duration: 180; easing.type: Easing.OutCubic }
            }
            // Cap the card so it never exceeds the screen even on small
            // displays; cardCol implicitHeight covers the search + list +
            // footer block.
            height: Math.min(cardCol.implicitHeight + 34, parent.height * 0.72)
            color: root.bg
            border.color: root.sep
            border.width: 1
            radius: 0
            transformOrigin: Item.Center
            scale: panel.reveal

            // Swallow clicks so the underlying dismiss MouseArea doesn't fire.
            MouseArea { anchors.fill: parent }

            focus: root.visible_
            Keys.onPressed: function(event) {
                if (event.key === Qt.Key_Escape) {
                    // First Esc steps out of a drilled-in category; a
                    // second Esc closes the palette. Drives muscle-memory
                    // closer to "back" than to "close everything".
                    if (!root.goUp()) root.close();
                    event.accepted = true;
                } else if (event.key === Qt.Key_Down
                           || (event.key === Qt.Key_Tab && !(event.modifiers & Qt.ShiftModifier))) {
                    // Tab + Down step forward, Shift+Tab + Up step backward,
                    // both wrap. Paging clamps (see Key_PageDown). Matches
                    // launcher convention everywhere else.
                    root.moveSelection(1, true);
                    event.accepted = true;
                } else if (event.key === Qt.Key_Up
                           || event.key === Qt.Key_Backtab
                           || (event.key === Qt.Key_Tab && (event.modifiers & Qt.ShiftModifier))) {
                    root.moveSelection(-1, true);
                    event.accepted = true;
                } else if (event.key === Qt.Key_PageDown) {
                    root.moveSelection(8, false);
                    event.accepted = true;
                } else if (event.key === Qt.Key_PageUp) {
                    root.moveSelection(-8, false);
                    event.accepted = true;
                } else if (event.key === Qt.Key_Home) {
                    root.selectedIndex = 0;
                    resultList.positionViewAtIndex(0, ListView.Beginning);
                    event.accepted = true;
                } else if (event.key === Qt.Key_End) {
                    root.selectedIndex = Math.max(0, root.filteredItems.length - 1);
                    resultList.positionViewAtIndex(root.selectedIndex, ListView.End);
                    event.accepted = true;
                } else if (event.key === Qt.Key_Return || event.key === Qt.Key_Enter) {
                    const it = root.filteredItems[root.selectedIndex];
                    if (it) root.activate(it);
                    event.accepted = true;
                } else if (event.key === Qt.Key_Backspace) {
                    // Backspace deletes a char first; once the query is
                    // empty it walks back up one level so the same key
                    // unwinds both the typed query and the breadcrumb.
                    if (root.query.length > 0) root.query = root.query.slice(0, -1);
                    else root.goUp();
                    event.accepted = true;
                } else if (event.text && event.text.length === 1) {
                    const ch = event.text;
                    // Printable range; lets letters, digits, and spaces in,
                    // keeps modifier-driven control codes out.
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
                                    if (root.query.length === 0) return "TYPE TO SEARCH GITHUB";
                                    if (root.ghRunning) return "SEARCHING GITHUB…";
                                    const total = root.filteredItems.length;
                                    return total === 0
                                        ? "NO REPOS MATCH"
                                        : total + " REPO" + (total === 1 ? "" : "S");
                                }
                                const total = root.filteredItems.length;
                                if (root.query.length === 0) {
                                    return total + " ENTRIES  ·  " + root.allItems.length + " TOTAL";
                                }
                                return total === 0
                                    ? "NO MATCHES"
                                    : total + " MATCH" + (total === 1 ? "" : "ES");
                            }
                            color: root.sumi
                            font.family: root.mono
                            font.pixelSize: 11
                            font.letterSpacing: 2
                        }
                    }

                    Text {
                        anchors.right: parent.right
                        anchors.verticalCenter: parent.verticalCenter
                        text: root.categoryFilter === ""
                              ? "↑↓ / TAB  ·  ↵ OPEN  ·  ESC CLOSE"
                              : "↑↓ / TAB  ·  ↵ " + (root.fileMode ? "OPEN FILE" : (root.ghMode ? "OPEN REPO" : "RUN")) + "  ·  ESC BACK"
                        color: root.sumi
                        font.family: root.mono
                        font.pixelSize: 10
                        font.letterSpacing: 2
                        opacity: 0.6
                    }
                }

                Rectangle { width: parent.width; height: 1; color: root.sep }

                // No focus indicator on TextInput — the caret and the
                // live count above act as the focus tell.
                Item {
                    width: parent.width
                    height: 34

                    Text {
                        id: searchPrompt
                        anchors.left: parent.left
                        anchors.verticalCenter: parent.verticalCenter
                        text: root.fileMode ? "󰉖" : (root.ghMode ? "󰊤" : "󰍉")
                        color: root.seal
                        font.family: root.mono
                        font.pixelSize: 16
                    }

                    Text {
                        id: queryText
                        anchors.left: searchPrompt.right
                        anchors.leftMargin: 10
                        anchors.verticalCenter: parent.verticalCenter
                        text: root.query.length === 0
                              ? (root.fileMode
                                 ? "Type to search files in ~ …"
                                 : root.ghMode
                                    ? "Type to search GitHub repos …"
                                    : "Type to search apps, themes, settings…")
                              : root.query
                        color: root.query.length === 0 ? root.sumi : root.ink
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

                Rectangle { width: parent.width; height: 1; color: root.sep }

                // Fixed row height in the delegate keeps positionViewAtIndex
                // honest under fast keyboard navigation; the wrapping Item's
                // clip prevents the bottom row bleeding into the footer
                // hairline mid-scroll.
                Item {
                    id: listArea
                    width: parent.width
                    height: Math.max(60, card.height - 34 - 43 - 34 - 22 - 12 * 5)
                    clip: true

                    // In file mode the list shrinks to ~44% of the card so
                    // a 520px-ish preview pane fits alongside it. The 1px
                    // hairline + 1px inverse hairline divider sits between
                    // them. animated alongside card.width for a single
                    // smooth widen-and-split motion.
                    readonly property real listFraction: (root.fileMode || root.ghMode) ? 0.44 : 1.0

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
                                Behavior on color { ColorAnimation { duration: 90 } }
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
                                    Behavior on colorizationColor { ColorAnimation { duration: 90 } }
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
                                color: row.isSelected ? root.seal : root.sumi
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
                                if (root.fileMode) {
                                    if (root.query.length === 0) return "TYPE TO SEARCH ~";
                                    if (root.fdRunning) return "SEARCHING…";
                                    return "NO FILES MATCH";
                                }
                                if (root.ghMode) {
                                    if (root.query.length === 0) return "TYPE TO SEARCH GITHUB";
                                    if (root.ghRunning) return "SEARCHING GITHUB…";
                                    return "NO REPOS MATCH";
                                }
                                return root.appsLoaded ? "NOTHING MATCHES" : "INDEXING APPS…";
                            }
                            color: root.sumi
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
                            text: root.ghMode
                                  ? root.previewRepo
                                  : (root.previewPath ? Data.basename(root.previewPath) : "")
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
                            text: root.ghMode
                                  ? root.previewRepoUrl
                                  : (root.previewPath ? Data.tildify(Data.dirname(root.previewPath), root.homeDir) : "")
                            color: root.sumi
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
                                text: root.query.length === 0
                                      ? "PREVIEW APPEARS HERE"
                                      : (root.ghMode ? "SELECT A REPO" : "SELECT A FILE")
                                color: root.sumi
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
                                color: root.sumi
                                font.family: root.mono
                                font.pixelSize: 11
                                lineHeight: 1.4
                                wrapMode: Text.WordWrap
                                textFormat: Text.PlainText
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
                            if (it.isCategory) return "→ open " + it.target.toLowerCase();
                            return "$ " + it.exec;
                        }
                        color: root.sumi
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
