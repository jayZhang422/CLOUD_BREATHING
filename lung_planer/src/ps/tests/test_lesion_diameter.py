"""The lesion's maximum diameter comes from its STL and the CT scale, not from typing."""
import sys
import unittest
from itertools import combinations
from pathlib import Path
from types import SimpleNamespace
from unittest.mock import Mock, patch

import numpy as np

sys.path.insert(0, str(Path(__file__).resolve().parents[1]))
from cas_frontend import lesion_components
from cas_frontend.lesion_components import max_feret_diameter
from cas_frontend.planner import PlannerController
from cas_frontend.planning_constraints import default_parameters


def brute_force(points):
    return max(float(np.linalg.norm(a - b)) for a, b in combinations(points, 2))


class MaxFeretTests(unittest.TestCase):
    def test_known_shapes(self):
        corners = np.array([(x, y, z) for x in (0., 3.) for y in (0., 4.) for z in (0., 12.)])
        self.assertAlmostEqual(max_feret_diameter(corners), 13., places=9)  # sqrt(3^2+4^2+12^2)
        theta = np.linspace(0., np.pi, 40)[:, None]
        phi = np.linspace(0., 2. * np.pi, 80, endpoint=False)[None, :]
        sphere = 5. * np.stack([np.sin(theta) * np.cos(phi), np.sin(theta) * np.sin(phi),
                                np.cos(theta) * np.ones_like(phi)], axis=-1).reshape(-1, 3)
        self.assertAlmostEqual(max_feret_diameter(sphere), 10., places=2)

    def test_matches_brute_force_on_random_clouds(self):
        rng = np.random.default_rng(11)
        for count in (4, 30, 400):
            cloud = rng.normal(0., 3., (count, 3)) * np.array([1., 2., 0.5])
            with self.subTest(count=count):
                self.assertAlmostEqual(max_feret_diameter(cloud), brute_force(cloud), places=9)

    def test_flat_and_degenerate_sets_have_no_hull_but_still_measure(self):
        line = np.array([(0., 0., 0.), (1., 1., 1.), (4., 4., 4.), (2., 2., 2.)])
        self.assertAlmostEqual(max_feret_diameter(line), np.sqrt(48.), places=9)
        flat = np.array([(0., 0., 0.), (6., 0., 0.), (0., 8., 0.), (3., 3., 0.)])
        self.assertAlmostEqual(max_feret_diameter(flat), 10., places=9)
        self.assertEqual(max_feret_diameter(np.zeros((1, 3))), 0.)
        self.assertEqual(max_feret_diameter(np.empty((0, 3))), 0.)

    def test_inspect_components_reports_it_per_component(self):
        # A 2x3x6 box (diagonal 7) as a closed triangle mesh.
        v = np.array([(x, y, z) for x in (0., 2.) for y in (0., 3.) for z in (0., 6.)])
        faces = ((0, 1, 3), (0, 3, 2), (4, 6, 7), (4, 7, 5), (0, 4, 5), (0, 5, 1),
                 (2, 3, 7), (2, 7, 6), (0, 2, 6), (0, 6, 4), (1, 5, 7), (1, 7, 3))
        triangles = [lesion_components.ref.Triangle(*map(tuple, v[list(f)])) for f in faces]
        with patch.object(lesion_components.ref, 'read_stl', return_value=triangles), \
             patch.object(Path, 'read_bytes', return_value=b'stl'):
            catalog = lesion_components.inspect_components('lesion.stl')
        self.assertEqual(len(catalog['components']), 1)
        self.assertAlmostEqual(catalog['components'][0]['max_diameter_src'], 7., places=9)


def planner(spacing=None, rows=(), selected=(), params=None):
    h = SimpleNamespace(
        _ct_calibration=({} if spacing is None else dict(pixel_spacing_mm=[spacing, spacing], slice_spacing_mm=1.)),
        _lesion_components=[dict(id=name, max_diameter_src=size) for name, size in rows],
        _component_ids=list(selected), _params=dict(params or default_parameters()),
        _timer=Mock(), _pending=None, _revision=0, _active_cancel=None, _result={'x': 1},
        _geometry_current=True, _stale=False, _preview_case=object(), _plan_case_identity='a',
        _expected_case_identity='b', _status='', changed=Mock())
    h._ct_spacing = lambda: PlannerController._ct_spacing(h)
    h._auto_lesion_diameter = lambda: PlannerController._auto_lesion_diameter(h)
    h._fill_lesion_diameter = lambda: PlannerController._fill_lesion_diameter(h)
    return h


class PlannerDiameterTests(unittest.TestCase):
    def test_single_lesion_is_scaled_by_the_ct_voxel_size(self):
        h = planner(spacing=0.8, rows=[('a', 20.), ('b', 5.)], selected=['a'])
        PlannerController._fill_lesion_diameter(h)
        self.assertEqual(h._params['lesionDiameter'], 16.0)  # 20 voxels x 0.8 mm
        h._component_ids = ['b']
        PlannerController._fill_lesion_diameter(h)
        self.assertEqual(h._params['lesionDiameter'], 4.0)

    def test_without_ct_or_with_several_lesions_it_stays_empty(self):
        h = planner(spacing=None, rows=[('a', 20.)], selected=['a'])
        PlannerController._fill_lesion_diameter(h)
        self.assertEqual(h._params['lesionDiameter'], 0.)
        h = planner(spacing=0.8, rows=[('a', 20.), ('b', 5.)], selected=['a', 'b'])
        PlannerController._fill_lesion_diameter(h)
        self.assertEqual(h._params['lesionDiameter'], 0.)  # per-lesion values stay manual
        h = planner(spacing=0.8, rows=[('a', float('nan'))], selected=['a'])
        PlannerController._fill_lesion_diameter(h)
        self.assertEqual(h._params['lesionDiameter'], 0.)

    def test_ct_loaded_after_the_stl_fills_the_field(self):
        h = planner(spacing=None, rows=[('a', 20.)], selected=['a'])
        PlannerController.setCtCalibration(h, dict(pixel_spacing_mm=[0.8, 0.8], slice_spacing_mm=1.))
        self.assertEqual(h._params['lesionDiameter'], 16.0)

    def test_a_typed_diameter_survives_a_ct_change_but_an_auto_one_follows_it(self):
        h = planner(spacing=0.8, rows=[('a', 20.)], selected=['a'])
        PlannerController._fill_lesion_diameter(h)
        PlannerController.setCtCalibration(h, dict(pixel_spacing_mm=[0.5, 0.5], slice_spacing_mm=1.))
        self.assertEqual(h._params['lesionDiameter'], 10.0)  # was auto: rescaled
        h._params['lesionDiameter'] = 13.7                    # the doctor typed this
        PlannerController.setCtCalibration(h, dict(pixel_spacing_mm=[0.9, 0.9], slice_spacing_mm=1.))
        self.assertEqual(h._params['lesionDiameter'], 13.7)

    def test_finishing_the_stl_scan_fills_the_diameter(self):
        rows = [dict(id='a', max_diameter_src=20.), dict(id='b', max_diameter_src=5.)]
        h = planner(spacing=0.8)
        h.__dict__.update(_catalog_signature=('case', 'Tumor.stl', 0), _catalog_busy=True, _catalog_error='',
                          _catalog_previews={}, _catalog_sha='', _lesion_count=1,
                          lesionCatalogChanged=Mock())
        PlannerController._catalog_completed(h, dict(signature=h._catalog_signature, rows=rows,
                                                     previews={'a': 1, 'b': 2}, source_sha256='sha'))
        self.assertEqual(h._component_ids, ['a'])           # the largest lesion is selected by default
        self.assertEqual(h._params['lesionDiameter'], 16.0)
        # A stale scan must not touch the field.
        h._params['lesionDiameter'] = 7.
        PlannerController._catalog_completed(h, dict(signature=('other', 'x', 1), rows=rows))
        self.assertEqual(h._params['lesionDiameter'], 7.)

    def test_scan_worker_passes_the_diameter_through_to_the_ui_rows(self):
        from cas_frontend import planner as planner_module
        worker = planner_module.PlanningWorker()
        row = dict(id='a', rank=1, volume_cm3=1., triangles=object(), max_diameter_src=12.5)
        got = []
        worker.catalogCompleted.connect(got.append)
        with patch.object(worker, '_catalog', return_value=dict(components=[row], source_sha256='sha')), \
             patch.object(planner_module.ref, 'all_points', return_value=np.zeros((3, 3))), \
             patch.object(planner_module, 'prepare_mesh', return_value='mesh'):
            worker.scanLesions(dict(signature='s', directory='.', tumor='t.stl', center=[0, 0, 0], scale=1.))
        self.assertEqual(got[0]['rows'][0]['max_diameter_src'], 12.5)
        self.assertNotIn('triangles', got[0]['rows'][0])

    def test_value_is_capped_at_the_parameter_limit(self):
        h = planner(spacing=1.0, rows=[('a', 500.)], selected=['a'])
        PlannerController._fill_lesion_diameter(h)
        self.assertEqual(h._params['lesionDiameter'], 200.)


if __name__ == '__main__':
    unittest.main()
