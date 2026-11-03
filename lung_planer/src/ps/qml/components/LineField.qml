import QtQuick
import QtQuick.Controls
import ".."

TextField {
    id: field
    property string label: ""
    implicitHeight: Theme.fieldHeight
    placeholderTextColor: Theme.faint
    color: Theme.text
    selectionColor: Theme.accentGlow
    selectedTextColor: Theme.text
    font.pixelSize: 13
    leftPadding: 16
    rightPadding: 16
    topPadding: 10
    bottomPadding: 10
    selectByMouse: true
    background: Rectangle {
        radius: height / 2
        color: field.activeFocus ? Theme.background : Theme.input
        border.width: field.activeFocus ? 2 : 1
        border.color: field.activeFocus ? Theme.accent : (field.hovered ? Theme.accentGlow : Theme.stroke)
        Behavior on color { ColorAnimation { duration: Theme.durFast } }
        Behavior on border.color { ColorAnimation { duration: Theme.durFast } }
    }
}
