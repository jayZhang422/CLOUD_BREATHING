"""Exact native/reference predicates, boundary cases, and bounded cancellation."""
import os
from pathlib import Path
import platform
import sys
from threading import Event
import unittest
from unittest.mock import patch

import numpy as np

sys.path.insert(0, str(Path(__file__).resolve().parents[1]))
from cas_frontend.display_contact import contact_mask, numpy_contact_mask
from cas_frontend.display_contact_native import library
from cas_frontend.mesh_cpu import CpuMeshIndex
from cas_frontend.planning_cancel import cancellation_scope, PlanningCancelled


def cube(offset=0.):
    v = np.asarray([[x, y, z] for x in (0., 10.) for y in (0., 10.) for z in (0., 10.)])
    ids = ((0,1,3),(0,3,2),(4,6,7),(4,7,5),(0,4,5),(0,5,1),
           (2,3,7),(2,7,6),(0,2,6),(0,6,4),(1,5,7),(1,7,3))
    return v[np.asarray(ids)] + offset


# The shipped library is built for the board; on Linux aarch64 it must load.
@unittest.skipUnless(sys.platform == 'linux' and platform.machine() == 'aarch64',
                     'libdisplay_contact.so is a Linux aarch64 (KV260) binary')
class NativeContactTests(unittest.TestCase):
    @classmethod
    def setUpClass(cls):
        library()  # Missing/unloadable native binary is a test failure.

    def compare(self, mesh, points, tolerances=(0., 1.), leaf_size=8):
        index = CpuMeshIndex(mesh, leaf_size=leaf_size)
        for tolerance in tolerances:
            expected = numpy_contact_mask(index, points, tolerance)
            with patch.dict(os.environ, CLOUD_BREATHING_DISPLAY_CONTACT_BACKEND='native'):
                actual = contact_mask(index, points, tolerance)
            np.testing.assert_array_equal(actual, expected)
        return index

    def test_random_closed_mesh_and_disconnected_solids(self):
        rng = np.random.default_rng(20261025)
        mesh = np.concatenate((cube(), cube(np.asarray([20., 0., 0.]))))
        points = rng.uniform([-5., -5., -5.], [35., 15., 15.], (3000, 3))
        index = self.compare(mesh, points, (0., .01, 1.), 3)
        self.assertGreater(index._display_contact_stats['native_points'], 0)

    def test_distance_threshold_nextafter_and_degenerate_triangles(self):
        values = np.asarray([np.nextafter(-1., -np.inf), -1., np.nextafter(-1., np.inf),
                             -1.-1.e-8, -1.+1.e-8, 0., 5., 10., 11.])
        points = np.column_stack((values, np.full(len(values), 5.), np.full(len(values), 5.)))
        mesh = np.concatenate((cube(), np.zeros((1, 3, 3)),
            np.asarray([[[20.,0.,0.],[21.,0.,0.],[22.,0.,0.]]])))
        index = self.compare(mesh, points)
        self.assertGreater(index._display_contact_stats.get('numpy_guard_points', 0), 0)

    def test_ray_edges_vertices_and_adjacent_hit_deduplication(self):
        direction = np.asarray([1., .371390676, .127831]); direction /= np.linalg.norm(direction)
        targets = np.concatenate((cube().reshape(-1,3), [[10.,5.,5.],[10.,0.,5.],[10.,5.,10.]]))
        origins = targets - direction * 25.
        # Multiple coincident faces, then sheets around the ORIGINAL 1e-5 mm hit tolerance.
        for gap in (0., .999999e-5, 1.e-5, 1.000001e-5):
            mesh = np.concatenate((cube(), cube()+direction*gap))
            self.compare(mesh, origins, (0., .1), 3)

    def test_scaled_shifted_and_ill_conditioned_geometry(self):
        rng = np.random.default_rng(42)
        for scale, shift in ((1.e-3, 0.), (1., -500.), (1.e3, 1.e6)):
            mesh = cube()*scale+shift
            skinny = np.asarray([[[0.,0.,0.],[10.,0.,0.],[5.,1.e-13,0.]]])*scale+shift
            points = rng.uniform(-2.,12.,(800,3))*scale+shift
            self.compare(np.concatenate((mesh, skinny)), points, (0., scale))

    def test_new_index_uses_new_geometry_without_result_cache(self):
        points = np.asarray([[5.,5.,5.], [25.,25.,25.]])
        first, second = self.compare(cube(), points), self.compare(cube(20.), points)
        with patch.dict(os.environ, CLOUD_BREATHING_DISPLAY_CONTACT_BACKEND='native'):
            np.testing.assert_array_equal(contact_mask(first, points), [True, False])
            np.testing.assert_array_equal(contact_mask(second, points), [False, True])

    def test_normal_application_default_selects_native_library(self):
        index = CpuMeshIndex(cube())
        environment = dict(os.environ)
        environment.pop('CLOUD_BREATHING_DISPLAY_CONTACT_BACKEND', None)
        with patch.dict(os.environ, environment, clear=True):
            np.testing.assert_array_equal(contact_mask(index, [[5.,5.,5.],[15.,5.,5.]]), [True, False])
        self.assertEqual(index._display_contact_stats['native_points'], 2)

    def test_cancellation_between_bounded_native_batches(self):
        index, token = CpuMeshIndex(cube()), Event()
        from cas_frontend.display_contact_native import query
        calls = []
        def cancel_after_chunk(*args):
            result = query(*args)
            calls.append(len(args[1])); token.set()
            return result
        with patch.dict(os.environ, CLOUD_BREATHING_DISPLAY_CONTACT_BACKEND='native'), \
                patch('cas_frontend.display_contact_native.query', side_effect=cancel_after_chunk), \
                cancellation_scope(token):
            with self.assertRaises(PlanningCancelled):
                contact_mask(index, np.tile([[5.,5.,5.]], (1024,1)))
        self.assertEqual(calls, [256])


if __name__ == '__main__':
    unittest.main()
