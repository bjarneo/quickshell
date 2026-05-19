import QtQuick
import Quickshell
import Quickshell.Io
import "Palette.js" as Palette

// `seal` rides `driftAmount` (200ms rise, 2.8s taper) so each theme swap
// reads as a breath rather than a hard cut. The 1.55s lead-in lets
// theme-wash's animation exit first.
Item {
    id: theme

    readonly property string colorsPath: Quickshell.env("HOME") + "/.config/omarchy/current/theme/colors.toml"

    property color paper:   "#181616"
    property color ink:     "#c5c9c5"
    property color inkDeep: "#c8c093"
    property color sumi:    "#a6a69c"
    property color indigo:  "#658594"
    property color sealRaw: "#c4746e"
    property real  driftAmount: 0

    readonly property color seal: Qt.hsva(
        sealRaw.hsvHue,
        Math.min(1, sealRaw.hsvSaturation + driftAmount * 0.05),
        sealRaw.hsvValue,
        sealRaw.a
    )

    readonly property string serif: "serif"
    readonly property string mono:  "JetBrainsMono Nerd Font"

    readonly property color bg:     Qt.rgba(paper.r, paper.g, paper.b, 0.94)
    readonly property color fg:     ink
    readonly property color muted:  sumi
    readonly property color accent: seal
    readonly property color warn:   seal
    readonly property color sep:    Qt.rgba(ink.r, ink.g, ink.b, 0.18)
    readonly property color rowHi:  Qt.rgba(ink.r, ink.g, ink.b, 0.06)
    readonly property color rowSel: Qt.rgba(seal.r, seal.g, seal.b, 0.18)

    // Name of the last theme applied via IPC. Used to suppress the drift
    // animation when the hook pushes the same theme twice or races the
    // startup FileView read.
    property string lastAppliedName: ""

    // watchChanges: false — `omarchy theme set` does an atomic rm+mv on
    // the theme dir, which would race an inotify watch. The hook tells us
    // when to reload instead.
    FileView {
        id: paletteFile
        path: theme.colorsPath
        watchChanges: false
        onLoaded: Palette.apply(theme, Palette.parse(paletteFile.text()))
    }

    Timer {
        id: driftDelay
        interval: 1550
        repeat: false
        onTriggered: driftAnim.restart()
    }

    SequentialAnimation {
        id: driftAnim
        NumberAnimation {
            target: theme; property: "driftAmount"
            from: 0; to: 1
            duration: 200
            easing.type: Easing.OutQuad
        }
        NumberAnimation {
            target: theme; property: "driftAmount"
            to: 0
            duration: 2800
            easing.type: Easing.OutCubic
        }
    }

    IpcHandler {
        target: "theme"
        function apply(payload: string): void {
            let p;
            try { p = JSON.parse(payload); }
            catch (e) { console.warn("theme.apply: bad payload —", e); return; }
            if (!p || !p.colors) return;
            Palette.apply(theme, Palette.mapKeys(p.colors));
            if (p.name && p.name !== theme.lastAppliedName) {
                theme.lastAppliedName = p.name;
                driftDelay.restart();
            }
        }
        function reload(): void {
            paletteFile.reload();
            driftDelay.restart();
        }
    }
}
