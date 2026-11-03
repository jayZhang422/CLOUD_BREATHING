"""Per-workload measurements; overlapping intervals are explicitly named."""
import math


class PlTelemetry:
    def __init__(self):
        self.groups = {}

    def record(self, operation, context, count, response, elapsed_ms):
        key = context + '/' + operation
        group = self.groups.setdefault(key, dict(calls=0, records=0, batches={}, latency_ms=[],
                                                 wall_ms=0., cycles=0, timings_ms={}))
        group['calls'] += 1
        group['records'] += count
        group['batches'][str(count)] = group['batches'].get(str(count), 0) + 1
        group['latency_ms'].append(float(elapsed_ms))
        group['wall_ms'] += elapsed_ms
        group['cycles'] += int(response.get('cycles', 0))
        for source in ('timings_ms', 'transport_timings_ms', 'server_timings_ms', 'frontend_timings_ms'):
            for name, value in response.get(source, {}).items():
                full_name = source + '/' + name
                group['timings_ms'][full_name] = group['timings_ms'].get(full_name, 0.) + float(value)

    def summary(self):
        groups = {}
        for key, value in self.groups.items():
            latencies = sorted(value['latency_ms'])
            def percentile(fraction):
                position = (len(latencies) - 1) * fraction
                lo, hi = math.floor(position), math.ceil(position)
                return latencies[lo] + (latencies[hi] - latencies[lo]) * (position - lo)
            groups[key] = {name: item for name, item in value.items() if name != 'latency_ms'}
            groups[key]['latency_ms'] = dict(p50=percentile(.5), p95=percentile(.95),
                                             min=latencies[0], max=latencies[-1])
        return dict(groups=groups, nesting={
            'wall_ms': 'outer planner evaluator interval; contains frontend, transport, server and driver',
            'frontend_timings_ms': 'outer PlMetrics validation and privileged call',
            'transport_timings_ms': 'client startup, mesh preparation, ray packing, encode/write, wait/decode are sequential',
            'server_timings_ms': 'server total contains JSON parse, unpack/validation and driver; excludes blocked pipe read and response serialization',
            'timings_ms/prepare': 'driver preparation; contains mesh validation/key, BVH build and ray packing',
            'timings_ms/bvh_build': 'nested inside prepare',
            'timings_ms/pl_compute': 'hardware cycles overlap dma_wait',
            'job_ms': 'driver DMA submission through result validation; nested inside driver and wall',
            'all_phases_ms': 'geometry parent/child timers overlap; do not sum as elapsed time'})
