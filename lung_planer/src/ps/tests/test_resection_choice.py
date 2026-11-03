"""Lesions >= 15 mm resect their lobe; smaller ones keep the wedge planner."""
import struct
import sys
import tempfile
import unittest
from pathlib import Path
from types import SimpleNamespace
from unittest.mock import Mock, patch

import numpy as np

sys.path.insert(0, str(Path(__file__).resolve().parents[1]))
from cas_frontend import resection_choice as rc
from cas_frontend.interactive_planner import InteractivePlannerController, ReleasePlanner
from cas_frontend.planning_constraints import default_parameters

_FACES = ((0, 1, 3), (0, 3, 2), (4, 6, 7), (4, 7, 5), (0, 4, 5), (0, 5, 1),
          (2, 3, 7), (2, 7, 6), (0, 2, 6), (0, 6, 4), (1, 5, 7), (1, 7, 3))


def write_box(path, low, high):
    corners = np.array([(x, y, z) for x in (low[0], high[0]) for y in (low[1], high[1])
                        for z in (low[2], high[2])], dtype='<f4')
    data = bytearray(b'box'.ljust(80, b' ') + struct.pack('<I', len(_FACES)))
    for face in _FACES:
        data += struct.pack('<3f', 0., 0., 0.) + corners[list(face)].tobytes() + b'\0\0'
    Path(path).write_bytes(bytes(data))


class ThresholdTests(unittest.TestCase):
    def test_fifteen_mm_and_above_is_lobectomy(self):
        self.assertFalse(rc.needs_lobectomy(14.9))
        self.assertTrue(rc.needs_lobectomy(15.0))
        self.assertTrue(rc.needs_lobectomy(32.))
        self.assertFalse(rc.needs_lobectomy(0.))
        self.assertFalse(rc.needs_lobectomy(float('nan')))

    def test_diameter_uses_the_ct_pixel_size(self):
        self.assertEqual(rc.component_diameter_mm(dict(max_diameter_src=20.), 0.8), 16.)
        self.assertEqual(rc.component_diameter_mm(dict(max_diameter_src=20.), None), 0.)
        self.assertEqual(rc.component_diameter_mm(dict(max_diameter_src=float('nan')), 0.8), 0.)

    def test_lobe_labels(self):
        self.assertEqual(rc.lobe_label('lobes/RightUpperLobe.stl'), '右肺上叶')
        self.assertEqual(rc.lobe_label('RightMiddleLobe.stl'), '右肺中叶')
        self.assertEqual(rc.lobe_label('LeftLowerLobe.stl'), '左肺下叶')
        self.assertEqual(rc.lobe_label('Bronchus_plan_0_seg_10RL.stl'), '右肺下叶')
        self.assertEqual(rc.lobe_groups(['RightUpperLobe.stl', 'LungTumor.stl', 'Bronchus.stl',
                                         'PulmonaryArtery.stl', 'Bronchus_plan_0_seg_1RU.stl']),
                         dict(RU=dict(lobe=['RightUpperLobe.stl'], segments=['Bronchus_plan_0_seg_1RU.stl'])))


class LocateTests(unittest.TestCase):
    def setUp(self):
        self.tmp = tempfile.TemporaryDirectory()
        root = Path(self.tmp.name)
        # Two 10x10x10 source-unit boxes side by side; spacing 2 mm -> 8000 mm^3 = 8 cm^3 each.
        write_box(root / 'RightUpperLobe.stl', (0, 0, 0), (10, 10, 10))
        write_box(root / 'RightLowerLobe.stl', (10, 0, 0), (20, 10, 10))
        self.files = ['RightLowerLobe.stl', 'RightUpperLobe.stl', 'LungTumor.stl']

    def tearDown(self):
        self.tmp.cleanup()

    def test_lesion_center_picks_the_containing_lobe_and_volumes_use_the_ct_scale(self):
        located = rc.locate_lobes(self.tmp.name, self.files,
                                  [dict(id='a', center_src=(5, 5, 5)), dict(id='b', center_src=(15, 5, 5))], 2.)
        self.assertEqual(located['placements']['a']['lobe'], 'RU')
        self.assertTrue(located['placements']['a']['contains_center'])
        self.assertEqual(located['placements']['b']['lobe'], 'RL')
        self.assertAlmostEqual(located['lobes']['RU']['volume_cm3'], 8., places=6)
        self.assertAlmostEqual(located['total_lobe_volume_cm3'], 16., places=6)

    def test_lesion_points_give_wedge_style_coverage_margin_and_area(self):
        points = [(4, 4, 4), (6, 6, 6), (4, 6, 5)]
        located = rc.locate_lobes(self.tmp.name, self.files,
                                  [dict(id='a', index=1, center_src=(5, 5, 5), points_src=points)], 2.)
        placement = located['placements']['a']
        self.assertAlmostEqual(placement['coverage_percent'], 100.)
        # Closest vertex to the RU box wall: 4 source units * 2 mm.
        self.assertAlmostEqual(placement['tumor_margin_mm'], 8., places=6)
        self.assertAlmostEqual(located['lobes']['RU']['surface_area_cm2'], 6 * 400 / 100., places=6)
        plans, _, _ = rc.split_lesions([dict(id='a', index=1, diameter_mm=20., volume_cm3=1.)], located)
        self.assertAlmostEqual(plans[0]['lesions'][0]['tumor_margin_mm'], 8., places=6)
        self.assertAlmostEqual(plans[0]['total_volume_cm3'], 16., places=6)

    def test_segment_seams_do_not_count_as_the_lobe_margin(self):
        # One lobe made of two touching segments; the lesion sits beside their shared face.
        write_box(Path(self.tmp.name) / 'Bronchus_plan_0_seg_1RL.stl', (30, 0, 0), (40, 10, 10))
        write_box(Path(self.tmp.name) / 'Bronchus_plan_0_seg_2RL.stl', (40, 0, 0), (50, 10, 10))
        files = ['Bronchus_plan_0_seg_1RL.stl', 'Bronchus_plan_0_seg_2RL.stl', 'LungTumor.stl']
        points = [(39, 5, 5), (38, 5, 5), (38.5, 5.5, 5)]
        located = rc.locate_lobes(self.tmp.name, files,
                                  [dict(id='a', index=1, center_src=(38.5, 5, 5), points_src=points)], 1.)
        placement = located['placements']['a']
        self.assertAlmostEqual(placement['coverage_percent'], 100.)
        # Nearest outer wall is 4.5 units away (y or z); the seam at x=40 is ignored.
        self.assertAlmostEqual(placement['tumor_margin_mm'], 4.5, places=6)

    def test_a_lesion_outside_every_lobe_uses_the_nearest_one(self):
        located = rc.locate_lobes(self.tmp.name, self.files, [dict(id='a', center_src=(25, 5, 5))], 1.)
        placement = located['placements']['a']
        self.assertEqual(placement['lobe'], 'RL')
        self.assertFalse(placement['contains_center'])
        self.assertAlmostEqual(placement['distance_mm'], 5., places=6)

    def test_a_lesion_far_from_every_lobe_is_refused_not_given_the_wrong_lobe(self):
        # A right-lung lesion in a case whose STLs only describe other lobes.
        with self.assertRaises(ValueError):
            rc.locate_lobes(self.tmp.name, self.files, [dict(id='a', index=1, center_src=(60, 5, 5))], 1.)

    def test_segment_stls_make_up_a_lobe_without_a_lobe_stl(self):
        root = Path(self.tmp.name)
        write_box(root / 'Bronchus_plan_0_seg_4RM.stl', (0, 20, 0), (10, 30, 10))
        write_box(root / 'Bronchus_plan_0_seg_5RM.stl', (10, 20, 0), (20, 30, 10))
        files = self.files + ['Bronchus_plan_0_seg_4RM.stl', 'Bronchus_plan_0_seg_5RM.stl', 'Bronchus.stl']
        located = rc.locate_lobes(self.tmp.name, files, [dict(id='a', center_src=(15, 25, 5))], 1.)
        self.assertEqual(located['placements']['a']['lobe'], 'RM')
        self.assertTrue(located['placements']['a']['contains_center'])
        self.assertEqual(located['lobes']['RM']['files'], ['Bronchus_plan_0_seg_4RM.stl', 'Bronchus_plan_0_seg_5RM.stl'])
        self.assertAlmostEqual(located['lobes']['RM']['volume_cm3'], 2., places=6)

    def test_a_lobe_stl_wins_over_its_own_segments(self):
        root = Path(self.tmp.name)
        write_box(root / 'Bronchus_plan_0_seg_1RU.stl', (0, 0, 0), (5, 5, 5))
        located = rc.locate_lobes(self.tmp.name, self.files + ['Bronchus_plan_0_seg_1RU.stl'],
                                  [dict(id='a', center_src=(2, 2, 2))], 1.)
        self.assertEqual(located['lobes']['RU']['files'], ['RightUpperLobe.stl'])
        self.assertAlmostEqual(located['lobes']['RU']['volume_cm3'], 1., places=6)

    def test_no_lobe_stl_is_an_error(self):
        with self.assertRaises(ValueError):
            rc.locate_lobes(self.tmp.name, ['Lung.stl', 'LungTumor.stl'], [dict(id='a', center_src=(5, 5, 5))], 1.)

    def test_split_groups_lobectomies_and_drops_small_lesions_in_a_resected_lobe(self):
        located = rc.locate_lobes(self.tmp.name, self.files, [
            dict(id='big', center_src=(5, 5, 5)), dict(id='small_same', center_src=(4, 4, 4)),
            dict(id='small_other', center_src=(15, 5, 5))], 2.)
        lesions = [dict(id='big', index=1, diameter_mm=18., volume_cm3=2.),
                   dict(id='small_same', index=2, diameter_mm=8., volume_cm3=.2),
                   dict(id='small_other', index=3, diameter_mm=9., volume_cm3=.3)]
        plans, wedge, covered = rc.split_lesions(lesions, located)
        self.assertEqual(wedge, ['small_other'])
        self.assertEqual(covered, ['small_same'])
        self.assertEqual(len(plans), 1)
        self.assertEqual(plans[0]['label'], '右肺上叶')
        self.assertAlmostEqual(plans[0]['ratio_percent'], 50., places=6)
        self.assertEqual([item['index'] for item in plans[0]['lesions']], [1, 2])


def controller(rows, selected, spacing=0.8, diameter=0.):
    params = dict(default_parameters(), lesionDiameter=diameter)
    h = SimpleNamespace(
        _ct_calibration=dict(pixel_spacing_mm=[spacing, spacing], slice_spacing_mm=1.),
        _lesion_components=[dict(id=name, max_diameter_src=size, volume_cm3=1., center_mm=(5, 5, 5))
                            for name, size in rows],
        _component_ids=list(selected), _lesion_count=len(selected), _params=params,
        _busy=False, _stopping=False, _resections=[], _wedge_index_map={}, _lobe_revision=0,
        _lobe_task_active=False, _active_cancel=None, _timer=Mock(), _status='', _vertices=None,
        _directory='case', _files=['RightUpperLobe.stl'], ready=True,
        _lobe_pool=Mock(), _lobe_signals=Mock(), changed=Mock(), resectionChanged=Mock(),
        _invalidate=Mock())
    for name in ('_ct_spacing', '_ct_ready_for_operation', '_clear_resections', '_selected_lesions',
                 '_lobe_task_finished'):
        setattr(h, name, getattr(InteractivePlannerController, name).__get__(h))
    return h


class ControllerTests(unittest.TestCase):
    def test_small_lesions_go_straight_to_the_wedge_planner(self):
        h = controller([('a', 10.)], ['a'], diameter=8.)
        with patch.object(ReleasePlanner, 'autoPlan') as wedge:
            InteractivePlannerController.autoPlan(h)
        wedge.assert_called_once()
        h._lobe_pool.start.assert_not_called()

    def test_a_large_lesion_starts_the_lobe_task_instead(self):
        h = controller([('a', 25.)], ['a'], diameter=20.)
        with patch.object(ReleasePlanner, 'autoPlan') as wedge:
            InteractivePlannerController.autoPlan(h)
        wedge.assert_not_called()
        h._lobe_pool.start.assert_called_once()
        self.assertTrue(h._busy)

    def test_the_doctor_diameter_decides_for_a_single_lesion(self):
        h = controller([('a', 10.)], ['a'], diameter=15.)  # STL says 8 mm, doctor says 15 mm
        with patch.object(ReleasePlanner, 'autoPlan') as wedge:
            InteractivePlannerController.autoPlan(h)
        wedge.assert_not_called()
        self.assertEqual(h._selected_lesions()[0]['diameter_mm'], 15.)

    def test_mixed_selection_plans_only_the_remaining_small_lesion_as_a_wedge(self):
        h = controller([('big', 25.), ('small', 10.)], ['big', 'small'])
        with patch.object(ReleasePlanner, 'autoPlan'):
            InteractivePlannerController.autoPlan(h)
        located = dict(total_lobe_volume_cm3=10.,
                       lobes=dict(RU=dict(label='右肺上叶', files=['RightUpperLobe.stl'], volume_cm3=4.),
                                  RL=dict(label='右肺下叶', files=['RightLowerLobe.stl'], volume_cm3=6.)),
                       placements={'big': dict(lobe='RU', contains_center=True, distance_mm=0.),
                                   'small': dict(lobe='RL', contains_center=True, distance_mm=0.)})
        seen = {}

        def wedge(self_):
            seen.update(ids=list(self_._component_ids), diameter=self_._params['lesionDiameter'])
        with patch.object(ReleasePlanner, 'autoPlan', wedge):
            h._lobe_task_finished(h._lobe_revision, located, '')
        self.assertEqual(seen, dict(ids=['small'], diameter=8.))
        self.assertEqual(h._component_ids, ['big', 'small'])   # the user's selection is restored
        self.assertEqual(h._params['lesionDiameter'], 0.)
        self.assertEqual([plan['label'] for plan in h._resections], ['右肺上叶'])
        self.assertEqual(h._wedge_index_map, {'small': 2})

    def test_a_stale_lobe_result_is_dropped(self):
        h = controller([('big', 25.)], ['big'])
        with patch.object(ReleasePlanner, 'autoPlan'):
            InteractivePlannerController.autoPlan(h)
        h._lobe_revision += 1  # the STL was reloaded meanwhile
        h._lobe_task_finished(h._lobe_revision - 1, dict(placements={}), '')
        self.assertEqual(h._resections, [])
        self.assertFalse(h._busy)


if __name__ == '__main__':
    unittest.main()
