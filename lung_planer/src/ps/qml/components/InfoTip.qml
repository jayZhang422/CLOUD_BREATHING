import QtQuick
import QtQuick.Controls
import ".."

// A small "i" that explains something on hover. Used to keep long help text
// out of the panels while it stays one gesture away.
Item {
    id: tip
    property string text: ""
    property bool warn: false
    implicitWidth: 16
    implicitHeight: 16
    visible: text.length > 0

    Icon {
        anchors.fill: parent
        name: "info"; size: 16
        opacity: hover.containsMouse ? 1 : 0.55
        Behavior on opacity { NumberAnimation { duration: Theme.durFast } }
    }
    MouseArea { id: hover; anchors.fill: parent; anchors.margins: -4; hoverEnabled: true }

    TextMetrics { id: metrics; text: tip.text; font.pixelSize: Theme.fontCaption }

    ToolTip {
        visible: hover.containsMouse
        delay: 150
        timeout: 0
        width: Math.min(320, metrics.advanceWidth + 28)
        padding: 12
        contentItem: Text {
            text: tip.text
            color: tip.warn ? Theme.sun : "#ffffff"
            font.pixelSize: Theme.fontCaption
            lineHeight: 1.3
            wrapMode: Text.Wrap
        }
        background: Rectangle { color: Theme.navy; radius: Theme.radius }
        enter: Transition { NumberAnimation { property: "opacity"; from: 0; to: 1; duration: Theme.durBase } }
        exit: Transition { NumberAnimation { property: "opacity"; to: 0; duration: Theme.durFast } }
    }
}
