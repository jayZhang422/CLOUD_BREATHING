import QtQuick
import QtQuick.Controls
import QtQuick.Layouts
import ".."
import "../components"

Item {
    id: queuePage
    property var appWindow
    objectName: "patientQueuePage"

    Rectangle { anchors.fill: parent; color: Theme.background }

    ColumnLayout {
        anchors.fill: parent
        anchors.leftMargin: 22
        anchors.rightMargin: 22
        anchors.topMargin: 18
        anchors.bottomMargin: 14
        spacing: 0

        RowLayout {
            Layout.fillWidth: true
            Layout.preferredHeight: 48
            spacing: 12
            Text {
                Layout.fillWidth: true
                text: patientQueue.rows.length + " 条记录"
                color: Theme.muted
                font.pixelSize: Theme.fontBody
            }
            LineField {
                id: filterField
                Layout.preferredWidth: 270
                Layout.preferredHeight: 36
                placeholderText: appWindow.hidePatientInfo ? "搜索病人编号" : "搜索姓名、ID 或医院"
                onTextChanged: appWindow.queueFilter = text.trim().toLowerCase()
            }
            AppButton {
                objectName: "hidePatientInfoButton"
                text: appWindow.hidePatientInfo ? "显示病人信息" : "隐藏病人信息"
                iconName: appWindow.hidePatientInfo ? "eye" : "eye-off"
                tip: "隐藏后仅显示病人编号、模态和切片数量"
                onClicked: appWindow.hidePatientInfo = !appWindow.hidePatientInfo
            }
            ToolButton { iconName: "refresh-cw"; tip: "刷新病例"; onClicked: patientQueue.refresh() }
            AppButton {
                text: "导入 STL"; iconName: "folder-open"
                enabled: !stlDecimation.busy && !stlViewer.busy
                onClicked: stlDecimation.chooseDirectory()
            }
            AppButton {
                text: "导入 CT"; iconName: "folder-open"; warm: true
                tip: "导入一个 DICOM 文件夹"
                enabled: !ctImporter.busy
                onClicked: ctImporter.chooseDirectory()
            }
        }

        // STL decimation is occasional work: folded by default, opens by itself
        // while a reduction is running.
        Rectangle {
            id: stlTool
            property bool userOpen: false
            readonly property bool open: userOpen || stlDecimation.busy
            property real openness: open ? 1 : 0
            Behavior on openness { NumberAnimation { duration: Theme.durBase; easing.type: Theme.easeOut } }
            Layout.fillWidth: true
            Layout.topMargin: 14
            implicitHeight: 44 + reductionControls.implicitHeight * openness + (openness > 0.01 ? 12 : 0) * openness
            color: Theme.panel
            border.color: Theme.stroke
            radius: Theme.panelRadius
            clip: true
            Rectangle {
                id: stlHeader
                anchors.left: parent.left; anchors.right: parent.right; anchors.top: parent.top
                height: 44
                color: stlHeaderArea.containsMouse ? Theme.panelRaised : "transparent"
                radius: Theme.panelRadius
                Behavior on color { ColorAnimation { duration: Theme.durFast } }
                RowLayout {
                    anchors.fill: parent; anchors.leftMargin: 14; anchors.rightMargin: 14; spacing: 10
                    Icon { name: "box"; size: 16; opacity: 0.8 }
                    Text { text: "STL 模型减面"; color: Theme.text; font.pixelSize: Theme.fontBody; font.weight: Font.DemiBold }
                    Text {
                        Layout.fillWidth: true
                        text: stlDecimation.busy ? stlDecimation.status : (stlDecimation.source || "未导入")
                        color: stlDecimation.busy ? Theme.accent : Theme.faint
                        font.pixelSize: Theme.fontCaption; elide: Text.ElideMiddle
                    }
                    Icon { name: "chevron-down"; size: 16; rotation: 180 * stlTool.openness }
                }
                MouseArea {
                    id: stlHeaderArea
                    anchors.fill: parent; hoverEnabled: true; cursorShape: Qt.PointingHandCursor
                    onClicked: stlTool.userOpen = !stlTool.userOpen
                }
            }
            ColumnLayout {
                id: reductionControls
                anchors.left: parent.left; anchors.right: parent.right; anchors.top: stlHeader.bottom
                anchors.leftMargin: 14; anchors.rightMargin: 14
                opacity: stlTool.openness
                spacing: 8
                RowLayout {
                    Layout.fillWidth: true
                    spacing: 10
                    Item { Layout.fillWidth: true }
                    Text { text: "目标总面数"; color: Theme.muted; font.pixelSize: 12 }
                    SpinBox {
                        id: targetFaces
                        objectName: "stlReductionTarget"
                        from: 1000; to: 5000000; value: 150000; stepSize: 1000
                        editable: true
                        enabled: !stlDecimation.busy
                        Layout.preferredWidth: 150
                        contentItem: TextInput {
                            text: targetFaces.textFromValue(targetFaces.value, targetFaces.locale)
                            font.pixelSize: 12; color: Theme.text; selectionColor: Theme.accent
                            selectedTextColor: Theme.accentForeground
                            horizontalAlignment: Qt.AlignHCenter; verticalAlignment: Qt.AlignVCenter
                            readOnly: !targetFaces.editable
                            validator: targetFaces.validator
                            inputMethodHints: Qt.ImhDigitsOnly
                        }
                        background: Rectangle { color: Theme.input; border.color: Theme.stroke; radius: 4 }
                        up.indicator: Rectangle {
                            x: targetFaces.width - width; width: 28; height: targetFaces.height
                            color: targetFaces.up.pressed ? Theme.stroke : Theme.panelRaised
                            Text { anchors.centerIn: parent; text: "+"; color: Theme.text; font.pixelSize: 20 }
                        }
                        down.indicator: Rectangle {
                            width: 28; height: targetFaces.height
                            color: targetFaces.down.pressed ? Theme.stroke : Theme.panelRaised
                            Text { anchors.centerIn: parent; text: "−"; color: Theme.text; font.pixelSize: 20 }
                        }
                    }
                    AppButton {
                        text: "分器官减面"; primary: true
                        enabled: !!stlDecimation.source && !stlDecimation.busy && !stlViewer.busy
                        onClicked: stlDecimation.start(targetFaces.value)
                    }
                    AppButton { text: "取消"; visible: stlDecimation.busy; onClicked: stlDecimation.cancel() }
                    AppButton {
                        text: "载入原始"
                        enabled: !!stlDecimation.source && !stlDecimation.busy && !stlViewer.busy
                        onClicked: { stlDecimation.load(false); appWindow.appPage = 2 }
                    }
                    AppButton {
                        text: "查看减面结果"
                        enabled: !!stlDecimation.result && !stlDecimation.busy && !stlViewer.busy
                        onClicked: { stlDecimation.load(true); appWindow.appPage = 2 }
                    }
                }
                Text {
                    Layout.fillWidth: true
                    text: stlDecimation.status
                    color: Theme.text; font.pixelSize: 12; wrapMode: Text.WrapAnywhere
                }
                RowLayout {
                    Layout.fillWidth: true; spacing: 6
                    InfoTip { warn: true; text: "细节优先级：血管 / 肿瘤 > 气管 > 肺叶。载入减面结果后，显示、规划和中心线统一使用减面模型，计算精度需另行验证；原始文件保留。" }
                    Text { text: "减面会影响计算精度，原始文件保留"; color: Theme.faint; font.pixelSize: Theme.fontCaption }
                }
                ProgressBar { Layout.fillWidth: true; indeterminate: true; visible: stlDecimation.busy }
            }
        }

        RowLayout {
            Layout.fillWidth: true; Layout.fillHeight: true
            Layout.topMargin: 14; spacing: 16

            Rectangle {
                Layout.fillWidth: true; Layout.fillHeight: true
                color: Theme.queueBackground
                border.color: Theme.stroke
                border.width: 1
                radius: Theme.panelRadius
                clip: true
                ColumnLayout {
                    anchors.fill: parent
                    spacing: 0
                Rectangle {
                    Layout.fillWidth: true; Layout.preferredHeight: 38
                    color: Theme.queueHeader
                    radius: 0
                    RowLayout {
                        anchors.fill: parent; anchors.leftMargin: 14; anchors.rightMargin: 14; spacing: 8
                        Text { visible: !appWindow.hidePatientInfo; Layout.preferredWidth: 142; text: "患者 ID"; color: Theme.queueMuted; font.pixelSize: 12 }
                        Text { Layout.preferredWidth: appWindow.hidePatientInfo ? 200 : 128; text: appWindow.hidePatientInfo ? "病人" : "患者姓名"; color: Theme.queueMuted; font.pixelSize: 12 }
                        Text { Layout.preferredWidth: 62; text: "模态"; color: Theme.queueMuted; font.pixelSize: 12 }
                        Text { visible: !appWindow.hidePatientInfo; Layout.fillWidth: true; text: "机构 / 检查描述"; color: Theme.queueMuted; font.pixelSize: 12 }
                        Text { Layout.preferredWidth: 70; text: "切片"; color: Theme.queueMuted; font.pixelSize: 12 }
                        Item { visible: appWindow.hidePatientInfo; Layout.fillWidth: true }
                        Text { visible: !appWindow.hidePatientInfo; Layout.preferredWidth: 148; text: "入库时间"; color: Theme.queueMuted; font.pixelSize: 12 }
                    }
                    Rectangle { anchors.left: parent.left; anchors.right: parent.right; anchors.bottom: parent.bottom; height: 1; color: Theme.stroke }
                }
                ListView {
                    id: patientList
                    Layout.fillWidth: true; Layout.fillHeight: true; clip: true
                    boundsBehavior: Flickable.StopAtBounds
                    ScrollBar.vertical: ScrollBar { policy: ScrollBar.AsNeeded }
                    model: patientQueue.rows.filter(function(row) {
                        const q = appWindow.queueFilter
                        const text = appWindow.hidePatientInfo ? row.alias
                            : (row.patientName + " " + row.patientId + " " + row.institution + " " + row.studyDescription)
                        return !q || text.toLowerCase().indexOf(q) >= 0
                    })
                    delegate: Rectangle {
                        id: caseRow
                        required property var modelData
                        required property int index
                        property bool hovered: false
                        width: patientList.width; height: 48
                        color: appWindow.selectedStudyId === modelData.studyId ? Theme.queueSelected : (hovered ? Theme.queueHover : Theme.queueBackground)
                        Behavior on color { ColorAnimation { duration: Theme.durFast } }
                        // Selection bar slides in from the left edge.
                        Rectangle {
                            anchors.left: parent.left; anchors.verticalCenter: parent.verticalCenter
                            width: 3; radius: 1.5; color: Theme.queueAccent
                            height: appWindow.selectedStudyId === caseRow.modelData.studyId ? parent.height - 16 : 0
                            Behavior on height { NumberAnimation { duration: Theme.durBase; easing.type: Theme.easeOut } }
                        }
                        RowLayout {
                            anchors.fill: parent; anchors.leftMargin: 14; anchors.rightMargin: 14; spacing: 8
                            Text { visible: !appWindow.hidePatientInfo; Layout.preferredWidth: 142; text: caseRow.modelData.patientId || "—"; color: Theme.queueText; font.pixelSize: 12; elide: Text.ElideRight }
                            Text { Layout.preferredWidth: appWindow.hidePatientInfo ? 200 : 128; text: appWindow.hidePatientInfo ? caseRow.modelData.alias : (caseRow.modelData.patientName || "未命名"); color: Theme.queueText; font.pixelSize: 12; elide: Text.ElideRight }
                            Text { Layout.preferredWidth: 62; text: caseRow.modelData.modality || "CT"; color: Theme.queueAccent; font.pixelSize: 12; font.weight: Font.DemiBold }
                            Text { visible: !appWindow.hidePatientInfo; Layout.fillWidth: true; text: (caseRow.modelData.institution || "未记录机构") + "  /  " + (caseRow.modelData.studyDescription || "未记录检查"); color: Theme.queueText; font.pixelSize: 12; elide: Text.ElideRight }
                            Text { Layout.preferredWidth: 70; text: caseRow.modelData.sliceCount || "—"; color: Theme.queueMuted; font.pixelSize: 12 }
                            Item { visible: appWindow.hidePatientInfo; Layout.fillWidth: true }
                            Text { visible: !appWindow.hidePatientInfo; Layout.preferredWidth: 148; text: caseRow.modelData.createdAt || "—"; color: Theme.queueMuted; font.pixelSize: 12; elide: Text.ElideRight }
                        }
                        Rectangle { anchors.left: parent.left; anchors.right: parent.right; anchors.bottom: parent.bottom; height: 1; color: Theme.strokeSoft; opacity: 0.8 }
                        MouseArea {
                            anchors.fill: parent; hoverEnabled: true
                            onEntered: caseRow.hovered = true
                            onExited: caseRow.hovered = false
                            onClicked: {
                                appWindow.selectedStudyId = caseRow.modelData.studyId
                                appWindow.selectedStudy = caseRow.modelData
                            }
                            onDoubleClicked: appWindow.openStudy(caseRow.modelData.studyId)
                        }
                    }
                    ColumnLayout {
                        anchors.centerIn: parent; spacing: 12; visible: patientList.count === 0
                        Icon { Layout.alignment: Qt.AlignHCenter; name: "folder-open"; size: 32; opacity: 0.5 }
                        Text { Layout.alignment: Qt.AlignHCenter; text: appWindow.queueFilter ? "没有匹配的病例" : "暂无病例"; color: Theme.queueText; font.pixelSize: Theme.fontBody; font.weight: Font.DemiBold }
                        Text { Layout.alignment: Qt.AlignHCenter; visible: !appWindow.queueFilter; text: "导入一个 DICOM 文件夹开始阅片"; color: Theme.queueMuted; font.pixelSize: Theme.fontCaption }
                        AppButton { Layout.alignment: Qt.AlignHCenter; visible: !appWindow.queueFilter; text: "导入 CT"; iconName: "folder-open"; warm: true; enabled: !ctImporter.busy; onClicked: ctImporter.chooseDirectory() }
                    }
                }
                Rectangle {
                    Layout.fillWidth: true; Layout.preferredHeight: 32; color: Theme.queueHeader
                    radius: 0
                    RowLayout {
                        anchors.fill: parent; anchors.leftMargin: 14; anchors.rightMargin: 14
                        Text {
                            Layout.fillWidth: true
                            text: ctImporter.busy ? ctImporter.status : "本地数据库 · " + patientList.count + " 条记录"
                            color: ctImporter.busy ? Theme.queueAccent : Theme.queueMuted
                            font.pixelSize: 12; elide: Text.ElideRight
                        }
                    }
                }
            }
            }

            Rectangle {
                Layout.preferredWidth: 286; Layout.fillHeight: true
                color: Theme.panel
                border.color: Theme.strokeSoft
                border.width: 1
                radius: Theme.panelRadius
                ColumnLayout {
                    anchors.fill: parent; anchors.margins: 16; spacing: 12
                    RowLayout {
                        Layout.fillWidth: true
                        Text { text: "病例详情"; color: Theme.text; font.pixelSize: 14; font.weight: Font.DemiBold; Layout.fillWidth: true }
                        Text { text: appWindow.selectedStudy ? "已选中" : "未选择"; color: appWindow.selectedStudy ? Theme.accent : Theme.faint; font.pixelSize: 12 }
                    }
                    Rectangle { Layout.fillWidth: true; Layout.preferredHeight: 1; color: Theme.stroke }
                    Text {
                        Layout.fillWidth: true
                        text: !appWindow.selectedStudy ? "未选中病例"
                            : (appWindow.hidePatientInfo ? appWindow.selectedStudy.alias : (appWindow.selectedStudy.patientName || "未命名患者"))
                        color: Theme.text; font.pixelSize: 20; font.weight: Font.DemiBold; elide: Text.ElideRight
                    }
                    Text {
                        visible: !appWindow.hidePatientInfo
                        Layout.fillWidth: true
                        text: appWindow.selectedStudy ? ("ID  " + appWindow.selectedStudy.patientId) : "—"
                        color: Theme.muted; font.pixelSize: 12; elide: Text.ElideRight
                    }
                    Rectangle { Layout.fillWidth: true; Layout.preferredHeight: 1; color: Theme.stroke }
                    ColumnLayout {
                        Layout.fillWidth: true; spacing: 12
                        Text { text: "检查信息"; color: Theme.faint; font.pixelSize: 12; font.bold: true }
                        ColumnLayout {
                            visible: !appWindow.hidePatientInfo
                            Layout.fillWidth: true; spacing: 3
                            Text { text: "机构"; color: Theme.faint; font.pixelSize: 12 }
                            Text { text: appWindow.selectedStudy ? (appWindow.selectedStudy.institution || "—") : "—"; color: Theme.text; font.pixelSize: 12; Layout.fillWidth: true; wrapMode: Text.Wrap; maximumLineCount: 2; elide: Text.ElideRight }
                        }
                        ColumnLayout {
                            visible: !appWindow.hidePatientInfo
                            Layout.fillWidth: true; spacing: 3
                            Text { text: "检查描述"; color: Theme.faint; font.pixelSize: 12 }
                            Text { text: appWindow.selectedStudy ? (appWindow.selectedStudy.studyDescription || "—") : "—"; color: Theme.text; font.pixelSize: 12; Layout.fillWidth: true; wrapMode: Text.Wrap; maximumLineCount: 3; elide: Text.ElideRight }
                        }
                        ColumnLayout {
                            visible: !appWindow.hidePatientInfo
                            Layout.fillWidth: true; spacing: 3
                            Text { text: "序列"; color: Theme.faint; font.pixelSize: 12 }
                            Text { text: appWindow.selectedStudy ? (appWindow.selectedStudy.seriesDescription || "—") : "—"; color: Theme.text; font.pixelSize: 12; Layout.fillWidth: true; wrapMode: Text.Wrap; maximumLineCount: 2; elide: Text.ElideRight }
                        }
                        RowLayout {
                            Layout.fillWidth: true
                            Text { text: "模态"; color: Theme.faint; font.pixelSize: 12; Layout.fillWidth: true }
                            Text { text: appWindow.selectedStudy ? (appWindow.selectedStudy.modality || "CT") : "—"; color: Theme.accent; font.pixelSize: 12 }
                        }
                        RowLayout {
                            Layout.fillWidth: true
                            Text { text: appWindow.hidePatientInfo ? "切片" : "图像"; color: Theme.faint; font.pixelSize: 12; Layout.fillWidth: true }
                            Text { text: appWindow.selectedStudy ? ((appWindow.selectedStudy.sliceCount || 0) + " 张" + (appWindow.hidePatientInfo ? "" : " · " + (appWindow.selectedStudy.dimensions || "—"))) : "—"; color: Theme.text; font.pixelSize: 12 }
                        }
                        ColumnLayout {
                            visible: !appWindow.hidePatientInfo
                            Layout.fillWidth: true; spacing: 3
                            Text { text: "入库时间"; color: Theme.faint; font.pixelSize: 12 }
                            Text { text: appWindow.selectedStudy ? (appWindow.selectedStudy.createdAt || "—") : "—"; color: Theme.muted; font.pixelSize: 12; Layout.fillWidth: true; elide: Text.ElideRight }
                        }
                    }
                    Item { Layout.fillHeight: true }
                    AppButton {
                        Layout.fillWidth: true; Layout.preferredHeight: 36
                        text: "打开影像"; iconName: "scan-line"; warm: true
                        enabled: appWindow.selectedStudyId >= 0
                        onClicked: appWindow.openStudy(appWindow.selectedStudyId)
                    }
                }
            }
        }
    }
}
