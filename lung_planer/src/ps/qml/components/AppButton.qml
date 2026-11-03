import QtQuick
import QtQuick.Controls
import ".."

// Pill button. primary = teal fill, warm = sunny yellow (one hero action per
// page), onDark = sits on a black viewport.
Button {
    id: control
    property string iconName: ""
    property bool primary: false
    property bool warm: false
    property bool onDark: false
    property bool danger: false
    property string tip: ""
    implicitHeight: Theme.controlHeight
    leftPadding: 16
    rightPadding: 16
    opacity: enabled ? 1 : 0.45
    scale: down ? 0.97 : 1
    Behavior on scale { NumberAnimation { duration: Theme.durFast; easing.type: Theme.easeOut } }
    Behavior on opacity { NumberAnimation { duration: Theme.durBase } }
    ToolTip.visible: hovered && tip.length > 0
    ToolTip.text: tip
    ToolTip.delay: 500
    contentItem: Item {
        implicitWidth: labelRow.implicitWidth
        implicitHeight: 18
        Row {
            id: labelRow
            anchors.centerIn: parent
            spacing: control.iconName.length > 0 ? 8 : 0
            Icon {
                name: control.iconName
                inverse: control.onDark
                onAccent: control.primary
                visible: control.iconName.length > 0
                width: visible ? 16 : 0; height: 16
                anchors.verticalCenter: parent.verticalCenter
            }
            Text {
                text: control.text
                color: control.primary ? Theme.accentForeground
                     : control.warm ? Theme.sunForeground
                     : control.danger ? Theme.error
                     : control.onDark ? Theme.viewerText : Theme.text
                font.pixelSize: Theme.fontLabel
                font.weight: control.primary || control.warm ? Font.DemiBold : Font.Medium
                anchors.verticalCenter: parent.verticalCenter
            }
        }
    }
    background: Rectangle {
        radius: height / 2
        color: control.primary ? (control.down ? Qt.darker(Theme.accent, 1.2) : control.hovered ? Qt.lighter(Theme.accent, 1.15) : Theme.accent)
             : control.warm ? (control.down ? Qt.darker(Theme.sun, 1.1) : control.hovered ? Theme.sunHover : Theme.sun)
             : control.onDark ? (control.down ? Theme.viewerStroke : control.hovered ? Theme.viewerControl : Theme.viewerField)
             : (control.down ? Theme.accentDim : control.hovered ? Theme.panelRaised : Theme.input)
        border.width: control.activeFocus ? 2 : ((control.primary || control.warm) ? 0 : 1)
        border.color: control.activeFocus ? Theme.accent
            : (control.onDark ? Theme.viewerStroke : (control.hovered ? Theme.accentGlow : Theme.stroke))
        Behavior on color { ColorAnimation { duration: Theme.durFast } }
        Behavior on border.color { ColorAnimation { duration: Theme.durFast } }
    }
}
