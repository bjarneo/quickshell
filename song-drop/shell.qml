import QtQuick
import Quickshell
import Quickshell.Wayland
import Quickshell.Io
import Quickshell.Services.Mpris

// Listens to MPRIS. On each track change, drops a fluid blob from the
// centre of the top bar, lets it splash, and morphs it into a box that
// shows the song name. Box holds for 5s, then fades.
ShellRoot {
    id: root

    // ---------- Theme (follows omarchy, same source the navbar reads) ----------
    readonly property string colorsPath: Quickshell.env("HOME") + "/.config/omarchy/current/theme/colors.toml"
    readonly property string themeNamePath: Quickshell.env("HOME") + "/.config/omarchy/current/theme.name"

    property color paper: "#181616"
    property color ink:   "#c5c9c5"
    property color seal:  "#c4746e"

    readonly property color accent: seal
    readonly property color textOnAccent: paper
    readonly property string mono: "JetBrainsMono Nerd Font"

    readonly property int barHeight: 26

    // ---------- Track state ----------
    property string trackTitle: ""
    property string trackArtist: ""
    property string lastShownKey: ""

    // Cascade scalar for the title glyphs: each char N is fully visible once
    // titleCascade > N (with a 1-unit fade window). One unit = 8ms of wall
    // time during the reveal animation, giving an 8ms-per-glyph "typed in"
    // stagger. metaOpacity fades the surrounding icon/separator/artist in
    // parallel without dragging the title cascade along with it.
    property real titleCascade: 0
    property real metaOpacity: 0

    function parseColors(text) {
        const re = /^\s*([A-Za-z_][A-Za-z0-9_]*)\s*=\s*"([^"]+)"/;
        const lines = text.split("\n");
        for (let i = 0; i < lines.length; i++) {
            const m = lines[i].match(re);
            if (!m) continue;
            if (m[1] === "background")      root.paper = m[2];
            else if (m[1] === "foreground") root.ink   = m[2];
            else if (m[1] === "color1")     root.seal  = m[2];
        }
    }

    FileView {
        id: paletteFile
        path: root.colorsPath
        watchChanges: true
        onFileChanged: reload()
        onLoaded: root.parseColors(paletteFile.text())
    }
    FileView {
        id: themeMarker
        path: root.themeNamePath
        watchChanges: true
        onFileChanged: { reload(); paletteFile.reload(); }
    }

    function showTrack(player) {
        if (!player || !player.trackTitle) return;
        const key = player.trackTitle + "" + (player.trackArtist || "");
        if (key === root.lastShownKey) return;
        root.lastShownKey = key;
        // Reset cascade BEFORE swapping the title so the Repeater's freshly
        // built char delegates evaluate opacity against cascade=0 (otherwise
        // they'd briefly inherit a fully-revealed state from the prior track
        // before the dropAnim init ScriptAction runs).
        root.titleCascade = 0;
        root.metaOpacity = 0;
        root.trackTitle = player.trackTitle;
        root.trackArtist = player.trackArtist || "";
        dropAnim.restart();
    }

    // Subscribe to every MPRIS player. postTrackChanged fires after the
    // metadata has settled, avoiding a flash of stale title/artist.
    Item {
        visible: false
        Repeater {
            model: Mpris.players
            delegate: Item {
                required property MprisPlayer modelData
                Connections {
                    target: modelData
                    function onPostTrackChanged() { root.showTrack(modelData); }
                }
            }
        }
    }

    // ---------- Overlay panel ----------
    PanelWindow {
        id: overlay
        color: "transparent"
        anchors { top: true; left: true; right: true }
        implicitHeight: 140
        // Auto mode would reserve 140px at the top of the screen with these
        // three anchors. Ignore makes the overlay float over windows without
        // pushing anything down (and ignores other layers' exclusion zones
        // so the drop starts at y=0, flush with the navbar's top edge).
        exclusionMode: ExclusionMode.Ignore
        WlrLayershell.layer: WlrLayer.Overlay
        WlrLayershell.namespace: "omarchy-song-drop"
        mask: Region {}  // fully click-through

        Item {
            id: stage
            anchors.fill: parent

            readonly property real boxWidth: Math.min(420, parent.width - 40)
            readonly property real boxHeight: 44
            readonly property real boxY: root.barHeight + 14
            readonly property real centerX: width / 2
            readonly property real impactY: boxY + boxHeight / 2 - 8

            // ---- Pre-roll ----
            // Subliminal cue: 80ms before the drop falls, the bar's centre
            // brightens by ~4% (ink overlay at 0.04 opacity). Painted on the
            // overlay layer so it stacks on top of the navbar without the two
            // shells needing to talk to each other. Pill-shaped + antialiased
            // so the edges don't read as a hard rectangle.
            Rectangle {
                id: preRoll
                width: 240
                height: root.barHeight
                radius: root.barHeight / 2
                x: stage.centerX - width / 2
                y: 0
                color: root.ink
                opacity: 0
                antialiasing: true
            }

            // ---- Falling drop ----
            // Stretch is animated: width = size / sqrt(stretch), height = size * stretch.
            // This conserves area so it looks like a liquid mass, not a stretched pill.
            Rectangle {
                id: drop
                property real cx: stage.centerX
                property real cy: root.barHeight
                property real size: 14
                property real stretch: 1.0

                width: size / Math.sqrt(stretch)
                height: size * stretch
                radius: Math.min(width, height) / 2
                x: cx - width / 2
                y: cy - height / 2
                color: root.accent
                opacity: 0
                antialiasing: true
            }

            // Trailing droplet for the liquid tail
            Rectangle {
                id: tail
                property real cx: stage.centerX
                property real cy: root.barHeight
                width: 6; height: 6; radius: 3
                x: cx - width / 2
                y: cy - height / 2
                color: root.accent
                opacity: 0
            }

            // ---- Splash droplets ----
            // Four small dots that fly outward on impact. Inline (not in a
            // Repeater) so each has its own id and the animations can
            // reference them statically.
            Rectangle {
                id: splash0
                property real travel: 0
                readonly property real angle: -2.5
                width: 5; height: 5; radius: 2.5
                x: stage.centerX + Math.cos(angle) * travel - width/2
                y: stage.impactY  + Math.sin(angle) * travel - height/2
                color: root.accent
                opacity: 0
            }
            Rectangle {
                id: splash1
                property real travel: 0
                readonly property real angle: -2.0
                width: 5; height: 5; radius: 2.5
                x: stage.centerX + Math.cos(angle) * travel - width/2
                y: stage.impactY  + Math.sin(angle) * travel - height/2
                color: root.accent
                opacity: 0
            }
            Rectangle {
                id: splash2
                property real travel: 0
                readonly property real angle: -1.14
                width: 5; height: 5; radius: 2.5
                x: stage.centerX + Math.cos(angle) * travel - width/2
                y: stage.impactY  + Math.sin(angle) * travel - height/2
                color: root.accent
                opacity: 0
            }
            Rectangle {
                id: splash3
                property real travel: 0
                readonly property real angle: -0.64
                width: 5; height: 5; radius: 2.5
                x: stage.centerX + Math.cos(angle) * travel - width/2
                y: stage.impactY  + Math.sin(angle) * travel - height/2
                color: root.accent
                opacity: 0
            }

            // ---- Settled box ----
            Rectangle {
                id: box
                width: stage.boxWidth
                height: stage.boxHeight
                x: stage.centerX - width / 2
                y: stage.boxY
                radius: 10
                color: root.accent
                opacity: 0
                scale: 0
                transformOrigin: Item.Top
                antialiasing: true

                Rectangle {
                    anchors.fill: parent
                    anchors.margins: 1
                    radius: parent.radius - 1
                    color: "transparent"
                    border.width: 1
                    border.color: Qt.rgba(root.textOnAccent.r, root.textOnAccent.g, root.textOnAccent.b, 0.18)
                }

                Row {
                    id: labelRow
                    anchors.centerIn: parent
                    spacing: 10
                    opacity: 0

                    Text {
                        text: ""
                        font.family: root.mono
                        font.pixelSize: 13
                        color: root.textOnAccent
                        opacity: root.metaOpacity
                        anchors.verticalCenter: parent.verticalCenter
                    }
                    // Title chars cascade: per-glyph Text in a Row so each
                    // can carry its own opacity. The Row is wrapped in a
                    // clipped Item to retain the original elide-style cutoff
                    // when titles overrun the box. Width budget mirrors the
                    // previous single-Text formula.
                    Item {
                        id: titleClip
                        anchors.verticalCenter: parent.verticalCenter
                        height: 16
                        width: Math.min(titleRow.implicitWidth,
                            stage.boxWidth - 90 - (artistText.visible ? artistText.width + 18 : 0))
                        clip: true

                        Row {
                            id: titleRow
                            spacing: 0
                            anchors.left: parent.left
                            anchors.verticalCenter: parent.verticalCenter

                            Repeater {
                                id: titleChars
                                model: root.trackTitle.split("")
                                delegate: Text {
                                    required property string modelData
                                    required property int index
                                    // U+00A0 keeps Row width math stable;
                                    // a literal " " can collapse to zero
                                    // width depending on the font.
                                    text: modelData === " " ? " " : modelData
                                    color: root.textOnAccent
                                    font.family: root.mono
                                    font.pixelSize: 12
                                    font.letterSpacing: 1
                                    font.weight: Font.Medium
                                    opacity: Math.max(0, Math.min(1, root.titleCascade - index))
                                }
                            }
                        }
                    }
                    Rectangle {
                        visible: root.trackArtist.length > 0
                        width: 1
                        height: 14
                        color: Qt.rgba(root.textOnAccent.r, root.textOnAccent.g, root.textOnAccent.b, 0.45)
                        opacity: root.metaOpacity
                        anchors.verticalCenter: parent.verticalCenter
                    }
                    Text {
                        id: artistText
                        visible: root.trackArtist.length > 0
                        text: root.trackArtist
                        color: Qt.rgba(root.textOnAccent.r, root.textOnAccent.g, root.textOnAccent.b, 0.78)
                        font.family: root.mono
                        font.pixelSize: 11
                        font.letterSpacing: 1
                        font.italic: true
                        opacity: root.metaOpacity
                        anchors.verticalCenter: parent.verticalCenter
                        elide: Text.ElideRight
                        width: Math.min(implicitWidth, stage.boxWidth / 2 - 20)
                    }
                }
            }

            // ---- Master timeline ----
            SequentialAnimation {
                id: dropAnim

                ScriptAction { script: {
                    drop.cy = root.barHeight - 4;
                    drop.size = 14;
                    drop.stretch = 1.0;
                    drop.opacity = 0;
                    tail.cy = root.barHeight - 4;
                    tail.opacity = 0;
                    box.scale = 0;
                    box.opacity = 0;
                    labelRow.opacity = 0;
                    preRoll.opacity = 0;
                    root.titleCascade = 0;
                    root.metaOpacity = 0;
                    splash0.travel = 0; splash0.opacity = 0;
                    splash1.travel = 0; splash1.opacity = 0;
                    splash2.travel = 0; splash2.opacity = 0;
                    splash3.travel = 0; splash3.opacity = 0;
                }}

                // 0) Pre-roll — 80ms of bar-centre brightening before the
                //    drop appears. 60ms ramp up to 0.04, 20ms hold, then the
                //    fall begins and preRoll decays in parallel with it.
                SequentialAnimation {
                    NumberAnimation {
                        target: preRoll; property: "opacity"
                        from: 0; to: 0.04
                        duration: 60
                        easing.type: Easing.OutQuad
                    }
                    PauseAnimation { duration: 20 }
                }

                // 1) Fall + teardrop stretch (drop and tail)
                ParallelAnimation {
                    // Drop becomes visible exactly when the fall starts —
                    // the pre-roll is meant to feel like it precedes the
                    // event, not accompany it.
                    ScriptAction { script: drop.opacity = 1 }
                    NumberAnimation {
                        target: preRoll; property: "opacity"
                        to: 0
                        duration: 240
                        easing.type: Easing.InQuad
                    }
                    NumberAnimation {
                        target: drop; property: "cy"
                        from: root.barHeight - 4
                        to: stage.boxY + stage.boxHeight/2 - 10
                        duration: 440
                        easing.type: Easing.InQuad
                    }
                    NumberAnimation {
                        target: drop; property: "stretch"
                        from: 1.0; to: 2.6
                        duration: 440
                        easing.type: Easing.InQuad
                    }
                    SequentialAnimation {
                        PauseAnimation { duration: 80 }
                        ParallelAnimation {
                            NumberAnimation { target: tail; property: "opacity"; from: 0; to: 1; duration: 100 }
                            NumberAnimation {
                                target: tail; property: "cy"
                                from: root.barHeight - 4
                                to: stage.boxY + stage.boxHeight/2 - 28
                                duration: 360
                                easing.type: Easing.InQuad
                            }
                        }
                    }
                }

                // 2) Squash on impact, launch splash
                ParallelAnimation {
                    NumberAnimation { target: drop; property: "stretch"; to: 0.45; duration: 110; easing.type: Easing.OutQuad }
                    NumberAnimation { target: drop; property: "size";    to: 30;   duration: 110; easing.type: Easing.OutQuad }
                    NumberAnimation {
                        target: tail; property: "cy"
                        to: stage.boxY + stage.boxHeight/2 - 6
                        duration: 110
                    }
                    NumberAnimation { target: tail; property: "opacity"; to: 0; duration: 110 }
                    ScriptAction { script: {
                        splash0.opacity = 1;
                        splash1.opacity = 1;
                        splash2.opacity = 1;
                        splash3.opacity = 1;
                    }}
                }

                // 3) Morph: drop dissolves, splash flies out, box scales in
                ParallelAnimation {
                    NumberAnimation { target: drop; property: "opacity"; to: 0; duration: 220 }
                    NumberAnimation { target: drop; property: "size";    to: 60; duration: 220 }

                    NumberAnimation { target: splash0; property: "travel"; from: 0; to: 36; duration: 360; easing.type: Easing.OutCubic }
                    NumberAnimation { target: splash1; property: "travel"; from: 0; to: 28; duration: 340; easing.type: Easing.OutCubic }
                    NumberAnimation { target: splash2; property: "travel"; from: 0; to: 30; duration: 360; easing.type: Easing.OutCubic }
                    NumberAnimation { target: splash3; property: "travel"; from: 0; to: 38; duration: 380; easing.type: Easing.OutCubic }

                    SequentialAnimation {
                        PauseAnimation { duration: 220 }
                        ParallelAnimation {
                            NumberAnimation { target: splash0; property: "opacity"; to: 0; duration: 160 }
                            NumberAnimation { target: splash1; property: "opacity"; to: 0; duration: 160 }
                            NumberAnimation { target: splash2; property: "opacity"; to: 0; duration: 160 }
                            NumberAnimation { target: splash3; property: "opacity"; to: 0; duration: 160 }
                        }
                    }

                    SequentialAnimation {
                        PauseAnimation { duration: 60 }
                        ParallelAnimation {
                            NumberAnimation {
                                target: box; property: "scale"
                                from: 0; to: 1
                                duration: 360
                                easing.type: Easing.OutBack
                                easing.overshoot: 1.6
                            }
                            NumberAnimation { target: box; property: "opacity"; from: 0; to: 1; duration: 240 }
                        }
                    }
                }

                // 4) Reveal label. labelRow snaps to fully opaque so the
                //    per-glyph cascade and metaOpacity ramps drive the
                //    perceived reveal — keeping labelRow as the master fade
                //    would multiply against the cascade and smear it into a
                //    wave instead of a "typed in" stagger.
                ScriptAction { script: labelRow.opacity = 1 }
                ParallelAnimation {
                    NumberAnimation {
                        target: root; property: "titleCascade"
                        from: 0
                        // +2 so the last char's 1-unit fade window completes.
                        to: root.trackTitle.length + 2
                        duration: (root.trackTitle.length + 2) * 8
                    }
                    NumberAnimation {
                        target: root; property: "metaOpacity"
                        from: 0; to: 1
                        duration: 220
                    }
                }

                // 5) Hold for 5 seconds
                PauseAnimation { duration: 5000 }

                // 6) Settle out — label leaves first, then the box inhales
                //    and collapses upward into the bar (mirrors the OutBack entry).
                SequentialAnimation {
                    NumberAnimation {
                        target: labelRow; property: "opacity"
                        to: 0
                        duration: 220
                        easing.type: Easing.InCubic
                    }
                    ParallelAnimation {
                        NumberAnimation {
                            target: box; property: "scale"
                            to: 0
                            duration: 520
                            easing.type: Easing.InBack
                            easing.overshoot: 1.4
                        }
                        NumberAnimation {
                            target: box; property: "opacity"
                            to: 0
                            duration: 440
                            easing.type: Easing.InCubic
                        }
                    }
                }
            }
        }
    }
}
