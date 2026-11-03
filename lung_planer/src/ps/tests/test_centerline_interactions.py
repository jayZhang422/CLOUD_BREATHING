"""Display actions must not republish expensive branch/marker models."""
from copy import deepcopy
from pathlib import Path
import tempfile
import unittest
from unittest.mock import patch

from PySide6.QtCore import QObject, Signal, QCoreApplication
from PySide6.QtTest import QSignalSpy

from cas_frontend.centerlines import grade_forest
from cas_frontend.centerline_controller import CenterlineController
from test_centerlines import tree_fixture


class Viewer(QObject):
    loadStarted = Signal()
    rowsChanged = Signal()
    sceneCenterMm = [0., 0., 0.]
    sceneScale = 1.


class Planner(QObject):
    changed = Signal()
    hasPlan = False


class CenterlineInteractionTests(unittest.TestCase):
    @classmethod
    def setUpClass(cls):
        cls.app = QCoreApplication.instance() or QCoreApplication([])

    def setUp(self):
        self.directory = tempfile.TemporaryDirectory()
        self.viewer, self.planner = Viewer(), Planner()
        self.controller = CenterlineController(self.viewer, self.planner, self.directory.name)
        self.addCleanup(self.directory.cleanup)
        self.addCleanup(self.controller.shutdown)
        tree = tree_fixture()
        tree.update(kind='airway', file='Bronchus.stl', cache_key='fixture')
        self.controller._trees = [tree]
        self.controller._update_roots()
        self.controller._refresh()
        self.rows = QSignalSpy(self.controller.rowsChanged)
        self.roots = QSignalSpy(self.controller.rootsChanged)
        self.relations = QSignalSpy(self.controller.relationChanged)

    def test_selection_updates_geometry_without_republishing_models(self):
        c = self.controller
        c.setOnlyAffected(False)
        count = self.rows.count()
        selection = QSignalSpy(c.selectionChanged)
        c.selectBranch('0:1')
        self.assertEqual(c.selectedRow, 1)
        self.assertGreater(c.selectedGeometry.vertexData().size(), 0)
        self.assertEqual(selection.count(), 1)
        self.assertEqual(self.rows.count(), count)
        self.assertEqual(self.roots.count(), 0)
        self.assertEqual(self.relations.count(), 0)
        c.selectBranch('0:1')
        self.assertEqual(c.selectedRow, -1)
        self.assertEqual(c.selectedGeometry.vertexData().size(), 0)

    def test_display_and_endpoint_preview_do_not_recompute_or_republish(self):
        c = self.controller
        options, markers = c.roots, c.rootPoints
        with patch.object(c, '_refresh') as refresh:
            c.setVisible(False)
            c.setXray(False)
            c.setVisible(True)
            c.previewRoot(c.roots[0]['id'])
            refresh.assert_not_called()
        self.assertEqual(len(c.rootCandidatePoints), 1)
        self.assertIs(c.roots, options)
        self.assertIs(c.rootPoints, markers)
        self.assertEqual(self.rows.count(), 0)
        self.assertEqual(self.roots.count(), 0)
        self.assertEqual(self.relations.count(), 0)

    def test_filter_keeps_selection_and_does_not_change_root_models(self):
        c = self.controller
        c.selectBranch('0:2')
        self.assertEqual(c.selectedRow, -1)
        c.setOnlyAffected(False)
        self.assertEqual(c.selectedRow, 2)
        self.assertEqual(self.rows.count(), 1)
        c.setOnlyAffected(False)
        self.assertEqual(self.rows.count(), 1)
        self.assertEqual(self.roots.count(), 0)
        c.setOnlyAffected(True)
        self.assertEqual(c.selectedBranch, '0:2')
        self.assertEqual(c.selectedRow, -1)

    def test_source_switch_updates_endpoint_options(self):
        c = self.controller
        tree = deepcopy(c._trees[0])
        tree['nodes'][0]['radius_mm'] = 9.
        c._trees.append(tree)
        c.previewRoot(0)
        c.selectSource(1)
        self.assertIn('9.0 mm', c.roots[0]['label'])
        self.assertEqual(c.rootCandidatePoints, [])
        self.assertEqual(self.rows.count(), 0)
        self.assertEqual(self.roots.count(), 1)

    def test_root_markers_only_show_the_primary_component(self):
        tree = deepcopy(self.controller._trees[0])
        tree['nodes'].extend([
            dict(id=4, point=[20., 0., 0.], radius_mm=1.),
            dict(id=5, point=[29., 0., 0.], radius_mm=3.)])
        tree['branches'].append(dict(id=3, start=4, end=5,
            points=[[20., 0., 0.], [29., 0., 0.]], radii_mm=[1., 3.],
            length_mm=9., diameter_mm=4.))
        tree = grade_forest(tree)
        self.controller._trees = [tree]

        self.controller._update_roots()

        self.assertEqual(len(self.controller.rootPoints), 1)
        self.assertIn(5, {option['id'] for option in self.controller.roots})

    def test_invalid_selection_keeps_existing_highlight(self):
        c = self.controller
        c.selectBranch('0:1')
        for key in ('-1:0', '0:-1', '1:0', '0:100', 'invalid'):
            c.selectBranch(key)
            self.assertEqual(c.selectedBranch, '0:1')

    def test_completed_accepts_legacy_and_three_axis_spacing(self):
        c = self.controller
        for spacing, label in [(.8, '0.80 mm'), ([.5, .8, 2.3], '0.50 × 0.80 × 2.30 mm')]:
            tree = deepcopy(c._trees[0])
            tree.update(spacing_mm=spacing, cache_hit=False, cyclic_components=0,
                        component_count=1)
            c._completed(dict(revision=c._revision, trees=[tree], errors=[], elapsed_ms=12))
            self.assertIn(label, c.summary)
            self.assertTrue(c._trees[0]['branches'])

    def test_npy_takes_precedence_over_matching_stl(self):
        root = Path(self.directory.name)
        for name in ('Bronchus.stl', 'Bronchus.npy', 'Artery.stl', 'Tumor.npy'):
            (root/name).touch()
        self.viewer.directory = str(root)
        self.controller._loaded()
        self.assertEqual({s['file'] for s in self.controller._sources},
                         {'Bronchus.npy', 'Artery.stl'})

    def test_save_reuses_current_analysis_but_refreshes_new_geometry(self):
        c = self.controller
        import numpy as np
        vertices = np.eye(4, 3)
        self.planner._vertices = vertices
        c._report = {'trees': []}
        c._signature = 'current'
        with patch.object(c, '_plan_is_current', return_value=True), patch.object(c, '_plan_signature', return_value='current'), patch.object(c, '_refresh') as refresh:
            self.assertIsNotNone(c.export_report())
            refresh.assert_not_called()
        with patch.object(c, '_plan_is_current', return_value=True), patch.object(c, '_plan_signature', return_value='new'):
            # Synchronous callers must never obtain the previous candidate.
            self.assertIsNone(c.export_report())


if __name__ == '__main__':
    unittest.main()
