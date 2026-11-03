"""The status-line lobe follows segment STLs and never names a far-away lobe."""
import sys
import unittest
from pathlib import Path

import numpy as np

sys.path.insert(0, str(Path(__file__).resolve().parents[1]))
from cas_frontend.lobe_focus import NEAREST_LOBE_TOLERANCE, find_lobe_focus

_FACES = ((0, 1, 3), (0, 3, 2), (4, 6, 7), (4, 7, 5), (0, 4, 5), (0, 5, 1),
          (2, 3, 7), (2, 7, 6), (0, 2, 6), (0, 6, 4), (1, 5, 7), (1, 7, 3))


def box(low, high):
    corners = np.array([(x, y, z) for x in (low[0], high[0]) for y in (low[1], high[1])
                        for z in (low[2], high[2])], dtype=np.float64)
    return corners[np.asarray(_FACES)]


class LobeFocusTests(unittest.TestCase):
    def test_a_lesion_inside_right_segments_names_the_right_lobe(self):
        surfaces = [('LeftUpperLobe.stl', box((200, 0, 0), (300, 100, 100))),
                    ('LeftLowerLobe.stl', box((200, 100, 0), (300, 200, 100))),
                    ('Bronchus_plan_0_seg_6RL.stl', box((0, 0, 0), (50, 100, 100))),
                    ('Bronchus_plan_0_seg_8RL.stl', box((50, 0, 0), (100, 100, 100))),
                    ('Bronchus_plan_0_seg_1RU.stl', box((0, 100, 0), (100, 200, 100))),
                    ('LungTumor1.stl', box((60, 40, 40), (70, 50, 50)))]
        report = find_lobe_focus(surfaces)
        self.assertEqual(report['selected_lobes'], ['右肺下叶'])
        self.assertEqual(report['unlocated'], [])
        self.assertNotIn('LeftLowerLobe.stl', report['selected'])
        self.assertIn('Bronchus_plan_0_seg_8RL.stl', report['selected'])

    def test_a_lesion_far_from_every_lobe_is_not_attributed(self):
        surfaces = [('LeftUpperLobe.stl', box((200, 0, 0), (300, 100, 100))),
                    ('LungTumor1.stl', box((20, 40, 40), (30, 50, 50)))]
        report = find_lobe_focus(surfaces)
        self.assertEqual(report['selected_lobes'], [])
        self.assertEqual(report['unlocated'], ['LungTumor1.stl'])

    def test_a_lesion_just_outside_a_lobe_uses_it(self):
        gap = NEAREST_LOBE_TOLERANCE / 2
        surfaces = [('RightUpperLobe.stl', box((0, 0, 0), (100, 100, 100))),
                    ('LungTumor1.stl', box((100 + gap - 5, 40, 40), (100 + gap + 5, 50, 50)))]
        report = find_lobe_focus(surfaces)
        self.assertEqual(report['selected_lobes'], ['右肺上叶'])


if __name__ == '__main__':
    unittest.main()
