import QtQuick
import QtQuick.Controls
import QtQuick.Layouts
import ".."
import "." as C

Rectangle {
    id: bar
    property var appWindow
    color: Theme.input
    implicitHeight: 44
    Rectangle { anchors.bottom: parent.bottom; width: parent.width; height: 1; color: Theme.strokeSoft }
    RowLayout {
        anchors.fill: parent; anchors.leftMargin: 16; anchors.rightMargin: 16; spacing: 6
        Text { text: "标注"; color: Theme.muted; font.pixelSize: 12; Layout.rightMargin: 8 }
        Repeater {
            model: [{icon: "mouse-pointer-2", label: "浏览"}, {icon: "pen-line", label: "记号笔"}, {icon: "highlighter", label: "荧光笔"}]
            C.ToolButton {
                required property int index
                required property var modelData
                iconName: modelData.icon; tip: modelData.label; checkable: true
                checked: appWindow.annotationMode === index
                onClicked: appWindow.annotationMode = index
            }
        }
        Rectangle { Layout.preferredWidth: 1; Layout.preferredHeight: 18; Layout.leftMargin: 8; Layout.rightMargin: 8; color: Theme.stroke }
        Repeater {
            model: [{color:"#ff4545",label:"红色"}, {color:"#ffdd33",label:"黄色"}, {color:"#36e889",label:"绿色"}, {color:"#29b6ff",label:"蓝色"}, {color:"#e879f9",label:"紫色"}, {color:"#ffffff",label:"白色"}]
            Button {
                id: swatch
                required property var modelData
                implicitWidth: 27; implicitHeight: 27
                onClicked: appWindow.annotationColor = modelData.color
                ToolTip.visible: hovered; ToolTip.text: modelData.label
                background: Rectangle {
                    color: "transparent"; radius: 4
                    border.width: 1
                    border.color: appWindow.annotationColor === swatch.modelData.color ? Theme.text : "transparent"
                    Rectangle { anchors.centerIn: parent; width: 15; height: 15; radius: 4; color: swatch.modelData.color; border.width: 1; border.color: Theme.stroke }
                }
            }
        }
        Rectangle { Layout.preferredWidth: 1; Layout.preferredHeight: 18; Layout.leftMargin: 8; Layout.rightMargin: 8; color: Theme.stroke }
        Text { text: "笔宽"; color: Theme.muted; font.pixelSize: 12 }
        AppSlider { Layout.preferredWidth: 90; from: 2; to: 24; value: appWindow.annotationWidth; onMoved: appWindow.annotationWidth = value }
        Text { text: Math.round(appWindow.annotationWidth) + " px"; color: Theme.muted; font.pixelSize: 12; Layout.preferredWidth: 35 }
        C.ToolButton { iconName: "undo-2"; tip: "撤销标注"; onClicked: appWindow.annotationCommand("undo") }
        C.ToolButton { iconName: "trash-2"; tip: "清除当前切片标注"; onClicked: appWindow.annotationCommand("clear") }
        AppButton { text: "暂存"; iconName: "save"; onClicked: appWindow.annotationCommand("save") }
        Item { Layout.fillWidth: true }
        Text { Layout.maximumWidth: bar.width > 1500 ? 420 : 180; elide: Text.ElideRight; text: annotations.status; color: Theme.faint; font.pixelSize: 12 }
    }
}
