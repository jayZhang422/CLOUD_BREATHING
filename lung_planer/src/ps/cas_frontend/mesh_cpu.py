"""Float64 CPU-only spatial queries; independent of FPGA packing/runtime."""
import heapq
import os
from time import perf_counter
import numpy as np

from .mesh_triangle import _points_triangles_distance2
from .ray_golden import HIT_TOLERANCE_MM, collapse_crossings


class CpuMeshIndex:
    def __init__(self, triangles, groups=None, leaf_size=32):
        self.triangles = np.asarray(triangles, dtype=np.float64)
        self.groups = np.zeros(len(triangles), dtype=int) if groups is None else np.asarray(groups)
        self.group_count = int(self.groups.max()) + 1
        low, high = self.triangles.min(axis=1), self.triangles.max(axis=1)
        centers = (low + high) / 2.
        self.nodes = []

        def split(ids):
            index = len(self.nodes)
            node = [low[ids].min(axis=0), high[ids].max(axis=0), None, None, None]
            self.nodes.append(node)
            if len(ids) <= leaf_size:
                node[4] = ids
            else:
                axis = int(np.argmax(np.ptp(centers[ids], axis=0)))
                mid = len(ids) // 2
                ids = ids[np.argpartition(centers[ids, axis], mid)]
                node[2], node[3] = split(ids[:mid]), split(ids[mid:])
            return index

        split(np.arange(len(triangles)))
        self.low = np.asarray([node[0] for node in self.nodes])
        self.high = np.asarray([node[1] for node in self.nodes])
        # The tree is immutable after construction; display-contact queries
        # can share this flattened traversal view across every point batch.
        self.nodes = tuple(tuple(node) for node in self.nodes)
        for node in self.nodes:
            if node[4] is not None:
                node[4].setflags(write=False)
        self.low.setflags(write=False)
        self.high.setflags(write=False)
        self._display_contact_arrays = None
        self._display_contact_array_builds = 0
        self._display_contact_array_build_ms = 0.

    def display_contact_arrays(self):
        cached = os.environ.get('CLOUD_BREATHING_DISPLAY_BVH_CACHE', '1') != '0'
        if cached and self._display_contact_arrays is not None:
            return self._display_contact_arrays
        started = perf_counter()
        children = np.asarray([[node[2] or 0, node[3] or 0]
                               for node in self.nodes], dtype=np.int32)
        leaf = np.asarray([node[4] is not None for node in self.nodes], dtype=bool)
        width = max(len(node[4]) for node in self.nodes if node[4] is not None)
        members = np.full((len(self.nodes), width), -1, dtype=np.int64)
        for index, node in enumerate(self.nodes):
            if node[4] is not None:
                members[index, :len(node[4])] = node[4]
        for values in (children, leaf, members):
            values.setflags(write=False)
        self._display_contact_array_builds += 1
        self._display_contact_array_build_ms += (perf_counter()-started)*1000.
        arrays = children, leaf, members, width
        if cached:
            self._display_contact_arrays = arrays
        return arrays

    def _ray_box(self, origin, direction, indices):
        low, high = self.low[indices] - 1e-7, self.high[indices] + 1e-7
        moving = np.abs(direction) > 1e-14
        valid = np.all(moving | ((origin >= low) & (origin <= high)), axis=1)
        inv = np.divide(1., direction, out=np.zeros(3), where=moving)
        first, second = (low - origin) * inv, (high - origin) * inv
        near = np.where(moving, np.minimum(first, second), -np.inf).max(axis=1)
        far = np.where(moving, np.maximum(first, second), np.inf).min(axis=1)
        return valid & (far >= np.maximum(near, 0.))

    def hits(self, origin, direction):
        origin, direction = np.asarray(origin), np.asarray(direction)
        active = np.asarray([0])
        leaves = []
        while len(active):
            active = active[self._ray_box(origin, direction, active)]
            children = []
            for index in active:
                node = self.nodes[index]
                if node[4] is not None:
                    leaves.append(node[4])
                else:
                    children.extend(node[2:4])
            active = np.asarray(children, dtype=int)
        if not leaves:
            return np.empty(0)
        ids = np.concatenate(leaves)
        triangles = self.triangles[ids]
        a = triangles[:, 0]
        e1, e2 = triangles[:, 1] - a, triangles[:, 2] - a
        h = np.cross(direction, e2)
        det = np.einsum('ij,ij->i', e1, h)
        inv = np.divide(1., det, out=np.zeros_like(det), where=np.abs(det) >= 1e-9)
        offset = origin - a
        u = inv * np.einsum('ij,ij->i', offset, h)
        q = np.cross(offset, e1)
        v = inv * np.einsum('ij,j->i', q, direction)
        t = inv * np.einsum('ij,ij->i', e2, q)
        valid = ((np.abs(det) >= 1e-9) & (u >= -1e-7) & (u <= 1.0000001)
                 & (v >= -1e-7) & (u + v <= 1.0000001) & (t >= 0.))
        return union_crossings(t[valid], self.groups[ids[valid]], self.group_count)

    def distance(self, point):
        point = np.asarray(point)
        delta = np.maximum(np.maximum(self.low - point, point - self.high), 0.)
        lower2 = np.einsum('ij,ij->i', delta, delta)
        best = float('inf')
        queue = [(float(lower2[0]), 0)]
        while queue:
            bound, index = heapq.heappop(queue)
            if bound > best:
                break
            node = self.nodes[index]
            if node[4] is not None:
                best = min(best, float(_points_triangles_distance2(point, self.triangles[node[4]]).min()))
            else:
                for child in node[2:4]:
                    if lower2[child] <= best:
                        heapq.heappush(queue, (float(lower2[child]), child))
        return float(np.sqrt(best))


def union_crossings(hits, groups, group_count):
    """Merge closed-solid ray intervals, including coincident segment seams.

    Odd parity means the ray starts inside that solid. Negative infinity is
    used internally, so the merged list retains the union's origin parity.
    """
    if group_count == 1:
        return collapse_crossings(hits)
    intervals = []
    for group in np.unique(groups):
        values = collapse_crossings(hits[groups == group])
        if len(values) % 2:
            values = np.r_[-np.inf, values]
        intervals.extend(zip(values[::2], values[1::2]))
    merged = []
    for start, end in sorted(intervals):
        if merged and start <= merged[-1][1] + HIT_TOLERANCE_MM:
            merged[-1][1] = max(merged[-1][1], end)
        else:
            merged.append([start, end])
    return np.asarray([value for interval in merged for value in interval if np.isfinite(value)])
