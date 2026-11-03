"""Byte-exact DDR records for the RTL dual-plane mesh engine."""
import numpy as np

ABI_VERSION = 0x00050000
CANDIDATE_BYTES = 160
RESULT_BYTES = 64
RESULT_DTYPE = np.dtype(dict(
    names=['volume', 'source_area', 'cut_area', 'source_triangles',
           'cut_triangles', 'boundary_segments', 'cap_loops', 'flags',
           'job_id', 'candidate_index', 'abi'],
    formats=['<f8', '<f8', '<f8', '<u4', '<u4', '<u4', '<u4', '<u4',
             '<u4', '<u4', '<u4'],
    offsets=[0, 8, 16, 24, 32, 36, 40, 44, 48, 52, 56], itemsize=RESULT_BYTES))


def decode_results(raw, count, job_id):
    """Reject partial, stale, reordered or nonfinite DDR results as a batch."""
    if len(raw) != count * RESULT_BYTES:
        raise RuntimeError('dual-plane mesh result byte count mismatch')
    rows = np.frombuffer(raw, dtype=RESULT_DTYPE, count=count)
    if (np.any(rows['job_id'] != job_id) or np.any(rows['abi'] != ABI_VERSION)
            or not np.array_equal(rows['candidate_index'], np.arange(count))):
        raise RuntimeError('dual-plane mesh stale or incomplete result identity')
    for name in ('volume', 'source_area', 'cut_area'):
        if not np.isfinite(rows[name]).all():
            raise RuntimeError('dual-plane mesh nonfinite result: ' + name)
    return rows


def pack_candidates(candidates, mesh_center):
    from . import planner_reference as ref
    candidates = np.asarray(candidates, dtype=np.float64).reshape(-1, 4, 3)
    if not np.isfinite(candidates).all():
        raise ValueError('nonfinite candidate')
    center = np.asarray(mesh_center, dtype=np.float64).reshape(3)
    descriptors = np.zeros((len(candidates), 20), dtype='<f8')
    for index, vertices in enumerate(candidates):
        for plane_index, (point, _, _, normal) in enumerate(ref.tetra_faces(
                [tuple(row) for row in vertices[:3]], tuple(vertices[3]))):
            descriptors[index, plane_index * 4:plane_index * 4 + 3] = normal
            descriptors[index, plane_index * 4 + 3] = float(np.dot(normal, point))
        # Ridge uses the exact same planes just packed above. The former
        # helper recomputed all four faces; retain its matrix operation order.
        normals = np.asarray([descriptors[index, 4:7], descriptors[index, 8:11]])
        offsets = np.asarray([descriptors[index, 7], descriptors[index, 11]])
        gram = normals @ normals.T
        if np.linalg.det(gram) < 1e-12:
            raise ValueError('dual-plane ridge is ill-conditioned')
        descriptors[index, 16:19] = center + normals.T @ np.linalg.solve(
            gram, offsets - normals @ center)
    return descriptors.view(np.uint8).reshape(-1)
