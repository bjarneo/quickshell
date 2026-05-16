import QtQuick
import Quickshell
import Quickshell.Wayland
import Quickshell.Io

// On every `omarchy theme set <name>`: old accent pulses out from centre,
// a splatter fan launches from an alternating corner, a sheen halo sweeps
// in, the new accent floods the row, the theme name pops, flecks settle,
// a closing ring snaps from the origin.
ShellRoot {
    id: root

    readonly property string colorsPath: Quickshell.env("HOME") + "/.config/omarchy/current/theme/colors.toml"
    readonly property string themeNamePath: Quickshell.env("HOME") + "/.config/omarchy/current/theme.name"

    property color accent:     "#5d799b"
    property color paper:      "#181616"
    property color ink:        "#c5c9c5"

    // Captured the instant a swap is detected, before paletteFile.reload()
    // overwrites root.accent. Stage 1 of the animation needs this.
    property color prevAccent: accent

    property string lastTheme: ""
    property int washCount: 0

    readonly property string mono: "JetBrainsMono Nerd Font"
    readonly property int barHeight: 26
    readonly property int washHeight: barHeight

    // Priority order for resolving the theme's main accent. Older or sparser
    // palettes may omit the explicit `accent` field, so we fall through to
    // color4 (conventional ANSI primary) and finally color1.
    readonly property var accentKeys: ["accent", "color4", "color1"]

    function parseColors(text) {
        const want = { background: null, foreground: null };
        for (let i = 0; i < accentKeys.length; i++) want[accentKeys[i]] = null;

        const re = /^\s*([A-Za-z_][A-Za-z0-9_]*)\s*=\s*"([^"]+)"/;
        const lines = text.split("\n");
        for (let i = 0; i < lines.length; i++) {
            const m = lines[i].match(re);
            if (m && m[1] in want) want[m[1]] = m[2];
        }

        for (let i = 0; i < accentKeys.length; i++) {
            const v = want[accentKeys[i]];
            if (v) { root.accent = v; break; }
        }
        if (want.background) root.paper = want.background;
        if (want.foreground) root.ink   = want.foreground;
    }

    function onThemeNameLoaded(name) {
        const trimmed = (name || "").trim();
        if (root.lastTheme === "") {
            root.lastTheme = trimmed;
            return;
        }
        if (trimmed && trimmed !== root.lastTheme) {
            root.prevAccent = root.accent;
            root.lastTheme = trimmed;
            root.washCount += 1;
            paletteFile.reload();
            washAnim.restart();
        }
    }

    // theme.name is the sole trigger. paletteFile is reloaded explicitly from
    // onThemeNameLoaded so we always parse exactly once per swap, in a known
    // order: theme name detected → palette refreshed → prevAccent captured →
    // animation restarted. Letting paletteFile watch on its own would race
    // with this and cause a double-parse on every swap.
    FileView {
        id: paletteFile
        path: root.colorsPath
        onLoaded: root.parseColors(paletteFile.text())
    }

    FileView {
        id: themeMarker
        path: root.themeNamePath
        watchChanges: true
        onFileChanged: reload()
        onLoaded: root.onThemeNameLoaded(themeMarker.text())
    }

    // Manual trigger for testing or shell-side hooks:
    //   qs -p ~/.config/quickshell/theme-wash/shell.qml ipc call wash run
    IpcHandler {
        target: "wash"
        function run(): void {
            root.prevAccent = root.accent;
            root.washCount += 1;
            paletteFile.reload();
            washAnim.restart();
        }
    }

    // Disc anchored at (cx, cy) with `r` radius. Used for every circular
    // shape in the animation (ghost, sheen, ink body, ring) so the geometry
    // stays consistent and tunable from one place.
    component RadialDisc: Rectangle {
        property real cx: 0
        property real cy: 0
        property real r: 0
        width: r * 2
        height: r * 2
        x: cx - r
        y: cy - r
        radius: r
        antialiasing: true
    }

    PanelWindow {
        id: overlay
        color: "transparent"
        anchors { top: true; left: true; right: true }
        implicitHeight: root.washHeight + 24
        exclusionMode: ExclusionMode.Ignore
        WlrLayershell.layer: WlrLayer.Overlay
        WlrLayershell.namespace: "omarchy-theme-wash"
        mask: Region {}  // fully click-through

        Item {
            id: stage
            anchors.fill: parent

            // Single-source-of-truth properties animated by washAnim; every
            // visual binds into these instead of running its own animation.
            property real ghostR: 0
            property real ghostOpacity: 0
            property real splatT: 0
            property real splatOpacity: 0
            property real haloR: 0
            property real haloOpacity: 0
            property real inkR: 0
            property real inkOpacity: 0
            property real fleckOpacity: 0
            property real labelOpacity: 0
            property real ringR: 0
            property real ringOpacity: 0

            readonly property bool fromRight: (root.washCount % 2) === 1
            readonly property real originX: fromRight ? band.width : 0
            readonly property real splatBaseAngle: fromRight ? Math.PI : 0

            Item {
                id: band
                x: 0; y: 0
                width: parent.width
                height: root.washHeight
                clip: true

                RadialDisc {
                    cx: band.width / 2
                    cy: root.washHeight / 2
                    r: stage.ghostR
                    color: root.prevAccent
                    opacity: stage.ghostOpacity
                }

                Repeater {
                    model: 7
                    delegate: Rectangle {
                        required property int index
                        readonly property real angle: stage.splatBaseAngle + (index - 3) * 0.14
                        readonly property real dist: 160 + (index % 4) * 38 + index * 6
                        readonly property real sz: 3 + ((index * 2) % 5)
                        // Parabolic bow — droplets curve up or down before
                        // being clipped at the band's vertical seams.
                        readonly property real bow:
                            (index % 2 === 0 ? -1 : 1)
                            * (8 + (index % 3) * 4)
                            * 4 * stage.splatT * (1 - stage.splatT)

                        width: sz; height: sz; radius: sz / 2
                        x: stage.originX + Math.cos(angle) * dist * stage.splatT - width / 2
                        y: Math.sin(angle) * dist * stage.splatT + bow + root.washHeight * 0.55 - height / 2
                        color: root.accent
                        opacity: stage.splatOpacity
                        antialiasing: true
                    }
                }

                // Sheen runs ahead of the ink body to give the wave front a
                // brighter leading edge — reads as a wave crest rather than
                // a flat disc.
                RadialDisc {
                    cx: stage.originX
                    cy: 0
                    r: stage.haloR
                    color: Qt.lighter(root.accent, 1.45)
                    opacity: stage.haloOpacity
                }

                RadialDisc {
                    cx: stage.originX
                    cy: 0
                    r: stage.inkR
                    color: root.accent
                    opacity: stage.inkOpacity
                }

                Text {
                    id: label
                    anchors.horizontalCenter: band.horizontalCenter
                    anchors.verticalCenter: band.verticalCenter
                    anchors.verticalCenterOffset: -1
                    text: root.lastTheme.toUpperCase()
                    color: root.paper
                    font.family: root.mono
                    font.pixelSize: 11
                    font.weight: Font.Bold
                    font.letterSpacing: 3
                    opacity: stage.labelOpacity
                }

                Repeater {
                    model: [
                        { fx: 0.16, fy: 0.70, sz: 3 },
                        { fx: 0.32, fy: 0.32, sz: 2 },
                        { fx: 0.51, fy: 0.62, sz: 3 },
                        { fx: 0.72, fy: 0.40, sz: 2 },
                        { fx: 0.86, fy: 0.65, sz: 3 }
                    ]
                    delegate: Rectangle {
                        required property var modelData
                        width: modelData.sz; height: modelData.sz
                        radius: modelData.sz / 2
                        x: band.width * modelData.fx - width / 2
                        y: root.washHeight * modelData.fy - height / 2
                        color: root.accent
                        opacity: stage.fleckOpacity
                        antialiasing: true
                    }
                }

                // Hollow ring: transparent fill + thick border on a
                // RadialDisc.
                RadialDisc {
                    cx: stage.originX
                    cy: 0
                    r: stage.ringR
                    color: "transparent"
                    border.color: root.accent
                    border.width: 2
                    opacity: stage.ringOpacity
                }
            }

            SequentialAnimation {
                id: washAnim

                ScriptAction { script: {
                    stage.ghostR = 8;  stage.ghostOpacity = 0;
                    stage.splatT = 0;  stage.splatOpacity = 0;
                    stage.haloR = 0;   stage.haloOpacity = 0;
                    stage.inkR = 0;    stage.inkOpacity = 0;
                    stage.fleckOpacity = 0;
                    stage.labelOpacity = 0;
                    stage.ringR = 0;   stage.ringOpacity = 0;
                }}

                ParallelAnimation {

                    SequentialAnimation {
                        ParallelAnimation {
                            NumberAnimation {
                                target: stage; property: "ghostR"
                                from: 8; to: Math.max(band.width * 0.45, 280)
                                duration: 460
                                easing.type: Easing.OutCubic
                            }
                            SequentialAnimation {
                                NumberAnimation { target: stage; property: "ghostOpacity"; from: 0; to: 0.55; duration: 120; easing.type: Easing.OutQuad }
                                NumberAnimation { target: stage; property: "ghostOpacity"; to: 0; duration: 360; easing.type: Easing.InCubic }
                            }
                        }
                    }

                    SequentialAnimation {
                        ParallelAnimation {
                            NumberAnimation { target: stage; property: "splatOpacity"; from: 0; to: 0.9; duration: 90 }
                            NumberAnimation {
                                target: stage; property: "splatT"
                                from: 0; to: 1
                                duration: 620
                                easing.type: Easing.OutCubic
                            }
                        }
                        PauseAnimation { duration: 60 }
                        NumberAnimation { target: stage; property: "splatOpacity"; to: 0; duration: 280; easing.type: Easing.InCubic }
                    }

                    SequentialAnimation {
                        PauseAnimation { duration: 140 }
                        ParallelAnimation {
                            NumberAnimation {
                                target: stage; property: "haloR"
                                from: 30; to: Math.max(band.width, 600) * 1.15
                                duration: 760
                                easing.type: Easing.OutCubic
                            }
                            SequentialAnimation {
                                NumberAnimation { target: stage; property: "haloOpacity"; from: 0; to: 0.45; duration: 200 }
                                NumberAnimation { target: stage; property: "haloOpacity"; to: 0; duration: 520; easing.type: Easing.InCubic }
                            }
                        }
                    }

                    SequentialAnimation {
                        PauseAnimation { duration: 220 }
                        ParallelAnimation {
                            NumberAnimation {
                                target: stage; property: "inkR"
                                from: 24; to: Math.max(band.width, 600) * 1.05
                                duration: 720
                                easing.type: Easing.OutCubic
                            }
                            SequentialAnimation {
                                NumberAnimation { target: stage; property: "inkOpacity"; from: 0; to: 0.94; duration: 220; easing.type: Easing.OutQuad }
                                PauseAnimation { duration: 480 }
                                NumberAnimation { target: stage; property: "inkOpacity"; to: 0; duration: 360; easing.type: Easing.InCubic }
                            }
                        }
                    }

                    SequentialAnimation {
                        PauseAnimation { duration: 520 }
                        NumberAnimation { target: stage; property: "labelOpacity"; from: 0; to: 1; duration: 180; easing.type: Easing.OutQuad }
                        PauseAnimation { duration: 460 }
                        NumberAnimation { target: stage; property: "labelOpacity"; to: 0; duration: 240; easing.type: Easing.InCubic }
                    }

                    SequentialAnimation {
                        PauseAnimation { duration: 420 }
                        NumberAnimation { target: stage; property: "fleckOpacity"; from: 0; to: 0.85; duration: 160 }
                        PauseAnimation { duration: 380 }
                        NumberAnimation { target: stage; property: "fleckOpacity"; to: 0; duration: 360; easing.type: Easing.InCubic }
                    }

                    SequentialAnimation {
                        PauseAnimation { duration: 1180 }
                        ParallelAnimation {
                            NumberAnimation {
                                target: stage; property: "ringR"
                                from: 12; to: Math.max(band.width, 600) * 0.85
                                duration: 360
                                easing.type: Easing.OutQuad
                            }
                            SequentialAnimation {
                                NumberAnimation { target: stage; property: "ringOpacity"; from: 0; to: 0.7; duration: 100 }
                                NumberAnimation { target: stage; property: "ringOpacity"; to: 0; duration: 260; easing.type: Easing.InCubic }
                            }
                        }
                    }
                }
            }
        }
    }
}
