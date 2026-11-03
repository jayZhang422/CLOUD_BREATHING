import QtQuick
import QtQuick.Controls
import ".."

ComboBox {
    id: combo
    implicitHeight: Theme.controlHeight
    leftPadding: 14
    rightPadding: 32
    property int elideMode: Text.ElideMiddle
    opacity: enabled ? 1 : 0.5
    contentItem: Text {
        text: combo.displayText
        color: combo.enabled ? Theme.text : Theme.faint
        font.pixelSize: Theme.fontLabel
        verticalAlignment: Text.AlignVCenter
        elide: combo.elideMode
    }
    indicator: Icon {
        x: combo.width - width - 12; y: (combo.height - height) / 2; name: "chevron-down"; size: 14
        rotation: combo.popup.visible ? 180 : 0
        Behavior on rotation { NumberAnimation { duration: Theme.durBase; easing.type: Theme.easeOut } }
    }
    background: Rectangle {
        color: combo.hovered || combo.popup.visible ? Theme.panelRaised : Theme.input
        radius: height / 2
        border.width: combo.activeFocus ? 2 : 1
        border.color: combo.activeFocus || combo.popup.visible ? Theme.accent : (combo.hovered ? Theme.accentGlow : Theme.stroke)
        Behavior on color { ColorAnimation { duration: Theme.durFast } }
        Behavior on border.color { ColorAnimation { duration: Theme.durFast } }
    }
    delegate: ItemDelegate {
        id: option
        required property int index
        required property var modelData
        width: combo.width
        implicitHeight: Theme.controlHeight
        highlighted: combo.highlightedIndex === index
        contentItem: Text {
            text: option.modelData
            color: Theme.text
            font.pixelSize: Theme.fontLabel
            leftPadding: 6
            elide: combo.elideMode
            verticalAlignment: Text.AlignVCenter
        }
        background: Rectangle { color: option.highlighted ? Theme.accentDim : "transparent"; radius: Theme.radius; anchors.margins: 3; anchors.fill: parent }
    }
    popup: Popup {
        y: combo.height + 4
        width: combo.width
        padding: 4
        implicitHeight: Math.min(contentItem.implicitHeight + 8, 260)
        enter: Transition {
            NumberAnimation { property: "opacity"; from: 0; to: 1; duration: Theme.durBase }
            NumberAnimation { property: "y"; from: combo.height - 2; to: combo.height + 4; duration: Theme.durBase; easing.type: Theme.easeOut }
        }
        exit: Transition { NumberAnimation { property: "opacity"; to: 0; duration: Theme.durFast } }
        contentItem: ListView {
            clip: true
            implicitHeight: contentHeight
            model: combo.popup.visible ? combo.delegateModel : null
            currentIndex: combo.highlightedIndex
        }
        background: Rectangle { color: Theme.background; border.color: Theme.stroke; radius: Theme.radius + 4 }
    }
}
