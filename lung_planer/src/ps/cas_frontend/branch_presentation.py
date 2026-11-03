"""Build list strings in a worker; no QML conversion of the entire branch list."""
from .centerlines import KINDS

COLORS = {'artery': '#ff6472', 'vein': '#55baff', 'airway': '#7de5ab'}
STATUS = {'full': '中心线整支在切除区', 'partial': '中心线部分进入切除区',
          'near': '管壁邻近（待复核）', 'outside': '中心线在切除区外'}
ORDER = {'partial': 0, 'full': 1, 'near': 2, 'outside': 3}
# Disconnected components shorter than this are skeleton debris at vessel ends;
# they stay in the data but are neither drawn nor listed (the largest is always kept).
MIN_DISPLAY_COMPONENT_MM = 20.


def displayed_components(tree):
    lengths = {}
    for b in tree['branches']:
        lengths[b['component']] = lengths.get(b['component'], 0.) + b['length_mm']
    main = max(lengths, key=lengths.get, default=None)
    return {component for component, length in lengths.items()
            if length >= MIN_DISPLAY_COMPONENT_MM or component == main}


def displayed_branches(tree):
    keep = displayed_components(tree)
    return [b for b in tree['branches'] if b['component'] in keep]


def affected_order(row):
    return ORDER[row['status']], row['kind'], row['generation'], row['key']


def display_rows(trees, analyses=None):
    rows, affected = [], []
    for index, tree in enumerate(trees):
        keep = displayed_components(tree)
        for b in tree['branches']:
            if b['component'] not in keep:
                continue
            row = (dict(analyses[index]['rows'][b['id']]) if analyses is not None else
                   {k: b[k] for k in ('id', 'generation', 'parent', 'root', 'component', 'diameter_mm', 'length_mm')})
            if analyses is None:
                row.update(status='outside', removed_length_mm=0., cut_points=[], downstream_affected=False)
            generation = f'第 {b["generation"]} 级' if b['generation'] else '未分级'
            status_text = STATUS[row['status']] if analyses is not None else '尚未计算切除关系'
            if analyses is not None and row['downstream_affected'] and row['status'] == 'outside':
                status_text = '仅下游连通受影响（本支中心线未进入切除区）'
            row.update(key=f'{index}:{b["id"]}', tree=index, file=tree['file'], kind=tree['kind'],
                label=f'{KINDS[tree["kind"]]} · {generation}',
                color=COLORS[tree['kind']],
                statusText=status_text,
                detail=f'管径约 {b["diameter_mm"]:.1f} mm · 长 {b["length_mm"]:.1f} mm'
                    + (f' · 区域内 {row["removed_length_mm"]:.1f} mm' if analyses is not None else '')
                    + (f' · 边界点 {len(row["cut_points"])}' if row['cut_points'] else '')
                    + ('\n与上游切断分支相连，下游连通可能受影响' if row['downstream_affected'] else ''))
            rows.append(row)
            if analyses is not None and (row['status'] != 'outside' or row['downstream_affected']):
                affected.append(row)
    affected.sort(key=affected_order)
    return rows, affected
