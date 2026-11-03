import QtQuick
import QtQuick.Controls
import ".."

// Secondary item at the foot of the teal sidebar (log out, quit).
// compact hides the label and shows it as a tooltip instead.
Button {
    id: link
    property string iconName: ""
    property bool compact: false
    height: 40
    padding: 0
    ToolTip.visible: compact && hovered
    ToolTip.text: text
    ToolTip.delay: 400
    contentItem: Item {
        Row {
            x: link.compact ? 33 : 30
            anchors.verticalCenter: parent.verticalCenter
            spacing: 12
            Icon { name: link.iconName; size: 20; inverse: true; anchors.verticalCenter: parent.verticalCenter }
            Text {
                visible: !link.compact
                text: link.text
                color: Theme.shellText
                font.pixelSize: Theme.fontLabel
                font.weight: Font.Medium
                anchors.verticalCenter: parent.verticalCenter
            }
        }
    }
    background: Rectangle {
        x: 12; width: parent.width - 24; height: parent.height
        radius: height / 2
        color: Theme.shellDeep
        opacity: link.hovered || link.down ? 1 : 0
        border.width: link.activeFocus ? 2 : 0
        border.color: Theme.shellText
        Behavior on opacity { NumberAnimation { duration: Theme.durFast } }
    }
}
