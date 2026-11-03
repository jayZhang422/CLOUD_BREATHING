import QtQuick
import QtQuick.Controls
import QtQuick.Layouts
import "../components"
import ".."

Item {
    id: reconstructionPage
    objectName: "reconstructionWorkspace"
    property var appWindow
    property alias stlViewport: fullStlHost
    signal resetScene()

    RowLayout {
        anchors.fill: parent
        spacing: 8
        Rectangle {
            Layout.preferredWidth: 264
            Layout.fillHeight: true
            color: Theme.panel; radius: Theme.panelRadius
            ColumnLayout {
                anchors.fill: parent
                anchors.margins: 16
                spacing: 12
                RowLayout {
                    Layout.fillWidth: true
                    Text { text: "三维结构"; color: Theme.text; font.pixelSize: Theme.fontTitle; font.weight: Font.DemiBold; Layout.fillWidth: true }
                    Text { text: stlViewer.rows.length + " 项"; color: Theme.muted; font.pixelSize: Theme.fontCaption }
                }
                RowLayout {
                    Layout.fillWidth: true
                    spacing: 6
                    AppButton {
                        id: loadStlButton
                        Layout.fillWidth: true
                        text: stlViewer.busy ? "读取中" : "加载 STL"
                        iconName: "folder-open"
                        primary: stlViewer.rows.length === 0
                        enabled: !stlViewer.busy && !ctfpga.busy
                        onClicked: stlViewer.chooseDirectory()
                    }
                    ToolButton { iconName: "rotate-ccw"; tip: "重置三维视角"; enabled: appWindow.stlSceneReady; onClicked: reconstructionPage.resetScene() }
                }
                Text {
                    text: stlViewer.status
                    visible: text.length > 0
                    color: stlViewer.status.indexOf("失败") >= 0 ? Theme.error : Theme.faint
                    font.pixelSize: Theme.fontCaption; wrapMode: Text.WordWrap; Layout.fillWidth: true
                    maximumLineCount: 2; elide: Text.ElideRight
                }

                // CT -> STL with ctfpga; shown until a structure set is loaded.
                ColumnLayout {
                    id: ctfpgaSection
                    objectName: "ctfpgaSection"
                    Layout.fillWidth: true
                    spacing: 8
                    visible: ctfpga.busy || stlViewer.rows.length === 0
                    RowLayout {
                        Layout.fillWidth: true
                        spacing: 6
                        Rectangle { Layout.fillWidth: true; height: 1; color: Theme.stroke }
                        Text { text: "CT → STL（ctfpga）"; color: Theme.muted; font.pixelSize: Theme.fontCaption; font.weight: Font.DemiBold }
                        Rectangle { Layout.fillWidth: true; height: 1; color: Theme.stroke }
                    }
                    RowLayout {
                        Layout.fillWidth: true
                        spacing: 6
                        Text {
                            Layout.fillWidth: true
                            text: "DICOM：" + (ctfpga.dicomDirectory.length > 0 ? ctfpga.dicomDirectory : "未选择")
                            color: Theme.faint; font.pixelSize: Theme.fontCaption
                            elide: Text.ElideMiddle
                        }
                        ToolButton { iconName: "folder-open"; tip: "选择 DICOM 文件夹"; enabled: ctfpga.available && !ctfpga.busy; onClicked: ctfpga.chooseDicom() }
                    }
                    RowLayout {
                        Layout.fillWidth: true
                        spacing: 6
                        AppButton {
                            objectName: "ctfpgaStartButton"
                            Layout.fillWidth: true
                            text: !ctfpga.available ? "ctfpga 未编译" : (ctfpga.busy ? "重建中" : "开始重建")
                            primary: ctfpga.available && !ctfpga.busy
                            enabled: ctfpga.available && !ctfpga.busy && !stlViewer.busy && ctfpga.dicomDirectory.length > 0
                            onClicked: ctfpga.start()
                        }
                        AppButton {
                            text: "取消"
                            danger: ctfpga.busy
                            enabled: ctfpga.busy
                            onClicked: ctfpga.cancel()
                        }
                    }
                    AppButton {
                        Layout.fillWidth: true
                        text: "已有推理结果 → STL"
                        tip: "选择含 prediction/ 的病例目录，只运行 BIN2STL、平滑和减面"
                        enabled: ctfpga.available && !ctfpga.busy && !stlViewer.busy
                        onClicked: ctfpga.chooseExistingCase()
                    }
                    // Progress card: overall bar plus one row per stage.
                    Rectangle {
                        id: progressCard
                        Layout.fillWidth: true
                        visible: ctfpga.elapsedText.length > 0
                        implicitHeight: progressColumn.implicitHeight + 24
                        radius: Theme.radius
                        color: Theme.toolbar
                        border.width: 1; border.color: Theme.strokeSoft
                        readonly property int doneCount: {
                            var n = 0
                            for (var i = 0; i < ctfpga.stages.length; ++i)
                                if (ctfpga.stages[i].status === "Done") n++
                            return n
                        }
                        readonly property bool failed: {
                            for (var i = 0; i < ctfpga.stages.length; ++i)
                                if (ctfpga.stages[i].status === "Failed") return true
                            return false
                        }
                        ColumnLayout {
                            id: progressColumn
                            anchors.left: parent.left; anchors.right: parent.right; anchors.top: parent.top
                            anchors.margins: 12
                            spacing: 8
                            RowLayout {
                                Layout.fillWidth: true
                                Text {
                                    Layout.fillWidth: true
                                    text: progressCard.failed ? "重建失败" : (ctfpga.busy ? "正在重建" : (progressCard.doneCount === ctfpga.stages.length ? "重建完成" : "已停止"))
                                    color: progressCard.failed ? Theme.error : Theme.text
                                    font.pixelSize: Theme.fontLabel; font.weight: Font.DemiBold
                                }
                                Text { text: ctfpga.elapsedText; color: Theme.muted; font.pixelSize: Theme.fontCaption }
                            }
                            Rectangle {
                                Layout.fillWidth: true; height: 4; radius: 2; color: Theme.strokeSoft
                                Rectangle {
                                    height: parent.height; radius: 2
                                    color: progressCard.failed ? Theme.error : Theme.accent
                                    width: parent.width * progressCard.doneCount / Math.max(1, ctfpga.stages.length)
                                    Behavior on width { NumberAnimation { duration: Theme.durSlow; easing.type: Theme.easeOut } }
                                }
                            }
                            Repeater {
                                model: ctfpga.stages
                                delegate: RowLayout {
                                    id: stageRow
                                    required property var modelData
                                    readonly property string stageState: modelData.status
                                    Layout.fillWidth: true
                                    spacing: 8
                                    Item {
                                        Layout.preferredWidth: 16; Layout.preferredHeight: 16
                                        Rectangle {
                                            anchors.fill: parent; radius: 8
                                            color: stageRow.stageState === "Done" ? Theme.success
                                                 : stageRow.stageState === "Failed" ? Theme.error : "transparent"
                                            border.width: stageRow.stageState === "Done" || stageRow.stageState === "Failed" ? 0 : 2
                                            border.color: stageRow.stageState === "Running" ? Theme.accent : Theme.stroke
                                            Icon {
                                                anchors.centerIn: parent; size: 10; inverse: true
                                                visible: stageRow.stageState === "Done" || stageRow.stageState === "Failed"
                                                name: stageRow.stageState === "Done" ? "check" : "x"
                                            }
                                            Rectangle {
                                                anchors.centerIn: parent; width: 6; height: 6; radius: 3
                                                color: Theme.accent
                                                visible: stageRow.stageState === "Running"
                                                SequentialAnimation on opacity {
                                                    running: stageRow.stageState === "Running"
                                                    loops: Animation.Infinite
                                                    NumberAnimation { to: 0.25; duration: 600 }
                                                    NumberAnimation { to: 1; duration: 600 }
                                                }
                                            }
                                        }
                                    }
                                    Text {
                                        text: stageRow.modelData.label
                                        color: stageRow.stageState === "Running" ? Theme.text
                                             : stageRow.stageState === "Done" ? Theme.muted
                                             : stageRow.stageState === "Failed" ? Theme.error : Theme.faint
                                        font.pixelSize: Theme.fontCaption
                                        font.weight: stageRow.stageState === "Running" ? Font.DemiBold : Font.Normal
                                    }
                                    Text {
                                        Layout.fillWidth: true
                                        text: stageRow.stageState === "Running" || stageRow.stageState === "Failed" ? stageRow.modelData.detail : ""
                                        color: Theme.faint; font.pixelSize: 10
                                        horizontalAlignment: Text.AlignRight
                                        elide: Text.ElideRight
                                    }
                                }
                            }
                        }
                    }
                    // While running, the stage rows above already show progress.
                    Text {
                        Layout.fillWidth: true
                        visible: !ctfpga.busy && text.length > 0
                        text: ctfpga.status
                        color: ctfpga.status.indexOf("失败") >= 0 ? Theme.error : Theme.faint
                        font.pixelSize: Theme.fontCaption; wrapMode: Text.WrapAnywhere
                        maximumLineCount: 3; elide: Text.ElideRight
                    }
                    Text {
                        Layout.fillWidth: true
                        visible: ctfpga.available && !ctfpga.busy && ctfpga.elapsedText.length === 0
                        text: "网格阶段约 8 分钟，峰值内存约 2.2 GB。"
                        color: Theme.faint; font.pixelSize: Theme.fontCaption; wrapMode: Text.WordWrap
                    }
                }

                ListView {
                    id: structureList
                    Layout.fillWidth: true; Layout.fillHeight: true
                    clip: true
                    model: stlViewer.rows
                    spacing: 4
                    boundsBehavior: Flickable.StopAtBounds
                    ScrollBar.vertical: ScrollBar { policy: ScrollBar.AsNeeded }
                    delegate: Rectangle {
                        id: structureRow
                        required property var modelData
                        required property int index
                        property bool open: false
                        width: structureList.width
                        height: open ? 84 : 44
                        radius: Theme.radius
                        clip: true
                        color: rowHover.hovered ? Theme.panelRaised : (structureRow.modelData.visible ? Theme.input : Theme.toolbar)
                        border.width: 1
                        border.color: open ? Theme.accentGlow : Theme.strokeSoft
                        Behavior on height { NumberAnimation { duration: Theme.durBase; easing.type: Theme.easeOut } }
                        Behavior on color { ColorAnimation { duration: Theme.durFast } }
                        Behavior on border.color { ColorAnimation { duration: Theme.durFast } }
                        HoverHandler { id: rowHover }
                        TapHandler { onTapped: structureRow.open = !structureRow.open }
                        ColumnLayout {
                            anchors.fill: parent
                            anchors.leftMargin: 6; anchors.rightMargin: 10; anchors.topMargin: 6; anchors.bottomMargin: 6
                            spacing: 4
                            RowLayout {
                                Layout.fillWidth: true
                                Layout.preferredHeight: 32
                                spacing: 4
                                ToolButton {
                                    iconName: structureRow.modelData.visible ? "eye" : "eye-off"
                                    tip: structureRow.modelData.visible ? "隐藏结构" : "显示结构"
                                    checkable: true
                                    checked: structureRow.modelData.visible
                                    onClicked: stlViewer.setVisible(structureRow.index, checked)
                                }
                                Text {
                                    Layout.fillWidth: true
                                    text: structureRow.modelData.name.replace(/\.stl$/i, "")
                                    color: structureRow.modelData.visible ? Theme.text : Theme.faint
                                    font.pixelSize: Theme.fontLabel
                                    elide: Text.ElideMiddle
                                }
                                Button {
                                    id: structureColor
                                    Layout.preferredWidth: 20; Layout.preferredHeight: 20
                                    onClicked: stlViewer.chooseColor(structureRow.index)
                                    ToolTip.visible: hovered; ToolTip.text: "修改结构颜色"
                                    background: Rectangle { color: structureRow.modelData.color; border.color: structureColor.hovered ? Theme.text : Theme.stroke; radius: 10 }
                                }
                            }
                            RowLayout {
                                Layout.fillWidth: true
                                Layout.leftMargin: 6
                                opacity: structureRow.open ? 1 : 0
                                Behavior on opacity { NumberAnimation { duration: Theme.durBase } }
                                Text { text: "不透明度"; color: Theme.faint; font.pixelSize: Theme.fontCaption }
                                AppSlider {
                                    id: opacitySlider
                                    Layout.fillWidth: true
                                    enabled: structureRow.open
                                    from: 0; to: 1; value: structureRow.modelData.opacity
                                    onMoved: stlViewer.setOpacity(structureRow.index, value)
                                }
                                Text { text: Math.round(structureRow.modelData.opacity * 100) + "%"; color: Theme.muted; font.pixelSize: Theme.fontCaption; Layout.preferredWidth: 34; horizontalAlignment: Text.AlignRight }
                            }
                        }
                    }
                    ColumnLayout {
                        anchors.centerIn: parent; spacing: 8; visible: structureList.count === 0 && !ctfpgaSection.visible
                        Icon { Layout.alignment: Qt.AlignHCenter; name: "box"; size: 28; opacity: 0.4 }
                        Text { Layout.alignment: Qt.AlignHCenter; text: "未加载 STL 结构"; color: Theme.faint; font.pixelSize: Theme.fontCaption }
                    }
                }

                CollapsibleSection {
                    Layout.fillWidth: true
                    title: "更多"
                    expanded: false
                    RowLayout {
                        Layout.fillWidth: true
                        spacing: 6
                        visible: typeof boardMode === "undefined" || !boardMode
                        AppCheckBox {
                            id: previewToggle
                            text: "减面预览"
                            checked: stlViewer.previewFaces > 0
                            onToggled: stlViewer.setPreviewFaces(checked ? previewLimit.value : 0)
                            ToolTip.visible: hovered
                            ToolTip.text: "预览不修改原始 STL"
                        }
                        SpinBox {
                            id: previewLimit
                            Layout.fillWidth: true
                            Layout.preferredHeight: 32
                            Layout.minimumWidth: 90
                            from: 1000; to: 300000; stepSize: 1000; value: 30000
                            enabled: previewToggle.checked
                            editable: true
                            onValueModified: stlViewer.setPreviewFaces(value)
                            palette.text: Theme.text
                            palette.buttonText: Theme.text
                            palette.base: Theme.input
                            palette.button: Theme.toolbar
                            palette.highlight: Theme.accent
                            leftPadding: 23
                            rightPadding: 23
                            contentItem: TextInput {
                                text: previewLimit.textFromValue(previewLimit.value, previewLimit.locale)
                                color: Theme.text
                                font.pixelSize: 12
                                selectionColor: Theme.accentGlow
                                selectedTextColor: Theme.text
                                horizontalAlignment: TextInput.AlignHCenter
                                verticalAlignment: TextInput.AlignVCenter
                                readOnly: !previewLimit.editable
                                validator: previewLimit.validator
                                inputMethodHints: Qt.ImhDigitsOnly
                            }
                            background: Rectangle { color: Theme.input; radius: 6; border.color: previewLimit.activeFocus ? Theme.accent : Theme.stroke }
                            up.indicator: Rectangle {
                                x: previewLimit.width - width
                                width: 22; height: previewLimit.height
                                color: previewLimit.up.pressed ? Theme.accentDim : "transparent"
                                Icon { anchors.centerIn: parent; name: "plus"; size: 12 }
                            }
                            down.indicator: Rectangle {
                                width: 22; height: previewLimit.height
                                color: previewLimit.down.pressed ? Theme.accentDim : "transparent"
                                Icon { anchors.centerIn: parent; name: "minus"; size: 12 }
                            }
                            ToolTip.visible: hovered
                            ToolTip.text: "所有结构的预览总面数上限"
                        }
                        Text { text: "面"; color: Theme.muted; font.pixelSize: 12 }
                    }
                    Text { text: stlViewer.timingText; visible: text.length > 0; color: Theme.faint; font.pixelSize: Theme.fontCaption; wrapMode: Text.WordWrap; Layout.fillWidth: true; maximumLineCount: 2; elide: Text.ElideRight }
                    RowLayout {
                        Layout.fillWidth: true
                        spacing: 6
                        Text { text: "合计 " + stlViewer.triangleCountText + " 面"; color: Theme.faint; font.pixelSize: Theme.fontCaption; Layout.fillWidth: true }
                        ToolButton {
                            objectName: "detach3DButton"
                            visible: !singleWindowMode
                            iconName: "maximize-2"
                            tip: appWindow.detached3D ? "将独立三维视图返回此页" : "在独立窗口中观察三维模型"
                            checkable: true
                            checked: appWindow.detached3D
                            enabled: appWindow.stlSceneReady
                            onClicked: appWindow.detached3D = !appWindow.detached3D
                        }
                        ToolButton { iconName: "gauge"; tip: "记录旋转帧时间"; enabled: appWindow.stlSceneReady && stlViewer.triangleCount > 0; onClicked: appWindow.runRotationBenchmark() }
                    }
                }
                AppButton {
                    objectName: "focus3DButton"
                    Layout.fillWidth: true
                    text: "专注三维"
                    iconName: "maximize-2"
                    tip: singleWindowMode ? "在当前全屏窗口中观察三维视图；Esc 返回" : "隐藏工作站，只观察当前三维视图；Esc 或返回按钮恢复"
                    enabled: appWindow.stlSceneReady && stlViewer.triangleCount > 0
                    onClicked: appWindow.enterFocus3D()
                }
            }
        }

        ColumnLayout {
            Layout.fillWidth: true
            Layout.fillHeight: true
            spacing: 0
            Item {
                id: viewArea
                Layout.fillWidth: true; Layout.fillHeight: true
                clip: true
                // Three 4:3 CT panels together have the same height as the square STL.
                readonly property real sceneSide: Math.max(0, Math.min(height - 16, (width - 24 + 48 / 9) * 9 / 13))
                readonly property real ctHeight: Math.max(0, (sceneSide - 12) / 3)
                readonly property real ctWidth: ctHeight * 4 / 3
                readonly property real leftInset: Math.max(8, (width - sceneSide - 6 - ctWidth) / 2)
                Item {
                    id: fullStlHost
                    objectName: "reconstructionStlViewport"
                    x: viewArea.leftInset
                    y: (viewArea.height - height) / 2
                    width: viewArea.sceneSide
                    height: width
                    Rectangle {
                        anchors.fill: parent
                        visible: reconstructionPage.appWindow.detached3D
                        color: Theme.background
                        border.color: Theme.strokeSoft
                        Column {
                            anchors.centerIn: parent
                            spacing: 14
                            Text { text: "三维视图已移至独立窗口"; color: Theme.muted; font.pixelSize: 13 }
                            AppButton {
                                anchors.horizontalCenter: parent.horizontalCenter
                                text: "返回此页"
                                iconName: "maximize-2"
                                onClicked: reconstructionPage.appWindow.detached3D = false
                            }
                        }
                    }
                }
                Column {
                    x: fullStlHost.x + fullStlHost.width + 6
                    y: fullStlHost.y
                    width: viewArea.ctWidth
                    height: viewArea.sceneSide
                    spacing: 6
                    SlicePanel {
                        objectName: "reconstructionAxialViewport"
                        appWindow: reconstructionPage.appWindow
                        pageActive: appWindow.appPage === 2 && session.authenticated
                        width: viewArea.ctWidth; height: viewArea.ctHeight
                        title: "轴位 / Axial"; sourceUrl: ctImporter.previewPath; axial: true; plane: "axial"
                        expandable: true
                        onExpandRequested: { appWindow.appPage = 1; appWindow.active3D = false; appWindow.selectedPlane = "axial" }
                    }
                    SlicePanel {
                        objectName: "reconstructionCoronalViewport"
                        appWindow: reconstructionPage.appWindow
                        pageActive: appWindow.appPage === 2 && session.authenticated
                        width: viewArea.ctWidth; height: viewArea.ctHeight
                        title: "冠状位 / Coronal"; sourceUrl: ctImporter.coronalPath; plane: "coronal"
                        expandable: true
                        onExpandRequested: { appWindow.appPage = 1; appWindow.active3D = false; appWindow.selectedPlane = "coronal" }
                    }
                    SlicePanel {
                        objectName: "reconstructionSagittalViewport"
                        appWindow: reconstructionPage.appWindow
                        pageActive: appWindow.appPage === 2 && session.authenticated
                        width: viewArea.ctWidth; height: viewArea.ctHeight
                        title: "矢状位 / Sagittal"; sourceUrl: ctImporter.sagittalPath; plane: "sagittal"
                        expandable: true
                        onExpandRequested: { appWindow.appPage = 1; appWindow.active3D = false; appWindow.selectedPlane = "sagittal" }
                    }
                }
            }
        }
    }
}
