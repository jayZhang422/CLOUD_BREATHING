pragma ComponentBehavior: Bound
import QtQuick
import QtQuick.Controls
import QtQuick.Layouts
import ".."
import "../components"

Item {
    id: page
    objectName: "planningPage"
    property var appWindow
    property alias stlViewport: planningHost
    property bool interiorPathOnly: false
    readonly property bool wide: width >= 1500
    function resetView() { appWindow.resetStlCamera() }

    // Workflow accordion. The step follows progress (load -> confirm lesion ->
    // tune) until the user opens a section themselves.
    //   0 model, 1 lesion & margin, 2 plans, 3 fine tuning, 4 engineering
    property int userStep: -2
    readonly property int autoStep: !planner.ready ? 0 : (planner.hasPlan ? 3 : 1)
    readonly property int openStep: userStep !== -2 ? userStep : autoStep
    readonly property int progressKey: (planner.hasPlan ? 2 : 0) + (planner.ready ? 1 : 0)
    onProgressKeyChanged: userStep = -2
    function toggleStep(n) { userStep = openStep === n ? -1 : n }

    // Verdicts for the two key constraints (empty until a current plan exists)
    readonly property bool resultReady: planner.hasPlan && planner.geometryCurrent && !planner.metricsPending
    readonly property string coverageVerdict: !resultReady || planner.result.coverage_percent === undefined ? ""
        : (Number(planner.result.coverage_percent) >= 99.999 ? "ok" : "bad")
    readonly property string clearanceVerdict: !resultReady || planner.result.tumor_margin_mm === undefined ? ""
        : (Number(planner.result.tumor_margin_mm) >= Number(planner.parameters.minClearance) ? "ok" : "bad")
    readonly property string baseVerdict: !resultReady || planner.result.min_base_clearance_mm === undefined ? ""
        : (planner.result.base_outside_valid ? "ok" : "bad")

    Rectangle { anchors.fill: parent; color: Theme.background }

    RowLayout {
        anchors.fill: parent
        spacing: 8

        // ───────── Left: workflow ─────────
        Rectangle {
            Layout.preferredWidth: page.wide ? 336 : 300
            Layout.fillHeight: true
            color: Theme.panel; radius: Theme.panelRadius
            ColumnLayout {
                anchors.fill: parent
                spacing: 0
                RowLayout {
                    Layout.fillWidth: true
                    Layout.leftMargin: 18; Layout.rightMargin: 16; Layout.topMargin: 14; Layout.bottomMargin: 8
                    Text { text: "手术路径规划"; color: Theme.text; font.pixelSize: Theme.fontTitle; font.weight: Font.DemiBold; Layout.fillWidth: true }
                    StatusChip {
                        text: planner.busy ? "计算中" : (planner.hasPlan ? "已有方案" : "待规划")
                        tone: planner.busy ? "warning" : (planner.hasPlan ? "success" : "neutral")
                        pulse: planner.busy
                    }
                }
                ScrollView {
                    id: parameterScroll
                    Layout.fillWidth: true
                    Layout.fillHeight: true
                    Layout.leftMargin: 12; Layout.rightMargin: 12
                    contentWidth: availableWidth
                    clip: true
                    ColumnLayout {
                        width: parameterScroll.availableWidth
                        spacing: 0

                        CollapsibleSection {
                            objectName: "planningModelSection"
                            Layout.fillWidth: true
                            title: "模型"; step: "1"
                            managed: true
                            expanded: page.openStep === 0
                            onToggleRequested: page.toggleStep(0)
                            summary: planner.tumorFile
                            AppButton {
                                objectName: "planningLoadStl"
                                text: stlViewer.busy ? "正在读取 STL..." : "加载 STL 文件夹"
                                iconName: "folder-open"
                                Layout.fillWidth: true
                                enabled: !stlViewer.busy && !planner.busy
                                onClicked: stlViewer.chooseDirectory()
                            }
                            Text {
                                text: planner.directory || "未加载模型"
                                color: Theme.faint
                                font.pixelSize: Theme.fontCaption
                                wrapMode: Text.WrapAnywhere
                                maximumLineCount: 2
                                elide: Text.ElideMiddle
                                Layout.fillWidth: true
                            }
                            RowLayout {
                                Layout.fillWidth: true
                                Text { text: "病灶 STL"; color: Theme.muted; font.pixelSize: Theme.fontCaption; Layout.fillWidth: true }
                                InfoTip { text: "选择参与规划的病灶连通块" }
                            }
                            AppComboBox {
                                id: tumorSelector
                                objectName: "planningTumorSelector"
                                Layout.fillWidth: true
                                model: planner.files
                                currentIndex: planner.files.indexOf(planner.tumorFile)
                                enabled: planner.files.length > 0 && !planner.busy
                                onActivated: planner.setTumorFile(currentText)
                            }
                            Text {
                                objectName: "planningLesionCatalogStatus"
                                text: planner.lesionCatalogStatus
                                color: Theme.muted; font.pixelSize: Theme.fontCaption
                                wrapMode: Text.Wrap; Layout.fillWidth: true
                            }
                            ScrollView {
                                id: lesionScroll
                                Layout.fillWidth: true; Layout.preferredHeight: 168
                                contentWidth: availableWidth; clip: true
                                ListView {
                                    id: lesionList
                                    objectName: "planningLesionComponentList"
                                    implicitWidth: lesionScroll.availableWidth
                                    model: planner.lesionComponents
                                    reuseItems: true; spacing: 4
                                    delegate: Rectangle {
                                        id: lesionRow
                                        required property var modelData
                                        width: lesionList.width; height: 52; radius: Theme.radius
                                        color: planner.previewComponentId === modelData.id ? Theme.accentDim : (lesionHover.hovered ? Theme.panelRaised : Theme.input)
                                        border.width: 1
                                        border.color: planner.previewComponentId === modelData.id ? Theme.accent : Theme.strokeSoft
                                        Behavior on color { ColorAnimation { duration: Theme.durFast } }
                                        Behavior on border.color { ColorAnimation { duration: Theme.durFast } }
                                        HoverHandler { id: lesionHover }
                                        RowLayout {
                                            anchors.fill: parent; anchors.leftMargin: 10; anchors.rightMargin: 8
                                            AppCheckBox {
                                                id: lesionCheck
                                                Layout.fillWidth: true
                                                text: lesionRow.modelData.label
                                                checked: lesionRow.modelData.selected
                                                enabled: !planner.busy && !planner.lesionCatalogBusy
                                                onToggled: planner.setLesionComponentSelected(lesionRow.modelData.id, checked)
                                                contentItem: Text {
                                                    text: lesionCheck.text
                                                    leftPadding: lesionCheck.indicator.width + lesionCheck.spacing
                                                    color: lesionCheck.enabled ? Theme.text : Theme.faint
                                                    font.pixelSize: Theme.fontCaption
                                                    wrapMode: Text.Wrap; maximumLineCount: 2; elide: Text.ElideRight
                                                    verticalAlignment: Text.AlignVCenter
                                                }
                                            }
                                            AppButton {
                                                text: planner.previewComponentId === lesionRow.modelData.id ? "取消" : "定位"
                                                Layout.preferredWidth: 56
                                                implicitHeight: 30
                                                onClicked: planner.previewLesionComponent(lesionRow.modelData.id)
                                            }
                                        }
                                    }
                                }
                            }
                            Text { text: "参与规划的肺表面"; color: Theme.muted; font.pixelSize: Theme.fontCaption }
                            ScrollView {
                                id: lungScroll
                                Layout.fillWidth: true
                                Layout.preferredHeight: 110
                                contentWidth: availableWidth
                                clip: true
                                Column {
                                    width: lungScroll.availableWidth
                                    Repeater {
                                        model: planner.files.filter(function(name) { return name !== planner.tumorFile })
                                        AppCheckBox {
                                            id: lungCheck
                                            required property string modelData
                                            width: parent.width
                                            text: modelData.replace(/\.stl$/i, "")
                                            checked: planner.lungFiles.indexOf(modelData) >= 0
                                            onToggled: planner.setLungFile(modelData, checked)
                                            contentItem: Text { text: lungCheck.text; leftPadding: 26; color: Theme.text; elide: Text.ElideMiddle; verticalAlignment: Text.AlignVCenter; font.pixelSize: Theme.fontLabel }
                                        }
                                    }
                                }
                            }
                        }

                        CollapsibleSection {
                            Layout.fillWidth: true
                            title: "病灶与切缘"; step: "2"
                            managed: true
                            expanded: page.openStep === 1
                            onToggleRequested: page.toggleStep(1)
                            summary: planner.ctReady ? "已关联 CT 标尺" : "未关联 CT"
                            RowLayout {
                                Layout.fillWidth: true; spacing: 6
                                Text {
                                    Layout.fillWidth: true; elide: Text.ElideRight
                                    color: planner.ctReady ? Theme.success : Theme.warning
                                    font.pixelSize: Theme.fontCaption
                                    text: planner.ctReady
                                        ? "已关联 CT 标尺 · 像素 " + Number(planner.ctCalibration.pixel_spacing_mm[0]).toFixed(3) + " mm · 层厚 " + Number(planner.ctCalibration.slice_spacing_mm || planner.ctCalibration.slice_thickness_mm).toFixed(3) + " mm"
                                        : "请先在二维阅片中导入并加载 CT"
                                }
                                InfoTip {
                                    warn: !planner.ctReady
                                    text: planner.ctReady
                                        ? "已关联 CT 物理标尺：STL 各轴按 PixelSpacing " + Number(planner.ctCalibration.pixel_spacing_mm[0]).toFixed(3) + " mm 换算；层厚 " + Number(planner.ctCalibration.slice_spacing_mm || planner.ctCalibration.slice_thickness_mm).toFixed(3) + " mm"
                                        : "请先在二维阅片中导入并加载 CT，量化分析将使用 CT 标尺"
                                }
                            }
                            RowLayout {
                                Layout.fillWidth: true
                                Text { text: "病灶类型"; color: Theme.muted; font.pixelSize: Theme.fontCaption; Layout.fillWidth: true }
                                InfoTip { text: "病灶类型由医生依据 CT 确认" }
                            }
                            AppComboBox {
                                objectName: "planningLesionType"
                                Layout.fillWidth: true
                                enabled: planner.ready && !planner.busy
                                model: ["实性", "囊性", "混合"]
                                // -1 until the doctor chooses: the type is never assumed.
                                currentIndex: ["solid", "cystic", "mixed"].indexOf(planner.parameters.lesionType)
                                displayText: currentIndex < 0 ? "请选择" : currentText
                                onActivated: planner.setLesionType(["solid", "cystic", "mixed"][currentIndex])
                            }
                            RowLayout {
                                Layout.fillWidth: true
                                Text { text: "病灶最大直径（STL 三维，自动）"; color: Theme.muted; font.pixelSize: Theme.fontCaption; Layout.fillWidth: true }
                                LineField {
                                    id: diameterInput
                                    objectName: "planningLesionDiameter"
                                    Layout.preferredWidth: 96
                                    implicitHeight: 32
                                    enabled: planner.ready && !planner.busy
                                    text: Number(planner.parameters.lesionDiameter) > 0 ? Number(planner.parameters.lesionDiameter).toFixed(1) : ""
                                    placeholderText: "需 CT 标尺"
                                    inputMethodHints: Qt.ImhFormattedNumbersOnly
                                    validator: DoubleValidator { bottom: 0; top: 200; decimals: 1; locale: "C"; notation: DoubleValidator.StandardNotation }
                                    onEditingFinished: {
                                        if (text === "" || acceptableInput) planner.setParameter("lesionDiameter", text === "" ? 0 : Number(text))
                                        text = Number(planner.parameters.lesionDiameter) > 0 ? Number(planner.parameters.lesionDiameter).toFixed(1) : ""
                                    }
                                    Connections {
                                        target: planner
                                        function onChanged() {
                                            if (!diameterInput.activeFocus) diameterInput.text = Number(planner.parameters.lesionDiameter) > 0 ? Number(planner.parameters.lesionDiameter).toFixed(1) : ""
                                        }
                                    }
                                }
                                Text { text: "mm"; color: Theme.muted; font.pixelSize: Theme.fontCaption }
                            }
                            Text {
                                objectName: "planningResectionRule"
                                Layout.fillWidth: true; wrapMode: Text.Wrap
                                color: Number(planner.parameters.lesionDiameter) >= planner.lobectomyThresholdMm ? Theme.warning : Theme.muted
                                font.pixelSize: Theme.fontCaption
                                text: Number(planner.parameters.lesionDiameter) <= 0
                                    ? "自动规划按每个病灶的最大直径选择：≥ " + Number(planner.lobectomyThresholdMm).toFixed(0) + " mm 肺叶切除，其余楔形切除。"
                                    : Number(planner.parameters.lesionDiameter) >= planner.lobectomyThresholdMm
                                      ? "≥ " + Number(planner.lobectomyThresholdMm).toFixed(0) + " mm：自动规划将切除病灶所在肺叶。"
                                      : "< " + Number(planner.lobectomyThresholdMm).toFixed(0) + " mm：自动规划做楔形切除。"
                            }
                            RowLayout {
                                Layout.fillWidth: true
                                Text { text: "切缘规则"; color: Theme.muted; font.pixelSize: Theme.fontCaption; Layout.fillWidth: true }
                                InfoTip { warn: true; text: "选择规则后切缘目标自动按参考填入，仍可手动调整。最大直径由所选的单个病灶 STL 按 CT 标尺算出，可改写；多个病灶时需逐个手动填写。参考规则不会确认适应证，病灶类型须由医生确认。" }
                            }
                            AppComboBox {
                                objectName: "planningMarginRule"
                                Layout.fillWidth: true
                                enabled: planner.ready && !planner.busy
                                model: ["手动（医生确定）", "国内共识 2023（≤2 cm）", "NSCLC 切缘参考（2025 综述）"]
                                currentIndex: Math.max(0, ["manual", "consensus_2023", "nccn_reference"].indexOf(planner.parameters.marginRule))
                                onActivated: planner.setMarginRule(["manual", "consensus_2023", "nccn_reference"][currentIndex])
                            }
                            Text {
                                objectName: "planningMarginReference"
                                Layout.fillWidth: true; wrapMode: Text.Wrap
                                color: Theme.muted; font.pixelSize: Theme.fontCaption
                                text: planner.marginReference.description
                            }
                            AppButton {
                                objectName: "applyMarginReferenceButton"
                                Layout.fillWidth: true
                                text: planner.marginReference.available ? "填入参考切缘 " + Number(planner.marginReference.suggestedMm).toFixed(1) + " mm" : "填入参考切缘"
                                enabled: planner.ready && !planner.busy && planner.marginReference.available
                                onClicked: planner.applyMarginReference()
                            }
                        }

                        CollapsibleSection {
                            Layout.fillWidth: true
                            title: "方案"; step: "3"
                            managed: true
                            expanded: page.openStep === 2
                            onToggleRequested: page.toggleStep(2)
                            summary: planner.candidates.length > 0 ? planner.candidates.length + " 个候选" : ""
                            RowLayout {
                                Layout.fillWidth: true
                                Text { text: "规划形状"; color: Theme.muted; font.pixelSize: Theme.fontCaption }
                                Text {
                                    objectName: "planningModelSelector"
                                    text: "双平面楔形"
                                    color: Theme.text; font.pixelSize: Theme.fontLabel; font.weight: Font.DemiBold
                                    Layout.fillWidth: true
                                }
                                InfoTip {
                                    objectName: "planningModelDescription"
                                    text: "两张切面与真实肺表面形成切除区域，无人工底面或单个深部尖点。调整姿态、展开角后重算；血管、支气管及器械条件仍需确认。"
                                }
                            }
                            AppComboBox {
                                objectName: "planningLesionResults"
                                Layout.fillWidth: true
                                visible: planner.lesionPlans.length > 1
                                enabled: !planner.busy && !planner.metricsPending
                                model: planner.lesionPlans; textRole: "label"
                                currentIndex: planner.selectedLesion
                                onActivated: planner.selectLesion(currentIndex)
                            }
                            AppComboBox {
                                objectName: "planningCandidates"
                                Layout.fillWidth: true
                                visible: planner.candidates.length > 0
                                enabled: !planner.busy && !planner.metricsPending
                                model: planner.candidates; textRole: "label"
                                currentIndex: planner.selectedCandidate
                                onActivated: planner.selectCandidate(currentIndex)
                            }
                            RowLayout {
                                Layout.fillWidth: true; spacing: 8
                                AppButton {
                                    objectName: "recomputePlanButton"
                                    Layout.fillWidth: true
                                    text: "按当前参数重算"
                                    iconName: "refresh-cw"
                                    enabled: planner.ready && !planner.busy && !planner.lobectomyOnly
                                    onClicked: planner.recompute()
                                }
                                AppButton {
                                    objectName: "loadSavedPlanButton"
                                    Layout.fillWidth: true
                                    text: "加载已保存"
                                    iconName: "folder-open"
                                    enabled: planner.ready && !planner.busy
                                    onClicked: planner.loadPlan()
                                }
                            }
                        }

                        CollapsibleSection {
                            Layout.fillWidth: true
                            title: "微调"; step: "4"
                            managed: true
                            expanded: page.openStep === 3
                            onToggleRequested: page.toggleStep(3)
                            Text { text: "姿态"; color: Theme.faint; font.pixelSize: Theme.fontCaption; font.weight: Font.DemiBold }
                            PlanParameter { Layout.fillWidth: true; label: "Yaw"; parameter: "yaw"; minimum: -180; maximum: 180; suffix: "°" }
                            PlanParameter { Layout.fillWidth: true; label: "Pitch"; parameter: "pitch"; minimum: -89; maximum: 89; suffix: "°" }
                            PlanParameter { Layout.fillWidth: true; label: "切面旋转"; parameter: "rotation"; minimum: 0; maximum: 360; suffix: "°" }
                            PlanParameter { Layout.fillWidth: true; label: "展开角（重设各切面）"; parameter: "wedgeAngle"; minimum: 20; maximum: 160; suffix: "°" }
                            RowLayout {
                                Layout.fillWidth: true; Layout.topMargin: 4
                                Text { text: "约束"; color: Theme.faint; font.pixelSize: Theme.fontCaption; font.weight: Font.DemiBold; Layout.fillWidth: true }
                                InfoTip { text: "完整评价实际肺内切面到病灶网格的距离。双平面楔形没有人工底面，底面间隙不适用；器械尺寸及通道需医生确认。" }
                            }
                            PlanParameter { Layout.fillWidth: true; label: "肿瘤切缘目标"; parameter: "minClearance"; minimum: 0.1; maximum: 80; step: 0.1; decimals: 1; suffix: " mm"; editable: true }
                        }

                        CollapsibleSection {
                            Layout.fillWidth: true
                            title: "工程选项"
                            managed: true
                            expanded: page.openStep === 4
                            onToggleRequested: page.toggleStep(4)
                            summary: planner.executionBackend === "pl" ? "PL 加速" : "纯 PS"
                            RowLayout {
                                Layout.fillWidth: true
                                Text { text: "计算后端"; color: Theme.muted; font.pixelSize: Theme.fontCaption; Layout.fillWidth: true }
                                InfoTip {
                                    objectName: "planningBackendDescription"
                                    text: planner.executionBackend === "pl"
                                        ? "PL 预筛选候选的覆盖与切缘，并计算候选的切除体积、表面积和切面面积；最终方案由 PS（Manifold float64）完整复核。PL 出错时停止任务，不回退到 CPU。"
                                        : "全部规划由 PS 计算，不访问 FPGA。切换后请重算。"
                                }
                            }
                            AppComboBox {
                                id: backendSelector
                                objectName: "planningBackend"
                                Layout.fillWidth: true
                                enabled: !planner.busy
                                elideMode: Text.ElideRight
                                model: ["PL 加速（严格模式）", "纯 PS（不使用 PL）"]
                                currentIndex: planner.executionBackend === "pl" ? 0 : 1
                                onActivated: planner.setExecutionBackend(currentIndex === 0 ? "pl" : "cpu")
                            }
                        }
                        Item { Layout.preferredHeight: 8 }
                    }
                }
                // Pinned actions: the main verb is always one click away.
                Rectangle {
                    Layout.fillWidth: true
                    implicitHeight: actionColumn.implicitHeight + 24
                    color: Theme.panel
                    Rectangle { anchors.top: parent.top; width: parent.width; height: 1; color: Theme.stroke }
                    ColumnLayout {
                        id: actionColumn
                        anchors.left: parent.left; anchors.right: parent.right; anchors.top: parent.top
                        anchors.margins: 12; spacing: 8
                        RowLayout {
                            Layout.fillWidth: true; spacing: 8
                            AppButton {
                                objectName: "autoPlanButton"
                                Layout.fillWidth: true
                                Layout.preferredHeight: 42
                                text: planner.busy ? "计算中..." : "自动规划"
                                iconName: "scan-line"
                                warm: true
                                enabled: planner.ready && !planner.busy
                                onClicked: planner.autoPlan()
                            }
                            AppButton {
                                objectName: "stopPlanButton"
                                Layout.preferredHeight: 42
                                visible: planner.busy
                                text: planner.stopping ? "正在停止..." : "停止"
                                danger: true
                                enabled: !planner.stopping
                                onClicked: planner.stopCalculation()
                            }
                        }
                        RowLayout {
                            Layout.fillWidth: true; spacing: 8
                            AppButton {
                                objectName: "savePlanButton"
                                Layout.fillWidth: true
                                text: "保存规划"
                                tip: "保存到 STL 文件夹，可在以后加载并重新校验"
                                iconName: "save"
                                enabled: planner.hasPlan && !planner.metricsPending
                                onClicked: planner.savePlan()
                            }
                            AppButton {
                                objectName: "saveAllPlansButton"
                                Layout.fillWidth: true
                                text: "导出全部"
                                tip: "导出全部病灶与联合清单"
                                enabled: planner.hasPlan && !planner.busy && !planner.metricsPending && planner.result.valid
                                onClicked: planner.saveAllPlans()
                            }
                        }
                    }
                }
            }
        }

        // ───────── Centre: 3D viewport ─────────
        ColumnLayout {
            Layout.fillWidth: true
            Layout.fillHeight: true
            spacing: 8
            Rectangle {
                Layout.fillWidth: true
                Layout.preferredHeight: Theme.subToolbarHeight
                color: Theme.panel; radius: Theme.subToolbarHeight / 2
                
                RowLayout {
                    anchors.fill: parent
                    anchors.leftMargin: 16
                    anchors.rightMargin: 12
                    spacing: 14
                    Text { text: "三维规划"; color: Theme.text; font.pixelSize: Theme.fontBody; font.weight: Font.DemiBold }
                    Text {
                        Layout.fillWidth: true
                        elide: Text.ElideRight
                        text: planner.metricsPending ? "预览中 · 完整校验在后台进行"
                            : ""
                        color: planner.metricsPending ? Theme.warning : Theme.faint
                        font.pixelSize: Theme.fontCaption
                        Behavior on color { ColorAnimation { duration: Theme.durBase } }
                    }
                    AppCheckBox {
                        id: interiorCheck
                        objectName: "planningInteriorOnly"
                        text: "仅显示肺内路径"
                        checked: page.interiorPathOnly
                        onToggled: page.interiorPathOnly = checked
                    }
                    AppButton { objectName: "resetPlanningView"; text: "重置视角"; iconName: "rotate-ccw"; onClicked: page.resetView() }
                }
            }
            Item {
                id: planningHost
                objectName: "planningStlViewport"
                Layout.fillWidth: true
                Layout.fillHeight: true
            }
            Rectangle {
                Layout.fillWidth: true
                Layout.preferredHeight: 34
                color: Theme.panel; radius: 17
                
                RowLayout {
                    anchors.fill: parent
                    anchors.leftMargin: 14
                    anchors.rightMargin: 14
                    StatusChip { text: "几何演示，非临床决策"; tone: "warning"; dot: false }
                    Item { Layout.fillWidth: true }
                    Text { text: planner.hasPlan || planner.lobectomyOnly ? "规划已生成" : "尚未生成规划"; color: Theme.faint; font.pixelSize: Theme.fontCaption }
                }
            }
        }

        // ───────── Right: results ─────────
        Rectangle {
            Layout.preferredWidth: page.wide ? 330 : 296
            Layout.fillHeight: true
            color: Theme.panel; radius: Theme.panelRadius
            ScrollView {
                id: resultScroll
                anchors.fill: parent
                anchors.margins: 14
                contentWidth: availableWidth
                clip: true
                ColumnLayout {
                    width: resultScroll.availableWidth
                    spacing: 10
                    RowLayout {
                        Layout.fillWidth: true
                        Text { text: "量化结果"; color: Theme.text; font.pixelSize: Theme.fontTitle; font.weight: Font.DemiBold; Layout.fillWidth: true }
                        BusyIndicator { running: planner.busy; visible: running; Layout.preferredWidth: 22; Layout.preferredHeight: 22 }
                    }

                    // Overall verdict
                    Rectangle {
                        id: verdictCard
                        Layout.fillWidth: true
                        implicitHeight: bannerColumn.implicitHeight + 24
                        radius: Theme.panelRadius
                        readonly property color tone: planner.lobectomyOnly ? Theme.success
                             : !planner.hasPlan ? Theme.faint
                             : (planner.busy || planner.metricsPending ? Theme.warning
                                : (planner.result.valid ? Theme.success : Theme.error))
                        color: planner.lobectomyOnly ? Theme.successDim
                             : !planner.hasPlan ? Theme.panelRaised
                             : (planner.busy || planner.metricsPending ? Theme.warningDim
                                : (planner.result.valid ? Theme.successDim : Theme.errorDim))
                        Behavior on color { ColorAnimation { duration: Theme.durSlow } }
                        Rectangle {
                            width: 3; radius: 1.5
                            anchors.left: parent.left; anchors.top: parent.top; anchors.bottom: parent.bottom
                            anchors.topMargin: 12; anchors.bottomMargin: 12
                            color: verdictCard.tone
                            Behavior on color { ColorAnimation { duration: Theme.durSlow } }
                        }
                        ColumnLayout {
                            id: bannerColumn
                            anchors.fill: parent; anchors.leftMargin: 16; anchors.rightMargin: 12; anchors.topMargin: 12; anchors.bottomMargin: 12
                            spacing: 4
                            Text {
                                text: planner.lobectomyOnly ? (planner.resectionSummary.length > 0 ? planner.resectionSummary : "肺叶切除方案")
                                    : !planner.hasPlan ? "尚未生成方案"
                                    : (planner.busy || planner.metricsPending ? "正在计算指标…"
                                       : (planner.resectionSummary.length > 0
                                          ? planner.resectionSummary + (planner.result.valid ? "" : "（几何约束未通过）")
                                          : (planner.result.valid ? "几何约束通过" : "几何约束未通过")))
                                color: !planner.hasPlan && !planner.lobectomyOnly ? Theme.text : verdictCard.tone
                                font.pixelSize: Theme.fontTitle; font.weight: Font.DemiBold
                                Layout.fillWidth: true
                                Behavior on color { ColorAnimation { duration: Theme.durSlow } }
                            }
                            RowLayout {
                                Layout.fillWidth: true; spacing: 6
                                Text {
                                    objectName: "planningClinicalStatus"
                                    text: "临床条件待确认"
                                    color: Theme.warning
                                    font.pixelSize: Theme.fontLabel; font.weight: Font.Medium
                                }
                                InfoTip { warn: true; text: "适应证、病理切缘、淋巴结、肺功能及器械可行性需胸外科医生确认。" }
                            }
                            Text {
                                objectName: "planningStatus"
                                text: planner.status
                                color: Theme.muted
                                font.pixelSize: Theme.fontCaption
                                wrapMode: Text.Wrap
                                maximumLineCount: 3; elide: Text.ElideRight
                                Layout.fillWidth: true
                            }
                        }
                    }

                    // Lobectomy: lesions >= 15 mm resect their whole lobe. Same figures as the wedge.
                    Repeater {
                        model: planner.resectionPlans
                        delegate: ColumnLayout {
                            id: lobePlan
                            required property var modelData
                            objectName: "planningLobectomy_" + modelData.lobe
                            Layout.fillWidth: true
                            spacing: 10
                            readonly property var lesion: modelData.lesions.length ? modelData.lesions[0] : ({})
                            readonly property real coverage: modelData.lesions.reduce(function(low, m) {
                                return m.coverage_percent === undefined || m.coverage_percent === null ? low : Math.min(low, m.coverage_percent) }, Infinity)
                            readonly property real margin: modelData.lesions.reduce(function(low, m) {
                                return m.tumor_margin_mm === undefined || m.tumor_margin_mm === null ? low : Math.min(low, m.tumor_margin_mm) }, Infinity)
                            Text {
                                text: "肺叶切除 · " + lobePlan.modelData.label
                                color: Theme.text; font.pixelSize: Theme.fontLabel; font.weight: Font.DemiBold; Layout.fillWidth: true
                            }
                            PlanMetric {
                                Layout.fillWidth: true; label: "病灶覆盖率"; metric: "lobe_coverage_percent"; unit: "%"
                                value: isFinite(lobePlan.coverage) ? lobePlan.coverage : NaN
                                verdict: isFinite(lobePlan.coverage) ? (lobePlan.coverage >= 99.999 ? "ok" : "bad") : ""
                                hint: "目标 100%"
                            }
                            PlanMetric {
                                Layout.fillWidth: true; label: "切除体积 / 双肺总体积"; metric: "lobe_ratio_percent"; unit: "%"; decimals: 2
                                value: Number(lobePlan.modelData.ratio_percent)
                            }
                            CollapsibleSection {
                                Layout.fillWidth: true
                                title: "更多指标"
                                expanded: false
                                PlanMetric { Layout.fillWidth: true; compact: true; label: "肺部切除体积（估计）"; metric: "lobe_volume_cm3"; unit: "cm³"; value: Number(lobePlan.modelData.volume_cm3) }
                                PlanMetric { Layout.fillWidth: true; compact: true; label: "双肺模型总体积"; metric: "lobe_total_cm3"; unit: "cm³"; value: Number(lobePlan.modelData.total_volume_cm3) }
                                PlanMetric { Layout.fillWidth: true; compact: true; label: "肺表面交集面积"; metric: "lobe_area_cm2"; unit: "cm²"; value: Number(lobePlan.modelData.surface_area_cm2) }
                            }
                        }
                    }
                    Text {
                        visible: planner.resectionPlans.length > 0 && !planner.lobectomyOnly
                        Layout.fillWidth: true; wrapMode: Text.Wrap
                        color: Theme.muted; font.pixelSize: Theme.fontCaption
                        text: "规则：病灶最大直径 ≥ " + Number(planner.lobectomyThresholdMm).toFixed(0) + " mm 切除所在肺叶，< "
                              + Number(planner.lobectomyThresholdMm).toFixed(0) + " mm 做双平面楔形切除。"
                              + "下方指标为楔形切除病灶。"
                    }

                    // The three numbers that matter
                    PlanMetric { visible: !planner.lobectomyOnly; Layout.fillWidth: true; label: "病灶覆盖率"; metric: "coverage_percent"; unit: "%"; slow: false; verdict: page.coverageVerdict; hint: "目标 100%" }
                    PlanMetric {
                        visible: !planner.lobectomyOnly
                        Layout.fillWidth: true; label: "切割侧面最小切缘（模型）"; metric: "tumor_margin_mm"; unit: "mm"; decimals: 3; slow: false
                        verdict: page.clearanceVerdict
                        hint: "要求 ≥ " + Number(planner.parameters.minClearance).toFixed(1) + " mm"
                    }
                    PlanMetric { visible: !planner.lobectomyOnly; Layout.fillWidth: true; label: "切除体积 / 双肺总体积"; metric: "resection_ratio_percent"; unit: "%"; decimals: 2 }
                    Text {
                        visible: planner.marginReference.available && planner.marginReference.targetMeetsReference === false
                        Layout.fillWidth: true; wrapMode: Text.Wrap
                        color: Theme.warning; font.pixelSize: Theme.fontCaption
                        text: "当前切缘目标低于所选参考规则；请由医生确认调整依据。"
                    }

                    // Everything else folds away
                    CollapsibleSection {
                        visible: !planner.lobectomyOnly
                        Layout.fillWidth: true
                        Layout.topMargin: 4
                        title: "更多指标"
                        expanded: false
                        PlanMetric { Layout.fillWidth: true; compact: true; label: "肺部切除体积（估计）"; metric: "resection_volume_cm3"; unit: "cm³" }
                        PlanMetric { Layout.fillWidth: true; compact: true; label: "双肺模型总体积"; metric: "lung_volume_cm3"; unit: "cm³" }
                        PlanMetric { Layout.fillWidth: true; compact: true; label: "肺表面交集面积"; metric: "surface_area_cm2"; unit: "cm²" }
                    }

                    CollapsibleSection {
                        Layout.fillWidth: true
                        title: "血管 / 支气管分支"
                        visible: typeof centerlines !== "undefined"
                        expanded: false
                        BranchAnalysisPanel {
                            objectName: "branchAnalysisPanel"
                            Layout.fillWidth: true
                            analysis: typeof centerlines !== "undefined" ? centerlines : null
                        }
                    }

                    CollapsibleSection {
                        Layout.fillWidth: true
                        objectName: "planningStructureAppearance"
                        title: "器官外观"
                        summary: stlViewer.rows.length + " 项"
                        expanded: false
                        Repeater {
                            model: stlViewer.rows
                            ColumnLayout {
                                id: structureAppearance
                                required property var modelData
                                required property int index
                                Layout.fillWidth: true
                                spacing: 2
                                RowLayout {
                                    Layout.fillWidth: true
                                    AppCheckBox {
                                        id: structureCheck
                                        objectName: "planningStructureVisible-" + structureAppearance.index
                                        Layout.fillWidth: true
                                        text: structureAppearance.modelData.name.replace(/\.stl$/i, "")
                                        checked: structureAppearance.modelData.visible
                                        onToggled: stlViewer.setVisible(structureAppearance.index, checked)
                                        contentItem: Text { text: structureCheck.text; leftPadding: 26; color: Theme.text; elide: Text.ElideMiddle; verticalAlignment: Text.AlignVCenter; font.pixelSize: Theme.fontLabel }
                                    }
                                    Button {
                                        id: structureColor
                                        objectName: "planningStructureColor-" + structureAppearance.index
                                        Layout.preferredWidth: 26; Layout.preferredHeight: 26
                                        onClicked: stlViewer.chooseColor(structureAppearance.index)
                                        ToolTip.visible: hovered
                                        ToolTip.text: "修改颜色"
                                        background: Rectangle { color: structureAppearance.modelData.color; radius: 6; border.color: structureColor.hovered ? Theme.text : Theme.stroke }
                                    }
                                }
                                RowLayout {
                                    Layout.fillWidth: true
                                    Text { text: "不透明度"; color: Theme.faint; font.pixelSize: Theme.fontCaption }
                                    AppSlider {
                                        objectName: "planningStructureOpacity-" + structureAppearance.index
                                        Layout.fillWidth: true
                                        from: 0; to: 1; stepSize: 0.01
                                        value: structureAppearance.modelData.opacity
                                        onMoved: stlViewer.setOpacity(structureAppearance.index, value)
                                    }
                                    Text { text: Math.round(structureAppearance.modelData.opacity * 100) + "%"; color: Theme.muted; font.pixelSize: Theme.fontCaption; Layout.preferredWidth: 36; horizontalAlignment: Text.AlignRight }
                                }
                            }
                        }
                    }

                    CollapsibleSection {
                        Layout.fillWidth: true
                        title: "计算详情"
                        expanded: false
                        Text {
                            objectName: "planningBackendDetails"
                            Layout.fillWidth: true
                            wrapMode: Text.Wrap
                            color: Theme.muted
                            font.pixelSize: Theme.fontCaption
                            lineHeight: 1.4
                            text: !planner.hasPlan || planner.metricsPending ? "几何校验：等待更新" :
                                  "双平面楔形：无人工底面，底面校验不适用"
                                    + "\n切缘：完整病灶三角面到实际肺内有限切面的最小距离"
                                    + "\n体积：原始肺网格与双半空间的布尔交集"
                                    + "\n辅助封口位于肺外，不是手术切面"
                                    + "\n计算后端：" + (planner.result.metric_backend || "等待")
                        }
                    }
                    Item { Layout.preferredHeight: 8 }
                }
            }
        }
    }
}
