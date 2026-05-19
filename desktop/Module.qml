import QtQuick
import QtQuick.Layouts

Item {
    id: modItem
    required property var root

    property string glyph: ""
    property string tooltip: ""
    property color color: root.ink
    property string fontFamily: root.mono
    property int fontSize: 12

    signal activated()
    signal rightActivated()

    Layout.alignment: root.isHorizontal ? Qt.AlignVCenter : Qt.AlignHCenter
    Layout.preferredWidth:  root.isHorizontal ? 24 : root.barHeight
    Layout.preferredHeight: root.isHorizontal ? root.barHeight : 24

    // Short hover delay before the tooltip appears so a sweep across
    // the bar doesn't flash labels for every icon in passing.
    Timer {
        id: tipDelay
        interval: 320
        onTriggered: {
            if (!modItem.tooltip) return;
            const p = modItem.mapToItem(null, modItem.width / 2, modItem.height / 2);
            modItem.root.showTooltip(modItem.tooltip, p.x, p.y);
        }
    }

    Rectangle {
        anchors.fill: parent
        anchors.margins: 3
        radius: 0
        color: mouse.containsMouse ? Qt.rgba(modItem.root.ink.r, modItem.root.ink.g, modItem.root.ink.b, 0.08) : "transparent"
        Behavior on color { ColorAnimation { duration: 180 } }
    }

    Bloom { id: bloom; root: modItem.root }

    Text {
        anchors.centerIn: parent
        text: modItem.glyph
        color: modItem.color
        font.family: modItem.fontFamily
        font.pixelSize: modItem.fontSize
    }

    MouseArea {
        id: mouse
        anchors.fill: parent
        hoverEnabled: true
        acceptedButtons: Qt.LeftButton | Qt.RightButton
        cursorShape: Qt.PointingHandCursor
        onEntered: {
            bloom.fire(mouseX, mouseY);
            if (modItem.tooltip) tipDelay.restart();
        }
        onExited: {
            tipDelay.stop();
            modItem.root.hideTooltip(modItem.tooltip);
        }
        onClicked: (e) => {
            tipDelay.stop();
            modItem.root.hideTooltip(modItem.tooltip);
            if (e.button === Qt.RightButton) modItem.rightActivated();
            else modItem.activated();
        }
    }
}
