import QtQuick
import QtQuick.Controls
import QtQuick.Layouts
import "pages"
import "components"

ApplicationWindow {
    id: window
    visible: true
    visibility: singleWindowMode ? Window.FullScreen : Window.AutomaticVisibility
    width: 1920
    height: 1080
    minimumWidth: 1280
    minimumHeight: 720
    maximumWidth: resourceWall.enabled ? 1280 : 16777215
    maximumHeight: resourceWall.enabled ? 720 : 16777215
    title: session.authenticated ? "云端呼吸 工作站" : "云端呼吸 登录"
    color: Theme.sky
    font.family: Qt.platform.os === "windows" ? "Microsoft YaHei" : "Noto Sans CJK SC"
    // Basic-style defaults (tooltips, progress, scrollbars) read these.
    palette.toolTipBase: Theme.navy
    palette.toolTipText: "#ffffff"
    palette.dark: Theme.accent
    palette.mid: Theme.accentGlow

    readonly property color appBackground: Theme.background
    readonly property color surface: Theme.panel
    readonly property color surfaceRaised: Theme.panelRaised
    readonly property color stroke: Theme.stroke
    readonly property color textPrimary: Theme.text
    readonly property color textSecondary: Theme.muted
    readonly property color accent: Theme.accent
    readonly property color accentDim: Theme.accentDim
    readonly property color accentForeground: Theme.accentForeground
    readonly property color alert: Theme.error
    readonly property color viewerAlert: Theme.viewerError
    property int authPage: 0
    property int appPage: 0
    property string selectedPlane: "axial"
    property bool active3D: false
    property bool detached3D: false
    property bool focus3D: false
    property bool applicationClosing: false
    // Only the comparison harness sets a fixed pixel viewport. Product focus
    // fills the display; its increased workload is reported separately.
    property real directFocusViewportSide: 0
    readonly property Window detachedStlWindow: detachedWindowLoader.item as Window
    readonly property Window detached3DWindow: detachedStlWindow
    property int annotationMode: 0
    property string annotationColor: "#ff4545"
    property real annotationWidth: 4
    signal annotationCommand(string command)
    readonly property bool ctNavigationEnabled: session.authenticated && (appPage === 1 || appPage === 2) && !active3D
    property string queueFilter: ""
    property int selectedStudyId: -1
    property var selectedStudy: null
    // Privacy mode, on by default: patients show as 病人N with modality and slice count only.
    property bool hidePatientInfo: true
    function patientAlias(studyId) {
        const rows = patientQueue.rows
        for (let i = 0; i < rows.length; ++i)
            if (rows[i].studyId === studyId) return rows[i].alias
        return studyId >= 0 ? "病人" : ""
    }
    readonly property string currentPatientTitle: hidePatientInfo
        ? (ctImporter.studyId >= 0 ? patientAlias(ctImporter.studyId) : "未载入患者")
        : (ctImporter.patientText.length > 0 ? ctImporter.patientText : "未载入患者")
    readonly property string currentPatientMeta: hidePatientInfo
        ? (ctImporter.sliceCount > 0 ? "CT · " + ctImporter.sliceCount + " 张切片" : "等待影像序列")
        : ([ctImporter.institutionText, ctImporter.studyText].filter(function(v) { return v && v.length > 0 }).join(" · ")
           || (ctImporter.sliceCount > 0 ? ctImporter.sliceCount + " 张切片" : "等待影像序列"))
    property int desktopWidth: 1920
    property int desktopHeight: 1080
    property bool desktopMaximized: false
    property bool registerVisited: false
    property bool queueVisited: false
    property bool imagingVisited: false
    property bool reconstructionVisited: false
    property bool planningVisited: false
    property bool stlCreated: false
    readonly property bool stlSceneReady: sharedStlLoader.status === Loader.Ready
    readonly property ImagingPage imagingWorkspace: imagingPageLoader.item as ImagingPage
    readonly property ReconstructionPage reconstructionWorkspace: reconstructionPageLoader.item as ReconstructionPage
    readonly property PlanningPage planningWorkspace: planningPageLoader.item as PlanningPage
    readonly property StlView sharedStlScene: sharedStlLoader.item as StlView
    readonly property bool performancePresentationVisible: visible && visibility !== Window.Minimized
    // Page-level policy avoids a Python call on every input/frame change.
    // Only telemetry publication slows down; the renderer and controls do not.
    readonly property bool performanceRenderActive: session.authenticated && stlSceneReady
        && stlViewer.triangleCount > 0 && activeStlViewport !== null
    readonly property var activeStlViewport: !session.authenticated ? null : (appPage === 1 && imagingWorkspace
        ? imagingWorkspace.stlViewport
        : (appPage === 2 && reconstructionWorkspace ? reconstructionWorkspace.stlViewport
            : (appPage === 3 && planningWorkspace ? planningWorkspace.stlViewport : null)))

    function updatePerformancePresentation() {
        performanceMonitor.setPresentationState(performancePresentationVisible, performanceRenderActive)
    }
    onPerformancePresentationVisibleChanged: updatePerformancePresentation()
    onPerformanceRenderActiveChanged: updatePerformancePresentation()
    Component.onCompleted: updatePerformancePresentation()

    onClosing: {
        // Restore handlers must not show this window while the app is closing.
        applicationClosing = true
        detached3D = false
        focus3D = false
    }
    onAuthPageChanged: { if (authPage === 1) registerVisited = true }
    onDetached3DChanged: {
        if (singleWindowMode) {
            if (detached3D) { detached3D = false; enterFocus3D() }
            return
        }
        if (!detached3D && focus3D) focus3D = false
        if (detached3D && (appPage !== 2 || !session.authenticated || !stlSceneReady)) {
            detached3D = false
            return
        }
        if (sharedStlScene) {
            sharedStlScene.finishInputGesture()
            sharedStlScene.stopRotationBenchmark()
        }
        if (detached3D) {
            // The initial window has exactly the embedded viewport dimensions.
            // Reparenting retains the model, camera, material and render scale.
            detachedStlWindow.width = Math.max(1, Math.round(activeStlViewport.width))
            detachedStlWindow.height = Math.max(1, Math.round(activeStlViewport.height))
            detachedStlWindow.x = window.x + Math.max(0, Math.round((window.width - detachedStlWindow.width) / 2))
            detachedStlWindow.y = window.y + Math.max(0, Math.round((window.height - detachedStlWindow.height) / 2))
            active3D = true
            detachedStlWindow.requestActivate()
        }
        benchmark.attachPresentationWindow(detached3D ? detachedStlWindow : window)
        Qt.callLater(function() { if (window.sharedStlScene) window.sharedStlScene.forceActiveFocus() })
    }
    onFocus3DChanged: {
        if (singleWindowMode) {
            if (focus3D && (applicationClosing || !session.authenticated || appPage !== 2)) focus3D = false
            benchmark.attachPresentationWindow(window)
            Qt.callLater(function() { if (window.sharedStlScene) window.sharedStlScene.forceActiveFocus() })
            return
        }
        if (focus3D) {
            if (!detached3D || applicationClosing || !session.authenticated || appPage !== 2) {
                focus3D = false
                return
            }
            // Clear the native owner before hiding the main window. Keeping
            // the owner would let some window managers hide the child too.
            detachedStlWindow.transientParent = null
            Qt.callLater(function() {
                if (!window.focus3D || !window.detached3D || window.applicationClosing) return
                detachedStlWindow.show()
                detachedStlWindow.raise()
                detachedStlWindow.requestActivate()
                window.hide()
            })
        } else {
            detachedStlWindow.transientParent = window
            if (!applicationClosing) {
                window.show()
                window.raise()
                window.requestActivate()
            }
        }
    }
    function enterFocus3D() {
        if (applicationClosing || appPage !== 2 || !session.authenticated || !stlSceneReady) return
        if (singleWindowMode) { active3D = true; focus3D = true; return }
        detached3D = true
        focus3D = detached3D
    }
    function leaveDetached3D() {
        detached3D = false
        focus3D = false
    }
    onAppPageChanged: {
        if (appPage !== 2) { detached3D = false; focus3D = false }
        if (!session.authenticated) return
        pageCurtainFade.restart()
        benchmark.beginPageSwitch(appPage,
            appPage === 0 ? !queueVisited : (appPage === 1 ? !imagingVisited : (appPage === 2 ? !reconstructionVisited : !planningVisited)))
        if (appPage === 0) queueVisited = true
        else if (appPage === 1) { imagingVisited = true; stlCreated = true }
        else if (appPage === 2) { reconstructionVisited = true; stlCreated = true }
        else if (appPage === 3) { planningVisited = true; stlCreated = true }
    }
    Connections {
        target: session
        function onAuthenticatedChanged() {
            if (session.authenticated) {
                window.queueVisited = true
                if (window.appPage === 1) { window.imagingVisited = true; window.stlCreated = true }
                if (window.appPage === 2) { window.reconstructionVisited = true; window.stlCreated = true }
                if (window.appPage === 3) { window.planningVisited = true; window.stlCreated = true }
            } else {
                if (window.sharedStlScene) {
                    window.sharedStlScene.finishInputGesture()
                    window.sharedStlScene.stopRotationBenchmark()
                }
                window.detached3D = false
                window.focus3D = false
                window.imagingVisited = false
                window.reconstructionVisited = false
                window.planningVisited = false
                window.queueVisited = false
                window.registerVisited = false
                window.authPage = 0
                window.appPage = 0
            }
        }
    }
    Connections {
        target: reconstructionPageLoader.item
        ignoreUnknownSignals: true
        function onResetScene() {
            if (window.sharedStlScene) window.sharedStlScene.resetCamera()
        }
    }

    Connections {
        target: resourceWall
        function onEnabledChanged() {
            if (singleWindowMode) return
            if (resourceWall.enabled) {
                window.showNormal()
                window.width = 1280
                window.height = 720
            } else {
                window.width = window.desktopWidth
                window.height = window.desktopHeight
                if (window.desktopMaximized) window.showMaximized()
            }
        }
    }

    function openStudy(studyId) {
        ctImporter.loadStudy(studyId)
        if (window.selectedStudy && window.selectedStudy.stlDirectory)
            stlViewer.loadDirectory(window.selectedStudy.stlDirectory)
        window.appPage = 1
        window.selectedPlane = "axial"
        window.active3D = false
    }

    function previousSelectedPlane() {
        if (selectedPlane === "coronal") ctImporter.previousCoronal()
        else if (selectedPlane === "sagittal") ctImporter.previousSagittal()
        else ctImporter.previousSlice()
    }

    function nextSelectedPlane() {
        if (selectedPlane === "coronal") ctImporter.nextCoronal()
        else if (selectedPlane === "sagittal") ctImporter.nextSagittal()
        else ctImporter.nextSlice()
    }

    Shortcut { sequence: "Up"; enabled: window.ctNavigationEnabled; onActivated: window.previousSelectedPlane() }
    Shortcut { sequence: "Down"; enabled: window.ctNavigationEnabled; onActivated: window.nextSelectedPlane() }
    Shortcut { sequence: "PageUp"; enabled: window.ctNavigationEnabled; onActivated: window.previousSelectedPlane() }
    Shortcut { sequence: "PageDown"; enabled: window.ctNavigationEnabled; onActivated: window.nextSelectedPlane() }


    // ───────── App shell: teal frame, sidebar, white content card ─────────
    // Below 1500 px the sidebar shrinks to icons so the 720p board display
    // keeps enough room for the three-column planning page.
    readonly property bool sidebarCompact: width < 1500
    readonly property int sidebarW: sidebarCompact ? Theme.sidebarCompactWidth : Theme.sidebarWidth
    readonly property int workflowDone: (queueVisited ? 1 : 0) + (imagingVisited ? 1 : 0)
        + (reconstructionVisited ? 1 : 0) + (planningVisited ? 1 : 0)

    Rectangle {
        id: appShell
        visible: session.authenticated
        anchors.fill: parent
        anchors.margins: Theme.shellMargin
        anchors.bottomMargin: Theme.footerHeight
        radius: Theme.shellRadius
        color: Theme.shell

        RowLayout {
            id: brandRow
            x: window.sidebarCompact ? 23 : 22
            y: 22
            spacing: 10
            BrandLogo { Layout.preferredWidth: 30; Layout.preferredHeight: 30 }
            Text {
                visible: !window.sidebarCompact
                text: "云端呼吸"; color: Theme.shellText
                font.pixelSize: Theme.fontTitle; font.weight: Font.DemiBold
            }
        }

        // Workflow: 患者 -> 阅片 -> 重建 -> 规划. The current page is a white
        // pill that runs into the content card.
        Column {
            id: navColumn
            x: 0
            y: 86
            width: window.sidebarW
            spacing: 6
            Repeater {
                model: [{label: "患者队列", icon: "users"}, {label: "二维阅片", icon: "scan-line"}, {label: "三维重建", icon: "box"}, {label: "量化分析", icon: "gauge"}]
                delegate: Button {
                    id: navItem
                    required property var modelData
                    required property int index
                    readonly property bool current: window.appPage === index
                    readonly property bool done: !current && (index === 0 ? window.queueVisited
                        : (index === 1 ? window.imagingVisited : (index === 2 ? window.reconstructionVisited : window.planningVisited)))
                    objectName: "moduleTab" + index
                    text: modelData.label
                    width: navColumn.width
                    height: 46
                    padding: 0
                    ToolTip.visible: window.sidebarCompact && hovered
                    ToolTip.text: modelData.label
                    ToolTip.delay: 400
                    onClicked: {
                        window.appPage = index
                        window.active3D = false
                    }
                    contentItem: Item {
                        Row {
                            x: window.sidebarCompact ? 33 : 30
                            anchors.verticalCenter: parent.verticalCenter
                            spacing: 12
                            Icon { name: navItem.modelData.icon; size: 20; inverse: !navItem.current; anchors.verticalCenter: parent.verticalCenter }
                            Text {
                                visible: !window.sidebarCompact
                                text: navItem.text
                                color: navItem.current ? Theme.navy : Theme.shellText
                                font.pixelSize: Theme.fontBody
                                font.weight: navItem.current ? Font.Bold : Font.Medium
                                anchors.verticalCenter: parent.verticalCenter
                                Behavior on color { ColorAnimation { duration: Theme.durBase } }
                            }
                        }
                    }
                    background: Item {
                        Rectangle {
                            x: 12; width: parent.width - 24; height: parent.height
                            radius: height / 2
                            color: Theme.shellDeep
                            opacity: navItem.hovered && !navItem.current ? 1 : 0
                            Behavior on opacity { NumberAnimation { duration: Theme.durFast } }
                        }
                        Rectangle {
                            x: 12; height: parent.height
                            radius: height / 2
                            width: navItem.current ? parent.width - 12 : 0
                            color: Theme.background
                            Behavior on width { NumberAnimation { duration: Theme.durSlow; easing.type: Theme.easeOut } }
                            // square off the right end so the pill flows into the card
                            Rectangle {
                                anchors.right: parent.right; anchors.top: parent.top; anchors.bottom: parent.bottom
                                width: Math.min(parent.radius, parent.width / 2)
                                color: parent.color
                            }
                        }
                        Rectangle {
                            visible: navItem.activeFocus
                            x: 12; width: parent.width - 24; height: parent.height
                            radius: height / 2
                            color: "transparent"; border.width: 2; border.color: Theme.shellText
                        }
                    }
                }
            }
        }

        Column {
            id: footNav
            x: 0
            width: window.sidebarW
            anchors.bottom: parent.bottom
            anchors.bottomMargin: 16
            spacing: 2
            SideLink {
                width: parent.width
                iconName: "log-out"; text: "退出登录"; compact: window.sidebarCompact
                onClicked: session.logout()
            }
            SideLink {
                width: parent.width
                visible: singleWindowMode
                iconName: "x"; text: "退出程序"; compact: window.sidebarCompact
                onClicked: Qt.quit()
            }
        }
    }

    Rectangle {
        id: contentCard
        visible: session.authenticated
        anchors.fill: parent
        anchors.leftMargin: Theme.shellMargin + window.sidebarW
        anchors.topMargin: Theme.shellMargin + Theme.cardInset
        anchors.rightMargin: Theme.shellMargin + Theme.cardInset
        anchors.bottomMargin: Theme.footerHeight + Theme.shellMargin + Theme.cardInset
        radius: Theme.cardRadius
        color: Theme.background
    }

    Item {
        id: pageHeader
        visible: session.authenticated
        anchors.left: contentCard.left; anchors.right: contentCard.right; anchors.top: contentCard.top
        anchors.leftMargin: 28; anchors.rightMargin: 22
        height: Theme.headerHeight
        Text {
            id: pageTitle
            property real shift: 0
            anchors.verticalCenter: parent.verticalCenter
            text: ["患者队列", "二维阅片", "三维重建", "量化分析"][window.appPage]
            color: Theme.text
            font.pixelSize: Theme.fontHeading; font.weight: Font.DemiBold
            transform: Translate { x: pageTitle.shift }
            onTextChanged: titleAnim.restart()
            ParallelAnimation {
                id: titleAnim
                NumberAnimation { target: pageTitle; property: "shift"; from: -12; to: 0; duration: Theme.durSlow; easing.type: Theme.easeOut }
                NumberAnimation { target: pageTitle; property: "opacity"; from: 0; to: 1; duration: Theme.durSlow }
            }
        }
        Row {
            anchors.right: parent.right
            anchors.verticalCenter: parent.verticalCenter
            spacing: 12
            StatusChip {
                visible: window.appPage === 3
                anchors.verticalCenter: parent.verticalCenter
                text: planner.executionBackend === "pl" ? "PL 加速" : "纯 PS"
                tone: planner.executionBackend === "pl" ? "accent" : "neutral"
            }
            // Current patient, where the reference shows the signed-in user.
            Rectangle {
                id: patientPill
                height: 42
                radius: 21
                color: Theme.panel
                width: 6 + 34 + 10 + patientText.width + 18
                Rectangle {
                    x: 4; anchors.verticalCenter: parent.verticalCenter
                    width: 34; height: 34; radius: 17
                    color: Theme.blush
                    Icon { anchors.centerIn: parent; name: "user"; size: 17 }
                }
                Column {
                    id: patientText
                    x: 6 + 34 + 10
                    anchors.verticalCenter: parent.verticalCenter
                    width: Math.min(260, Math.max(patientName.implicitWidth, patientMeta.implicitWidth))
                    Text {
                        id: patientName
                        width: parent.width
                        text: window.currentPatientTitle
                        color: Theme.text; font.pixelSize: Theme.fontLabel; font.weight: Font.DemiBold
                        elide: Text.ElideRight
                    }
                    Text {
                        id: patientMeta
                        width: parent.width
                        text: window.currentPatientMeta
                        color: Theme.muted; font.pixelSize: Theme.fontCaption
                        elide: Text.ElideRight
                    }
                }
            }
        }
    }

    // Area the pages live in: the card minus a small inset that keeps square
    // panels clear of its rounded corners. Fills the window when logged out.
    Item {
        id: contentArea
        anchors.fill: parent
        anchors.leftMargin: session.authenticated ? Theme.shellMargin + window.sidebarW + Theme.cardInset : 0
        anchors.rightMargin: session.authenticated ? Theme.shellMargin + 2 * Theme.cardInset : 0
        anchors.topMargin: session.authenticated
            ? Theme.shellMargin + Theme.cardInset + Theme.headerHeight + (window.appPage === 1 || window.appPage === 2 ? Theme.subToolbarHeight : 0) : 0
        anchors.bottomMargin: session.authenticated ? Theme.footerHeight + Theme.shellMargin + 2 * Theme.cardInset : Theme.footerHeight
    }

    function runRotationBenchmark() {
        if (window.sharedStlScene) window.sharedStlScene.runRotationBenchmark()
    }
    function resetStlCamera() {
        if (window.sharedStlScene) window.sharedStlScene.resetCamera()
    }

    Loader {
        id: detachedWindowLoader
        active: !singleWindowMode
        sourceComponent: Window {
        objectName: "detachedStlWindow"
        title: window.focus3D ? "云端呼吸 · 专注三维（Esc 返回）" : "云端呼吸 · 三维视图（独立窗口）"
        color: "#000000"
        width: 811; height: 811
        minimumWidth: 256; minimumHeight: 256
        visible: window.detached3D && session.authenticated && window.appPage === 2
        transientParent: window
        flags: Qt.Window
        onClosing: function(close) {
            if (!window.applicationClosing) {
                // Closing this view returns to the workstation, not the app.
                close.accepted = false
                window.leaveDetached3D()
            }
        }
        Item {
            id: detachedStlHost
            objectName: "detachedStlHost"
            anchors.fill: parent
            focus: true
        }
        Shortcut { sequence: "Escape"; onActivated: window.leaveDetached3D() }
        }
    }

    // A single native surface for EGLFS. Moving the scene within that surface
    // retains its camera/geometries and never hides the application window.
    Rectangle {
        id: directFocusHost
        objectName: "directFocusHost"
        anchors.fill: parent
        z: 100
        visible: singleWindowMode && window.focus3D
        color: "black"
        Item {
            id: directFocusViewport
            anchors.centerIn: parent
            width: window.directFocusViewportSide > 0 ? Math.min(parent.width, window.directFocusViewportSide) : parent.width
            height: window.directFocusViewportSide > 0 ? Math.min(parent.height, window.directFocusViewportSide) : parent.height
        }
    }
    Shortcut { sequence: "Escape"; enabled: singleWindowMode && window.focus3D; onActivated: window.leaveDetached3D() }
    Shortcut { sequence: "Ctrl+Q"; enabled: singleWindowMode; onActivated: Qt.quit() }

    StackLayout {
        anchors.fill: contentArea
        currentIndex: session.authenticated ? window.appPage + 2 : window.authPage
        focus: true
        Keys.onPressed: function(event) {
            if (!window.ctNavigationEnabled || ctImporter.sliceCount <= 0)
                return
            if (event.key === Qt.Key_Up || event.key === Qt.Key_PageUp) {
                window.previousSelectedPlane()
                event.accepted = true
            } else if (event.key === Qt.Key_Down || event.key === Qt.Key_PageDown) {
                window.nextSelectedPlane()
                event.accepted = true
            }
        }

        Loader { Layout.fillWidth: true; Layout.fillHeight: true; sourceComponent: LoginPage { appWindow: window } }
        Loader { Layout.fillWidth: true; Layout.fillHeight: true; active: window.registerVisited; sourceComponent: RegisterPage { appWindow: window } }
        Loader { id: queuePageLoader; objectName: "queuePageLoader"; Layout.fillWidth: true; Layout.fillHeight: true; active: window.queueVisited; sourceComponent: QueuePage { appWindow: window } }
        Loader {
            id: imagingPageLoader
            objectName: "imagingPageLoader"
            Layout.fillWidth: true; Layout.fillHeight: true
            active: window.imagingVisited
            sourceComponent: ImagingPage { appWindow: window }
        }
        Loader {
            id: reconstructionPageLoader
            objectName: "reconstructionPageLoader"
            Layout.fillWidth: true; Layout.fillHeight: true
            active: window.reconstructionVisited
            sourceComponent: ReconstructionPage { appWindow: window }
        }
        Loader {
            id: planningPageLoader
            objectName: "planningPageLoader"
            Layout.fillWidth: true; Layout.fillHeight: true
            active: window.planningVisited
            sourceComponent: PlanningPage { appWindow: window }
        }
    }
    // Page switch: a background-coloured veil fades out over the new page.
    // Done as a sibling (not an opacity on the pages) so the shared 3D view
    // is never pushed into an offscreen layer.
    Rectangle {
        id: pageCurtain
        z: 5
        anchors.fill: contentArea
        color: Theme.background
        opacity: 0
        visible: opacity > 0.01
        NumberAnimation on opacity {
            id: pageCurtainFade
            running: false
            from: 0.9; to: 0; duration: Theme.durSlow; easing.type: Theme.easeOut
        }
    }
    Loader {
        id: sharedStlLoader
        objectName: "sharedStlLoader"
        // Backend geometries survive logout. Keep their View3D alive too;
        // rebinding old geometries to a recreated scene can render them black.
        active: window.stlCreated
        visible: session.authenticated && active && window.activeStlViewport !== null
        parent: singleWindowMode && window.focus3D ? directFocusViewport
            : (window.detached3D && window.detachedStlWindow ? window.detachedStlWindow.contentItem : (window.activeStlViewport || window.contentItem))
        anchors.fill: parent
        sourceComponent: StlView {
            objectName: "sharedStlScene"
            showLayers: false
            showTitle: true
            focusMode: window.focus3D
            navigateOnDoubleClick: window.appPage === 1
            plannerController: window.appPage === 3 ? planner : null
            interiorPathOnly: window.planningWorkspace ? window.planningWorkspace.interiorPathOnly : false
            border.color: Theme.viewerStroke
            onSceneActivated: window.active3D = true
            onOpenReconstruction: { window.appPage = 2; window.active3D = true }
            onReturnToWorkspace: window.leaveDetached3D()
        }
    }
    DirectDialogs { }
    AnnotationBar {
        appWindow: window
        anchors.left: contentArea.left; anchors.right: contentArea.right
        anchors.bottom: contentArea.top
        anchors.bottomMargin: 6
        height: Theme.subToolbarHeight - 6
        visible: session.authenticated && (window.appPage === 1 || window.appPage === 2)
    }
    Rectangle {
        id: performanceBar
        z: 11
        anchors.left: parent.left; anchors.right: parent.right; anchors.bottom: parent.bottom
        height: Theme.footerHeight
        color: "transparent"
        RowLayout {
            anchors.fill: parent; anchors.leftMargin: Theme.shellMargin + 14; anchors.rightMargin: Theme.shellMargin + 14; spacing: 14
            Rectangle { Layout.preferredWidth: 7; Layout.preferredHeight: 7; radius: 4; color: resourceWall.overBudget ? Theme.error : (performanceMonitor.available ? Theme.success : Theme.warning) }
            Text { text: resourceWall.enabled ? resourceWall.status : "本地运行"; color: resourceWall.overBudget ? Theme.error : Theme.muted; font.pixelSize: Theme.fontCaption }
            Text { text: "STL  " + stlViewer.triangleCountText + " 面"; color: Theme.muted; font.pixelSize: Theme.fontCaption }
            Text { text: "内存  " + performanceMonitor.memoryMb.toFixed(0) + " MB"; visible: performanceMonitor.available && window.width > 1100; color: Theme.muted; font.pixelSize: Theme.fontCaption }
            Item { Layout.fillWidth: true }
            Text {
                text: "诊断"; font.pixelSize: Theme.fontCaption
                color: diagnosticsArea.containsMouse || diagnosticsPopup.visible ? Theme.accent : Theme.faint
                Behavior on color { ColorAnimation { duration: Theme.durFast } }
            }
            Icon {
                name: "chevron-up"; size: 12; opacity: 0.6
                rotation: diagnosticsPopup.visible ? 180 : 0
                Behavior on rotation { NumberAnimation { duration: Theme.durBase; easing.type: Theme.easeOut } }
            }
        }
        MouseArea {
            id: diagnosticsArea
            anchors.fill: parent; hoverEnabled: true
            cursorShape: Qt.PointingHandCursor
            onClicked: diagnosticsPopup.visible ? diagnosticsPopup.close() : diagnosticsPopup.open()
        }
    }
    Popup {
        id: diagnosticsPopup
        parent: Overlay.overlay
        x: window.width - width - 12
        y: window.height - Theme.footerHeight - height - 8
        width: 340
        padding: 14
        closePolicy: Popup.CloseOnEscape | Popup.CloseOnPressOutside
        enter: Transition {
            NumberAnimation { property: "opacity"; from: 0; to: 1; duration: Theme.durBase }
            NumberAnimation { property: "y"; from: window.height - Theme.footerHeight - diagnosticsPopup.height + 4; to: window.height - Theme.footerHeight - diagnosticsPopup.height - 8; duration: Theme.durBase; easing.type: Theme.easeOut }
        }
        exit: Transition { NumberAnimation { property: "opacity"; to: 0; duration: Theme.durFast } }
        background: Rectangle { color: Theme.panel; border.color: Theme.stroke; radius: Theme.panelRadius }
        contentItem: ColumnLayout {
            spacing: 10
            Text { text: "运行诊断"; color: Theme.text; font.pixelSize: Theme.fontBody; font.weight: Font.DemiBold }
            Text { visible: !performanceMonitor.available; text: "采样不可用"; color: Theme.error; font.pixelSize: Theme.fontCaption }
            GridLayout {
                visible: performanceMonitor.available
                Layout.fillWidth: true
                columns: 2; columnSpacing: 12; rowSpacing: 6
                Text { text: "进程 CPU"; color: Theme.faint; font.pixelSize: Theme.fontCaption }
                Text { text: performanceMonitor.cpuPercent.toFixed(1) + " %"; color: Theme.text; font.pixelSize: Theme.fontCaption; Layout.alignment: Qt.AlignRight }
                Text { text: "进程内存"; color: Theme.faint; font.pixelSize: Theme.fontCaption }
                Text { text: performanceMonitor.memoryMb.toFixed(0) + " MB"; color: Theme.text; font.pixelSize: Theme.fontCaption; Layout.alignment: Qt.AlignRight }
                Text { text: "GPU 整机"; color: Theme.faint; font.pixelSize: Theme.fontCaption }
                Text { text: gpuMonitor.available ? gpuMonitor.percent.toFixed(0) + " %" : "—"; color: Theme.text; font.pixelSize: Theme.fontCaption; Layout.alignment: Qt.AlignRight }
                Text { text: "线程"; color: Theme.faint; font.pixelSize: Theme.fontCaption }
                Text { text: performanceMonitor.threadCount; color: Theme.text; font.pixelSize: Theme.fontCaption; Layout.alignment: Qt.AlignRight }
                Text { text: "磁盘读 / 写"; color: Theme.faint; font.pixelSize: Theme.fontCaption }
                Text { text: performanceMonitor.readMbS.toFixed(1) + " / " + performanceMonitor.writeMbS.toFixed(1) + " MB/s"; color: Theme.text; font.pixelSize: Theme.fontCaption; Layout.alignment: Qt.AlignRight }
                Text { text: "系统 CPU"; color: Theme.faint; font.pixelSize: Theme.fontCaption }
                Text { text: performanceMonitor.systemCpuPercent.toFixed(0) + " %"; color: Theme.text; font.pixelSize: Theme.fontCaption; Layout.alignment: Qt.AlignRight }
                Text { text: "系统 RAM 占用 / 可用"; color: Theme.faint; font.pixelSize: Theme.fontCaption }
                Text { text: performanceMonitor.systemMemoryPercent.toFixed(0) + " % / " + performanceMonitor.systemAvailableMemoryMb.toFixed(0) + " MiB"; color: Theme.text; font.pixelSize: Theme.fontCaption; Layout.alignment: Qt.AlignRight }
            }
            Rectangle { Layout.fillWidth: true; implicitHeight: 1; color: Theme.strokeSoft }
            AppButton {
                id: kv260ModeButton
                visible: typeof boardMode === "undefined" || !boardMode
                Layout.fillWidth: true
                text: resourceWall.enabled ? "退出 KV260 约束，回到桌面模式" : "启用 KV260 约束模式"
                iconName: "monitor"
                ToolTip.visible: hovered
                ToolTip.text: "桌面模拟：窗口 1280×720、最多 4 核 CPU 亲和；高面数仅提示，不设应用内存上限，也不模拟真实功耗。板端可用内存仍受 Linux 桌面、GPU 共享内存和 PYNQ 占用影响。"
                onClicked: {
                    if (!resourceWall.enabled) {
                        window.desktopWidth = window.width
                        window.desktopHeight = window.height
                        window.desktopMaximized = window.visibility === Window.Maximized
                    }
                    resourceWall.setEnabled(!resourceWall.enabled)
                    diagnosticsPopup.close()
                }
            }
        }
    }
}
