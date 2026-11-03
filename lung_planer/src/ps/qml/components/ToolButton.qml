import QtQuick
import QtQuick.Controls
import ".."

Button {
    id: tool
    property string iconName: ""
    property string tip: ""
    property color iconColor: Theme.text
    property bool inverseIcon: false
    implicitWidth: 32
    implicitHeight: 32
    padding: 7
    opacity: enabled ? 1 : 0.35
    scale: down ? 0.92 : 1
    Behavior on scale { NumberAnimation { duration: Theme.durFast; easing.type: Theme.easeOut } }
    ToolTip.visible: hovered && tip.length > 0
    ToolTip.text: tip
    ToolTip.delay: 500
    contentItem: Item {
        implicitWidth: 18; implicitHeight: 18
        Icon { anchors.centerIn: parent; name: tool.iconName; iconColor: tool.iconColor; inverse: tool.inverseIcon; visible: tool.iconName.length > 0; size: 17 }
        Text { anchors.fill: parent; text: tool.text; visible: tool.iconName.length === 0; color: tool.inverseIcon ? Theme.viewerText : Theme.text; font.pixelSize: 12; horizontalAlignment: Text.AlignHCenter; verticalAlignment: Text.AlignVCenter }
    }
    background: Rectangle {
        radius: height / 2
        color: tool.checked ? (tool.inverseIcon ? Theme.viewerBarSelected : Theme.accentDim)
             : (tool.down || tool.hovered ? (tool.inverseIcon ? Theme.viewerControl : Theme.panelRaised) : "transparent")
        border.width: tool.checked || tool.activeFocus ? 1 : 0
        border.color: tool.inverseIcon ? Theme.viewerAccent : Theme.accent
        Behavior on color { ColorAnimation { duration: Theme.durFast } }
    }
}
