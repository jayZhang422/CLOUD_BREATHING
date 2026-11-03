import QtQuick
import QtQuick.Controls
import ".."

CheckBox {
    id: control
    implicitHeight: 30
    spacing: 8
    padding: 0
    contentItem: Text {
        text: control.text
        color: control.enabled ? Theme.text : Theme.faint
        font.pixelSize: Theme.fontLabel
        leftPadding: control.text.length ? control.indicator.width + control.spacing : 0
        verticalAlignment: Text.AlignVCenter
    }
    indicator: Rectangle {
        width: 18; height: 18; y: (control.height - height) / 2; radius: 6
        color: control.checked ? Theme.accent : (control.hovered ? Theme.panelRaised : Theme.input)
        border.color: control.checked ? Theme.accent : (control.activeFocus || control.hovered ? Theme.accent : Theme.faint)
        border.width: control.activeFocus ? 2 : 1
        Behavior on color { ColorAnimation { duration: Theme.durFast } }
        Behavior on border.color { ColorAnimation { duration: Theme.durFast } }
        Icon {
            anchors.centerIn: parent; name: "check"; onAccent: true; size: 13
            opacity: control.checked ? 1 : 0
            scale: control.checked ? 1 : 0.4
            Behavior on opacity { NumberAnimation { duration: Theme.durFast } }
            Behavior on scale { NumberAnimation { duration: Theme.durBase; easing.type: Easing.OutBack } }
        }
    }
}
