import json
import sys
from pathlib import Path
from tempfile import TemporaryDirectory
from types import SimpleNamespace
import unittest
from unittest.mock import Mock, patch

import numpy as np
from PySide6.QtCore import QCoreApplication

sys.path.insert(0, str(Path(__file__).resolve().parents[1]))
from cas_frontend.planner import PlannerController, PlanningWorker, planning_case_identity
from cas_frontend.ui_dialogs import UiDialogs
from cas_frontend.interactive_planner import install_case_reuse
from cas_frontend.lesion_components import inspect_components
from cas_frontend.planning_geometry import PlanningCase
from test_adaptive_planner import box, PARAMS
from cas_frontend.planning_constraints import default_parameters, WEDGE_SCHEMA


PARAMETERS = dict(default_parameters(), planningModel='plane_wedge',
                  wedgeAngle=90., cutTilts=[45., 45.])
VERTICES = np.asarray(((0., 0., 0.), (40., 0., 0.),
                       (0., 40., 0.), (0., 0., 40.)))


def saved_plan(backend='cpu'):
    result = dict(valid=True, coverage_percent=100.)
    return dict(schema=WEDGE_SCHEMA, planning_backend=backend,
        lung_files=['Left.stl'], tumor_file='Tumor.stl',
        tumor_source_sha256='tumor-source', lesion_component_ids=['component-1'],
        planning_case_identity='a' * 64, vertices_mm=VERTICES.tolist(),
        parameters=PARAMETERS, result=result)


def planner_harness():
    return SimpleNamespace(
        ready=True, _busy=False, _directory='case', _backend='cpu',
        _lung=['Left.stl'], _tumor='Tumor.stl', _catalog_sha='tumor-source',
        _params=dict(PARAMETERS), _lesion_components=[dict(id='component-1')],
        _invalidate=Mock(), _draw=Mock(), _enqueue=Mock(),
        _stale=True, lesionCatalogChanged=Mock(), changed=Mock())


class PlanPersistenceTests(unittest.TestCase):
    @classmethod
    def setUpClass(cls):
        cls.app = QCoreApplication.instance() or QCoreApplication([])

    def test_restore_queues_fixed_vertices_and_expected_case_identity(self):
        with TemporaryDirectory() as folder:
            path = Path(folder) / 'plan.json'
            path.write_text(json.dumps(saved_plan()), encoding='utf-8')
            planner = planner_harness()

            PlannerController.loadPlanFromPath(planner, str(path))

            planner._invalidate.assert_called_once()
            planner._enqueue.assert_called_once_with('manual')
            planner._draw.assert_called_once_with(update_surface=True)
            np.testing.assert_array_equal(planner._vertices, VERTICES)
            self.assertEqual(planner._expected_case_identity, 'a' * 64)
            self.assertEqual(planner._component_ids, ['component-1'])
            self.assertTrue(planner._stale)
            self.assertFalse(planner._geometry_current)

    def test_removed_tetra_plan_formats_are_rejected_without_mutating_the_planner(self):
        for schema in ('cloud-breathing-plan-v1', 'cloud-breathing-plan-v2'):
            with TemporaryDirectory() as folder:
                path = Path(folder) / 'plan.json'
                path.write_text(json.dumps(dict(saved_plan(), schema=schema)), encoding='utf-8')
                planner = planner_harness()

                PlannerController.loadPlanFromPath(planner, str(path))

                planner._invalidate.assert_not_called()
                planner._enqueue.assert_not_called()
                self.assertIn('双平面楔形', planner._status)

    def test_wedge_plan_restores_on_the_pl_backend(self):
        with TemporaryDirectory() as folder:
            path = Path(folder) / 'plan.json'
            path.write_text(json.dumps(saved_plan('pl')), encoding='utf-8')
            planner = planner_harness()
            planner._backend = 'pl'

            PlannerController.loadPlanFromPath(planner, str(path))

            planner._enqueue.assert_called_once_with('manual')

    def test_restore_rejects_changed_case_before_mutating_planner(self):
        with TemporaryDirectory() as folder:
            path = Path(folder) / 'plan.json'
            value = saved_plan()
            value['tumor_source_sha256'] = 'different-source'
            path.write_text(json.dumps(value), encoding='utf-8')
            planner = planner_harness()

            PlannerController.loadPlanFromPath(planner, str(path))

            planner._invalidate.assert_not_called()
            planner._enqueue.assert_not_called()
            self.assertIn('病灶 STL 已变化', planner._status)

    def test_restore_handles_auto_safety_fit_and_current_safety_fit(self):
        with TemporaryDirectory() as folder:
            path = Path(folder) / 'plan.json'
            value = saved_plan()
            value['parameters'] = dict(value['parameters'], safetyFit=True)
            path.write_text(json.dumps(value), encoding='utf-8')
            planner = planner_harness()
            planner._params['safetyFit'] = True
            PlannerController.loadPlanFromPath(planner, str(path))
            planner._enqueue.assert_called_once_with('manual')
            self.assertIs(planner._params['safetyFit'], True)

    def test_malformed_json_root_does_not_mutate_current_plan(self):
        with TemporaryDirectory() as folder:
            path = Path(folder) / 'plan.json'
            path.write_text('[]', encoding='utf-8')
            planner = planner_harness()
            PlannerController.loadPlanFromPath(planner, str(path))
            planner._invalidate.assert_not_called()
            planner._enqueue.assert_not_called()
            self.assertIn('JSON 对象', planner._status)

    def test_case_identity_binds_selected_files_and_geometry(self):
        case = SimpleNamespace(lung_files=['Left.stl'], tumor_file='Tumor.stl',
            triangles=np.asarray([[[0., 0., 0.], [1., 0., 0.], [0., 1., 0.]]]),
            points=np.asarray([[2., 3., 4.]]))
        identity = planning_case_identity(case)
        self.assertEqual(len(identity), 64)
        changed = SimpleNamespace(**vars(case))
        changed.points = case.points + 1.
        self.assertNotEqual(planning_case_identity(changed), identity)
        renamed = SimpleNamespace(**vars(case))
        renamed.lung_files = ['Right.stl']
        self.assertNotEqual(planning_case_identity(renamed), identity)

    def test_worker_rejects_geometry_mismatch_before_full_evaluation(self):
        with TemporaryDirectory() as folder:
            for name in ('Left.stl', 'Tumor.stl'):
                (Path(folder) / name).touch()
            case = SimpleNamespace(lung_files=['Left.stl'], tumor_file='Tumor.stl',
                triangles=np.asarray([[[0., 0., 0.], [1., 0., 0.], [0., 1., 0.]]]),
                points=np.asarray([[2., 3., 4.]]))
            job = dict(directory=folder, lung=['Left.stl'], tumor='Tumor.stl',
                tumor_triangles=[], mode='manual', params={}, vertices=VERTICES,
                revision=1, expected_case_identity='b' * 64)
            worker = PlanningWorker()
            with patch('cas_frontend.planner.make_case', return_value=case), \
                 patch('cas_frontend.planner.run_case') as evaluate:
                with self.assertRaisesRegex(ValueError, '几何与已保存规划不一致'):
                    worker._execute(job, 'cpu')
                evaluate.assert_not_called()

            job['expected_case_identity'] = planning_case_identity(case)
            payload = dict(result={}, case=case, vertices=VERTICES, params={},
                           alternatives=[], points=np.empty((0, 3)), surface=[], path=[], interior=[])
            with patch('cas_frontend.planner.make_case', return_value=case), \
                 patch('cas_frontend.planner.run_case', return_value=payload):
                restored = worker._execute(job, 'cpu')
            self.assertEqual(restored['planning_case_identity'], job['expected_case_identity'])

    def test_eglfs_open_dialog_lists_and_returns_json_file(self):
        with TemporaryDirectory() as folder:
            target = Path(folder) / 'saved-plan.JSON'
            target.write_text('{}', encoding='utf-8')
            (Path(folder) / 'notes.txt').write_text('ignored', encoding='utf-8')
            selected = []
            dialogs = UiDialogs()

            dialogs.open('加载规划 JSON', str(Path(folder) / 'default.json'), selected.append)
            self.assertEqual([row['name'] for row in dialogs.files], ['saved-plan.JSON'])
            dialogs.selectFile('saved-plan.JSON')
            self.assertTrue(dialogs.accept(dialogs.value))
            self.assertEqual(selected, [str(target)])

    def test_real_saved_plan_reloads_same_metrics_and_geometry_without_search(self):
        with TemporaryDirectory() as folder:
            for name, triangles in (
                    ('lung.stl', box(np.zeros(3), 10.)),
                    ('tumor.stl', box(np.asarray((7., 1., 1.)), .8))):
                lines = ['solid fixture']
                for triangle in triangles:
                    lines.extend(('facet normal 0 0 0', 'outer loop'))
                    lines.extend('vertex %s %s %s' % tuple(point) for point in triangle.points)
                    lines.extend(('endloop', 'endfacet'))
                lines.append('endsolid fixture')
                (Path(folder) / name).write_text('\n'.join(lines), encoding='ascii')
            catalog = inspect_components(Path(folder) / 'tumor.stl')
            component_id = catalog['components'][0]['id']
            job = dict(directory=folder, lung=['lung.stl'], tumor='tumor.stl',
                lesion_component_ids=[component_id],
                lesion_source_sha256=catalog['source_sha256'],
                mode='auto', params=dict(default_parameters(), **PARAMS, planningModel='plane_wedge', wedgeAngle=90.,
                                         cutTilts=[45., 45.]), vertices=None, revision=1)
            worker = PlanningWorker()
            install_case_reuse(worker)
            planned = worker._execute(job, 'cpu')
            self.assertTrue(planned['result']['valid'])
            case = planned['case']
            before_external = case._display_patch_cache[planned['vertices'].tobytes()][1].copy()
            before_result = planned['result']
            path = Path(folder) / 'planning_result.json'
            save = SimpleNamespace(_stale=False, _busy=False, _geometry_current=True,
                _result=before_result, _vertices=planned['vertices'], _params=planned['params'],
                _plan_case_identity=planned['planning_case_identity'], _component_ids=[component_id],
                _directory=folder, _backend='cpu', _lung=['lung.stl'], _tumor='tumor.stl',
                _catalog_sha=catalog['source_sha256'], changed=Mock())
            PlannerController.saveToPath(save, str(path))
            self.assertTrue(path.is_file(), getattr(save, '_status', ''))
            load = planner_harness()
            load._backend, load._lung, load._tumor = 'cpu', ['lung.stl'], 'tumor.stl'
            load._catalog_sha = catalog['source_sha256']
            load._lesion_components = [dict(id=component_id)]
            load._params = dict(planned['params'])
            PlannerController.loadPlanFromPath(load, str(path))
            load._enqueue.assert_called_once_with('manual')
            restored_job = dict(job, mode='manual', params=load._params, vertices=load._vertices,
                               expected_case_identity=load._expected_case_identity)
            with patch('scipy.optimize.minimize', side_effect=AssertionError('Search must be skipped')):
                restored = worker._execute(restored_job, 'cpu')
            np.testing.assert_array_equal(restored['vertices'], planned['vertices'])
            for key in ('valid', 'coverage_percent', 'clearance_mm', 'min_base_clearance_mm',
                        'surface_area_cm2', 'cut_area_cm2', 'resection_volume_cm3'):
                self.assertEqual(restored['result'][key], before_result[key], key)
            for key in ('surface', 'path', 'interior'):
                np.testing.assert_array_equal(restored[key], planned[key])
            np.testing.assert_array_equal(
                restored['case']._display_patch_cache[restored['vertices'].tobytes()][1], before_external)


if __name__ == '__main__':
    unittest.main()
