import QtQuick
import QtQuick.Layouts
import ".."

// Section with a numbered/plain header that folds with a short height
// animation. Children go in the body.
// managed: the parent owns `expanded` (accordion); a header click then only
// emits toggleRequested().
ColumnLayout {
    id: section
    property string title: ""
    property string step: ""          // e.g. "1"; empty hides the badge
    property string summary: ""       // shown on the header while folded
    property bool expanded: true
    property bool managed: false
    signal toggleRequested()
    default property alias content: body.data
    // 0..1; animated so only the fold itself eases, not live content changes.
    property real openness: expanded ? 1 : 0
    Behavior on openness { NumberAnimation { duration: Theme.durBase; easing.type: Theme.easeOut } }
    spacing: 0

    Rectangle {
        Layout.fillWidth: true
        implicitHeight: 42
        color: headerArea.containsMouse ? Theme.panelRaised : "transparent"
        radius: Theme.radius
        Behavior on color { ColorAnimation { duration: Theme.durFast } }
        RowLayout {
            anchors.fill: parent
            anchors.leftMargin: 6; anchors.rightMargin: 6
            spacing: 10
            Rectangle {
                visible: section.step.length > 0
                Layout.preferredWidth: 22; Layout.preferredHeight: 22
                radius: 11
                color: section.expanded ? Theme.accent : Theme.panelRaised
                border.width: section.expanded ? 0 : 1
                border.color: Theme.stroke
                Behavior on color { ColorAnimation { duration: Theme.durBase } }
                Text { anchors.centerIn: parent; text: section.step; font.pixelSize: Theme.fontCaption; font.weight: Font.DemiBold; color: section.expanded ? Theme.accentForeground : Theme.muted }
            }
            Text {
                text: section.title
                color: section.expanded ? Theme.text : Theme.muted
                font.pixelSize: Theme.fontBody; font.weight: Font.DemiBold
                Layout.fillWidth: !summaryText.visible
                Behavior on color { ColorAnimation { duration: Theme.durFast } }
            }
            Text {
                id: summaryText
                visible: section.openness < 0.5 && section.summary.length > 0
                Layout.fillWidth: true
                text: section.summary; color: Theme.faint; font.pixelSize: Theme.fontCaption
                elide: Text.ElideMiddle; horizontalAlignment: Text.AlignRight
            }
            Icon {
                name: "chevron-down"; size: 16
                rotation: 180 * section.openness
            }
        }
        MouseArea {
            id: headerArea
            anchors.fill: parent; hoverEnabled: true
            cursorShape: Qt.PointingHandCursor
            onClicked: { if (section.managed) section.toggleRequested(); else section.expanded = !section.expanded }
        }
    }
    Item {
        id: clipBox
        Layout.fillWidth: true
        Layout.preferredHeight: (body.implicitHeight + 14) * section.openness
        visible: section.openness > 0.001
        clip: true
        ColumnLayout {
            id: body
            anchors.left: parent.left; anchors.right: parent.right; anchors.top: parent.top
            anchors.topMargin: 4
            opacity: section.openness
            spacing: 10
        }
    }
    Rectangle { Layout.fillWidth: true; implicitHeight: 1; color: Theme.strokeSoft }
}
