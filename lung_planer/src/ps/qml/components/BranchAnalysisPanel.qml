pragma ComponentBehavior: Bound
import QtQuick
import QtQuick.Controls
import QtQuick.Layouts
import ".."

ColumnLayout {
    id: panel
    property var analysis
    spacing: 8
    visible: analysis !== null
    RowLayout {
        Layout.fillWidth: true
        Text { text: "精度间距"; color: Theme.muted; font.pixelSize: Theme.fontCaption }
        InfoTip { text: "拓扑级数：根部分支为一级，每次分叉递增。" }
        AppComboBox {
            id: spacingSelector
            Layout.fillWidth: true
            model: ["0.4 mm · 精细", "0.8 mm · 标准", "1.2 mm · 快速"]
            currentIndex: 1
            enabled: panel.analysis && !panel.analysis.busy
            onActivated: panel.analysis.setSpacing([0.4, 0.8, 1.2][currentIndex])
        }
    }
    AppButton {
        objectName: "extractCenterlinesButton"
        Layout.fillWidth: true
        text: panel.analysis && panel.analysis.busy ? "正在提取中心线…" : "提取 / 读取中心线缓存"
        iconName: "scan-line"
        enabled: panel.analysis && !panel.analysis.busy && panel.analysis.sourceCount > 0 && !stlViewer.busy
        onClicked: panel.analysis.extract()
    }
    Text {
        objectName: "centerlineStatus"
        visible: text.length > 0
        text:panel.analysis ? panel.analysis.status : ""
        color: Theme.muted; font.pixelSize: Theme.fontCaption
        wrapMode: Text.WrapAnywhere; Layout.fillWidth: true
    }
    BusyIndicator { running: panel.analysis && panel.analysis.busy; visible: running; Layout.preferredHeight: 24; Layout.preferredWidth: 24 }
    ColumnLayout {
        visible: panel.analysis && panel.analysis.ready
        Layout.fillWidth: true; spacing: 6
        Text {
            visible: false
            text: panel.analysis ? panel.analysis.summary : ""
            color: Theme.faint; font.pixelSize: Theme.fontCaption
            wrapMode: Text.Wrap; Layout.fillWidth: true
        }
        AppCheckBox {
            text: "显示中心线与高亮"; Layout.fillWidth: true
            checked: panel.analysis && panel.analysis.visible
            onToggled: panel.analysis.setVisible(checked)
        }
        AppCheckBox {
            text: "淡化原始表面，查看内部中心线"; Layout.fillWidth: true
            checked: panel.analysis && panel.analysis.xray
            onToggled: panel.analysis.setXray(checked)
        }
        CollapsibleSection {
            Layout.fillWidth: true; title: "校正根部"; expanded: false
            AppComboBox {
                Layout.fillWidth: true
                model: panel.analysis ? panel.analysis.sourceLabels : []
                currentIndex: panel.analysis ? panel.analysis.selectedSource : 0
                onActivated: panel.analysis.selectSource(currentIndex)
            }
            AppComboBox {
                id: rootSelector
                objectName: "centerlineRootSelector"
                Layout.fillWidth: true
                property var endpoints: panel.analysis ? panel.analysis.roots : []
                model: endpoints.map(function(r) { return r.label })
                onActivated: if (currentIndex >= 0) panel.analysis.previewRoot(endpoints[currentIndex].id)
            }
            Text { text: "选端点后，三维白球预览其位置。"; color: Theme.faint; font.pixelSize: Theme.fontCaption; wrapMode: Text.Wrap; Layout.fillWidth: true }
            AppButton {
                text: "将所选端点设为该树根部"; Layout.fillWidth: true
                enabled: rootSelector.currentIndex >= 0 && !panel.analysis.busy
                onClicked: panel.analysis.setRoot(rootSelector.endpoints[rootSelector.currentIndex].id)
            }
        }
        RowLayout {
            Layout.fillWidth: true; spacing: 10
            Repeater {
                model: [{c: "#ff6472", t: "动脉"}, {c: "#55baff", t: "静脉"}, {c: "#7de5ab", t: "支气管"}, {c: "#ffc857", t: "邻近"}, {c: "#ff343d", t: "切除"}]
                RowLayout {
                    id: legendItem
                    required property var modelData
                    spacing: 4
                    Rectangle { Layout.preferredWidth: 8; Layout.preferredHeight: 8; radius: 4; color: legendItem.modelData.c }
                    Text { text: legendItem.modelData.t; color: Theme.muted; font.pixelSize: Theme.fontCaption }
                }
            }
            Item { Layout.fillWidth: true }
            InfoTip { text: "切除区内亮红 · 边界点红球\n管壁邻近黄 · 选中浅金" }
        }
        AppCheckBox {
            text: "仅列出受影响 / 邻近分支"; Layout.fillWidth: true
            checked: panel.analysis && panel.analysis.onlyAffected
            onToggled: panel.analysis.setOnlyAffected(checked)
        }
        AppComboBox {
            objectName: "branchAnalysisScope"
            Layout.fillWidth: true
            visible: panel.analysis && panel.analysis.unionAvailable
            enabled: !planner.busy && !panel.analysis.busy
            model: ["当前病灶的切除分支", "全部病灶联合切除 · 分支与长度去重"]
            currentIndex: panel.analysis && panel.analysis.analysisScope === "union" ? 1 : 0
            onActivated: panel.analysis.setAnalysisScope(currentIndex === 1 ? "union" : "current")
        }
        Text {
            objectName: "branchAnalysisVerdict"
            visible: text.length > 0
            text: panel.analysis ? [panel.analysis.analysisStatus,
                (panel.analysis.planCurrent ? "实际进入 " + panel.analysis.enteredCount
                    + " 条 · 管壁邻近 " + panel.analysis.nearCount
                    + " 条 · 仅下游连通受影响 " + panel.analysis.downstreamCount + " 条" : "")
                ].filter(function(v) { return v.length > 0 }).join("\n") : ""
            color: Theme.warning; font.pixelSize: Theme.fontCaption
            wrapMode: Text.Wrap; Layout.fillWidth: true
        }
        ScrollView {
            id: branchScroll
            objectName: "centerlineBranchList"
            Layout.fillWidth: true; Layout.preferredHeight: 260
            contentWidth: availableWidth; clip: true
            ListView {
                id: branchList
                objectName: "centerlineBranchListView"
                implicitWidth: branchScroll.availableWidth
                spacing: 5
                model: panel.analysis ? panel.analysis.branchModel : null
                reuseItems: true
                cacheBuffer: 128
                currentIndex: panel.analysis ? panel.analysis.selectedRow : -1
                onCurrentIndexChanged: if (currentIndex >= 0) positionViewAtIndex(currentIndex, ListView.Contain)
                delegate: Rectangle {
                    id: branchRow
                    required property var branch
                    width: branchList.width
                    implicitHeight: branchText.implicitHeight + 16
                    radius: Theme.radius
                    color: panel.analysis.selectedBranch === branch.key ? Theme.accentDim : (rowHover.containsMouse ? Theme.panelRaised : Theme.input)
                    border.color: panel.analysis.selectedBranch === branch.key ? Theme.accent : Theme.strokeSoft
                    Behavior on color { ColorAnimation { duration: Theme.durFast } }
                    Behavior on border.color { ColorAnimation { duration: Theme.durFast } }
                    Column {
                        id: branchText
                        x: 8; y: 8; width: parent.width - 16; spacing: 3
                        // The branch colours are tuned for the black 3D view; on the
                        // light panel they are shown as a dot plus a darkened label.
                        Row {
                            width: parent.width; spacing: 6
                            Rectangle { width: 9; height: 9; radius: 4.5; color: branchRow.branch.color; anchors.verticalCenter: parent.verticalCenter }
                            Text { width: parent.width - 15; text: branchRow.branch.label; color: Qt.darker(branchRow.branch.color, 2.2); font.pixelSize: Theme.fontLabel; wrapMode: Text.Wrap }
                        }
                        Text { width: parent.width; text: branchRow.branch.statusText; color: branchRow.branch.status === "partial" || branchRow.branch.status === "full" ? Theme.error : Theme.warning; font.pixelSize: Theme.fontCaption; wrapMode: Text.Wrap }
                        Text { width: parent.width; text: branchRow.branch.detail; color: Theme.muted; font.pixelSize: Theme.fontCaption; wrapMode: Text.Wrap }
                    }
                    MouseArea { id: rowHover; anchors.fill: parent; hoverEnabled: true; onClicked: panel.analysis.selectBranch(branchRow.branch.key) }
                }
            }
        }
        RowLayout {
            Layout.fillWidth: true; spacing: 6
            InfoTip { text: "中心线与管径为体素近似，细于间距的分支可能遗漏。黄色仅为管壁邻近筛查。"; warn: true }
            Text { text: "体素近似，仅供筛查"; color: Theme.faint; font.pixelSize: Theme.fontCaption }
        }
    }
}
