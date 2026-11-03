import QtQuick
import QtQuick.Controls
import ".."

Slider {
    id: control
    implicitHeight: 26
    opacity: enabled ? 1 : 0.35
    background: Rectangle {
        x: control.leftPadding; y: control.topPadding + control.availableHeight / 2 - height / 2
        width: control.availableWidth; height: 6; radius: 3; color: Theme.panelRaised
        Rectangle { width: parent.width * control.visualPosition; height: parent.height; radius: 3; color: Theme.accent }
    }
    handle: Rectangle {
        x: control.leftPadding + control.visualPosition * (control.availableWidth - width)
        y: control.topPadding + control.availableHeight / 2 - height / 2
        width: 16; height: 16; radius: 8
        color: control.pressed ? Theme.sun : "#ffffff"
        border.width: 2
        border.color: control.activeFocus || control.pressed ? Theme.accent : Theme.accentGlow
        scale: control.pressed ? 1.2 : (control.hovered ? 1.1 : 1)
        Behavior on scale { NumberAnimation { duration: Theme.durFast; easing.type: Theme.easeOut } }
        Behavior on color { ColorAnimation { duration: Theme.durFast } }
    }
}
