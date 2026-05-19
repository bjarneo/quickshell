import QtQuick
import QtQuick.Layouts
import Quickshell
import Quickshell.Wayland

PanelWindow {
    id: bar
    required property var root

    color: "transparent"
    // Anchors track barEdge — three sides anchored, the side opposite
    // the bar's edge is left free for the bar's thickness to extend.
    anchors {
        top:    bar.root.barEdge !== "bottom"
        bottom: bar.root.barEdge !== "top"
        left:   bar.root.barEdge !== "right"
        right:  bar.root.barEdge !== "left"
    }
    implicitHeight: bar.root.isHorizontal ? bar.root.barHeight : 0
    implicitWidth:  bar.root.isHorizontal ? 0 : bar.root.barHeight
    exclusiveZone:  bar.root.barHeight

    WlrLayershell.layer: WlrLayer.Top
    WlrLayershell.namespace: "omarchy-menu"

    Rectangle {
        anchors.fill: parent
        color: bar.root.bg
        opacity: bar.root.isIdle ? 0.7 : 1.0
        Behavior on opacity {
            NumberAnimation {
                duration: bar.root.isIdle ? 6000 : 60
                easing.type: bar.root.isIdle ? Easing.OutQuart : Easing.OutQuad
            }
        }

        // 静 (stillness) mark, parked in the bar's trailing corner.
        Text {
            anchors.right:  bar.root.isHorizontal ? parent.right  : undefined
            anchors.bottom: bar.root.isHorizontal ? undefined     : parent.bottom
            anchors.rightMargin:  bar.root.isHorizontal ? 8 : 0
            anchors.bottomMargin: bar.root.isHorizontal ? 0 : 8
            anchors.verticalCenter:   bar.root.isHorizontal ? parent.verticalCenter   : undefined
            anchors.horizontalCenter: bar.root.isHorizontal ? undefined : parent.horizontalCenter
            text: "静"
            color: Qt.rgba(bar.root.ink.r, bar.root.ink.g, bar.root.ink.b, 0.07)
            font.family: bar.root.serif
            font.pixelSize: bar.root.barHeight + 6
            font.weight: Font.Light
            z: 0
        }

        // Inner-edge hairline (facing the rest of the screen).
        Rectangle {
            visible: bar.root.isHorizontal
            anchors.left:   parent.left
            anchors.right:  parent.right
            anchors.top:    bar.root.barEdge === "bottom" ? parent.top    : undefined
            anchors.bottom: bar.root.barEdge === "top"    ? parent.bottom : undefined
            height: 1
            color: bar.root.sep
        }
        Rectangle {
            visible: !bar.root.isHorizontal
            anchors.top:    parent.top
            anchors.bottom: parent.bottom
            anchors.right:  bar.root.barEdge === "left"  ? parent.right : undefined
            anchors.left:   bar.root.barEdge === "right" ? parent.left  : undefined
            width: 1
            color: bar.root.sep
        }

        // Centre cluster: clock only, clickable. Horizontal bars show
        // "HH:MM" on one line; vertical bars stack HH and MM.
        Item {
            id: clockItem
            anchors.horizontalCenter: parent.horizontalCenter
            anchors.verticalCenter:   parent.verticalCenter
            z: 10
            Component.onCompleted: bar.root.calendarAnchorItem = clockItem

            implicitWidth:  bar.root.isHorizontal
                            ? clockOneLine.implicitWidth + 14
                            : Math.max(clockHH.implicitWidth, clockMM.implicitWidth) + 8
            implicitHeight: bar.root.isHorizontal
                            ? clockOneLine.implicitHeight + 8
                            : (clockHH.implicitHeight + clockMM.implicitHeight + 6)

            Bloom { id: clockBloom; root: bar.root }

            Text {
                id: clockOneLine
                visible: bar.root.isHorizontal
                anchors.centerIn: parent
                text: bar.root.hh + ":" + bar.root.mm
                color: clockMouse.containsMouse ? bar.root.seal : bar.root.ink
                font.family: bar.root.mono
                font.pixelSize: 12
                font.letterSpacing: 2
                font.weight: Font.Light
                Behavior on color { ColorAnimation { duration: 180 } }
            }
            Text {
                id: clockHH
                visible: !bar.root.isHorizontal
                anchors.horizontalCenter: parent.horizontalCenter
                anchors.bottom: parent.verticalCenter
                anchors.bottomMargin: 1
                text: bar.root.hh
                color: clockMouse.containsMouse ? bar.root.seal : bar.root.ink
                font.family: bar.root.mono
                font.pixelSize: 11
                font.weight: Font.Light
                Behavior on color { ColorAnimation { duration: 180 } }
            }
            Text {
                id: clockMM
                visible: !bar.root.isHorizontal
                anchors.horizontalCenter: parent.horizontalCenter
                anchors.top: parent.verticalCenter
                anchors.topMargin: 1
                text: bar.root.mm
                color: clockMouse.containsMouse ? bar.root.seal : bar.root.ink
                font.family: bar.root.mono
                font.pixelSize: 11
                font.weight: Font.Light
                Behavior on color { ColorAnimation { duration: 180 } }
            }

            Timer {
                id: clockTipDelay
                interval: 320
                onTriggered: {
                    const p = clockItem.mapToItem(null, clockItem.width / 2, clockItem.height / 2);
                    bar.root.showTooltip("Calendar", p.x, p.y);
                }
            }

            MouseArea {
                id: clockMouse
                anchors.fill: parent
                hoverEnabled: true
                cursorShape: Qt.PointingHandCursor
                onEntered: { clockBloom.fire(mouseX, mouseY); clockTipDelay.restart(); }
                onExited:  { clockTipDelay.stop(); bar.root.hideTooltip("Calendar"); }
                onClicked: {
                    clockTipDelay.stop();
                    bar.root.hideTooltip("Calendar");
                    if (bar.root.calendarVisible) bar.root.calendarVisible = false;
                    else bar.root.openCalendar();
                }
            }
        }

        GridLayout {
            anchors.fill: parent
            anchors.leftMargin:   bar.root.isHorizontal ? 10 : 0
            anchors.rightMargin:  bar.root.isHorizontal ? 10 : 0
            anchors.topMargin:    bar.root.isHorizontal ? 0  : 10
            anchors.bottomMargin: bar.root.isHorizontal ? 0  : 10
            flow: bar.root.isHorizontal ? GridLayout.LeftToRight : GridLayout.TopToBottom
            rowSpacing: 4
            columnSpacing: 4
            columns: bar.root.isHorizontal ? -1 : 1
            rows:    bar.root.isHorizontal ? 1  : -1

            Module {
                root: bar.root
                glyph: bar.root.icoOmarchy
                tooltip: "Menu"
                color: bar.root.seal
                fontFamily: "omarchy"
                fontSize: 14
                onActivated: bar.root.paletteToggleRequested()
                onRightActivated: bar.root.run("xdg-terminal-exec")
            }

            Separator { root: bar.root }

            Repeater {
                model: 10
                delegate: Workspace {
                    required property int index
                    root: bar.root
                    wsId: index + 1
                    label: bar.root.indexKanji(index + 1)
                    active: bar.root.activeWs === (index + 1)
                    present: bar.root.existingWs.indexOf(index + 1) !== -1
                    onActivated: bar.root.run("hyprctl dispatch workspace " + (index + 1))
                }
            }

            Item {
                Layout.fillWidth:  bar.root.isHorizontal
                Layout.fillHeight: !bar.root.isHorizontal
            }

            Separator { root: bar.root }

            // Pop-up / overlay openers sit on the inside of the right
            // cluster — weather, display tweaks, screenshots browser.
            Module {
                id: weatherMod
                root: bar.root
                Component.onCompleted: bar.root.weatherAnchorItem = weatherMod
                // Muted middle dot stands in until the first wttr fetch
                // lands; a "?" marks an unreachable network.
                glyph: bar.root.weatherUnavailable ? "?"
                       : (bar.root.weatherLoaded ? bar.root.weatherIcon : "·")
                tooltip: bar.root.weatherUnavailable
                         ? "Weather offline"
                         : (bar.root.weatherLoaded
                            ? bar.root.weatherTempC + "°C"
                            : "Weather…")
                color: bar.root.weatherUnavailable ? bar.root.inkDeep : bar.root.ink
                fontSize: 13
                onActivated: {
                    if (bar.root.weatherVisible) bar.root.weatherVisible = false;
                    else bar.root.openWeather();
                }
                onRightActivated: bar.root.refreshWeather()
            }

            Module {
                root: bar.root
                // Nerd Font mdi-palette (U+F03D8). Left-click opens a
                // quick-handle popup (blueprint picker + GUI escape
                // hatch); right-click regenerates the system theme from
                // a random local wallpaper via the CLI.
                glyph: bar.root.icoAether
                tooltip: "Aether"
                onActivated: {
                    if (bar.root.aetherVisible) bar.root.aetherVisible = false;
                    else bar.root.openAether();
                }
                onRightActivated: bar.root.run("sh -c 'aether --generate \"$(aether --random-wallpaper)\"'")
            }

            Module {
                id: displayMod
                root: bar.root
                Component.onCompleted: bar.root.displayAnchorItem = displayMod
                // Nerd Font mdi-monitor (U+F0379). Left-click opens the
                // display popup (warmth / brightness / gamma / monitor
                // tweaks); right-click jumps straight to a reset.
                glyph: bar.root.icoDisplay
                tooltip: "Display"
                color: (bar.root.warmthK < 6500 || bar.root.gammaPct !== 100 || bar.root.brightnessPct < 100)
                       ? bar.root.seal : bar.root.ink
                onActivated: {
                    if (bar.root.displayVisible) bar.root.displayVisible = false;
                    else bar.root.openDisplay();
                }
                onRightActivated: bar.root.resetDisplay()
            }

            Module {
                root: bar.root
                // Nerd Font mdi-camera (U+F0100). Left-click browses
                // recent shots; right-click triggers a fresh capture.
                glyph: bar.root.icoCamera
                tooltip: "Screenshots"
                onActivated: {
                    if (bar.root.screenshotsVisible) bar.root.screenshotsVisible = false;
                    else bar.root.openScreenshots();
                }
                onRightActivated: bar.root.run("omarchy-capture-screenshot")
            }

            Module {
                root: bar.root
                glyph: bar.root.icoFilm
                tooltip: "Videos"
                onActivated: {
                    if (bar.root.videosVisible) bar.root.videosVisible = false;
                    else bar.root.openVideos();
                }
                onRightActivated: bar.root.run("xdg-open " + JSON.stringify(Quickshell.env("HOME") + "/Videos"))
            }

            Separator { root: bar.root }

            // System indicators read right-to-left as
            //   battery · sound · wifi · bluetooth · cpu · [edge]
            // so the most-glanced item (battery) sits adjacent to the
            // bar-position chevron.
            Module {
                root: bar.root
                glyph: "󰍛"
                tooltip: "CPU " + Math.round(bar.root.cpuVal) + "%"
                color: bar.root.cpuVal > 80 ? bar.root.seal : bar.root.ink
                onActivated: bar.root.run("omarchy-launch-or-focus-tui btop")
            }

            Module {
                root: bar.root
                glyph: bar.root.btIcon
                tooltip: {
                    if (!bar.root.btPowered) return "Bluetooth off";
                    return bar.root.btCount > 0
                        ? "Bluetooth · " + bar.root.btCount + " connected"
                        : "Bluetooth on";
                }
                onActivated: bar.root.run("omarchy-launch-bluetooth")
            }

            Module {
                id: netMod
                root: bar.root
                glyph: bar.root.netIcon
                tooltip: {
                    if (bar.root.netKind === "eth") return "Ethernet";
                    if (bar.root.netKind === "wifi") {
                        const name = bar.root.wifiSsid || "(hidden)";
                        return "Wi-Fi · " + name + " · " + bar.root.wifiSignal + "%";
                    }
                    return "Offline";
                }
                onActivated: bar.root.run("omarchy-launch-wifi")

                // Network-burst dot: traverses the wifi glyph's outermost
                // arc once when a heavy rx+tx burst is detected.
                // Geometry is eyeballed for the Nerd Font wifi icon
                // rendered at fontSize 12 inside the 24x26 Module slot.
                Item {
                    id: arc
                    anchors.fill: parent
                    property real t: 0
                    property real op: 0
                    readonly property real cx: width / 2
                    readonly property real cy: 17
                    readonly property real r:  6

                    Rectangle {
                        width: 3
                        height: 3
                        radius: 1.5
                        color: Qt.lighter(bar.root.seal, 1.7)
                        antialiasing: true
                        opacity: arc.op
                        x: arc.cx - arc.r * Math.cos(Math.PI * arc.t) - width / 2
                        y: arc.cy - arc.r * Math.sin(Math.PI * arc.t) - height / 2
                    }

                    ParallelAnimation {
                        id: arcAnim
                        NumberAnimation {
                            target: arc; property: "t"
                            from: 0; to: 1
                            duration: 700
                            easing.type: Easing.InOutQuad
                        }
                        SequentialAnimation {
                            NumberAnimation { target: arc; property: "op"; from: 0; to: 1; duration: 120; easing.type: Easing.OutQuad }
                            PauseAnimation { duration: 380 }
                            NumberAnimation { target: arc; property: "op"; to: 0; duration: 200; easing.type: Easing.InCubic }
                        }
                    }

                    Connections {
                        target: bar.root
                        function onNetBurst() { arc.t = 0; arcAnim.restart(); }
                    }
                }
            }

            Module {
                root: bar.root
                glyph: bar.root.audioIcon
                tooltip: bar.root.audioMuted
                         ? "Audio muted · " + bar.root.audioVol + "%"
                         : "Audio " + bar.root.audioVol + "%"
                onActivated: bar.root.run("omarchy-launch-audio")
                onRightActivated: bar.root.run("pamixer -t")
            }

            // Surfaces only when omarchy-update-available exits 0. Sits
            // beside the battery so it shares the system-status cluster's
            // line of sight without disturbing the existing icon cadence.
            Module {
                root: bar.root
                visible: bar.root.omarchyUpdateAvailable
                glyph: bar.root.icoUpdate
                tooltip: bar.root.omarchyLatestTag
                         ? "Omarchy update available · " + bar.root.omarchyLatestTag
                         : "Omarchy update available"
                color: bar.root.seal
                fontSize: 10
                onActivated: bar.root.openOmarchyUpdate()
            }

            Module {
                root: bar.root
                glyph: bar.root.batteryIcon()
                // Hide power below 0.05 W: idle Full / Not charging
                // states often report a sub-noise trickle that just
                // adds chatter to the tooltip.
                tooltip: {
                    let s = "Battery " + bar.root.batVal + "%";
                    if (bar.root.batPower >= 0.05) {
                        const sign = bar.root.batState === "Charging"    ? "+"
                                   : bar.root.batState === "Discharging" ? "-"
                                   : "";
                        s += "  " + sign + bar.root.batPower.toFixed(1) + " W";
                    }
                    return s;
                }
                color: bar.root.batVal <= 10 ? bar.root.seal : bar.root.batVal <= 20 ? bar.root.indigo : bar.root.ink
                onActivated: bar.root.run("omarchy-menu power")
            }

            Module {
                root: bar.root
                glyph: bar.root.edgeArrow()
                tooltip: "Move bar"
                color: bar.root.inkDeep
                fontSize: 12
                onActivated: bar.root.cycleBarEdge()
            }
        }
    }
}
