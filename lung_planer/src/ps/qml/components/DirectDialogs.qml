import QtQuick
import QtQuick.Controls
import QtQuick.Layouts
import ".."

// Controls Dialog is an Item popup on Qt 6.7, not a QWidget/native dialog.
Dialog {
    id: dialog
    objectName: "directDialog"
    parent: Overlay.overlay
    anchors.centerIn: parent
    width: Math.min(800, parent ? parent.width - 48 : 800)
    height: Math.min(uiDialogs.kind === "color" ? 490 : 670, parent ? parent.height - 48 : 670)
    modal: true
    title: uiDialogs.title
    closePolicy: Popup.CloseOnEscape
    padding: 20
    palette.windowText: Theme.text
    palette.text: Theme.text
    palette.buttonText: Theme.text
    palette.base: Theme.input
    palette.button: Theme.panelRaised
    background: Rectangle { color: Theme.panel; radius: Theme.authRadius; border.color: Theme.stroke }
    enter: Transition {
        NumberAnimation { property: "opacity"; from: 0; to: 1; duration: Theme.durBase }
        NumberAnimation { property: "scale"; from: 0.97; to: 1; duration: Theme.durBase; easing.type: Theme.easeOut }
    }
    exit: Transition { NumberAnimation { property: "opacity"; to: 0; duration: Theme.durFast } }
    Overlay.modal: Rectangle { color: "#8c14264a" }
    onRejected: uiDialogs.cancel()
    onClosed: { if (uiDialogs.kind !== "") uiDialogs.cancel() }
    Connections {
        target: uiDialogs
        function onRequested() {
            pathField.text = uiDialogs.path
            valueField.text = uiDialogs.value
            dialog.open()
        }
        function onChanged() { pathField.text = uiDialogs.path }
    }
    contentItem: ColumnLayout {
        spacing: 14
        RowLayout {
            visible: uiDialogs.kind !== "color"
            Layout.fillWidth: true
            AppButton { text: "上一级"; iconName: "arrow-left"; onClicked: uiDialogs.up() }
            TextField {
                id: pathField
                objectName: "dialogPath"
                Layout.fillWidth: true
                color: Theme.text
                selectByMouse: true
                onAccepted: uiDialogs.browse(text)
                background: Rectangle { color: Theme.input; radius: 5; border.color: Theme.stroke }
            }
            AppButton { text: "转到"; onClicked: uiDialogs.browse(pathField.text) }
        }
        Text { visible: uiDialogs.kind === "directory"; text: "单击进入文件夹，确认将选择当前目录"; color: Theme.muted; font.pixelSize: 14 }
        ListView {
            objectName: "dialogFolders"
            visible: uiDialogs.kind !== "color" && uiDialogs.kind !== "open"
            Layout.fillWidth: true
            Layout.fillHeight: true
            clip: true
            model: uiDialogs.entries
            ScrollBar.vertical: ScrollBar { }
            delegate: ItemDelegate {
                required property var modelData
                width: ListView.view.width
                height: 44
                text: modelData.name
                contentItem: Text { text: parent.text; color: Theme.text; verticalAlignment: Text.AlignVCenter; elide: Text.ElideMiddle }
                background: Rectangle { color: parent.hovered ? Theme.panelRaised : "transparent"; radius: 5 }
                onClicked: uiDialogs.browse(modelData.path)
            }
        }
        Text { visible: uiDialogs.kind === "open"; text: "规划文件"; color: Theme.muted }
        ListView {
            objectName: "dialogFiles"
            visible: uiDialogs.kind === "open"
            Layout.fillWidth: true
            Layout.fillHeight: true
            clip: true
            model: uiDialogs.files
            ScrollBar.vertical: ScrollBar { }
            delegate: ItemDelegate {
                required property var modelData
                width: ListView.view.width
                height: 44
                highlighted: uiDialogs.value === modelData.name
                text: modelData.name
                contentItem: Text { text: parent.text; color: Theme.text; verticalAlignment: Text.AlignVCenter; elide: Text.ElideMiddle }
                background: Rectangle { color: parent.highlighted || parent.hovered ? Theme.panelRaised : "transparent"; radius: 5 }
                onClicked: {
                    uiDialogs.selectFile(modelData.name)
                    valueField.text = modelData.name
                }
            }
        }
        Flow {
            visible: uiDialogs.kind === "color"
            Layout.fillWidth: true
            spacing: 12
            Repeater {
                model: ["#d66a6a", "#72a9c3", "#e5b56e", "#a8bec5", "#60c7aa", "#a69be0", "#f080b0", "#ffffff", "#ff4500", "#45d9ff", "#bbff55", "#999999"]
                delegate: Button {
                    required property string modelData
                    width: 50; height: 45
                    background: Rectangle { color: parent.modelData; radius: 6; border.color: Theme.stroke }
                    onClicked: valueField.text = modelData
                }
            }
        }
        Rectangle {
            visible: uiDialogs.kind === "color"
            Layout.fillWidth: true
            Layout.fillHeight: true
            color: /^#[0-9a-fA-F]{6}$/.test(valueField.text) ? valueField.text : "transparent"
            radius: 6
            border.color: Theme.stroke
        }
        Text { text: uiDialogs.kind === "color" ? "自定义颜色（#RRGGBB）" : "文件名"; visible: uiDialogs.kind !== "directory"; color: Theme.muted }
        TextField {
            id: valueField
            objectName: "dialogValue"
            visible: uiDialogs.kind !== "directory"
            Layout.fillWidth: true
            color: Theme.text
            selectByMouse: true
            background: Rectangle { color: Theme.input; radius: 5; border.color: Theme.stroke }
        }
        Text { Layout.fillWidth: true; text: uiDialogs.error; visible: text.length > 0; wrapMode: Text.Wrap; color: Theme.error }
        RowLayout {
            Layout.fillWidth: true
            Item { Layout.fillWidth: true }
            AppButton { text: "取消"; onClicked: dialog.reject() }
            AppButton {
                objectName: "dialogConfirm"
                text: "确认"
                primary: true
                onClicked: {
                    if (uiDialogs.kind !== "color" && pathField.text !== uiDialogs.path && !uiDialogs.browse(pathField.text)) return
                    if (uiDialogs.accept(valueField.text)) dialog.close()
                }
            }
        }
    }
}
