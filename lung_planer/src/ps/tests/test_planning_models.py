"""Analytic and integration checks for the independent desktop research path."""
import json
import math
from pathlib import Path
import sys
from tempfile import TemporaryDirectory
from threading import Event
import unittest
from unittest.mock import patch

import numpy as np
sys.path[:0] = [str(Path(__file__).resolve().parents[1]), str(Path(__file__).resolve().parent)]
from cas_frontend.planning_models import (build_region, evaluate_region, planes,
    _validate_container, run_research, _finite_margin)
from cas_frontend.planning_constraints import default_parameters, restore_parameters, PLAN_SCHEMA
from cas_frontend.planning_cancel import cancellation_scope, PlanningCancelled
from cas_frontend.planning_geometry import PlanningCase
from cas_frontend.planning_run import run_case
from cas_frontend.planner import PlannerController
from cas_frontend.centerlines import clip_segments, analyze_resection
from test_centerlines import tree_fixture
from test_plan_persistence import planner_harness, saved_plan
from test_adaptive_planner import box
from cas_frontend import planner_reference as ref

SCHEMA = 'cloud-breathing-plan-research-v1'


def parameters():
    return dict(default_parameters(), planningModel='plane_wedge', yaw=-math.degrees(math.atan(.35)),
        pitch=0., rotation=0., minClearance=1., wedgeAngle=90., cutTilts=[45., 45.])


def make_case(center=(0., 0., 0.)):
    tumor, lung = box(np.asarray(center), .5), box(np.zeros(3), 10.)
    with TemporaryDirectory() as directory:
        for name in ('lung.stl', 'tumor.stl'):
            (Path(directory)/name).touch()
        with patch.object(ref, 'read_stl', side_effect=lambda p: tumor if p.name == 'tumor.stl' else lung):
            return PlanningCase(directory, ['lung.stl'], 'tumor.stl', ray_mode='cpu')


class ResearchModelTests(unittest.TestCase):
    def test_two_halfspaces_have_analytic_volume_and_no_artificial_base(self):
        case, p = make_case(), parameters()
        vertices = build_region(case, p)
        payload = evaluate_region(case, vertices, p, review=False)
        r = payload['result']
        h = 1. + math.sqrt(2.)*(1.+1e-5)
        self.assertAlmostEqual(r['resection_volume_cm3']*1000., 20.*(100.+20.*h), places=7)
        self.assertEqual(len(r['cutting_planes']), 2)
        self.assertTrue(r['valid'])
        self.assertIsNone(r['min_base_clearance_mm'])
        self.assertFalse(r['base_constraint_applicable'])
        self.assertEqual(r['clinical_status'], 'PENDING_CONFIRMATION')
        self.assertTrue(all(r['geometric_surface_access']))
        self.assertAlmostEqual(r['tumor_margin_mm'], 1.00001, places=7)

    def test_plane_wedge_is_clipped_to_the_selected_stl_and_reports_whole_lung_volume(self):
        tumor = box(np.zeros(3), .5)
        segment = box(np.zeros(3), 6.)
        whole_lung = box(np.zeros(3), 10.)
        with TemporaryDirectory() as directory:
            for name in ('Bronchus_plan_0_seg_1LU.stl', 'LeftUpperLobe.stl', 'tumor.stl'):
                (Path(directory)/name).touch()
            meshes = {'tumor.stl': tumor, 'Bronchus_plan_0_seg_1LU.stl': segment,
                      'LeftUpperLobe.stl': whole_lung}
            with patch.object(ref, 'read_stl', side_effect=lambda p: meshes[p.name]):
                case = PlanningCase(directory, ['Bronchus_plan_0_seg_1LU.stl'], 'tumor.stl', ray_mode='cpu',
                                    whole_lung_files=['Bronchus_plan_0_seg_1LU.stl', 'LeftUpperLobe.stl'])
        p = parameters()
        vertices = build_region(case, p)
        payload = evaluate_region(case, vertices, p, review=False)
        surface = np.asarray(payload['surface'])
        self.assertTrue(payload['result']['valid'])
        self.assertGreater(len(surface), 0)
        self.assertAlmostEqual(case.lung_volume, 6.**3*8.)
        self.assertAlmostEqual(case.whole_lung_volume, 10.**3*8.)
        self.assertLessEqual(np.max(np.abs(surface)), 6. + 1e-9)
        self.assertGreater(np.max(np.abs(surface)), 5.999)
        self.assertTrue(all(payload['result']['geometric_surface_access']))

    def test_caps_can_move_away_without_changing_volume_area_or_cut_distance(self):
        case, p = make_case(), parameters()
        vertices = build_region(case, p)
        before = evaluate_region(case, vertices, p, review=False)
        ridge = (vertices[1]+vertices[3])/2.
        moved = ridge+2.*(vertices-ridge)
        after = evaluate_region(case, moved, p, review=False)
        for key in ('resection_volume_cm3', 'surface_area_cm2', 'cut_area_cm2', 'tumor_margin_mm'):
            self.assertAlmostEqual(before['result'][key], after['result'][key], places=8)
        segments = np.asarray([[[-10., 0., z], [10., 0., z]] for z in (-9., -2., 0., 2., 9.)])
        clip1, clip2 = clip_segments(segments, vertices), clip_segments(segments, moved)
        np.testing.assert_array_equal(clip1[0], clip2[0])
        np.testing.assert_allclose(clip1[1], clip2[1], atol=1e-10)
        tree = tree_fixture()
        report1 = analyze_resection(tree, vertices, lung_index=case._cpu_index)
        report2 = analyze_resection(tree, moved, lung_index=case._cpu_index)
        expected = 1. + math.sqrt(2.)*(1.+1e-5)
        self.assertAlmostEqual(report1['rows'][0]['removed_length_mm'],expected,places=8)
        for a,b in zip(report1['rows'], report2['rows']):
            self.assertEqual(a['status'],b['status'])
            self.assertEqual(a['downstream_affected'],b['downstream_affected'])
            self.assertAlmostEqual(a['removed_length_mm'],b['removed_length_mm'],places=8)

    def test_caps_inside_lung_and_degenerate_geometry_are_rejected(self):
        case, p = make_case(), parameters()
        v = build_region(case, p)
        ridge = (v[1]+v[3])/2.
        with self.assertRaisesRegex(ValueError, '辅助包围面'):
            _validate_container(case, ridge+.01*(v-ridge), p)
        for malformed in (np.zeros((4,3)), np.full((4,3), np.nan), np.zeros((3,3))):
            with self.assertRaises(ValueError):
                _validate_container(case, malformed, p)

    def test_complete_triangle_distance_detects_interior_contact_and_threshold(self):
        case = make_case()
        # The plane intersects a tumor face even though its vertices are remote.
        cut = np.asarray([[[-3.,0.,0.], [3.,0.,0.], [0.,3.,0.]]])
        self.assertAlmostEqual(_finite_margin(case, cut), 0., places=10)
        cut = np.asarray([[[-3.,-3.,1.5], [3.,-3.,1.5], [0.,4.,1.5]]])
        self.assertAlmostEqual(_finite_margin(case, cut), 1., places=10)
        p = parameters()
        v = build_region(case, p)
        strict = dict(p, minClearance=1.00002)
        self.assertFalse(evaluate_region(case, v, strict, review=False)['result']['valid'])

    def test_pose_roundtrip_keeps_asymmetric_tilts_and_full_rotation(self):
        case = make_case((6.,0.,0.))
        p = parameters()
        p.update(rotation=310., cutTilts=[25.,65.])
        restored = restore_parameters(json.loads(json.dumps(p)), SCHEMA)
        np.testing.assert_allclose(build_region(case,p), build_region(case,restored), atol=1e-10)

    def test_schema_requires_new_model_and_complete_pose_and_rejects_old_mislabel(self):
        p = parameters()
        for key in ('planningModel','cutTilts','wedgeAngle'):
            malformed = dict(p); del malformed[key]
            with self.assertRaises(ValueError):
                restore_parameters(malformed, SCHEMA)
        with self.assertRaises(ValueError):
            restore_parameters(p, PLAN_SCHEMA)
        for tilts in ([float('nan'),45.], [True,45.], [5.,45.], [45.], [45.,45.,45.]):
            with self.assertRaises(ValueError):
                restore_parameters(dict(p,cutTilts=tilts),SCHEMA)

    def test_actual_cpu_dispatch_rejects_pl_and_cancellation(self):
        case, p = make_case(), parameters()
        job = dict(directory='unused',params=p,mode='manual',vertices=build_region(case,p))
        with patch('cas_frontend.planning_models.structure_review', return_value={}):
            payload = run_case(case, job, 'cpu', None)
        self.assertTrue(payload['result']['valid'])
        with self.assertRaisesRegex(RuntimeError, 'PL 预筛选不可用'):
            run_case(case,job,'pl',None)
        with self.assertRaises(PlanningCancelled):
            run_research(case,dict(job,mode='auto'),cancelled=lambda: True)
        token = Event(); token.set()
        with self.assertRaises(PlanningCancelled), cancellation_scope(token):
            run_case(case,job,'cpu',None)

    def test_saved_new_plan_queues_revalidation_and_malformed_model_never_mutates(self):
        with TemporaryDirectory() as directory:
            plan = saved_plan()
            plan.update(schema=SCHEMA,planning_backend='cpu',parameters=parameters())
            path = Path(directory)/'plan.json'
            path.write_text(json.dumps(plan), encoding='utf8')
            controller = planner_harness(); controller._backend='cpu'
            PlannerController.loadPlanFromPath(controller,str(path))
            controller._enqueue.assert_called_once_with('manual')
            self.assertEqual(controller._params['cutTilts'],[45.,45.])
            self.assertTrue(controller._stale)
            del plan['parameters']['planningModel']
            path.write_text(json.dumps(plan),encoding='utf8')
            controller = planner_harness(); controller._backend='cpu'
            PlannerController.loadPlanFromPath(controller,str(path))
            controller._invalidate.assert_not_called()
            controller._enqueue.assert_not_called()


if __name__ == '__main__':
    unittest.main()
