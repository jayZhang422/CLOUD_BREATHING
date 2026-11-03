"""Exercise original lesion/candidate switching with the branch controller."""
import json
import os
from pathlib import Path
import tempfile
import threading
from types import SimpleNamespace
import unittest
from unittest.mock import patch

import numpy as np
from PySide6.QtCore import QObject, Signal, QCoreApplication
from PySide6.QtTest import QTest, QSignalSpy

from cas_frontend.planner import PlannerController
from cas_frontend.centerline_controller import CenterlineController
from test_centerlines import tree_fixture, TETRA
from test_branch_analysis_pl import cube, cases


class Viewer(QObject):
    loadStarted = Signal()
    rowsChanged = Signal()
    statusChanged = Signal()
    sceneCenterMm = [0., 0., 0.]
    sceneScale = 1.
    busy = False


class Lung:
    def hits(self, origin, direction):
        # Synthetic lung contains all fixture branch segments.
        return np.asarray([100.])


class CenterlineMultiLesionTests(unittest.TestCase):
    @classmethod
    def setUpClass(cls):
        cls.app = QCoreApplication.instance() or QCoreApplication([])

    def setUp(self):
        self.folder = tempfile.TemporaryDirectory()
        self.addCleanup(self.folder.cleanup)
        self.viewer = Viewer()
        with patch.dict(os.environ, CLOUD_BREATHING_PLANNER_BACKEND='cpu'):
            self.planner = PlannerController(self.viewer)
        self.addCleanup(self.planner.shutdown)
        self.branches = CenterlineController(self.viewer, self.planner, self.folder.name)
        self.addCleanup(self.branches.shutdown)
        self.planner.centerlines = self.branches
        self.planner.setCtCalibration(dict(pixel_spacing_mm=[1., 1.], slice_spacing_mm=1.))
        tree = tree_fixture()
        tree.update(kind='airway', file='Bronchus.stl', cache_key='fixture',
                    source_sha256='synthetic', spacing_mm=.8)
        self.branches._trees = [tree]
        self.branches._update_roots()
        self.trees = self.branches._trees
        self.extractions = QSignalSpy(self.branches.request)
        empty = np.empty((0, 3, 3))
        params = dict(self.planner._params)

        def payload(vertices, lesion):
            return dict(vertices=vertices.copy(), params=dict(params),
                result=dict(valid=True, base_area_cm2=1., lesion_index=lesion,
                            lesion_volume_cm3=1., lesion_component_id=f'component-{lesion}'),
                planning_case_identity='a' * 64,
                points=np.zeros((1, 3)), case=SimpleNamespace(_cpu_index=Lung(), triangles=cube()),
                surface=empty, path=[], interior=empty)

        self.first = payload(TETRA, 1)
        self.second = payload(TETRA + 1000, 2)
        self.first['alternatives'] = [payload(TETRA, 1), payload(TETRA + 1000, 1)]
        self.planner._completed(dict(self.first, revision=self.planner._revision,
                                     lesion_plans=[self.first, self.second]))
        self.branches._refresh()
        self.wait_until(lambda: self.branches.planCurrent)
        self.assertGreater(self.branches.affectedCount, 0)

    def wait_until(self, predicate):
        for _ in range(250):
            if predicate():
                return
            QTest.qWait(10)
        self.fail('Timed out: ' + self.branches.analysisStatus)

    def test_lesion_switch_updates_relation_and_immediate_save(self):
        self.planner.selectLesion(1)
        QTest.qWait(250)
        self.assertEqual(self.branches.affectedCount, 0)
        self.assertEqual(self.branches.removedGeometry.vertexData().size(), 0)
        self.planner.selectLesion(0)
        target = Path(self.folder.name) / 'lesion1.json'
        self.planner.saveToPath(str(target))
        self.wait_until(target.exists)
        saved = json.loads(target.read_text(encoding='utf-8'))
        self.assertEqual(saved['schema'], 'cloud-breathing-plan-research-v1')
        self.assertEqual(saved['planning_case_identity'], 'a' * 64)
        self.assertEqual(saved['vertices_mm'], TETRA.tolist())
        self.assertTrue(saved['result']['valid'])
        self.assertEqual(saved['lesion_index'], 1)
        self.assertTrue(any(r['removed_length_mm'] > 0
            for t in saved['branch_analysis']['trees'] for r in t['rows']))
        self.assertIs(self.branches._trees, self.trees)
        self.assertEqual(self.extractions.count(), 0)

    def test_candidate_switch_exports_selected_candidate(self):
        self.planner.selectCandidate(1)
        target = Path(self.folder.name) / 'candidate2.json'
        self.planner.saveToPath(str(target))
        self.wait_until(target.exists)
        saved = json.loads(target.read_text(encoding='utf-8'))
        self.assertTrue(all(r['status'] == 'outside'
            for t in saved['branch_analysis']['trees'] for r in t['rows']))
        self.assertEqual(self.branches.affectedCount, 0)
        self.assertEqual(self.extractions.count(), 0)

    def test_union_view_and_bundle_keep_candidate_snapshot(self):
        self.branches.setAnalysisScope('union')
        self.wait_until(lambda: self.branches.planCurrent)
        self.assertEqual(self.branches.export_report()['region_count'], 2)
        single = Path(self.folder.name) / 'single-from-union.json'
        bundle = Path(self.folder.name) / 'all.json'
        self.planner.saveToPath(str(single))
        self.planner.saveAllToPath(str(bundle))
        self.planner.selectCandidate(1)
        self.wait_until(lambda: single.exists() and bundle.exists())
        saved = json.loads(bundle.read_text(encoding='utf-8'))
        self.assertEqual(saved['lesion_count'], 2)
        self.assertEqual(saved['union_branch_analysis']['analysis_scope'], 'union')
        self.assertEqual(saved['lesions'][0]['branch_analysis']['analysis_scope'], 'current')
        self.assertEqual(json.loads(single.read_text())['branch_analysis']['analysis_scope'], 'current')
        a = saved['lesions'][0]['branch_analysis']['trees'][0]['rows']
        u = saved['union_branch_analysis']['trees'][0]['rows']
        self.assertEqual([r['removed_length_mm'] for r in a], [r['removed_length_mm'] for r in u])
        self.assertEqual(self.extractions.count(), 0)

    def test_model_reload_rejects_old_catalog_and_empty_selection_not_ready(self):
        self.planner._catalog_signature = ('old', 'Tumor.stl', 1)
        signature = self.planner._catalog_signature
        self.viewer.loadStarted.emit()
        self.planner._catalog_completed(dict(signature=signature, rows=[dict(id='old')]))
        self.assertEqual(self.planner.lesionComponents, [])
        self.assertFalse(self.planner.ready)

    def test_backend_switch_disables_new_relation_without_erasing_centerlines(self):
        self.planner.setExecutionBackend('pl')
        QTest.qWait(250)
        self.assertFalse(self.branches.planCurrent)
        self.assertEqual(self.branches.affectedCount, 0)
        self.assertIsNone(self.branches.export_report())
        self.assertTrue(self.branches.ready)
        # The wedge is the only model on both backends; the centrelines above stay.
        self.assertEqual(self.planner.planningModel, 'plane_wedge')
        self.assertEqual(self.branches.removedGeometry.vertexData().size(), 0)

    def test_pl_plans_support_both_lesions_and_saved_backend(self):
        self.planner.setExecutionBackend('pl')
        first, second = dict(self.first), dict(self.second)
        first['case'], second['case'] = cases()[1], cases()[1]
        self.planner._completed(dict(first, revision=self.planner._revision,
                                     lesion_plans=[first, second]))
        self.wait_until(lambda: self.branches.planCurrent)
        self.assertGreater(self.branches.affectedCount, 0)
        self.planner.selectLesion(1)
        self.assertFalse(self.branches.planCurrent)
        self.assertEqual(self.branches.removedGeometry.vertexData().size(), 0)
        target = Path(self.folder.name) / 'pl-lesion2.json'
        self.planner.saveToPath(str(target))
        # An immediate switch must not change the queued save's snapshot.
        self.planner.selectLesion(0)
        self.wait_until(target.exists)
        saved = json.loads(target.read_text(encoding='utf-8'))
        self.assertEqual(saved['lesion_index'], 2)
        self.assertEqual(saved['branch_analysis']['planning_backend'], 'pl')
        self.assertTrue(all(r['status'] == 'outside'
            for t in saved['branch_analysis']['trees'] for r in t['rows']))
        self.wait_until(lambda: self.branches.planCurrent)
        self.assertGreater(self.branches.affectedCount, 0)

    def test_slow_old_candidate_cannot_restore_stale_highlights(self):
        started, release = threading.Event(), threading.Event()
        engine = self.branches._relation_worker.engine
        original = engine.run

        def slow(*args, **kwargs):
            started.set()
            release.wait(2.)
            return original(*args, **kwargs)

        with patch.object(engine, 'run', side_effect=slow):
            self.planner.selectCandidate(1)
            self.branches._refresh()
            self.wait_until(started.is_set)
            self.assertFalse(self.branches.planCurrent)
            self.planner.selectCandidate(0)
            self.branches._refresh()
            self.assertTrue(self.branches.planCurrent)
            self.assertGreater(self.branches.affectedCount, 0)
            release.set()
            self.wait_until(lambda: not self.branches._relation_jobs)
            self.assertTrue(self.branches.planCurrent)
            self.assertGreater(self.branches.affectedCount, 0)

    def test_pl_failure_clears_relation_and_does_not_save_false_success(self):
        self.planner.setExecutionBackend('pl')
        case = cases()[1]
        case._ray_hits_many.side_effect = RuntimeError('hardware timeout')
        first = dict(self.first, case=case)
        self.planner._completed(dict(first, revision=self.planner._revision))
        target = Path(self.folder.name) / 'failed.json'
        self.planner.saveToPath(str(target))
        self.wait_until(lambda: '保存失败' in self.planner.status)
        self.assertFalse(target.exists())
        # The save and the on-screen relation use separate background jobs;
        # either may report first.
        self.wait_until(lambda: 'hardware timeout' in self.branches.analysisStatus)
        self.assertFalse(self.branches.planCurrent)
        self.assertEqual(self.branches.affectedCount, 0)


if __name__ == '__main__':
    unittest.main()
