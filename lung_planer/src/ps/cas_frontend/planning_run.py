"""One dual-plane wedge planning workload on the CPU or the PL mesh accelerator."""
import numpy as np

from .planning_geometry import PlanningCase
from .planning_cancel import checkpoint


def make_case(job, backend, pl, *, cache_pl_mesh=True):
    checkpoint()
    accelerated = backend == 'pl'
    model = job.get('params', {}).get('planningModel', 'plane_wedge')
    def mesh_evaluator(triangles, origins, directions, **kwargs):
        checkpoint()
        result = pl.evaluate_mesh_rays(triangles, origins, directions,
                                    timeout_cycles=900_000_000, timeout_seconds=15., **kwargs)
        checkpoint()
        return result
    def distance_evaluator(triangles, points):
        checkpoint()
        groups = getattr(case, '_triangle_groups', None)
        solid_ids = groups
        result = pl.evaluate_mesh_distances(triangles, points,
                                          timeout_cycles=900_000_000, timeout_seconds=15.,
                                          solid_ids=solid_ids)
        checkpoint()
        return result
    case = PlanningCase(
        job['directory'], job['lung'], job['tumor'],
        mesh_evaluator=mesh_evaluator if accelerated else None,
        ray_mode='bvh_pl' if accelerated else 'cpu',
        # PL evaluates dual-plane candidates; the exact surface Boolean of every
        # finalist remains the PS/Manifold authority.
        strict_pl=False,
        distance_evaluator=distance_evaluator if accelerated else None,
        tumor_triangles=job.get('tumor_triangles'),
        whole_lung_files=job.get('whole_lung', job.get('source_lung')),
        ct_spacing=job.get('ct_spacing'))
    case._planning_model = model
    case._dual_plane_pl = pl if accelerated and model == 'plane_wedge' else None
    # The source-coordinate case mesh is immutable; wire packing can be reused.
    case.triangles.setflags(write=False)
    checkpoint()
    case.points.setflags(write=False)
    if accelerated and cache_pl_mesh and hasattr(case, '_mesh_resource'):
        pl.cache_mesh_resource(case._mesh_resource)
    if accelerated and model == 'plane_wedge' and job.get('mode') == 'auto':
        from .planning_models import prepare_research_candidates
        from .planning_cancel import cancellation_scope
        with cancellation_scope(job.get('_cancel_token')):
            prepare_research_candidates(case, dict(job, backend=backend))
    return case


def run_case(case, job, backend, pl, progress=lambda message: None,
             cancelled=lambda: False):
    """Run the dual-plane wedge search and convert display geometry to STL source coordinates."""
    from .planning_models import model_name, run_research
    if model_name(job['params']) != 'plane_wedge':
        raise ValueError('不支持的规划模型：仅保留双平面楔形')
    research = run_research(case, dict(job, backend=backend), progress, cancelled)
    # The search evaluates in physical millimetres.  The QML scene still
    # consumes immutable STL source coordinates, so convert every display
    # mesh back while retaining physical vertices for persistence.
    display_alternatives = []
    for item in research.get('alternatives', []):
        display_alternatives.append(dict(item,
            vertices=case.to_source_vertices(item['vertices']),
            surface=case.to_source_vertices(item['surface']),
            path=case.to_source_vertices(item['path']),
            interior=case.to_source_vertices(item['interior'])))
    physical_vertices = np.asarray(research['vertices'], dtype=np.float64).copy()
    return dict(research,
        vertices=case.to_source_vertices(research['vertices']),
        surface=case.to_source_vertices(research['surface']),
        points=case.to_source_points(research['points']),
        path=case.to_source_vertices(research['path']),
        interior=case.to_source_vertices(research['interior']),
        alternatives=display_alternatives,
        physical_vertices=physical_vertices)


def diagnostics(result):
    return {key: value for key, value in result.items()
            if key not in ('lung_files', 'tumor_file')}
