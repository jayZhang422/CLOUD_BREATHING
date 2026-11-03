import QtQuick
import QtQuick.Controls
import QtQuick.Layouts
import QtQuick3D
import ".."
import "." as C

Rectangle {
    id: root
    color: "#000000"
    border.color: Theme.viewerStroke
    clip: true
    focus: true
    signal sceneActivated()
    signal openReconstruction()
    signal returnToWorkspace()
    property bool navigateOnDoubleClick: false
    property bool showLayers: true
    property bool showTitle: true
    property bool focusMode: false
    property bool hideShellsWhileDragging: true
    property bool hidePlanningShellsDuringMotion: true
    property bool hideXrayOrgansDuringMotion: true
    property bool shellDragActive: false
    property bool wheelMotionActive: false
    readonly property bool cameraInMotion: shellDragActive || wheelMotionActive || benchmarkSpinning
    readonly property bool contextShellsHidden: hideShellsWhileDragging && cameraInMotion
        && (!planning || hidePlanningShellsDuringMotion)
    function isMotionContextSurface(row) {
        // Protect lesions even when the x-ray material makes them transparent.
        if (/tumou?r|lesion|nodule|肿瘤|结节|病灶/i.test(row.name)) return false
        if (row.opacity < 0.5) return true
        return hideXrayOrgansDuringMotion && planning
            && ((branchOverlay && branchAnalysis.xray) || plannerController.lesionPreviewVisible)
    }
    // Diagnostic ablations: visibility only, never detach live geometry.
    property bool diagnosticHideVesselSurfaces: false
    property bool diagnosticHideCenterlines: false
    property bool diagnosticHideRootMarkers: false
    property bool diagnosticHideWedge: false
    property bool relatedBranchesOnly: false
    property bool batchedRootMarkers: true
    property bool lightweightCenterlines: true
    Timer {
        id: shellMotionRestore
        interval: 250
        onTriggered: root.shellDragActive = false
    }
    Timer {
        id: wheelMotionRestore
        interval: 250
        onTriggered: root.wheelMotionActive = false
    }
    // Three shared policies; default off. Qt may rebuild SSAA render targets
    // on a transition; unchanged explicitTextureSize does NOT rule that out.
    property string aaMode: typeof sceneDisplay !== "undefined" ? sceneDisplay.aaMode : "off"
    readonly property bool adaptiveInteractionAA: aaMode === "drag"
    property bool interactionAAActive: false
    property int interactionAAIdleMs: 250
    readonly property string effectiveAntialiasing: aaMode === "off" ? "none"
        : adaptiveInteractionAA && (interactionAAActive || cameraInMotion) ? "none" : "ssaa"
    signal interactionAATransition(string mode)
    signal interactionAAEvent(string event)
    onEffectiveAntialiasingChanged: interactionAATransition(effectiveAntialiasing)
    onAdaptiveInteractionAAChanged: { if (!adaptiveInteractionAA) restoreInteractionAA() }
    Timer {
        id: interactionAARestore
        interval: root.interactionAAIdleMs
        onTriggered: { root.interactionAAEvent("timer-fired"); root.interactionAAActive = false }
    }
    function beginInteractionAA() {
        if (!adaptiveInteractionAA) return
        interactionAARestore.stop()
        interactionAAActive = true
    }
    function endInteractionAA() {
        if (adaptiveInteractionAA) interactionAAEvent("gesture-ended")
        if (interactionAAActive) interactionAARestore.restart()
    }
    function restoreInteractionAA() {
        interactionAARestore.stop()
        interactionAAActive = false
    }
    // Only the benchmark sets this diagnostic; production keeps both lights.
    property bool diagnosticDisableSecondLight: false
    // Opt-in benchmark only: exact positions for the unlit centerline overlay.
    property bool diagnosticUseCompactCenterlines: false
    property var diagnosticCenterlineGeometries: null
    property string lightingPath: typeof sceneLightingPath !== "undefined" ? sceneLightingPath : "fragment"
    property var plannerController: null
    readonly property bool planning: plannerController !== null
    // Keep GPU attachments across reconstruction/planning page transitions.
    readonly property var geometryPlanner: typeof planner !== "undefined" ? planner : plannerController
    readonly property var branchAnalysis: typeof centerlines !== "undefined" ? centerlines : null
    readonly property bool branchOverlay: root.planning && branchAnalysis !== null && branchAnalysis.ready && branchAnalysis.visible
    property bool interiorPathOnly: false
    property alias showPlan: root.interiorPathOnly
    readonly property int msaaSamples: typeof boardMsaaSamples !== "undefined" ? boardMsaaSamples : 2
    readonly property string antialiasing: typeof sceneAntialiasing !== "undefined" ? sceneAntialiasing : "none"
    readonly property string renderPath: typeof sceneRenderPath !== "undefined" ? sceneRenderPath : "offscreen"
    // Inline is an explicit no-AA experiment, not the normal product path.
    // SSAA needs an offscreen target and must not be silently downgraded.
    readonly property string effectiveRenderPath: "offscreen"
    readonly property int viewportWidth: Math.round(scene.width)
    readonly property int viewportHeight: Math.round(scene.height)
    function projectVertex(point) {
        // Include camera state so projected handles follow rotation and resize.
        var cameraState = orbitRotation.scalar + orbitRotation.x + orbitRotation.y + orbitRotation.z
            + panX + panY + panZ + distance + coordinateConvention + scene.width + scene.height
        return scene.mapFrom3DScene(point)
    }

    // STL has no trustworthy anatomical axis metadata. The user can choose a
    // known convention; only the camera changes, never the registered meshes.
    property int coordinateConvention: 0
    property real yaw: 0
    property real pitch: 0
    // The orientation is independent of Euler angle limits. yaw/pitch remain
    // compatible preset inputs and counters; dragging preserves the full roll.
    property quaternion orbitRotation: Qt.quaternion(1, 0, 0, 0)
    property bool orbitUpdating: false
    onYawChanged: { if (!orbitUpdating) syncOrbitPreset() }
    onPitchChanged: { if (!orbitUpdating) syncOrbitPreset() }
    property real panX: 0
    property real panY: 0
    property real panZ: 0
    property real distance: 260
    // Display geometry is normalized to a ~200-unit span. The former 170
    // limit blocked even a 2x zoom of a fitted lung (~263 units away). Allow
    // close inspection; this only moves the camera, never source geometry.
    readonly property real minimumCameraDistance: 40
    readonly property real maximumCameraDistance: 1400
    // The focus-toolbar toggle enlarges the model without changing geometry.
    // Its second click restores the saved observation distance.
    property real focusZoomFactor: 2.0
    property bool focusZoomActive: false
    property real focusZoomRestoreDistance: -1
    property bool benchmarkSpinning: false
    property real rotationDegreesPerSecond: 125
    property real rotationBenchmarkSeconds: 4.8
    property bool inputPending: false
    // Keep the animation clock alive between input deliveries, rather than
    // restarting it after every flush. Stop on a pause even if still pressed.
    property bool continuousInputScheduling: true
    property bool inputClockActive: false
    property int editingVertex: -1
    property bool vertexInputPending: false
    property point vertexInputPosition: Qt.point(0, 0)
    function vertexRay(position, depth) {
        return scene.mapTo3DScene(Qt.vector3d(position.x, position.y, depth))
    }
    function flushVertexInput() {
        if (!vertexInputPending || editingVertex < 0) return
        vertexInputPending = false
        plannerController.dragVertex(editingVertex,
            vertexRay(vertexInputPosition, 1), vertexRay(vertexInputPosition, 2000))
    }
    function endVertexInput() {
        if (editingVertex < 0) return
        flushVertexInput()
        plannerController.endVertexDrag()
        editingVertex = -1
        endInteractionAA()
    }
    Connections {
        target: root.plannerController
        function onVertexReleaseRequested() { root.endVertexInput() }
        function onVertexGestureChanged() {
            if (!root.plannerController.vertexEditing && root.editingVertex >= 0) {
                root.editingVertex = -1
                root.vertexInputPending = false
                root.endInteractionAA()
            }
        }
    }
    Timer {
        id: inputClockIdle
        interval: 120
        onTriggered: root.stopInputClock()
    }
    function stopInputClock() {
        flushPendingInput()
        inputClockIdle.stop()
        inputClockActive = false
    }
    // Diagnostic only: an empty driver preserves product scheduling.
    property string diagnosticTrajectoryMode: ""
    property real diagnosticTrajectoryLastAngle: 0
    signal diagnosticTrajectoryFrame(real seconds, real angle)
    // Mutating fields of this plain JS object avoids property notifications
    // for diagnostics and preset counters on every input event.
    property var interactionState: ({
        inputEvents: 0, cameraUpdates: 0, animationTicks: 0, inputFlushes: 0,
        lodTimerRestarts: 0,
        mode: "", dx: 0, dy: 0, yawDelta: 0, pitchDelta: 0,
        pendingRotation: Qt.quaternion(1, 0, 0, 0), rotationElapsed: 0
    })
    property bool cameraResetPending: false
    // Display-only experiment: retain both geometries and protect fine anatomy.
    // Planning always uses the full mesh. No simplification happens per frame.
    property bool interactionLodMotion: false
    property real interactionLodFitDistance: 260
    readonly property real interactionLodZoom: interactionLodFitDistance / Math.max(1, distance)
    readonly property real interactionLodThreshold: typeof interactionLodMinimumZoom !== "undefined"
        ? interactionLodMinimumZoom : 1.5
    readonly property bool hasPreparedInteractionLod: stlViewer.loadTimings.interaction_lod_models > 0
    readonly property bool interactionLodActive: interactionLodMotion && !planning
        && hasPreparedInteractionLod && interactionLodZoom >= interactionLodThreshold
    Timer {
        id: interactionLodRestore
        interval: 250
        onTriggered: { if (!root.benchmarkSpinning) root.restoreInteractionDetail() }
    }
    function markInteractionMotion() {
        if (planning || !hasPreparedInteractionLod || interactionLodZoom < interactionLodThreshold) return
        interactionLodMotion = true
        interactionState.lodTimerRestarts++
        interactionLodRestore.restart()
    }
    function restoreInteractionDetail() {
        interactionLodRestore.stop()
        interactionLodMotion = false
    }
    function getInteractionLodDiagnostics() {
        var fullFaces = 0
        var currentFaces = 0
        stlViewer.rows.forEach(function(row) {
            if (!row.visible || row.opacity <= 0) return
            fullFaces += row.triangleCount
            currentFaces += root.interactionLodActive && row.hasInteractionLod && row.opacity < 0.5
                ? row.interactionTriangleCount : row.triangleCount
        })
        return {active: interactionLodActive, mode: stlViewer.loadTimings.interaction_lod_mode || "off",
            ratio: stlViewer.loadTimings.interaction_lod_ratio || 0.5,
            zoom: interactionLodZoom, minimum_zoom: interactionLodThreshold,
            timer_restarts: interactionState.lodTimerRestarts,
            full_faces: fullFaces, current_faces: currentFaces,
            extra_payload_bytes: stlViewer.loadTimings.interaction_lod_extra_bytes || 0,
            planning_protected: planning}
    }
    onPlanningChanged: { stopInputClock(); commitOrbitCounters(); restoreInteractionDetail(); restoreInteractionAA(); shellDragActive = false; shellMotionRestore.stop(); wheelMotionActive = false; wheelMotionRestore.stop() }

    function runRotationBenchmark(seconds) {
        if (benchmarkSpinning || stlViewer.triangleCount <= 0) return
        flushPendingInput()
        interactionState.rotationElapsed = 0
        if (seconds !== undefined && seconds > 0) rotationBenchmarkSeconds = seconds
        benchmark.beginRotation()
        benchmarkSpinning = true
    }

    FrameAnimation {
        id: interactionFrame
        running: root.visible && (root.editingVertex >= 0 || root.benchmarkSpinning || root.inputPending || root.inputClockActive || root.diagnosticTrajectoryMode !== "")
        onTriggered: {
            root.flushVertexInput()
            root.interactionState.animationTicks++
            root.flushPendingInput()
            if (root.diagnosticTrajectoryMode !== "" && root.diagnosticTrajectoryMode !== "hold") {
                const seconds = inputTrajectoryClock.seconds()
                const angle = 50 * Math.sin(2 * Math.PI * seconds / 4)
                const delta = angle - root.diagnosticTrajectoryLastAngle
                root.diagnosticTrajectoryLastAngle = angle
                if (root.diagnosticTrajectoryMode === "direct") root.orbitDegrees(delta, 0, true)
                else if (root.diagnosticTrajectoryMode === "queue") {
                    root.queueInput(-delta * Math.min(scene.width, scene.height) / 270, 0, "rotate")
                    root.flushPendingInput()
                } else if (root.diagnosticTrajectoryMode === "mouse") {
                    root.diagnosticTrajectoryFrame(seconds, angle)
                    root.flushPendingInput()
                }
            }
            if (root.benchmarkSpinning) {
                // FrameAnimation uses the Qt animation clock: one camera write
                // per frame, with angular speed independent of delivered FPS.
                const remaining = root.rotationBenchmarkSeconds - root.interactionState.rotationElapsed
                const seconds = Math.min(Math.max(0, frameTime), remaining)
                root.orbitDegrees(root.rotationDegreesPerSecond * seconds, 0, true)
                root.interactionState.rotationElapsed += seconds
                if (root.interactionState.rotationElapsed >= root.rotationBenchmarkSeconds)
                    root.stopRotationBenchmark()
            }
        }
    }

    onVisibleChanged: {
        if (!visible) {
            endVertexInput()
            stopInputClock()
            restoreInteractionAA()
            shellDragActive = false
            shellMotionRestore.stop()
            wheelMotionActive = false
            wheelMotionRestore.stop()
            flushPendingInput()
            commitOrbitCounters()
            stopRotationBenchmark()
            restoreInteractionDetail()
        }
    }

    function getInteractionDiagnostics() {
        return {
            input_events: interactionState.inputEvents,
            camera_updates: interactionState.cameraUpdates,
            animation_ticks: interactionState.animationTicks,
            input_flushes: interactionState.inputFlushes,
            continuous_input_scheduling: continuousInputScheduling,
            input_clock_active: inputClockActive,
            input_clock_timer_running: inputClockIdle.running,
            coalesced_events: Math.max(0, interactionState.inputEvents - interactionState.inputFlushes),
            rotation_seconds: interactionState.rotationElapsed,
            rotation_degrees_per_second: rotationDegreesPerSecond,
            pacing: "QtQuick.FrameAnimation"
        }
    }

    function resetInteractionDiagnostics() {
        interactionState.inputEvents = 0
        interactionState.cameraUpdates = 0
        interactionState.animationTicks = 0
        interactionState.inputFlushes = 0
    }

    function getRenderDiagnostics() {
        const stats = scene.renderStats
        let constantModels = 0
        for (let i = 0; i < surfaceModels.count; ++i) {
            const model = surfaceModels.objectAt(i)
            if (model && model.visible && model.usesConstantUnlit) constantModels++
        }
        return {
            render_path_request: renderPath,
            render_path_effective: effectiveRenderPath,
            scene_aa_request: antialiasing,
            scene_aa_policy: effectiveAntialiasing,
            aa_mode: aaMode,
            batched_root_markers: batchedRootMarkers,
            lightweight_centerlines: lightweightCenterlines,
            adaptive_interaction_aa: adaptiveInteractionAA,
            interaction_aa_active: interactionAAActive,
            camera_in_motion: cameraInMotion,
            context_shells_hidden: contextShellsHidden,
            xray_organs_motion_policy: hideXrayOrgansDuringMotion,
            related_branches_only: relatedBranchesOnly,
            interaction_aa_timer_running: interactionAARestore.running,
            scene_aa_effective: Number(scene.environment.antialiasingMode),
            viewport_size: [scene.width, scene.height],
            explicit_texture_size: [scene.explicitTextureWidth, scene.explicitTextureHeight],
            lighting_path: lightingPath,
            visible_constant_materials: constantModels,
            render_stats: {
                fps: stats.fps,
                frame_time_ms: stats.frameTime,
                sync_time_ms: stats.syncTime,
                render_prepare_time_ms: stats.renderPrepareTime,
                render_time_ms: stats.renderTime,
                max_frame_time_ms: stats.maxFrameTime,
                timing_kind: "Qt Quick 3D CPU-side statistics, not GPU hardware elapsed time"
            }
        }
    }

    function commitOrbitCounters() {
        if (interactionState.yawDelta === 0 && interactionState.pitchDelta === 0) return
        orbitUpdating = true
        yaw += interactionState.yawDelta
        pitch += interactionState.pitchDelta
        orbitUpdating = false
        interactionState.yawDelta = 0
        interactionState.pitchDelta = 0
    }

    function resetCamera() {
        stopInputClock()
        flushPendingInput()
        stopRotationBenchmark()
        restoreInteractionDetail()
        commitOrbitCounters()
        orbitUpdating = true
        yaw = 0; pitch = 0
        orbitUpdating = false
        orbitRotation = Qt.quaternion(1, 0, 0, 0)
        panX = 0; panY = 0; panZ = 0; distance = 260
        fitVisible()
    }

    function fitVisible() {
        flushPendingInput()
        commitOrbitCounters()
        stopRotationBenchmark()
        restoreInteractionDetail()
        focusZoomActive = false
        focusZoomRestoreDistance = -1
        var low = [Infinity, Infinity, Infinity]
        var high = [-Infinity, -Infinity, -Infinity]
        var count = 0
        stlViewer.rows.forEach(function(row) {
            if (!row.visible || row.opacity <= 0) return
            var a = row.boundsMin
            var b = row.boundsMax
            var mirrored = root.planning && root.plannerController.mirrorActive === true
                && root.plannerController.lungFiles.some(function(name) { return name.split('/').pop() === row.name })
            var minimum = [mirrored ? root.plannerController.mirrorOffset - b.x : a.x, a.y, a.z]
            var maximum = [mirrored ? root.plannerController.mirrorOffset - a.x : b.x, b.y, b.z]
            for (var axis = 0; axis < 3; axis++) {
                low[axis] = Math.min(low[axis], minimum[axis])
                high[axis] = Math.max(high[axis], maximum[axis])
            }
            count++
        })
        if (count === 0) return
        panX = (low[0] + high[0]) / 2
        panY = (low[1] + high[1]) / 2
        panZ = (low[2] + high[2]) / 2
        var radius = Math.sqrt(Math.pow(high[0] - low[0], 2)
            + Math.pow(high[1] - low[1], 2) + Math.pow(high[2] - low[2], 2)) / 2
        var verticalHalf = viewCamera.fieldOfView * Math.PI / 360
        var horizontalHalf = Math.atan(Math.tan(verticalHalf) * Math.max(1, scene.width) / Math.max(1, scene.height))
        distance = Math.max(minimumCameraDistance, Math.min(maximumCameraDistance, radius * 1.08 / Math.sin(Math.min(verticalHalf, horizontalHalf))))
        interactionLodFitDistance = distance
    }

    function stopRotationBenchmark() {
        if (!benchmarkSpinning) return
        benchmarkSpinning = false
        commitOrbitCounters()
        benchmark.endRotation()
        interactionLodRestore.restart()
    }

    function multiplyRotation(a, b) {
        const scalar = a.scalar * b.scalar - a.x * b.x - a.y * b.y - a.z * b.z
        const x = a.scalar * b.x + a.x * b.scalar + a.y * b.z - a.z * b.y
        const y = a.scalar * b.y - a.x * b.z + a.y * b.scalar + a.z * b.x
        const z = a.scalar * b.z + a.x * b.y - a.y * b.x + a.z * b.scalar
        const length = Math.sqrt(scalar * scalar + x * x + y * y + z * z)
        return Qt.quaternion(scalar / length, x / length, y / length, z / length)
    }

    function rotationAround(x, y, z, degrees) {
        const half = degrees * Math.PI / 360
        const sine = Math.sin(half)
        return Qt.quaternion(Math.cos(half), x * sine, y * sine, z * sine)
    }

    function syncOrbitPreset() {
        orbitRotation = multiplyRotation(rotationAround(0, 1, 0, yaw), rotationAround(1, 0, 0, pitch))
    }

    function orbitDegrees(horizontal, vertical, deferCounters) {
        const angle = Math.sqrt(horizontal * horizontal + vertical * vertical)
        if (angle === 0) return
        markInteractionMotion()
        // Right multiplication applies the increment around the camera's own
        // screen axes. Passing over the poles or the back never changes input
        // direction and never clamps or reconstructs the accumulated attitude.
        const increment = rotationAround(vertical / angle, horizontal / angle, 0, angle)
        orbitRotation = multiplyRotation(orbitRotation, increment)
        interactionState.cameraUpdates++
        interactionState.yawDelta += horizontal
        interactionState.pitchDelta += vertical
        if (!deferCounters) commitOrbitCounters()
    }

    function rotate(dx, dy) {
        // Equal drags as a fraction of the viewport produce equal rotations.
        const degreesPerPixel = 270 / Math.max(1, Math.min(scene.width, scene.height))
        // Treat dragging as grabbing the front of the model: the camera orbits
        // in the opposite direction so the visible surface follows the mouse.
        orbitDegrees(-dx * degreesPerPixel, -dy * degreesPerPixel)
    }

    function pan(dx, dy) {
        if (dx === 0 && dy === 0) return
        markInteractionMotion()
        // Move both camera and focal point along the current screen axes.
        // Matching the perspective scale at the focal plane makes the model
        // follow the mouse by the same number of pixels at every zoom level.
        const unitsPerPixel = 2 * distance * Math.tan(viewCamera.fieldOfView * Math.PI / 360)
            / Math.max(1, scene.height)
        const right = cameraRig.mapDirectionToScene(Qt.vector3d(1, 0, 0))
        const up = cameraRig.mapDirectionToScene(Qt.vector3d(0, 1, 0))
        const horizontal = -dx * unitsPerPixel
        const vertical = dy * unitsPerPixel
        panX += right.x * horizontal + up.x * vertical
        panY += right.y * horizontal + up.y * vertical
        panZ += right.z * horizontal + up.z * vertical
        interactionState.cameraUpdates++
    }

    function frontReferencePoint(radius) {
        // Useful for projection diagnostics: a point along the current view
        // normal, rather than a fixed world point which may be behind the model.
        const towardCamera = cameraRig.mapDirectionToScene(Qt.vector3d(0, 0, 1))
        return Qt.vector3d(panX + towardCamera.x * radius,
            panY + towardCamera.y * radius, panZ + towardCamera.z * radius)
    }

    function zoomBySteps(steps) {
        if (!isFinite(steps) || steps === 0) return
        // Opposite scrolls are exact inverses unless the distance hits a limit.
        const nextDistance = Math.max(minimumCameraDistance, Math.min(maximumCameraDistance, distance * Math.pow(0.9, steps)))
        if (nextDistance === distance) return
        distance = nextDistance
        markInteractionMotion()
        interactionState.cameraUpdates++
    }

    function zoomByFactor(factor) {
        if (!isFinite(factor) || factor <= 0) return
        flushPendingInput()
        zoomBySteps(Math.log(factor) / -Math.log(0.9))
    }

    function applyFocusZoom() {
        if (focusZoomActive || !isFinite(distance) || focusZoomFactor <= 1) return
        focusZoomRestoreDistance = distance
        zoomByFactor(focusZoomFactor)
        focusZoomActive = true
    }

    function restoreFocusZoom() {
        if (!focusZoomActive) return
        if (focusZoomRestoreDistance > 0) distance = focusZoomRestoreDistance
        focusZoomRestoreDistance = -1
        focusZoomActive = false
        interactionState.cameraUpdates++
    }

    function queueInput(dx, dy, mode) {
        if (dx === 0 && dy === 0) return
        if (continuousInputScheduling) {
            inputClockActive = true
            inputClockIdle.restart()
        }
        markInteractionMotion()
        interactionState.inputEvents++
        if (inputPending && interactionState.mode !== mode) flushPendingInput()
        interactionState.mode = mode
        if (mode === "rotate") {
            const degreesPerPixel = 270 / Math.max(1, Math.min(scene.width, scene.height))
            const horizontal = -dx * degreesPerPixel
            const vertical = -dy * degreesPerPixel
            const angle = Math.sqrt(horizontal * horizontal + vertical * vertical)
            // Preserve the order of camera-local rotations within a frame.
            // Simply summing dx/dy would lose a curved drag's small roll.
            const increment = rotationAround(vertical / angle, horizontal / angle, 0, angle)
            interactionState.pendingRotation = multiplyRotation(interactionState.pendingRotation, increment)
            interactionState.yawDelta += horizontal
            interactionState.pitchDelta += vertical
        } else {
            interactionState.dx += dx
            interactionState.dy += dy
        }
        inputPending = true
    }

    function flushPendingInput() {
        if (!inputPending) return
        inputPending = false
        interactionState.inputFlushes++
        if (interactionState.mode === "rotate") {
            orbitRotation = multiplyRotation(orbitRotation, interactionState.pendingRotation)
            interactionState.cameraUpdates++
        } else if (interactionState.mode === "pan") {
            pan(interactionState.dx, interactionState.dy)
        } else if (interactionState.mode === "zoom") {
            zoomBySteps(-interactionState.dy / 15)
        }
        interactionState.pendingRotation = Qt.quaternion(1, 0, 0, 0)
        interactionState.dx = 0
        interactionState.dy = 0
        interactionState.mode = ""
    }

    function finishInputGesture() {
        // Preserve the final mouse delta even when release precedes the next
        // animation frame. No tail motion is discarded.
        stopInputClock()
        commitOrbitCounters()
        benchmark.endRotation()
    }

    function zoomByWheel(angleDelta, pixelDelta) {
        const steps = pixelDelta !== 0 ? pixelDelta / 60 : angleDelta / 120
        zoomBySteps(steps)
    }

    Connections {
        target: stlViewer
        function onLoadStarted() {
            root.stopRotationBenchmark()
            root.restoreInteractionDetail()
            root.cameraResetPending = true
        }
        function onRowsChanged() {
            // Rows change on successful loading, not on visibility/color edits.
            // Page switches reparent this one view and retain the camera.
            if (root.cameraResetPending && stlViewer.triangleCount > 0) {
                root.cameraResetPending = false
                root.resetCamera()
            }
        }
    }

    Keys.onPressed: function(event) {
        flushPendingInput()
        commitOrbitCounters()
        if (event.key === Qt.Key_Left) orbitDegrees(6, 0)
        else if (event.key === Qt.Key_Right) orbitDegrees(-6, 0)
        else if (event.key === Qt.Key_Up) orbitDegrees(0, 6)
        else if (event.key === Qt.Key_Down) orbitDegrees(0, -6)
        else if (event.key === Qt.Key_Plus || event.key === Qt.Key_Equal) zoomBySteps(1)
        else if (event.key === Qt.Key_Minus) zoomBySteps(-1)
        else if (event.key === Qt.Key_R) resetCamera()
        else if (event.key === Qt.Key_F) fitVisible()
        else return
        stopRotationBenchmark()
        event.accepted = true
    }

    View3D {
        id: scene
        objectName: "stlView3D"
        renderMode: root.effectiveRenderPath === "inline" ? View3D.Inline : View3D.Offscreen
        anchors.fill: parent
        anchors.rightMargin: root.showLayers ? layers.width : 0
        explicitTextureWidth: typeof boardRenderScale !== "undefined" && boardRenderScale < 1
                              ? Math.max(1, Math.round(width * boardRenderScale)) : 0
        explicitTextureHeight: typeof boardRenderScale !== "undefined" && boardRenderScale < 1
                               ? Math.max(1, Math.round(height * boardRenderScale)) : 0
        environment: SceneEnvironment {
            backgroundMode: SceneEnvironment.Color
            clearColor: "#000000"
            antialiasingMode: root.effectiveAntialiasing === "ssaa" ? SceneEnvironment.SSAA
                : (root.effectiveAntialiasing === "msaa" && root.msaaSamples > 0 ? SceneEnvironment.MSAA : SceneEnvironment.NoAA)
            // SSAA Medium renders at 1.2x each native dimension, then downsamples.
            antialiasingQuality: root.effectiveAntialiasing === "ssaa" ? SceneEnvironment.Medium
                : root.msaaSamples >= 8 ? SceneEnvironment.VeryHigh
                : (root.msaaSamples >= 4 ? SceneEnvironment.High : SceneEnvironment.Medium)
            temporalAAEnabled: false
        }
        camera: viewCamera

        Node {
            id: cameraTarget
            position: Qt.vector3d(root.panX, root.panY, root.panZ)
            Node {
                rotation: root.coordinateConvention === 1 ? Qt.quaternion(Math.SQRT1_2, Math.SQRT1_2, 0, 0)
                    : (root.coordinateConvention === 2 ? Qt.quaternion(0, 0, Math.SQRT1_2, Math.SQRT1_2)
                        : Qt.quaternion(1, 0, 0, 0))
                Node {
                    id: cameraRig
                    rotation: root.orbitRotation
                    PerspectiveCamera { id: viewCamera; z: root.distance; clipFar: 5000; clipNear: 1; fieldOfView: 60; fieldOfViewOrientation: PerspectiveCamera.Vertical }
                }
            }
        }
        DirectionalLight { id: keyLight; objectName: "stlKeyLight"; eulerRotation.x: -35; eulerRotation.y: -35; brightness: 1.2 }
        DirectionalLight { id: fillLight; objectName: "stlFillLight"; visible: !root.diagnosticDisableSecondLight; eulerRotation.x: 40; eulerRotation.y: 140; brightness: 0.5 }

        Repeater3D {
            id: surfaceModels
            model: stlViewer.rows
            delegate: Model {
                required property var modelData
                readonly property bool mirrored: root.planning && root.plannerController.mirrorActive === true
                    && root.plannerController.lungFiles.some(function(name) { return name.split('/').pop() === modelData.name })
                objectName: "stlSurface:" + modelData.name
                // Keep each geometry attached to one model for its lifetime.
                // Replacing geometry on a live transparent model can leave the
                // mesh absent even though QML still reports it as visible.
                geometry: modelData.geometry
                visible: modelData.visible && modelData.opacity > 0
                    && !(root.contextShellsHidden && root.isMotionContextSurface(modelData))
                    && !(root.diagnosticHideVesselSurfaces && /arter|vein|venous|bronch|血管|动脉|静脉|气管/i.test(modelData.name))
                    && !(root.interactionLodActive && modelData.hasInteractionLod && modelData.opacity < 0.5)
                scale: Qt.vector3d(mirrored ? -1 : 1, 1, 1)
                x: mirrored ? root.plannerController.mirrorOffset : 0
                // Only the board's already-unlit shells have constant color.
                // Opaque/lit/plan materials keep the reference shading path.
                readonly property bool usesConstantUnlit: root.lightingPath === "constant" && !root.planning
                    && typeof boardMode !== "undefined" && boardMode && modelData.opacity < 0.5
                // Lobectomy target: shown in the resection colour on the planning page only.
                readonly property bool resectedLobe: root.planning && root.plannerController.resectionLobeNames !== undefined
                    && root.plannerController.resectionLobeNames.indexOf(modelData.name) >= 0
                materials: usesConstantUnlit ? constantMaterial : referenceMaterial
                C.FlatUnlitMaterial {
                    id: constantMaterial
                    surfaceColor: modelData.color
                    surfaceOpacity: modelData.opacity
                }
                DefaultMaterial {
                    id: referenceMaterial
                    diffuseColor: resectedLobe ? "#e0605a" : modelData.color
                    opacity: resectedLobe && stlViewer.manualOpacityNames.indexOf(modelData.name) < 0
                        ? Math.max(modelData.opacity, 0.45)
                        : stlViewer.manualOpacityNames.indexOf(modelData.name) < 0
                        && ((root.branchOverlay && root.branchAnalysis.xray)
                        || (root.planning && root.plannerController.lesionPreviewVisible))
                        ? Math.min(modelData.opacity, 0.14) : modelData.opacity
                    cullMode: Material.NoCulling
                    lighting: typeof boardMode !== "undefined" && boardMode && modelData.opacity < 0.5
                        ? DefaultMaterial.NoLighting : DefaultMaterial.FragmentLighting
                }
            }
        }
        Repeater3D {
            model: stlViewer.rows.filter(function(row) { return row.hasInteractionLod })
            delegate: Model {
                required property var modelData
                geometry: modelData.interactionGeometry
                objectName: "stlInteractionSurface:" + modelData.name
                visible: modelData.visible && modelData.opacity > 0 && !root.contextShellsHidden && root.interactionLodActive && modelData.opacity < 0.5
                materials: DefaultMaterial {
                    diffuseColor: modelData.color
                    opacity: modelData.opacity
                    cullMode: Material.NoCulling
                    lighting: typeof boardMode !== "undefined" && boardMode && modelData.opacity < 0.5
                        ? DefaultMaterial.NoLighting : DefaultMaterial.FragmentLighting
                }
            }
        }
        Repeater3D {
            model: root.branchAnalysis !== null && root.branchAnalysis.ready ? [
                { geometry: root.branchAnalysis.arteryGeometry, color: "#ff6472" },
                { geometry: root.branchAnalysis.veinGeometry, color: "#55baff" },
                { geometry: root.branchAnalysis.airwayGeometry, color: "#7de5ab" },
                { geometry: root.branchAnalysis.nearGeometry, color: "#ffc857", relation: true },
                { geometry: root.branchAnalysis.removedGeometry, color: "#ff343d", relation: true },
                { geometry: root.branchAnalysis.selectedGeometry, color: "#fff3b0" }
            ] : []
            delegate: Model {
                required property var modelData
                required property int index
                geometry: modelData.geometry
                objectName: "centerlineOverlay:" + index
                visible: root.branchOverlay && !root.diagnosticHideCenterlines && !root.diagnosticUseCompactCenterlines
                    && !(index < 3 && root.lightweightCenterlines && sceneDisplay.ready)
                    && (!root.relatedBranchesOnly || index >= 3)
                    && (index !== 5 || root.branchAnalysis.selectedBranch !== "")
                    && (!modelData.relation || root.branchAnalysis.planCurrent)
                depthBias: -0.03
                materials: DefaultMaterial {
                    diffuseColor: modelData.color
                    lighting: DefaultMaterial.NoLighting
                    cullMode: Material.NoCulling
                }
            }
        }
        // Fixed attachments: rebinding geometry on Mali/Qt 6.7 can lose the
        // original mesh after switching back. Toggle model visibility instead.
        Repeater3D {
            model: root.diagnosticCenterlineGeometries
                ? root.diagnosticCenterlineGeometries : []
            delegate: Model {
                required property var modelData
                required property int index
                geometry: modelData
                visible: root.branchOverlay && !root.diagnosticHideCenterlines && root.diagnosticUseCompactCenterlines
                    && (!root.relatedBranchesOnly || index >= 3)
                    && (index !== 5 || root.branchAnalysis.selectedBranch !== "")
                    && (!(index === 3 || index === 4) || root.branchAnalysis.planCurrent)
                depthBias: -0.03
                materials: DefaultMaterial {
                    diffuseColor: ["#ff6472", "#55baff", "#7de5ab", "#ffc857", "#ff343d", "#fff3b0"][index]
                    lighting: DefaultMaterial.NoLighting
                    cullMode: Material.NoCulling
                }
            }
        }
        Repeater3D {
            model: typeof sceneDisplay !== "undefined" ? sceneDisplay.lineGeometries : []
            delegate: Model {
                required property var modelData
                required property int index
                geometry: modelData
                visible: root.branchOverlay && root.lightweightCenterlines && sceneDisplay.ready
                    && !root.diagnosticHideCenterlines && !root.relatedBranchesOnly && !root.diagnosticUseCompactCenterlines
                depthBias: -0.03
                materials: DefaultMaterial {
                    diffuseColor: ["#ff6472", "#55baff", "#7de5ab"][index]
                    lighting: DefaultMaterial.NoLighting
                    cullMode: Material.NoCulling
                }
            }
        }
        Model {
            objectName: "batchedRootMarkers"
            geometry: typeof sceneDisplay !== "undefined" ? sceneDisplay.rootGeometry : null
            visible: root.branchOverlay && root.batchedRootMarkers && !root.diagnosticHideRootMarkers && !root.relatedBranchesOnly
            materials: DefaultMaterial { diffuseColor: "#ffd56b"; lighting: DefaultMaterial.NoLighting }
        }
        Repeater3D {
            objectName: "centerlineRootMarkers"
            model: root.branchAnalysis !== null ? root.branchAnalysis.rootPoints : []
            delegate: Model {
                required property var modelData
                source: "#Sphere"
                visible: root.branchOverlay && !root.batchedRootMarkers && !root.diagnosticHideRootMarkers && !root.relatedBranchesOnly
                position: modelData.point
                scale: Qt.vector3d(0.017, 0.017, 0.017)
                materials: DefaultMaterial { diffuseColor: "#ffd56b"; lighting: DefaultMaterial.NoLighting }
            }
        }
        Repeater3D {
            model: root.branchAnalysis !== null ? root.branchAnalysis.rootCandidatePoints : []
            delegate: Model {
                required property vector3d modelData
                source: "#Sphere"; position: modelData
                visible: root.branchOverlay && !root.diagnosticHideRootMarkers
                scale: Qt.vector3d(0.028, 0.028, 0.028)
                materials: DefaultMaterial { diffuseColor: "#ffffff"; lighting: DefaultMaterial.NoLighting }
            }
        }
        Repeater3D {
            model: root.branchAnalysis !== null ? root.branchAnalysis.cutPoints : []
            delegate: Model {
                required property vector3d modelData
                source: "#Sphere"; position: modelData
                visible: root.branchOverlay
                scale: Qt.vector3d(0.014, 0.014, 0.014)
                materials: DefaultMaterial { diffuseColor: "#ff343d"; lighting: DefaultMaterial.NoLighting }
            }
        }
        Model {
            objectName: "planningLesionPreviewModel"
            visible: root.planning && root.plannerController.lesionPreviewVisible
            geometry: root.geometryPlanner ? root.geometryPlanner.lesionPreviewGeometry : null
            depthBias: -0.07
            materials: DefaultMaterial {
                diffuseColor: "#fff36c"; opacity: 0.95
                cullMode: Material.NoCulling; lighting: DefaultMaterial.NoLighting
            }
        }
        Model {
            objectName: "planningTetraModel"
            visible: root.planning && root.plannerController.hasPlan && root.plannerController.planningModel !== "plane_wedge" && !root.interiorPathOnly && !root.diagnosticHideWedge
            geometry: root.geometryPlanner ? root.geometryPlanner.tetraGeometry : null
            materials: DefaultMaterial { diffuseColor: "#28dcb9"; opacity: 0.22; cullMode: Material.NoCulling; lighting: DefaultMaterial.NoLighting }
        }
        Model {
            objectName: "planningSurfaceModel"
            visible: root.planning && root.plannerController.hasPlan && root.plannerController.planningSurfaceVisible && !root.diagnosticHideWedge
            geometry: root.geometryPlanner ? root.geometryPlanner.surfaceGeometry : null
            materials: DefaultMaterial { diffuseColor: "#ffd56b"; opacity: 0.92; cullMode: Material.NoCulling; lighting: DefaultMaterial.NoLighting }
        }
        Model {
            objectName: "planningEdgesModel"
            visible: root.planning && root.plannerController.hasPlan && root.plannerController.planningModel !== "plane_wedge" && !root.interiorPathOnly && !root.diagnosticHideWedge
            geometry: root.geometryPlanner ? root.geometryPlanner.edgeGeometry : null
            depthBias: -0.01
            materials: DefaultMaterial { diffuseColor: "#4ef5ce"; lighting: DefaultMaterial.NoLighting }
        }
        Model {
            objectName: "planningPathModel"
            visible: root.planning && root.plannerController.hasPlan && (root.interiorPathOnly || root.plannerController.planningModel === "plane_wedge") && !root.diagnosticHideWedge
            geometry: root.geometryPlanner ? root.geometryPlanner.pathGeometry : null
            depthBias: -0.02
            materials: DefaultMaterial { diffuseColor: "#4ef5ce"; lighting: DefaultMaterial.NoLighting }
        }
        Model {
            objectName: "planningInteriorTetraModel"
            visible: root.planning && root.plannerController.hasPlan && (root.interiorPathOnly || root.plannerController.planningModel === "plane_wedge") && !root.diagnosticHideWedge
            geometry: root.geometryPlanner ? root.geometryPlanner.interiorTetraGeometry : null
            materials: DefaultMaterial { diffuseColor: "#28dcb9"; opacity: 0.34; cullMode: Material.NoCulling; lighting: DefaultMaterial.FragmentLighting }
        }
    }

    Item {
        anchors.fill: scene
        z: 2
        visible: root.planning
        Repeater {
            model: root.planning && root.plannerController.hasPlan && root.plannerController.vertexHandlesAvailable ? 4 : 0
            delegate: Rectangle {
                id: vertexHandle
                objectName: "planVertex" + index
                required property int index
                readonly property vector3d projected: root.projectVertex(root.plannerController.sceneVertices[index])
                x: projected.x - width / 2; y: projected.y - height / 2
                width: 22; height: 22; radius: 11
                visible: projected.z > 0
                color: index < 3 ? Theme.viewerAccent : "#f19c64"
                border.width: 2; border.color: "white"
                Text { anchors.centerIn: parent; text: vertexHandle.index < 3 ? "B" + (vertexHandle.index + 1) : "A"; color: Theme.viewerBar; font.pixelSize: 10; font.bold: true }
            }
        }
        // Capture on a stationary surface. A moving handle MouseArea can
        // emit position changes solely because its own projected parent moved.
        MouseArea {
            id: vertexInputArea
            objectName: "planVertexInputArea"
            anchors.fill: parent
            acceptedButtons: Qt.LeftButton
            enabled: root.planning && root.plannerController.hasPlan && root.plannerController.geometryCurrent && root.plannerController.vertexHandlesAvailable
            preventStealing: true
            onPressed: function(mouse) {
                var hit = -1
                var best = 16 * 16
                for (var i = 0; i < 3; ++i) {
                    var p = root.projectVertex(root.plannerController.sceneVertices[i])
                    var d = (p.x-mouse.x)*(p.x-mouse.x) + (p.y-mouse.y)*(p.y-mouse.y)
                    if (p.z > 0 && d <= best) { best = d; hit = i }
                }
                var position = Qt.point(mouse.x, mouse.y)
                if (hit >= 0) {
                    root.finishInputGesture()
                    root.stopRotationBenchmark()
                }
                if (hit < 0 || !root.plannerController.beginVertexDrag(hit,
                        root.vertexRay(position, 1), root.vertexRay(position, 2000))) {
                    mouse.accepted = false
                    return
                }
                root.editingVertex = hit
                root.forceActiveFocus()
                root.sceneActivated()
                root.beginInteractionAA()
            }
            onPositionChanged: function(mouse) {
                if (!pressed || root.editingVertex < 0) return
                root.vertexInputPosition = Qt.point(mouse.x, mouse.y)
                root.vertexInputPending = true
            }
            onReleased: function(mouse) {
                if (root.editingVertex >= 0) {
                    root.vertexInputPosition = Qt.point(mouse.x, mouse.y)
                    root.vertexInputPending = true
                    root.endVertexInput()
                }
            }
            onCanceled: root.endVertexInput()
            onPressedChanged: {
                // pressedChanged may precede released. Let released flush
                // the final position before using this lost-grab fallback.
                if (!pressed && root.editingVertex >= 0) {
                    var gesture = root.editingVertex
                    Qt.callLater(function() {
                        if (!vertexInputArea.pressed && root.editingVertex === gesture)
                            root.endVertexInput()
                    })
                }
            }
            onPressAndHold: function(mouse) { mouse.accepted = false }
        }
    }

    MouseArea {
        objectName: "stlInteractionArea"
        anchors.fill: scene
        acceptedButtons: Qt.LeftButton | Qt.MiddleButton | Qt.RightButton
        property real lastX: 0
        property real lastY: 0
        onPressed: function(mouse) {
            root.finishInputGesture()
            root.stopRotationBenchmark()
            root.forceActiveFocus(); root.sceneActivated(); lastX = mouse.x; lastY = mouse.y
            if (mouse.button === Qt.LeftButton && !(mouse.modifiers & Qt.ShiftModifier)
                    && stlViewer.triangleCount > 0) benchmark.beginRotation()
        }
        onReleased: { root.finishInputGesture(); shellMotionRestore.restart(); root.endInteractionAA() }
        onCanceled: { root.finishInputGesture(); shellMotionRestore.restart(); root.endInteractionAA() }
        onPositionChanged: function(mouse) {
            if (!pressed) return
            const dx = mouse.x - lastX
            const dy = mouse.y - lastY
            if (dx !== 0 || dy !== 0) { shellMotionRestore.stop(); root.shellDragActive = true; root.beginInteractionAA() }
            if (pressedButtons & Qt.RightButton) root.queueInput(dx, dy, "zoom")
            else if ((pressedButtons & Qt.MiddleButton) || (mouse.modifiers & Qt.ShiftModifier)) {
                root.queueInput(dx, dy, "pan")
            } else root.queueInput(dx, dy, "rotate")
            lastX = mouse.x; lastY = mouse.y
        }
        onDoubleClicked: {
            if (root.adaptiveInteractionAA) root.interactionAAEvent("double-click")
            if (root.navigateOnDoubleClick) root.openReconstruction()
            else root.resetCamera()
        }
        onWheel: function(wheel) {
            root.flushPendingInput()
            if (wheel.angleDelta.y !== 0 || wheel.pixelDelta.y !== 0) root.stopRotationBenchmark()
            if (wheel.angleDelta.y !== 0 || wheel.pixelDelta.y !== 0) {
                root.wheelMotionActive = true
                wheelMotionRestore.restart()
                root.beginInteractionAA()
                root.endInteractionAA()
            }
            root.zoomByWheel(wheel.angleDelta.y, wheel.pixelDelta.y)
            wheel.accepted = true
        }
    }

    ColumnLayout {
        id: layers
        visible: root.showLayers
        width: Math.min(190, root.width * 0.38)
        anchors.top: parent.top
        anchors.bottom: parent.bottom
        anchors.right: parent.right
        spacing: 0
        Rectangle {
            Layout.fillWidth: true; Layout.preferredHeight: 37
            color: Theme.viewerBar
            RowLayout {
                anchors.fill: parent; anchors.leftMargin: 7; anchors.rightMargin: 7
                Text { text: "3D 结构"; color: "#edf4f5"; font.pixelSize: 12; Layout.fillWidth: true }
                Button {
                    text: "加载"; implicitWidth: 48; implicitHeight: 25
                    onClicked: stlViewer.chooseDirectory()
                    ToolTip.visible: hovered; ToolTip.text: "加载 STL 文件夹"
                }
                Button {
                    text: "测帧"; implicitWidth: 48; implicitHeight: 25
                    enabled: stlViewer.triangleCount > 0 && !root.benchmarkSpinning
                    onClicked: root.runRotationBenchmark()
                    ToolTip.visible: hovered; ToolTip.text: "固定 300 次角度更新，记录连续旋转帧间隔"
                }
            }
        }
        ScrollView {
            Layout.fillWidth: true; Layout.fillHeight: true
            background: Rectangle { color: Theme.viewerBar }
            ListView {
                id: modelList
                model: stlViewer.rows
                spacing: 1
                delegate: Column {
                    id: layerItem
                    required property var modelData
                    required property int index
                    width: modelList.width - 12
                    spacing: 3
                    padding: 4
                    RowLayout {
                        width: parent.width - 10
                        CheckBox {
                            checked: layerItem.modelData.visible
                            onToggled: stlViewer.setVisible(layerItem.index, checked)
                            implicitWidth: 27
                        }
                        Text { text: layerItem.modelData.name; color: "#edf4f5"; font.pixelSize: 11; elide: Text.ElideRight; Layout.fillWidth: true }
                        Button {
                            id: colorButton
                            implicitWidth: 22; implicitHeight: 22
                            onClicked: stlViewer.chooseColor(layerItem.index)
                            background: Rectangle { color: layerItem.modelData.color; border.color: "#73848c"; radius: 2 }
                            ToolTip.visible: hovered; ToolTip.text: "更改颜色"
                        }
                    }
                    Slider {
                        id: layerOpacitySlider
                        width: parent.width - 10
                        from: 0.0; to: 1.0
                        value: layerItem.modelData.opacity
                        onMoved: stlViewer.setOpacity(layerItem.index, value)
                        background: Rectangle {
                            x: layerOpacitySlider.leftPadding; y: layerOpacitySlider.topPadding + layerOpacitySlider.availableHeight / 2 - height / 2
                            width: layerOpacitySlider.availableWidth; height: 3; color: Theme.viewerStroke
                            Rectangle { width: parent.width * layerItem.modelData.opacity; height: parent.height; color: Theme.viewerAccent }
                        }
                        handle: Rectangle { x: layerOpacitySlider.leftPadding + layerOpacitySlider.visualPosition * (layerOpacitySlider.availableWidth - width); y: layerOpacitySlider.topPadding + layerOpacitySlider.availableHeight / 2 - height / 2; width: 10; height: 10; radius: 5; color: "#edf4f5" }
                    }
                }
            }
        }
        Text {
            Layout.fillWidth: true; Layout.preferredHeight: 35
            text: stlViewer.status
            color: "#91a1aa"; font.pixelSize: 11
            wrapMode: Text.Wrap; leftPadding: 7
            verticalAlignment: Text.AlignVCenter
        }
    }

    Rectangle {
        anchors.left: parent.left; anchors.right: parent.right; anchors.top: parent.top; anchors.margins: 1
        visible: root.showTitle
        height: 36; color: Theme.viewerBar
        RowLayout {
            anchors.fill: parent; anchors.leftMargin: 10; anchors.rightMargin: 8; spacing: 8
            Icon { name: "box"; inverse: true; size: 13; opacity: 0.82 }
            Text { text: root.planning ? "手术路径规划 / 3D" : "三维模型 / 3D"; color: Theme.viewerText; font.pixelSize: 11; Layout.fillWidth: true }
            ComboBox {
                objectName: "interactionAAButton"
                visible: false
                model: ["SSAA：常开", "SSAA：拖动关", "SSAA：常关"]
                currentIndex: ["on", "drag", "off"].indexOf(root.aaMode)
                implicitWidth: 138
                implicitHeight: 28
                onActivated: sceneDisplay.setAAMode(["on", "drag", "off"][currentIndex])
                contentItem: Text { text: parent.displayText; color: "#ffffff"; verticalAlignment: Text.AlignVCenter; leftPadding: 8; font.pixelSize: 11 }
                background: Rectangle { color: Theme.viewerField; radius: 14; border.color: Theme.viewerStroke }
            }
            C.AppButton {
                visible: false
                text: root.lightweightCenterlines ? "中心线：轻量" : "中心线：标准"
                onDark: true
                implicitHeight: 28
                tip: "轻量采用四棱管，完整分支与选中/切除高亮不裁减；标准采用六棱管"
                onClicked: root.lightweightCenterlines = !root.lightweightCenterlines
            }
            C.AppButton {
                objectName: "relatedBranchesOnlyButton"
                visible: false
                text: root.relatedBranchesOnly ? "分支：相关" : "分支：全部"
                onDark: true
                implicitHeight: 28
                tip: "相关模式仅显示邻近/切除中心线及选中分支，隐藏普通根部标记；完整数据及列表保留"
                onClicked: root.relatedBranchesOnly = !root.relatedBranchesOnly
            }
            C.AppButton {
                objectName: "returnFocus3DButton"
                visible: root.focusMode
                text: "返回工作站"
                iconName: "arrow-left"
                onDark: true
                tip: "退出专注三维（Esc）"
                implicitHeight: 28
                onClicked: root.returnToWorkspace()
            }
            ComboBox {
                id: orientationSelector
                objectName: "stlCoordinateConvention"
                visible: false
                implicitWidth: 110; implicitHeight: 28
                model: ["原始轴视图", "LPS 正面", "RAS 正面"]
                currentIndex: root.coordinateConvention
                onActivated: { root.coordinateConvention = currentIndex; root.resetCamera() }
                palette.text: Theme.viewerText; palette.buttonText: Theme.viewerText; palette.base: Theme.viewerField; palette.button: Theme.viewerControl
                palette.highlight: Theme.viewerBarSelected; palette.highlightedText: Theme.viewerText
                ToolTip.visible: hovered
                ToolTip.text: "STL 不带可靠方向信息；仅在确认坐标约定后选 LPS/RAS，模型坐标不变"
            }
            C.ToolButton { iconName: "maximize-2"; tip: "适配可见结构（F），保留观察角度"; inverseIcon: true; iconColor: Theme.viewerText; implicitWidth: 26; implicitHeight: 26; onClicked: root.fitVisible() }
            C.AppButton {
                objectName: "focusZoom2xButton"
                visible: root.focusMode
                text: root.focusZoomActive ? "恢复比例" : "放大 2 倍"
                iconName: "zoom-in"
                onDark: true
                tip: root.focusZoomActive ? "恢复进入专注三维前的比例" : "将当前观察放大两倍；仍可滚轮缩放或按 F 适配"
                implicitHeight: 28
                onClicked: root.focusZoomActive ? root.restoreFocusZoom() : root.applyFocusZoom()
            }
            C.ToolButton { iconName: "rotate-ccw"; tip: "重置视角"; inverseIcon: true; iconColor: Theme.viewerText; implicitWidth: 26; implicitHeight: 26; onClicked: root.resetCamera() }
        }
    }
    Column {
        anchors.centerIn: scene; spacing: 10
        visible: stlViewer.triangleCount <= 0 && !stlViewer.busy
        Icon { name: "box"; inverse: true; size: 36; anchors.horizontalCenter: parent.horizontalCenter; opacity: 0.32 }
        Text { text: "未加载三维模型"; color: Theme.viewerMuted; font.pixelSize: 12; anchors.horizontalCenter: parent.horizontalCenter }
    }
    Text { anchors.left: scene.left; anchors.bottom: scene.bottom; anchors.margins: 12; text: stlViewer.rows.length + " 个结构  ·  " + stlViewer.triangleCountText + " 面"; color: Theme.viewerMuted; font.pixelSize: 10; visible: stlViewer.triangleCount > 0 }
}

