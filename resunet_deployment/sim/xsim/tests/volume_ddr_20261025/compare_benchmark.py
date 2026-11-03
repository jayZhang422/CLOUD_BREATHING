"""只读比较两份真实板测报告；不把历史板测当作本次RTL的实测。"""
from pathlib import Path
import json
import statistics

HERE = Path(__file__).resolve().parent
ROOT = HERE.parents[3]
RUNS = ROOT / 'src/host/python/bin_udp/output/ct_01/fixed_benchmark/all_models_fused_residual/runs'


def main():
    names = ('suite_20261024_225415_402985.json', 'suite_20261025_125220_770757.json')
    reports = [json.loads((RUNS / name).read_text(encoding='utf-8')) for name in names]
    models = [{m['task']: m for m in report['models']} for report in reports]
    result = dict(scope='Historical board measurements before the current RTL fixes; no new board measurement',
                  reports=[str(RUNS / name) for name in names], models={})
    for task in ('lobe', 'airway', 'vessel', 'tumor'):
        old, new = (model[task] for model in models)
        assert old['execution_schedule_sha256'] == new['execution_schedule_sha256'], task
        indexed = [{(r['slice'], r['repeat']): r for r in m['runs']} for m in (old, new)]
        assert indexed[0].keys() == indexed[1].keys(), task
        for key, a in indexed[0].items():
            b = indexed[1][key]
            assert a['input_sha256'] == b['input_sha256'], (task, key, 'input')
            assert a['output_sha256'] == b['output_sha256'], (task, key, 'output')
        seconds = [statistics.mean(r['hardware_seconds'] for r in m['runs']) for m in (old, new)]
        stages = [{s['name']: s for s in m['runs'][0]['stages']} for m in (old, new)]
        assert stages[0].keys() == stages[1].keys(), task
        breakdown = []
        for name, a in stages[0].items():
            b = stages[1][name]
            assert a['op'] == b['op'], (task, name)
            samples = [[next(s for s in r['stages'] if s['name'] == name)['hardware'] for r in m['runs']]
                       for m in (old, new)]
            counters = {}
            for counter in ('total', 'reader_request_stall', 'reader_memory_stall', 'input_wait',
                            'memory_reads', 'memory_writes'):
                counters[counter] = [statistics.mean(s['cycles'][counter] for s in sample) for sample in samples]
            stage_seconds = [statistics.mean(s['seconds'] for s in sample) for sample in samples]
            breakdown.append(dict(name=name, op=a['op'], seconds=stage_seconds,
                                  delta_seconds=stage_seconds[1] - stage_seconds[0], counters=counters))
        op_deltas = {str(op): sum(s['delta_seconds'] for s in breakdown if s['op'] == op)
                     for op in sorted({s['op'] for s in breakdown})}
        result['models'][task] = dict(runs=len(old['runs']), identical_schedule_input_output=True,
            hardware_seconds=seconds, slowdown_percent=(seconds[1] / seconds[0] - 1) * 100,
            delta_seconds=seconds[1] - seconds[0], delta_seconds_by_op=op_deltas, stages=breakdown)
    destination = HERE / 'results/benchmark_comparison.json'
    destination.write_text(json.dumps(result, ensure_ascii=False, indent=2) + '\n', encoding='utf-8')
    for task, model in result['models'].items():
        print(task, model['hardware_seconds'], 'delta_by_op', model['delta_seconds_by_op'])
    print('[COMPARISON PASSED] matching schedules, inputs and outputs; historical measurements only')


if __name__ == '__main__':
    main()
