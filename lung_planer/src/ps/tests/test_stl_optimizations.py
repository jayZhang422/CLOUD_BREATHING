"""STL selection, exact cut unions and stable Qt list contracts."""
import tempfile
from pathlib import Path
from types import SimpleNamespace
import unittest
from unittest.mock import patch

import numpy as np
from PySide6.QtCore import QCoreApplication
from PySide6.QtTest import QSignalSpy, QAbstractItemModelTester

from cas_frontend.centerlines import analyze_resection, grade_forest, prepare_tree
from cas_frontend.branch_list_model import BranchListModel, BranchFilterModel
from cas_frontend.lesion_components import selected_components
from cas_frontend.planner import PlanningWorker


def line_tree():
    return grade_forest(dict(nodes=[dict(id=i, point=p, radius_mm=.01)
        for i, p in enumerate([[-1, 1, 1], [11, 1, 1]])], branches=[dict(
        id=0, start=0, end=1, points=[[-1, 1, 1], [11, 1, 1]],
        radii_mm=[.01, .01], length_mm=12., diameter_mm=.02)]))


def tetra(x):
    # On y=z=1 this cuts x..x+2.
    return np.array([[x, 0, 0], [x+4, 0, 0], [x, 4, 0], [x, 0, 4]], float)


class UnionTests(unittest.TestCase):
    def test_collective_cuts_remove_both_alternative_paths(self):
        points = np.array([[0,0,0],[2,2,0],[2,-2,0],[4,0,0],[6,0,0]],float)
        branches=[]
        for start,end in [(0,1),(0,2),(1,3),(2,3),(3,4)]:
            p=points[[start,end]]
            branches.append(dict(id=len(branches),start=start,end=end,points=p.tolist(),
                radii_mm=[.01,.01],length_mm=float(np.linalg.norm(p[1]-p[0])),diameter_mm=.02))
        tree=grade_forest(dict(nodes=[dict(id=i,point=p.tolist(),radius_mm=.01)
            for i,p in enumerate(points)],branches=branches),[0])
        shape=np.array([[-.4,-.4,-.4],[1.2,-.4,-.4],[-.4,1.2,-.4],[-.4,-.4,1.2]])
        upper,lower=shape+[1,1,0],shape+[1,-1,0]
        self.assertFalse(analyze_resection(tree,upper)['rows'][4]['downstream_affected'])
        self.assertFalse(analyze_resection(tree,lower)['rows'][4]['downstream_affected'])
        result=analyze_resection(tree,[upper,lower])['rows'][4]
        self.assertEqual(result['status'],'outside')
        self.assertTrue(result['downstream_affected'])

    def test_overlap_duplicate_and_disjoint_have_exact_lengths(self):
        for regions, expected, pieces in [([tetra(0), tetra(1)], 3., 1),
                ([tetra(0), tetra(0)], 2., 1), ([tetra(0), tetra(5)], 4., 2)]:
            result = analyze_resection(line_tree(), regions)
            self.assertAlmostEqual(result['rows'][0]['removed_length_mm'], expected)
            self.assertEqual(len(result['removed_segments']), pieces)
            self.assertEqual(len(result['rows'][0]['cut_points']), pieces * 2)

    def test_union_keeps_lung_gaps_and_cached_arrays_readonly(self):
        class Lung:
            def intervals_many(self, segments, lengths):
                return [[(1., 1.5), (2.5, 4.)] for _ in segments]
        tree = line_tree()
        prepared = prepare_tree(tree)
        result = analyze_resection(tree, [tetra(0), tetra(1)], Lung(), {}, prepared)
        self.assertAlmostEqual(result['rows'][0]['removed_length_mm'], 2.)
        self.assertEqual(len(result['removed_segments']), 2)
        self.assertEqual(prepared['segments'].dtype, np.float64)
        self.assertFalse(prepared['segments'].flags.writeable)

    def test_point_contact_does_not_create_removed_length(self):
        result = analyze_resection(line_tree(), [tetra(-3), tetra(11)])
        self.assertEqual(result['rows'][0]['removed_length_mm'], 0.)


class SelectionAndModelTests(unittest.TestCase):
    @classmethod
    def setUpClass(cls):
        cls.app = QCoreApplication.instance() or QCoreApplication([])

    def test_nonleading_single_and_multiple_selection(self):
        rows = [dict(id=str(i), rank=i, triangles=object(), volume_cm3=4-i) for i in (1, 2, 3)]
        catalog = dict(components=rows, source_sha256='sha')
        self.assertEqual(selected_components(catalog, ['3']), [rows[2]])
        worker = PlanningWorker()
        with patch.object(worker, '_catalog', return_value=catalog), \
             patch.object(worker, '_execute', side_effect=lambda job, *a, **k: dict(result=job)):
            output = worker._execute_multiple_lesions(dict(directory='.', tumor='Tumor.stl',
                lesion_component_ids=['3', '2'], backend='cpu', revision=0, params={}))
        self.assertEqual([p['result']['lesion_source_rank'] for p in output['lesion_plans']], [2, 3])
        self.assertIs(output['lesion_plans'][1]['result']['tumor_triangles'], rows[2]['triangles'])
        for invalid in ([], ['1', '1'], ['missing']):
            with self.assertRaises(ValueError):
                selected_components(catalog, invalid)

    def test_worker_lung_selection_is_cached_until_a_file_changes(self):
        worker = PlanningWorker()
        with tempfile.TemporaryDirectory() as folder:
            for name in ['a.stl', 'b.stl', 'Tumor.stl']:
                (Path(folder) / name).write_bytes(b'x')
            job = dict(directory=folder, lung=['a.stl', 'b.stl'], tumor='Tumor.stl',
                       revision=1, lung_selection_policy='explicit', ct_spacing=(1., 1., 1.))
            with patch('cas_frontend.planner.auto_select_target_lung',
                       return_value=['b.stl']) as select:
                first = worker._select_lung(job)
                second = worker._select_lung(job)
                self.assertEqual(first['lung'], ['b.stl'])
                self.assertEqual(first['lung_selection_policy'], 'lesion-containing-surface')
                self.assertEqual(second['lung'], ['b.stl'])
                self.assertEqual(select.call_count, 1)
                (Path(folder) / 'Tumor.stl').write_bytes(b'xx')
                worker._select_lung(job)
                self.assertEqual(select.call_count, 2)
            with patch('cas_frontend.planner.auto_select_target_lung',
                       return_value=['a.stl', 'b.stl']):
                worker._lung_selection_key = None
                unchanged = worker._select_lung(job)
            self.assertIs(unchanged, job)

    def test_source_changed_is_rejected_before_planning(self):
        with tempfile.TemporaryDirectory() as folder:
            path = Path(folder) / 'Tumor.stl'
            path.write_bytes(b'changed')
            with self.assertRaisesRegex(ValueError, '已变化'):
                PlanningWorker()._catalog(path, 'old-sha')

    def test_single_small_component_and_candidates_keep_source_identity(self):
        rows=[dict(id=str(i),rank=i,triangles=object(),volume_cm3=4-i) for i in (1,2)]
        catalog=dict(components=rows,source_sha256='sha')
        worker=PlanningWorker()
        with tempfile.TemporaryDirectory() as folder:
            for name in ['Lung.stl','Tumor.stl']:
                (Path(folder)/name).touch()
            with patch.object(worker,'_catalog',return_value=catalog), \
                    patch('cas_frontend.planner.make_case',
                          return_value=SimpleNamespace(_planning_case_identity='a'*64)) as build, \
                    patch('cas_frontend.planner.run_case',return_value=dict(result={},alternatives=[dict(result={})])):
                output=worker._execute(dict(directory=folder,lung=['Lung.stl'],tumor='Tumor.stl',
                    lesion_component_ids=['2'],revision=0,mode='auto'),'cpu')
        self.assertIs(build.call_args.args[0]['tumor_triangles'],rows[1]['triangles'])
        self.assertEqual(output['result']['lesion_source_rank'],2)
        self.assertEqual(output['alternatives'][0]['result']['lesion_component_id'],'2')

    def test_filter_changes_rows_without_reset_or_source_rebinding(self):
        source = BranchListModel()
        proxy = BranchFilterModel(source)
        rows = [dict(key=f'0:{i}', status=status, downstream_affected=False,
            generation=1, diameter_mm=1., removed_length_mm=float(i), kind='artery',
            tree=0, id=i) for i, status in enumerate(['outside', 'partial', 'full'])]
        source.replace(rows)
        a, b = QSignalSpy(source.modelReset), QSignalSpy(proxy.modelReset)
        proxy.set_only_affected(False)
        self.assertEqual(proxy.rowCount(), 3)
        self.assertEqual([proxy.data(proxy.index(i, 0), source.RowRole)['key'] for i in range(3)],
            ['0:0', '0:1', '0:2'])
        proxy.set_only_affected(True)
        self.assertEqual(proxy.rowCount(), 2)
        source.replace(rows)
        self.assertEqual((a.count(), b.count()), (0, 0))

    def test_segmented_view_updates_remain_valid_when_status_and_order_change(self):
        from cas_frontend.branch_presentation import affected_order
        source=BranchListModel(); view=BranchFilterModel(source)
        tester=QAbstractItemModelTester(view,QAbstractItemModelTester.FailureReportingMode.Fatal)
        reset=None
        rng=np.random.default_rng(125)
        for turn in range(30):
            rows=[dict(key=f'0:{i}',status=str(rng.choice(['outside','partial','near'])),
                downstream_affected=bool(rng.integers(2)),generation=int(rng.integers(1,5)),
                kind='artery') for i in range(50)]
            source.replace(rows)
            if reset is None:
                reset=QSignalSpy(view.modelReset)
            only=bool(turn%2); view.set_only_affected(only)
            target=sorted([r for r in rows if r['status']!='outside' or r['downstream_affected']],key=affected_order) if only else rows
            self.assertEqual([view.data(view.index(i,0),source.RowRole) for i in range(view.rowCount())],target)
        self.assertEqual(reset.count(),0)


if __name__ == '__main__':
    unittest.main()
