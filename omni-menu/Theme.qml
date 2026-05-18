import QtQuick
import Quickshell
import Quickshell.Io

// Live palette state, sourced from omarchy's current theme. parseColors
// remaps the six toml keys we care about onto Kanagawa Dragon names; the
// derived colors fall out as Qt.rgba expressions.
Item {
    id: theme

    readonly property string colorsPath: Quickshell.env("HOME") + "/.config/omarchy/current/theme/colors.toml"
    readonly property string themeNamePath: Quickshell.env("HOME") + "/.config/omarchy/current/theme.name"

    property color paper:   "#181616"
    property color ink:     "#c5c9c5"
    property color inkDeep: "#c8c093"
    property color sumi:    "#a6a69c"
    property color indigo:  "#658594"
    property color seal:    "#c4746e"

    readonly property color bg:     Qt.rgba(paper.r, paper.g, paper.b, 0.96)
    readonly property color fg:     ink
    readonly property color muted:  sumi
    readonly property color sep:    Qt.rgba(ink.r, ink.g, ink.b, 0.18)
    readonly property color rowHi:  Qt.rgba(ink.r, ink.g, ink.b, 0.06)
    readonly property color rowSel: Qt.rgba(seal.r, seal.g, seal.b, 0.18)

    function parseColors(text) {
        const want = { background: null, foreground: null, accent: null,
                       color1: null, color7: null, color8: null };
        const re = /^\s*([A-Za-z_][A-Za-z0-9_]*)\s*=\s*"([^"]+)"/;
        const lines = text.split("\n");
        for (let i = 0; i < lines.length; i++) {
            const m = lines[i].match(re);
            if (m && (m[1] in want)) want[m[1]] = m[2];
        }
        if (want.background) theme.paper   = want.background;
        if (want.foreground) theme.ink     = want.foreground;
        if (want.color7)     theme.inkDeep = want.color7;
        if (want.color8)     theme.sumi    = want.color8;
        if (want.accent)     theme.indigo  = want.accent;
        if (want.color1)     theme.seal    = want.color1;
    }

    FileView {
        id: paletteFile
        path: theme.colorsPath
        watchChanges: true
        onFileChanged: reload()
        onLoaded: theme.parseColors(paletteFile.text())
    }

    // omarchy-theme-set rm -rf's current/theme/ and mv's a fresh dir in, so
    // colors.toml gets a new inode each swap and paletteFile's inotify watch
    // dies with it. theme.name is rewritten in place, so its inode is stable
    // and works as a swap-detection beacon for re-arming paletteFile.
    FileView {
        id: themeMarker
        path: theme.themeNamePath
        watchChanges: true
        onFileChanged: { reload(); paletteFile.reload(); }
    }
}
