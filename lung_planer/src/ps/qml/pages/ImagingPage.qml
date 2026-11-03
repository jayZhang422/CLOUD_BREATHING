import QtQuick
import QtQuick.Controls
import QtQuick.Layouts
import "../components"
import ".."

Item {
    id: workspacePage
    objectName: "imagingWorkspace"
    property var appWindow
    property alias stlViewport: stlHost
    property int expandedView: -1
    readonly property var selectedPanel: appWindow.selectedPlane === "coronal" ? coronalPanel
        : (appWindow.selectedPlane === "sagittal" ? sagittalPanel : axialPanel)
    readonly property int selectedCount: appWindow.selectedPlane === "coronal" ? ctImporter.coronalCount
        : (appWindow.selectedPlane === "sagittal" ? ctImporter.sagittalCount : ctImporter.sliceCount)

    function toggleView(index) { expandedView = expandedView === index ? -1 : index }

    RowLayout {
        anchors.fill: parent
        spacing: 8
        Rectangle {
            Layout.preferredWidth: 256
            Layout.fillHeight: true
            color: Theme.panel; radius: Theme.panelRadius
            ColumnLayout {
                anchors.fill: parent
                anchors.margins: 16
                spacing: 14
                Text { text: "阅片"; color: Theme.text; font.pixelSize: Theme.fontTitle; font.weight: Font.DemiBold }

                // Series
                ColumnLayout {
                    Layout.fillWidth: true
                    spacing: 8
                    AppButton {
                        id: importCtButton
                        Layout.fillWidth: true
                        text: ctImporter.busy ? "正在导入" : "导入 CT"
                        iconName: "folder-open"
                        primary: ctImporter.sliceCount <= 0
                        enabled: !ctImporter.busy
                        onClicked: ctImporter.chooseDirectory()
                    }
                    Text {
                        Layout.fillWidth: true
                        text: ctImporter.metadataText.length > 0 ? ctImporter.metadataText : "尚未选择序列"
                        color: Theme.faint
                        font.pixelSize: Theme.fontCaption
                        wrapMode: Text.WordWrap
                        maximumLineCount: workspacePage.height < 700 ? 2 : 4
                        elide: Text.ElideRight
                    }
                }

                // Current slice + paging + zoom, one card
                Rectangle {
                    Layout.fillWidth: true
                    implicitHeight: sliceCard.implicitHeight + 24
                    radius: Theme.panelRadius
                    color: Theme.panelRaised
                    ColumnLayout {
                        id: sliceCard
                        anchors.left: parent.left; anchors.right: parent.right; anchors.top: parent.top
                        anchors.margins: 12
                        spacing: 10
                        RowLayout {
                            Layout.fillWidth: true
                            Text {
                                text: appWindow.selectedPlane === "axial" ? "轴位"
                                    : (appWindow.selectedPlane === "coronal" ? "冠状位" : "矢状位")
                                color: Theme.text; font.pixelSize: Theme.fontLabel; font.weight: Font.DemiBold
                                Layout.fillWidth: true
                            }
                            Text {
                                text: workspacePage.selectedCount > 0 ? (workspacePage.selectedPanel.currentIndex + 1) + " / " + workspacePage.selectedCount : "—"
                                color: Theme.accent; font.pixelSize: Theme.fontLabel; font.weight: Font.DemiBold
                            }
                        }
                        RowLayout {
                            Layout.fillWidth: true
                            spacing: 4
                            ToolButton {
                                id: previousSliceButton
                                iconName: "arrow-left"
                                tip: "上一张（↑）"
                                enabled: workspacePage.selectedCount > 0 && workspacePage.selectedPanel.currentIndex > 0
                                onClicked: appWindow.previousSelectedPlane()
                            }
                            ToolButton {
                                id: nextSliceButton
                                iconName: "arrow-right"
                                tip: "下一张（↓）"
                                enabled: workspacePage.selectedCount > 0 && workspacePage.selectedPanel.currentIndex < workspacePage.selectedCount - 1
                                onClicked: appWindow.nextSelectedPlane()
                            }
                            Item { Layout.fillWidth: true }
                            ToolButton { iconName: "zoom-out"; tip: "缩小"; onClicked: workspacePage.selectedPanel.zoom = Math.max(0.5, workspacePage.selectedPanel.zoom - 0.1) }
                            Text { text: Math.round(workspacePage.selectedPanel.zoom * 100) + "%"; color: Theme.muted; font.pixelSize: Theme.fontCaption; Layout.preferredWidth: 38; horizontalAlignment: Text.AlignHCenter }
                            ToolButton { iconName: "zoom-in"; tip: "放大"; onClicked: workspacePage.selectedPanel.zoom = Math.min(4, workspacePage.selectedPanel.zoom + 0.1) }
                        }
                        RowLayout {
                            Layout.fillWidth: true
                            spacing: 4
                            ToolButton {
                                iconName: workspacePage.expandedView < 0 ? "expand" : "grid-2x2"
                                tip: workspacePage.expandedView < 0 ? "放大选中切面" : "恢复四视图布局"
                                onClicked: workspacePage.expandedView = workspacePage.expandedView < 0
                                    ? (appWindow.selectedPlane === "axial" ? 0 : (appWindow.selectedPlane === "coronal" ? 1 : 2)) : -1
                            }
                            Text { text: workspacePage.expandedView < 0 ? "四视图" : "单切面聚焦"; color: Theme.muted; font.pixelSize: Theme.fontCaption; Layout.fillWidth: true }
                            ToolButton {
                                iconName: "scan-line"; tip: "重置缩放和位置"
                                onClicked: { workspacePage.selectedPanel.zoom = 1; workspacePage.selectedPanel.panX = 0; workspacePage.selectedPanel.panY = 0 }
                            }
                        }
                    }
                }

                // 3D model
                ColumnLayout {
                    Layout.fillWidth: true
                    spacing: 8
                    AppButton {
                        Layout.fillWidth: true
                        text: stlViewer.busy ? "读取中" : "加载 STL"
                        iconName: "box"
                        enabled: !stlViewer.busy
                        onClicked: stlViewer.chooseDirectory()
                    }
                    Text {
                        text: stlViewer.rows.length > 0 ? stlViewer.rows.length + " 个结构 · " + stlViewer.triangleCountText + " 面" : "尚未选择模型"
                        color: Theme.faint
                        font.pixelSize: Theme.fontCaption
                        Layout.fillWidth: true
                        elide: Text.ElideRight
                    }
                }
                Item { Layout.fillHeight: true }
                Text {
                    text: ctImporter.status.length > 0 ? ctImporter.status : "就绪"
                    color: ctImporter.status.indexOf("失败") >= 0 ? Theme.error : Theme.faint
                    font.pixelSize: Theme.fontCaption
                    wrapMode: Text.WordWrap
                    Layout.fillWidth: true
                    maximumLineCount: 2
                    elide: Text.ElideRight
                }
            }
        }
        ColumnLayout {
            Layout.fillWidth: true
            Layout.fillHeight: true
            spacing: 0
            GridLayout {
                id: imageViewer
                Layout.fillWidth: true
                Layout.fillHeight: true
                Layout.margins: 0
                columns: 2
                rows: workspacePage.expandedView < 0 ? 2 : 3
                columnSpacing: 6
                rowSpacing: 6
                function rowFor(index) {
                    if (workspacePage.expandedView < 0) return Math.floor(index / 2)
                    return index === workspacePage.expandedView ? 0 : (index > workspacePage.expandedView ? index - 1 : index)
                }
                function columnFor(index) { return workspacePage.expandedView < 0 ? index % 2 : (index === workspacePage.expandedView ? 0 : 1) }
                function spanFor(index) { return workspacePage.expandedView === index ? 3 : 1 }
                function widthFor(index) { return workspacePage.expandedView < 0 ? 1 : (workspacePage.expandedView === index ? 3 : 1) }
                SlicePanel {
                    id: axialPanel
                    objectName: "imagingAxialPanel"
                    appWindow: workspacePage.appWindow
                    pageActive: appWindow.appPage === 1 && session.authenticated
                    Layout.fillWidth: true; Layout.fillHeight: true; Layout.minimumWidth: 0; Layout.minimumHeight: 0
                    Layout.row: imageViewer.rowFor(0); Layout.column: imageViewer.columnFor(0); Layout.rowSpan: imageViewer.spanFor(0)
                    Layout.preferredWidth: imageViewer.widthFor(0); Layout.preferredHeight: 1
                    title: "轴位 / Axial"; sourceUrl: ctImporter.previewPath; axial: true; plane: "axial"
                    expandable: true; onExpandRequested: workspacePage.toggleView(0)
                }
                SlicePanel {
                    id: coronalPanel
                    objectName: "imagingCoronalPanel"
                    appWindow: workspacePage.appWindow
                    pageActive: appWindow.appPage === 1 && session.authenticated
                    Layout.fillWidth: true; Layout.fillHeight: true; Layout.minimumWidth: 0; Layout.minimumHeight: 0
                    Layout.row: imageViewer.rowFor(1); Layout.column: imageViewer.columnFor(1); Layout.rowSpan: imageViewer.spanFor(1)
                    Layout.preferredWidth: imageViewer.widthFor(1); Layout.preferredHeight: 1
                    title: "冠状位 / Coronal"; sourceUrl: ctImporter.coronalPath; plane: "coronal"
                    expandable: true; onExpandRequested: workspacePage.toggleView(1)
                }
                SlicePanel {
                    id: sagittalPanel
                    objectName: "imagingSagittalPanel"
                    appWindow: workspacePage.appWindow
                    pageActive: appWindow.appPage === 1 && session.authenticated
                    Layout.fillWidth: true; Layout.fillHeight: true; Layout.minimumWidth: 0; Layout.minimumHeight: 0
                    Layout.row: imageViewer.rowFor(2); Layout.column: imageViewer.columnFor(2); Layout.rowSpan: imageViewer.spanFor(2)
                    Layout.preferredWidth: imageViewer.widthFor(2); Layout.preferredHeight: 1
                    title: "矢状位 / Sagittal"; sourceUrl: ctImporter.sagittalPath; plane: "sagittal"
                    expandable: true; onExpandRequested: workspacePage.toggleView(2)
                }
                Item {
                    id: stlHost
                    objectName: "imagingStlViewport"
                    Layout.fillWidth: true; Layout.fillHeight: true; Layout.minimumWidth: 0; Layout.minimumHeight: 0
                    Layout.row: imageViewer.rowFor(3); Layout.column: imageViewer.columnFor(3)
                    Layout.preferredWidth: 1; Layout.preferredHeight: 1
                }
            }
        }
    }
}
