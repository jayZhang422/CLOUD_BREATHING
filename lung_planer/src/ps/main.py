"""Cloud Breathing Qt workstation entry point."""

import os
import math
import sys
import json
from pathlib import Path

from PySide6.QtCore import QUrl, QTimer
from PySide6.QtQml import QQmlApplicationEngine
from PySide6.QtQuickControls2 import QQuickStyle
from PySide6.QtWidgets import QApplication
from PySide6.QtGui import QIcon
from PySide6.QtQuick import QQuickGraphicsConfiguration

from cas_frontend.auth import SessionController
from cas_frontend.annotations import AnnotationStore
from cas_frontend.benchmark import BenchmarkRecorder
from cas_frontend.ct_importer import CtImporter
from cas_frontend.gpu import GpuMonitor
from cas_frontend.patients import PatientQueue
from cas_frontend.performance import PerformanceMonitor
from cas_frontend.stl_focus import FocusedStlViewer as StlViewer
from cas_frontend.interactive_planner import PlannerController
from cas_frontend.centerline_controller import CenterlineController
from cas_frontend.display_options import DisplayOptions
from cas_frontend.graphics import configure_board_graphics
from cas_frontend.graphics import requested_msaa_samples
from cas_frontend.graphics import requested_scene_antialiasing
from cas_frontend.resource_wall import ResourceWall
from cas_frontend.ui_dialogs import UiDialogs
from cas_frontend.decimation import DecimationController
from cas_frontend.ctfpga_controller import CtfpgaController


def main() -> int:
    os.environ.setdefault('CLOUD_BREATHING_SCENE_AA', 'none')
    configure_board_graphics()
    render_path = os.environ.get("CLOUD_BREATHING_RENDER_PATH", "offscreen").lower()
    inline_rendering = render_path == "inline" and requested_scene_antialiasing() == "none"
    QQuickStyle.setStyle("Basic")
    app = QApplication(sys.argv)
    direct_display = app.platformName() == "eglfs" or os.environ.get("CLOUD_BREATHING_SINGLE_WINDOW") == "1"
    app.setOrganizationName("云端呼吸系统")
    app.setApplicationName("云端呼吸 前端")
    app.setWindowIcon(QIcon(str(Path(__file__).parent / "qml/assets/cloud-breathing-mark.svg")))

    engine = QQmlApplicationEngine()
    dialogs = UiDialogs()
    engine.rootContext().setContextProperty("uiDialogs", dialogs)
    engine.rootContext().setContextProperty("singleWindowMode", direct_display)
    if inline_rendering:
        engine.setInitialProperties({"visible": False})
    controller = SessionController()
    annotations = AnnotationStore(Path(__file__).parent)
    engine.rootContext().setContextProperty("annotations", annotations)
    patient_queue = PatientQueue()
    importer = CtImporter(Path(__file__).parent)
    stl_viewer = StlViewer()
    decimation = DecimationController(Path(__file__).parent, stl_viewer, dialogs if direct_display else None)
    engine.rootContext().setContextProperty('stlDecimation', decimation)
    ctfpga = CtfpgaController(Path(__file__).parent, stl_viewer, importer, dialogs if direct_display else None)
    engine.rootContext().setContextProperty('ctfpga', ctfpga)
    planner = PlannerController(stl_viewer)
    importer.calibrationChanged.connect(planner.setCtCalibration)
    centerlines = CenterlineController(stl_viewer, planner, Path(__file__).parent)
    planner.centerlines = centerlines
    display_options = DisplayOptions(centerlines, stl_viewer)
    engine.rootContext().setContextProperty("sceneDisplay", display_options)
    engine.rootContext().setContextProperty("centerlines", centerlines)
    if direct_display:
        importer.dialogs = dialogs
        stl_viewer.dialogs = dialogs
        planner.dialogs = dialogs
    benchmark = BenchmarkRecorder(Path(__file__).parent, stl_viewer)
    # Explicit benchmark diagnostic; ordinary application startup keeps both
    # samplers enabled. This does not disable the GPU renderer or frame timing.
    resource_sampling = os.environ.get("CLOUD_BREATHING_PAUSE_RESOURCE_MONITORS", "0").lower() not in ("1", "true", "yes")
    performance_monitor = PerformanceMonitor(sampling_enabled=resource_sampling)
    gpu_monitor = GpuMonitor(sampling_enabled=resource_sampling)
    resource_wall = ResourceWall()
    engine.rootContext().setContextProperty("session", controller)
    engine.rootContext().setContextProperty("patientQueue", patient_queue)
    engine.rootContext().setContextProperty("ctImporter", importer)
    engine.rootContext().setContextProperty("stlViewer", stl_viewer)
    engine.rootContext().setContextProperty("planner", planner)
    engine.rootContext().setContextProperty("benchmark", benchmark)
    engine.rootContext().setContextProperty("performanceMonitor", performance_monitor)
    engine.rootContext().setContextProperty("gpuMonitor", gpu_monitor)
    engine.rootContext().setContextProperty("resourceWall", resource_wall)
    board_mode = os.environ.get("CLOUD_BREATHING_KV260", "0").lower() in ("1", "true", "yes")
    engine.rootContext().setContextProperty("boardMode", board_mode)
    engine.rootContext().setContextProperty("boardMsaaSamples", requested_msaa_samples())
    engine.rootContext().setContextProperty("sceneAntialiasing", requested_scene_antialiasing())
    engine.rootContext().setContextProperty("sceneRenderPath", render_path)
    # Keep the reference material selectable for matched visual/FPS checks.
    lighting_path = os.environ.get("CLOUD_BREATHING_STL_LIGHTING", "constant" if board_mode else "fragment")
    engine.rootContext().setContextProperty("sceneLightingPath", lighting_path if lighting_path in ("fragment", "constant") else "fragment")
    # Qt Quick 3D can render the View3D into a smaller GPU texture and scale
    # it to the window.  This mirrors the old Mali GLES2 viewer's internal FBO
    # strategy and keeps the board-side window responsive for large models.
    try:
        render_scale = max(0.25, min(1.0, float(os.environ.get("CLOUD_BREATHING_RENDER_SCALE", "1.0"))))
    except ValueError:
        render_scale = 1.0
    engine.rootContext().setContextProperty("boardRenderScale", render_scale)
    try:
        lod_minimum_zoom = float(os.environ.get("CLOUD_BREATHING_INTERACTION_LOD_MIN_ZOOM", "1.5"))
        if not math.isfinite(lod_minimum_zoom):
            raise ValueError("non-finite LOD zoom threshold")
        lod_minimum_zoom = max(1.0, min(8.0, lod_minimum_zoom))
    except ValueError:
        lod_minimum_zoom = 1.5
    engine.rootContext().setContextProperty("interactionLodMinimumZoom", lod_minimum_zoom)
    importer.imported.connect(patient_queue.refresh)
    stl_viewer.rowsChanged.connect(lambda: resource_wall.updateTriangles(stl_viewer.triangleCount))
    qml_path = Path(__file__).parent / "qml" / "Main.qml"
    engine.load(QUrl.fromLocalFile(str(qml_path.resolve())))
    if not engine.rootObjects():
        ctfpga.shutdown()
        decimation.shutdown()
        display_options.shutdown()
        centerlines.shutdown()
        planner.shutdown()
        importer.shutdown()
        stl_viewer.shutdown()
        gpu_monitor.shutdown()
        return 1
    benchmark.attach(engine.rootObjects()[0])
    # Optional local verification hook: open a named case and saved plan in
    # the real workstation UI without affecting the normal desktop entry.
    auto_case = os.environ.get('CLOUD_BREATHING_AUTO_CASE', '').strip()
    auto_plan = os.environ.get('CLOUD_BREATHING_AUTO_PLAN', '').strip()
    if auto_case and auto_plan:
        def open_saved_plan():
            try:
                root_window = engine.rootObjects()[0]
                controller.login('cloud', 'cloud2026')
                root_window.setProperty('appPage', 3)
                root_window.setProperty('active3D', True)
                saved = json.loads(Path(auto_plan).read_text(encoding='utf-8'))
                lung_files = list(saved.get('lung_files') or [])
                spacing = saved.get('ct_spacing_mm') or [0.714844, 0.714844, 0.714844]
                planner.setCtCalibration(dict(pixel_spacing_mm=[spacing[0], spacing[1]],
                                              slice_spacing_mm=1.25,
                                              source='desktop-auto-open'))
                def after_stl():
                    if not stl_viewer.busy and planner.ready:
                        if lung_files:
                            planner._lung = lung_files
                            planner._active_lung_files = list(lung_files)
                        planner.loadPlanFromPath(auto_plan)
                        print('AUTO_OPEN_PLAN_REQUESTED', auto_plan, flush=True)
                        def check_plan():
                            if not planner.busy and not planner.metricsPending and planner.hasPlan:
                                root_window.setTitle('云端呼吸 工作站 · 已加载规划结果一 · 双平面楔形')
                                print('AUTO_OPEN_PLAN_READY', planner.planningModel,
                                      planner.result.get('resection_volume_cm3'), flush=True)
                            else:
                                QTimer.singleShot(500, check_plan)
                        QTimer.singleShot(500, check_plan)
                    else:
                        QTimer.singleShot(250, after_stl)
                stl_viewer.loadDirectory(auto_case)
                QTimer.singleShot(250, after_stl)
            except Exception as exc:
                print('AUTO_OPEN_FAILED', exc, flush=True)
        QTimer.singleShot(0, open_saved_plan)
    if inline_rendering:
        # Configure the instance before its first presentation. This is an
        # explicit experiment, not the normal offscreen rendering default.
        graphics = QQuickGraphicsConfiguration()
        graphics.setDepthBufferFor2D(False)
        engine.rootObjects()[0].setGraphicsConfiguration(graphics)
        engine.rootObjects()[0].show()
    app.aboutToQuit.connect(importer.shutdown)
    app.aboutToQuit.connect(decimation.shutdown)
    app.aboutToQuit.connect(ctfpga.shutdown)
    app.aboutToQuit.connect(stl_viewer.shutdown)
    app.aboutToQuit.connect(planner.shutdown)
    app.aboutToQuit.connect(centerlines.shutdown)
    app.aboutToQuit.connect(display_options.shutdown)
    app.aboutToQuit.connect(gpu_monitor.shutdown)
    app.aboutToQuit.connect(resource_wall.restore_affinity)
    return app.exec()


if __name__ == "__main__":
    raise SystemExit(main())
