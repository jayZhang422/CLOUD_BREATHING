"""Reuse must preserve safety work and reject every changed validation input."""
import tempfile
import io
import json
import types
import unittest
from unittest.mock import patch

import numpy as np

import test_strict_planner
from cas_frontend.frozen_mesh import FrozenMesh
from cas_frontend.pl_privileged import PrivilegedPlClient



class FrozenMeshTests(unittest.TestCase):
    def test_snapshots_resist_owner_mutation_and_writable_views(self):
        original = np.arange(18.).reshape(2, 3, 3)
        labels = np.array([0, 1])
        resource = FrozenMesh(original, labels)
        original[:] = 0
        labels[:] = 0
        self.assertEqual(resource.triangles[1, 2, 2], 17.)
        self.assertEqual(resource.solid_ids.tolist(), [0, 1])
        for value in (resource.triangles, resource.triangles[:, 0], resource.solid_ids):
            with self.assertRaises(ValueError):
                value.setflags(write=True)
        self.assertFalse(resource.matches(resource.triangles.view(), resource.solid_ids))
        self.assertFalse(resource.matches(resource.triangles, resource.solid_ids.copy()))

    def test_ordinary_readonly_array_is_repacked_after_owner_change(self):
        owner = np.arange(9.).reshape(1, 3, 3)
        readonly = owner.view()
        readonly.setflags(write=False)
        client = PrivilegedPlClient('unused.bit')
        client.process = types.SimpleNamespace(stdin=io.BytesIO())
        with patch.object(client, '_start'), patch.object(client, '_receive', return_value=dict(ok=True)):
            client.evaluate_mesh_rays(readonly, [[0, 0, 1]], [[0, 0, -1]])
            owner += 1
            client.evaluate_mesh_rays(readonly, [[0, 0, 1]], [[0, 0, -1]])
        first, second = [json.loads(line) for line in client.process.stdin.getvalue().splitlines()]
        self.assertNotEqual(first['mesh_key'], second['mesh_key'])
        self.assertIn('mesh', second)

    def test_service_restart_clears_residency_even_for_frozen_resource(self):
        resource = FrozenMesh(np.arange(9.).reshape(1, 3, 3))
        client = PrivilegedPlClient('unused.bit')
        client.cache_mesh_resource(resource)
        def issue():
            client.process = types.SimpleNamespace(stdin=io.BytesIO())
            with patch.object(client, '_start'), patch.object(client, '_receive', return_value=dict(ok=True)):
                client.evaluate_mesh_rays(resource.triangles, [[0, 0, 1]], [[0, 0, -1]], solid_ids=resource.solid_ids)
            return json.loads(client.process.stdin.getvalue())
        self.assertIn('mesh', issue())
        client.process = None
        client.close()
        self.assertIsNone(client._mesh_key)
        self.assertIsNone(client._mesh_wire_cache)
        self.assertIn('mesh', issue())
