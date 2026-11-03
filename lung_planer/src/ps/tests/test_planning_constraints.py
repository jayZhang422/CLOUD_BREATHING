"""Clinical references remain advisory; independent geometry checks are strict."""
import json
import sys
import unittest
from pathlib import Path
from tempfile import TemporaryDirectory
from unittest.mock import Mock, patch

import numpy as np

sys.path.insert(0, str(Path(__file__).resolve().parents[1]))
from cas_frontend import planner_reference as ref
from cas_frontend.planning_constraints import (default_parameters, margin_reference,
    restore_parameters, cut_plane_margin, PLAN_SCHEMA, WEDGE_SCHEMA)
from cas_frontend.planning_geometry import PlanningCase
from cas_frontend.planner import PlannerController
from test_plan_persistence import planner_harness, saved_plan
import test_pl_metrics_integration as metrics_fixture
from test_adaptive_planner import box
import test_strict_planner as strict_fixture
from cas_frontend.planning_run import run_case


class PlanningConstraintTests(unittest.TestCase):
    def test_new_default_uses_geometric_baseline_and_independent_one_mm_base(self):
        p = default_parameters()
        self.assertEqual(p['margin'], 1.)
        self.assertEqual(p['minClearance'], 1.)
        self.assertEqual(p['baseClearance'], 1.)
        wedge = dict(p, planningModel='plane_wedge', wedgeAngle=90., cutTilts=[45., 45.])
        self.assertEqual(restore_parameters(wedge, WEDGE_SCHEMA), wedge)
        for schema in ('cloud-breathing-plan-v1', PLAN_SCHEMA):
            with self.assertRaisesRegex(ValueError, '双平面楔形'):
                restore_parameters(p, schema)

    def test_mixed_and_solid_use_the_strict_diameter_reference(self):
        for kind in ('solid', 'mixed'):
            with self.subTest(kind=kind):
                p = dict(default_parameters(), lesionType=kind, lesionDiameter=12.,
                         marginRule='consensus_2023', minClearance=12.)
                rule = margin_reference(p)
                self.assertTrue(rule['available'])
                self.assertEqual(rule['thresholdMm'], 12.)
                self.assertFalse(rule['targetMeetsReference'])
                self.assertEqual(rule['suggestedMm'], 12.1)
                self.assertTrue(margin_reference(dict(p, minClearance=12.1))['targetMeetsReference'])

    def test_cystic_has_no_reference_and_asks_for_the_manual_rule(self):
        for rule_name in ('consensus_2023', 'nccn_reference'):
            rule = margin_reference(dict(default_parameters(), lesionType='cystic',
                                         lesionDiameter=12., marginRule=rule_name))
            self.assertFalse(rule['available'])
            self.assertIsNone(rule['suggestedMm'])
            # The cystic-specific message, not the "please confirm the type" fallback.
            self.assertIn('没有可引用的切缘参考', rule['description'])
            self.assertNotIn('请先由医生确认病灶类型', rule['description'])

    def test_solid_reference_uses_the_diameter_and_strict_boundary(self):
        p = dict(default_parameters(), lesionType='solid', lesionDiameter=12.3,
                 marginRule='consensus_2023', minClearance=12.3)
        rule = margin_reference(p)
        self.assertEqual(rule['thresholdMm'], 12.3)
        self.assertEqual(rule['suggestedMm'], 12.4)
        self.assertFalse(rule['targetMeetsReference'])
        self.assertEqual(p['minClearance'], 12.3)  # margin_reference itself never edits the target

    def test_nccn_reference_twenty_mm_and_unknown_or_out_of_scope_inputs(self):
        p = dict(default_parameters(), lesionType='solid', lesionDiameter=18.,
                 marginRule='nccn_reference', minClearance=20.)
        self.assertEqual(margin_reference(p)['suggestedMm'], 20.)
        self.assertTrue(margin_reference(p)['targetMeetsReference'])
        for change in (dict(lesionDiameter=0.), dict(lesionDiameter=20.1),
                       dict(lesionType='unconfirmed'), dict(lesionType='cystic')):
            rule = margin_reference(dict(p, **change))
            self.assertFalse(rule['available'])
            self.assertIsNone(rule['suggestedMm'])
            self.assertEqual(rule['clinicalStatus'], 'PENDING_CONFIRMATION')

    def test_saved_plans_with_old_lesion_types_restore_as_unconfirmed(self):
        p = dict(default_parameters(), planningModel='plane_wedge', wedgeAngle=90., cutTilts=[45., 45.])
        for old in ('pure_ggo', 'contains_solid', 'other'):
            with self.subTest(old=old):
                restored = restore_parameters(dict(p, lesionType=old), WEDGE_SCHEMA)
                self.assertEqual(restored['lesionType'], 'unconfirmed')
        for new in ('solid', 'cystic', 'mixed'):
            self.assertEqual(restore_parameters(dict(p, lesionType=new), WEDGE_SCHEMA)['lesionType'], new)

    def test_new_file_rejects_missing_invalid_or_unknown_rule_parameters(self):
        p = dict(default_parameters(), minClearance=20., planningModel='plane_wedge',
                 wedgeAngle=90., cutTilts=[45., 45.])
        restore_parameters(p, WEDGE_SCHEMA)  # the unmodified file is accepted
        for name, value in (('minClearance', float('nan')), ('baseClearance', -.1),
                            ('lesionDiameter', True), ('lesionType', 'auto-diagnosed'),
                            ('marginRule', 'always-approved'), ('constraintVersion', 1)):
            with self.subTest(name=name), self.assertRaises(ValueError):
                restore_parameters(dict(p, **{name: value}), WEDGE_SCHEMA)
        for name in ('baseClearance', 'lesionDiameter', 'lesionType', 'marginRule'):
            malformed = dict(p)
            del malformed[name]
            with self.assertRaises(ValueError):
                restore_parameters(malformed, WEDGE_SCHEMA)

    def geometry(self):
        case = metrics_fixture.PlMetricIntegrationTests().make_case()
        case.points = np.asarray(((0., 0., .5), (1., 0., .5), (0., 1., 1.)))
        vertices = np.asarray(((-100., -100., 0.), (100., -100., 0.),
                               (0., 100., 0.), (0., 0., 100.)))
        case.coverage = lambda v: (100., .5, ref.tetra_faces(list(map(tuple, v[:3])), tuple(v[3])))
        return case, vertices

    def test_external_base_does_not_limit_twenty_mm_tumor_margin(self):
        case, vertices = self.geometry()
        case.validate_base = Mock(return_value=(True, 1.2, 0))
        p = dict(default_parameters(), minClearance=20.)
        result, _ = case.evaluate(vertices, p)
        self.assertTrue(result['valid'])
        self.assertTrue(result['geometric_constraints_passed'])
        self.assertEqual(result['clearance_mm'], .5)
        self.assertGreater(result['tumor_margin_mm'], 20.)
        self.assertEqual(case.validate_base.call_args.args[1], 1.)
        self.assertEqual(result['clinical_status'], 'PENDING_CONFIRMATION')
        self.assertEqual(result['required_base_clearance_mm'], 1.)
        self.assertEqual(result['required_tumor_margin_mm'], 20.)

    def test_base_and_cut_margin_each_independently_reject_unsafe_result(self):
        case, vertices = self.geometry()
        p = default_parameters()
        for base_valid, gap, target in ((False, .9, 20.), (True, 1.2, 70.)):
            case.validate_base = Mock(return_value=(base_valid, gap, 0))
            result, _ = case.evaluate(vertices, dict(p, minClearance=target))
            self.assertFalse(result['valid'])
            self.assertEqual(case.validate_base.call_args.args[1], 1.)
        case.validate_base = Mock(return_value=(False, 1.2, 0))
        result, _ = case.evaluate(vertices, dict(p, baseClearance=2.))
        self.assertFalse(result['valid'])
        self.assertEqual(case.validate_base.call_args.args[1], 2.)

    def test_cut_plane_threshold_has_no_hidden_rounding_tolerance(self):
        case, vertices = self.geometry()
        faces = ref.tetra_faces(list(map(tuple, vertices[:3])), tuple(vertices[3]))
        measured = cut_plane_margin(case.points, faces)
        p = dict(default_parameters(), minClearance=measured)
        self.assertTrue(case.evaluate(vertices, p)[0]['valid'])
        p['minClearance'] = measured + 1e-8
        self.assertFalse(case.evaluate(vertices, p)[0]['valid'])
        # Independently evaluate affine extrema at triangle interior probes.
        for point in (case.points.mean(axis=0), .2*case.points[0]+.3*case.points[1]+.5*case.points[2]):
            scalar = min(-ref.dot(ref.sub(tuple(point), f[0]), f[3]) for f in faces[1:])
            self.assertGreaterEqual(scalar, measured - 1e-12)

    def reference_harness(self, vertices=None, geometry_current=False):
        h = planner_harness()
        h._params = default_parameters()
        h._alternatives, h._lesion_plans, h._result = [], [], {}
        h._vertices, h._geometry_current = vertices, geometry_current
        h._edited = Mock()
        h._set_reference_parameter = lambda name, value: PlannerController._set_reference_parameter(h, name, value)
        h._sync_margin_to_rule = lambda: PlannerController._sync_margin_to_rule(h)
        h.setParameter = lambda name, value: PlannerController.setParameter(h, name, value)
        return h

    def test_choosing_a_rule_fills_the_target_without_queueing_geometry(self):
        h = self.reference_harness()
        PlannerController.setLesionType(h, 'mixed')
        PlannerController.setParameter(h, 'lesionDiameter', 12.)
        self.assertEqual(h._params['minClearance'], 1.)  # manual rule: the doctor's value stays
        PlannerController.setMarginRule(h, 'consensus_2023')
        self.assertEqual(h._params['minClearance'], 12.1)
        self.assertEqual(h._params['baseClearance'], 1.)
        PlannerController.setMarginRule(h, 'nccn_reference')
        self.assertEqual(h._params['minClearance'], 20.)
        # No plan exists yet, so nothing may start a calculation.
        h._enqueue.assert_not_called()
        h._edited.assert_not_called()
        # Back to the manual rule: the last value is kept, not reset.
        PlannerController.setMarginRule(h, 'manual')
        self.assertEqual(h._params['minClearance'], 20.)

    def test_rule_follows_type_and_diameter_and_cystic_keeps_the_target(self):
        h = self.reference_harness()
        PlannerController.setMarginRule(h, 'consensus_2023')
        self.assertEqual(h._params['minClearance'], 1.)  # type and diameter still unknown
        PlannerController.setLesionType(h, 'solid')
        PlannerController.setParameter(h, 'lesionDiameter', 8.)
        self.assertEqual(h._params['minClearance'], 8.1)
        PlannerController.setParameter(h, 'lesionDiameter', 15.5)
        self.assertEqual(h._params['minClearance'], 15.6)
        PlannerController.setLesionType(h, 'cystic')
        self.assertEqual(h._params['minClearance'], 15.6)  # no reference for cystic: unchanged

    def test_an_existing_plan_is_refitted_through_the_normal_edit_path(self):
        h = self.reference_harness(vertices=object(), geometry_current=True)
        PlannerController.setLesionType(h, 'solid')
        PlannerController.setParameter(h, 'lesionDiameter', 12.)
        PlannerController.setMarginRule(h, 'consensus_2023')
        self.assertEqual(h._params['minClearance'], 12.1)
        h._edited.assert_called_once()

    def test_apply_button_still_refills_after_a_manual_edit(self):
        h = self.reference_harness()
        PlannerController.setLesionType(h, 'solid')
        PlannerController.setParameter(h, 'lesionDiameter', 12.)
        PlannerController.setMarginRule(h, 'consensus_2023')
        PlannerController.setParameter(h, 'minClearance', 30.)
        self.assertEqual(h._params['minClearance'], 30.)  # a manual adjustment is respected
        PlannerController.applyMarginReference(h)
        self.assertEqual(h._params['minClearance'], 12.1)

    def test_new_saved_parameters_restore_without_accepting_clinical_pass_flag(self):
        value = saved_plan()
        value.update(schema=WEDGE_SCHEMA, parameters=dict(default_parameters(),
            planningModel='plane_wedge', wedgeAngle=90., cutTilts=[45., 45.],
            lesionType='mixed', lesionDiameter=12., marginRule='consensus_2023',
            minClearance=12.1, baseClearance=2.))
        value['result']['clinical_status'] = 'APPROVED'
        with TemporaryDirectory() as folder:
            path = Path(folder) / 'plan.json'
            path.write_text(json.dumps(value), encoding='utf-8')
            h = planner_harness()
            PlannerController.loadPlanFromPath(h, str(path))
        h._enqueue.assert_called_once_with('manual')
        self.assertEqual(h._params, value['parameters'])
        self.assertEqual(h._result, {})  # only fresh evaluation can produce a result


if __name__ == '__main__':
    unittest.main()
