"""Board build: the dual-plane wedge is the only planning model on both backends."""
import os
import unittest
from unittest.mock import patch

from PySide6.QtCore import QObject, Signal, QCoreApplication

from cas_frontend.planner import PlannerController
from cas_frontend.planning_models import MODELS


class Viewer(QObject):
    loadStarted = Signal()
    rowsChanged = Signal()
    statusChanged = Signal()
    sceneCenterMm = [0., 0., 0.]
    sceneScale = 1.
    busy = False


class BackendModelTests(unittest.TestCase):
    @classmethod
    def setUpClass(cls):
        cls.app = QCoreApplication.instance() or QCoreApplication([])

    def planner(self, backend):
        with patch.dict(os.environ, CLOUD_BREATHING_PLANNER_BACKEND=backend):
            planner = PlannerController(Viewer())
        self.addCleanup(planner.shutdown)
        return planner

    def test_only_the_dual_plane_wedge_remains(self):
        self.assertEqual(MODELS, ('plane_wedge',))
        self.assertFalse(hasattr(PlannerController, 'setPlanningModel'))

    def test_both_backends_start_on_the_dual_plane_wedge(self):
        for backend in ('pl', 'cpu'):
            planner = self.planner(backend)
            self.assertEqual(planner.executionBackend, backend)
            self.assertEqual(planner.planningModel, 'plane_wedge')
            self.assertEqual(planner._params['planningModel'], 'plane_wedge')
            self.assertEqual(planner._params['wedgeAngle'], 90.)
            self.assertEqual(planner._params['cutTilts'], [45., 45.])
            self.assertNotIn('cutAzimuths', planner._params)
            self.assertFalse(planner.vertexHandlesAvailable)

    def test_backend_switch_keeps_the_wedge_and_invalidates_the_result(self):
        planner = self.planner('pl')
        planner._result = dict(valid=True)
        planner.setExecutionBackend('cpu')
        self.assertEqual(planner.executionBackend, 'cpu')
        self.assertEqual(planner.planningModel, 'plane_wedge')
        self.assertEqual(planner._params['cutTilts'], [45., 45.])
        self.assertEqual(planner._result, {})
        planner.setExecutionBackend('pl')
        self.assertEqual(planner.executionBackend, 'pl')
        self.assertEqual(planner.planningModel, 'plane_wedge')

    def test_wedge_angle_sets_both_cut_tilts(self):
        planner = self.planner('cpu')
        planner.setParameter('wedgeAngle', 70.)
        self.assertEqual(planner._params['cutTilts'], [35., 35.])

    def test_busy_planner_ignores_backend_changes(self):
        planner = self.planner('pl')
        planner._busy = True
        planner.setExecutionBackend('cpu')
        self.assertEqual(planner.executionBackend, 'pl')
        self.assertEqual(planner.planningModel, 'plane_wedge')


if __name__ == '__main__':
    unittest.main()
