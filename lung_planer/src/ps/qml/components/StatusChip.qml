import QtQuick
import ".."

// Small pill: tone is one of "neutral", "success", "warning", "danger", "accent".
// pulse makes the dot breathe (used while something is computing).
Rectangle {
    id: chip
    property string text: ""
    property string tone: "neutral"
    property bool dot: true
    property bool pulse: false
    readonly property color toneColor: tone === "success" ? Theme.success
        : tone === "warning" ? Theme.warning
        : tone === "danger" ? Theme.error
        : tone === "accent" ? Theme.accent : Theme.muted
    readonly property color toneFill: tone === "success" ? Theme.successDim
        : tone === "warning" ? Theme.warningDim
        : tone === "danger" ? Theme.errorDim
        : tone === "accent" ? Theme.accentDim : Theme.panelRaised
    implicitHeight: 24
    implicitWidth: chipRow.implicitWidth + 20
    radius: 12
    color: toneFill
    Behavior on color { ColorAnimation { duration: Theme.durBase } }
    Row {
        id: chipRow
        anchors.centerIn: parent
        spacing: 6
        Rectangle {
            id: dotMark
            visible: chip.dot
            width: 7; height: 7; radius: 4
            color: chip.toneColor
            anchors.verticalCenter: parent.verticalCenter
            Behavior on color { ColorAnimation { duration: Theme.durBase } }
            SequentialAnimation on opacity {
                running: chip.pulse && chip.visible
                loops: Animation.Infinite
                NumberAnimation { to: 0.25; duration: 700; easing.type: Easing.InOutSine }
                NumberAnimation { to: 1.0; duration: 700; easing.type: Easing.InOutSine }
                onRunningChanged: if (!running) dotMark.opacity = 1
            }
        }
        Text {
            text: chip.text; color: chip.toneColor
            font.pixelSize: Theme.fontCaption; font.weight: Font.Medium
            anchors.verticalCenter: parent.verticalCenter
            Behavior on color { ColorAnimation { duration: Theme.durBase } }
        }
    }
}
