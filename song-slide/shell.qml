import QtQuick
import Quickshell
import Quickshell.Wayland
import Quickshell.Io
import Quickshell.Services.Mpris

// Sibling of song-drop. Same MPRIS source, different choreography: a sharp
// text-only card slides in from the right edge with title, artist, and a
// flush bottom-edge progress bar. Entry ~220ms, exit ~260ms. On rapid track
// changes the content cross-fades in place instead of restarting the slide.
// Click-through overlay, themed off the live omarchy palette.
ShellRoot {
    id: root

    readonly property string colorsPath: Quickshell.env("HOME") + "/.config/omarchy/current/theme/colors.toml"
    readonly property string themeNamePath: Quickshell.env("HOME") + "/.config/omarchy/current/theme.name"

    property color paper: "#181616"
    property color ink:   "#c5c9c5"
    property color sumi:  "#a6a69c"
    property color seal:  "#c4746e"

    readonly property color accent: seal
    readonly property color cardBg: Qt.rgba(paper.r, paper.g, paper.b, 0.97)
    readonly property color border: Qt.rgba(ink.r, ink.g, ink.b, 0.16)
    readonly property color track:  Qt.rgba(ink.r, ink.g, ink.b, 0.10)
    readonly property color subtle: Qt.rgba(ink.r, ink.g, ink.b, 0.62)
    readonly property string mono:  "JetBrainsMono Nerd Font"

    // Card top inset: clears the navbar (26px) with a 14px gap.
    readonly property int topInset: 40

    property string liveTitle: ""
    property string liveArtist: ""
    property string incomingTitle: ""
    property string incomingArtist: ""
    property string lastShownKey: ""

    property var activePlayer: null

    function parseColors(text) {
        const re = /^\s*([A-Za-z_][A-Za-z0-9_]*)\s*=\s*"([^"]+)"/;
        const lines = text.split("\n");
        for (let i = 0; i < lines.length; i++) {
            const m = lines[i].match(re);
            if (!m) continue;
            if (m[1] === "background")      root.paper = m[2];
            else if (m[1] === "foreground") root.ink   = m[2];
            else if (m[1] === "color8")     root.sumi  = m[2];
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
    // colors.toml gets a fresh inode each omarchy swap; theme.name is
    // rewritten in place so its inode is the stable beacon.
    FileView {
        id: themeMarker
        path: root.themeNamePath
        watchChanges: true
        onFileChanged: { reload(); paletteFile.reload(); }
    }

    function showTrack(player) {
        if (!player || !player.trackTitle) return;
        // U+0001 separator so "AB"+"C" can't collide with "A"+"BC".
        const key = player.trackTitle + "" + (player.trackArtist || "");
        if (key === root.lastShownKey) return;
        root.lastShownKey = key;
        root.activePlayer = player;
        root.incomingTitle  = player.trackTitle;
        root.incomingArtist = player.trackArtist || "";

        // If the card is already docked, swap content in place; otherwise
        // run the slide-in. card.x === restX means "fully docked".
        if (card.x <= card.restX + 0.5 && card.opacity > 0.5) {
            crossfade.restart();
        } else {
            root.liveTitle  = root.incomingTitle;
            root.liveArtist = root.incomingArtist;
            slideIn.restart();
        }
    }

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
        anchors { top: true; right: true }
        // Surface = card + a generous lead-in so the slide can start fully
        // offscreen and overshoot inward without clipping.
        implicitWidth: 360
        implicitHeight: 108
        exclusionMode: ExclusionMode.Ignore
        WlrLayershell.layer: WlrLayer.Overlay
        WlrLayershell.namespace: "omarchy-song-slide"
        mask: Region {}  // fully click-through

        Item {
            id: stage
            anchors.fill: parent

            Rectangle {
                id: card
                readonly property real cardWidth: 320
                readonly property real cardHeight: 54
                readonly property real margin: 16
                readonly property real restX: parent.width - cardWidth - margin
                readonly property real offX:  parent.width + 12

                width: cardWidth
                height: cardHeight
                y: root.topInset
                x: offX
                opacity: 0
                radius: 0
                color: root.cardBg
                antialiasing: false
                border.width: 1
                border.color: root.border

                // Left accent stripe — the visual anchor that replaces what
                // album art used to do. 3px wide, full card height, flush
                // with the left border so it reads as part of the frame.
                Rectangle {
                    id: stripe
                    width: 3
                    height: parent.height
                    color: root.accent
                    anchors.left: parent.left
                    anchors.top: parent.top
                }

                // Title row: title left-aligned, current-time right-aligned.
                // Both share the same baseline for a clean horizontal line.
                Text {
                    id: titleText
                    text: root.liveTitle
                    color: root.ink
                    font.family: root.mono
                    font.pixelSize: 13
                    font.letterSpacing: 0.4
                    font.weight: Font.DemiBold
                    elide: Text.ElideRight
                    anchors.left: stripe.right
                    anchors.leftMargin: 12
                    anchors.right: timeLabel.visible ? timeLabel.left : parent.right
                    anchors.rightMargin: timeLabel.visible ? 10 : 12
                    anchors.top: parent.top
                    anchors.topMargin: 8
                }

                Text {
                    id: timeLabel
                    // Bind to integer seconds so MPRIS's sub-second position
                    // ticks don't churn the Text layout — fmt() floors
                    // anyway, but the binding itself re-runs per tick.
                    text: progressBar.fmt(progressBar.posSec) +
                          (progressBar.lenSec > 0 ? " / " + progressBar.fmt(progressBar.lenSec) : "")
                    color: root.subtle
                    font.family: root.mono
                    font.pixelSize: 10
                    font.letterSpacing: 0.5
                    anchors.right: parent.right
                    anchors.rightMargin: 12
                    anchors.verticalCenter: titleText.verticalCenter
                    visible: progressBar.lenSec > 0
                }

                Text {
                    id: artistText
                    text: root.liveArtist
                    color: root.subtle
                    font.family: root.mono
                    font.pixelSize: 10
                    font.italic: true
                    font.letterSpacing: 0.4
                    elide: Text.ElideRight
                    anchors.left: stripe.right
                    anchors.leftMargin: 12
                    anchors.right: parent.right
                    anchors.rightMargin: 12
                    anchors.top: titleText.bottom
                    anchors.topMargin: 2
                    visible: root.liveArtist.length > 0
                }

                Rectangle {
                    id: progressBar
                    height: 2
                    anchors.left: parent.left
                    anchors.right: parent.right
                    anchors.bottom: parent.bottom
                    color: root.track

                    readonly property real pos: root.activePlayer
                        ? root.activePlayer.position
                        : 0
                    readonly property real len: root.activePlayer
                        ? root.activePlayer.length
                        : 0
                    // Quantised seconds. Downstream bindings only re-fire
                    // when the displayed value actually steps, not per
                    // sub-second MPRIS tick.
                    readonly property int posSec: Math.floor(pos)
                    readonly property int lenSec: Math.floor(len)
                    readonly property real frac: len > 0
                        ? Math.max(0, Math.min(1, pos / len))
                        : 0

                    function fmt(s) {
                        if (!isFinite(s) || s < 0) return "0:00";
                        const m = Math.floor(s / 60);
                        const ss = Math.floor(s % 60);
                        return m + ":" + (ss < 10 ? "0" : "") + ss;
                    }

                    Rectangle {
                        width: parent.width * progressBar.frac
                        height: parent.height
                        color: root.accent
                        // Short enough that the fill keeps pace with the
                        // timestamp; longer than a frame so steps don't pop.
                        Behavior on width { NumberAnimation { duration: 120; easing.type: Easing.OutCubic } }
                    }
                }
            }

            // ---- Slide in: offscreen-right → rest, with a small overshoot ----
            ParallelAnimation {
                id: slideIn
                NumberAnimation {
                    target: card; property: "x"
                    from: card.offX; to: card.restX
                    duration: 220
                    easing.type: Easing.OutBack
                    easing.overshoot: 1.15
                }
                NumberAnimation {
                    target: card; property: "opacity"
                    from: 0; to: 1
                    duration: 160
                    easing.type: Easing.OutQuad
                }
                ScriptAction { script: hold.restart() }
            }

            // ---- Cross-fade content swap without restarting the slide ----
            // Dim to ~45%, commit new content at the dim trough, ramp back.
            // Reads as continuity (same card, new song) rather than a
            // restart.
            SequentialAnimation {
                id: crossfade
                NumberAnimation { target: card; property: "opacity"; to: 0.45; duration: 90; easing.type: Easing.InQuad }
                ScriptAction { script: {
                    root.liveTitle  = root.incomingTitle;
                    root.liveArtist = root.incomingArtist;
                }}
                NumberAnimation { target: card; property: "opacity"; to: 1; duration: 140; easing.type: Easing.OutQuad }
                ScriptAction { script: hold.restart() }
            }

            // ---- Hold, then exit ----
            Timer {
                id: hold
                interval: 4500
                repeat: false
                onTriggered: slideOut.restart()
            }

            ParallelAnimation {
                id: slideOut
                NumberAnimation {
                    target: card; property: "x"
                    to: card.offX
                    duration: 260
                    easing.type: Easing.InCubic
                }
                NumberAnimation {
                    target: card; property: "opacity"
                    to: 0
                    duration: 220
                    easing.type: Easing.InCubic
                }
            }
        }
    }
}
