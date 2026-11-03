"""Slider drags must not re-evaluate result-bound QML; QML never receives timing lists."""
import os
import unittest
from unittest.mock import Mock, patch

import numpy as np

from PySide6.QtCore import QObject, Signal, QCoreApplication

from cas_frontend.planner import PlannerController


class Viewer(QObject):
    loadStarted = Signal()
    rowsChanged = Signal()
    statusChanged = Signal()
    sceneCenterMm = [0., 0., 0.]
    sceneScale = 1.
    busy = False


class DragUpdateTests(unittest.TestCase):
    @classmethod
    def setUpClass(cls):
        cls.app = QCoreApplication.instance() or QCoreApplication([])

    def setUp(self):
        with patch.dict(os.environ, CLOUD_BREATHING_PLANNER_BACKEND='cpu'):
            self.planner = PlannerController(Viewer())
        self.addCleanup(self.planner.shutdown)
        self.counts = dict(changed=0, parameters=0)
        self.planner.changed.connect(lambda: self.counts.__setitem__('changed', self.counts['changed'] + 1))
        self.planner.parametersChanged.connect(
            lambda: self.counts.__setitem__('parameters', self.counts['parameters'] + 1))

    def test_full_change_also_updates_parameter_bindings(self):
        self.planner.changed.emit()
        self.assertEqual(self.counts, dict(changed=1, parameters=1))

    def test_drag_steps_after_the_first_notify_only_parameters(self):
        self.planner.beginParameterEdit('yaw')
        self.planner._timer.stop()
        self.counts.update(changed=0, parameters=0)
        for value in (10., 11., 12., 13.):
            self.planner.setParameter('yaw', value)
        self.assertEqual(self.counts['changed'], 1)       # first step: status becomes "范围预览"
        self.assertEqual(self.counts['parameters'], 4)    # every step moves the slider/value text
        self.assertEqual(self.planner._params['yaw'], 13.)
        self.planner.endParameterEdit('yaw')
        self.planner._timer.stop()
        self.assertEqual(self.counts['changed'], 2)       # release refreshes everything once

    def test_status_change_during_a_drag_still_refreshes_everything(self):
        self.planner.beginParameterEdit('yaw')
        self.planner.setParameter('yaw', 10.)
        before = self.counts['changed']
        self.planner._preview_error = '当前参数无法生成切除范围预览：test'
        self.planner.setParameter('yaw', 11.)
        self.assertEqual(self.counts['changed'], before + 1)
        self.planner.endParameterEdit('yaw')
        self.planner._timer.stop()

    def wedge_drag(self):
        """A planner whose drags take the wedge-preview path with a fake case."""
        self.planner._params.update(planningModel='plane_wedge', wedgeAngle=90., cutTilts=[45., 45.])
        self.planner._preview_case = Mock(to_source_vertices=lambda v: v)
        self.planner._preview_timer = Mock(isActive=Mock(return_value=False))
        self.planner._interior = Mock()
        self.region = patch('cas_frontend.planning_models.build_region', return_value=np.zeros((4, 3)))
        self.region.start()
        self.addCleanup(self.region.stop)
        self.planner.beginParameterEdit('yaw')
        self.planner._interior.reset_mock()

    def test_continuous_drag_throttles_instead_of_restarting_the_preview_timer(self):
        self.wedge_drag()
        timer = self.planner._preview_timer
        self.planner.setParameter('yaw', 10.)
        self.assertEqual(timer.start.call_count, 1)
        timer.isActive.return_value = True          # the throttle interval is running
        for value in (11., 12., 13.):
            self.planner.setParameter('yaw', value)
        self.assertEqual(timer.start.call_count, 1)  # not restarted, so it still fires
        timer.isActive.return_value = False
        self.planner._preview_inflight = True       # a preview is computing
        self.planner.setParameter('yaw', 14.)
        self.assertEqual(timer.start.call_count, 1)  # completion starts the newest pose
        self.assertEqual(self.planner._preview_pending[0], self.planner._preview_generation)
        self.planner._preview_inflight = False
        self.planner._parameter_dragging = False

    def test_cut_face_stays_visible_until_the_next_preview_replaces_it(self):
        self.wedge_drag()
        for value in (10., 11., 12.):
            self.planner.setParameter('yaw', value)
        self.assertFalse(any(len(c.args[0]) == 0 for c in self.planner._interior.setMesh.call_args_list))
        self.planner._parameter_dragging = False

    def test_qml_result_omits_timing_lists_but_python_keeps_them(self):
        self.planner._result = dict(valid=True, resection_volume_cm3=2.5,
            search_candidate_timings=[dict(index=i) for i in range(780)],
            dual_plane_mesh_call_timings=[dict(calls=1)], full_validation_timings=[dict(ms=1.)],
            search_phase_timing=dict(total_ms=3.))
        exposed = self.planner.result
        self.assertEqual(exposed, dict(valid=True, resection_volume_cm3=2.5,
                                       search_phase_timing=dict(total_ms=3.)))
        self.assertEqual(len(self.planner._result['search_candidate_timings']), 780)


if __name__ == '__main__':
    unittest.main()
