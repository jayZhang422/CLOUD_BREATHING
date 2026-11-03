"""Independent model constraints and clinician-selected margin references.

References describe selected patient populations, not clinical eligibility.
No geometry, saved file, or reference selection confirms clinical suitability.
"""
import math

import numpy as np


LESION_TYPES = ('unconfirmed', 'solid', 'cystic', 'mixed')
# Values written by earlier versions. They are not valid choices any more, and
# none maps onto the new types without a clinical decision, so a saved plan
# that carries one is restored as unconfirmed for the doctor to choose again.
LEGACY_LESION_TYPES = ('pure_ggo', 'contains_solid', 'other')
MARGIN_RULES = ('manual', 'consensus_2023', 'nccn_reference')
CONSTRAINT_VERSION = 2
PLAN_SCHEMA = 'cloud-breathing-plan-v2'
# The only saved-plan format: the dual-plane wedge (formerly the research model file).
WEDGE_SCHEMA = 'cloud-breathing-plan-research-v1'
NUMERIC_LIMITS = dict(yaw=(-180., 180.), pitch=(-89., 89.), margin=(1., 80.),
    baseOffset=(0., 80.), padding=(1., 3.), minClearance=(.1, 80.),
    baseClearance=(.1, 80.), lesionDiameter=(0., 200.), rotation=(0., 180.),
    # Candidate guard only: retain ordinary large-anatomy test cases while
    # rejecting the multi-thousand-cm2 degenerate bases seen in bad fits.
    baseArea=(0., 2000.))


def default_parameters():
    # New cases start with an explicit geometric safety baseline. A clinical
    # margin is selected separately from CT/pathology context and must not be
    # silently prescribed before the clinician confirms it.
    return dict(yaw=-34., pitch=-44., margin=1., baseOffset=8., padding=1.2,
        minClearance=1., baseClearance=1., rotation=60., baseArea=0.,
        lesionType='unconfirmed', marginRule='manual', lesionDiameter=0.,
        constraintVersion=CONSTRAINT_VERSION)


def restore_parameters(params, schema):
    """Validate before mutation; explicitly migrate the old coupled threshold."""
    if not isinstance(params, dict):
        raise ValueError('规划文件缺少规划参数')
    if schema != WEDGE_SCHEMA or params.get('planningModel') != 'plane_wedge':
        raise ValueError('仅支持双平面楔形规划文件')
    legacy, research = False, True
    required = set(NUMERIC_LIMITS)
    if not required <= params.keys():
        raise ValueError('规划文件缺少规划参数')
    result = {}
    for name, (low, high) in NUMERIC_LIMITS.items():
        if research and name == 'rotation':
            high = 360.
        value = params.get(name, params.get('minClearance') if name == 'baseClearance' else 0.)
        if (isinstance(value, bool) or not isinstance(value, (int, float))
                or not math.isfinite(value) or not low <= value <= high):
            raise ValueError('规划参数超出允许范围：' + name)
        result[name] = float(value)
    for name, choices, default in (('lesionType', LESION_TYPES, 'unconfirmed'),
                                    ('marginRule', MARGIN_RULES, 'manual')):
        value = params.get(name, default) if legacy else params.get(name)
        if name == 'lesionType' and value in LEGACY_LESION_TYPES:
            value = 'unconfirmed'
        if value not in choices:
            raise ValueError('规划规则无效：' + name)
        result[name] = value
    if not legacy and (type(params.get('constraintVersion')) is not int
                       or params['constraintVersion'] != CONSTRAINT_VERSION):
        raise ValueError('不支持的规划约束版本')
    result['constraintVersion'] = CONSTRAINT_VERSION
    if 'safetyFit' in params:
        if not isinstance(params['safetyFit'], bool):
            raise ValueError('安全包络标志无效')
        result['safetyFit'] = params['safetyFit']
    if not legacy and 'planningModel' in params:
        from .planning_models import MODELS
        if params['planningModel'] not in MODELS:
            raise ValueError('不支持的规划模型')
        result['planningModel'] = params['planningModel']
    if not legacy and 'wedgeAngle' in params:
        angle = params['wedgeAngle']
        if isinstance(angle, bool) or not isinstance(angle, (int,float)) or not math.isfinite(angle) or not 20. <= angle <= 160.:
            raise ValueError('楔形展开角超出范围')
        result['wedgeAngle'] = float(angle)
    if research:
        tilts = params.get('cutTilts')
        if (not isinstance(tilts, list) or len(tilts) != 2 or
            any(isinstance(a, bool) or not isinstance(a, (int, float)) or
                not math.isfinite(a) or not 10. <= a <= 80. for a in tilts)):
            raise ValueError('研究规划缺少有效的独立切面倾角')
        result['cutTilts'] = list(map(float, tilts))
        if 'wedgeAngle' not in result:
            raise ValueError('研究规划缺少展开角')
    return result


def base_clearance(params):
    # Direct legacy benchmark callers keep their original coupled semantics.
    return float(params.get('baseClearance', params['minClearance']))


def separate_constraints(params):
    return 'baseClearance' in params


def cut_plane_margin(points, faces):
    """Signed minimum to the three cutting side planes; face 0 is external.

    Each distance is affine on a tumor triangle, so all input vertices give
    the exact minimum on the represented triangle surface. Supporting planes
    give a conservative margin relative to the finite in-lung cut patches.
    This is a model metric, not a pathological margin or a deformation model.
    """
    sides = faces[1:]
    if len(sides) != 3:
        raise ValueError('切割侧面必须为三张')
    origins = np.asarray([f[0] for f in sides], dtype=np.float64)
    normals = np.asarray([f[3] for f in sides], dtype=np.float64)
    return float(np.min(-np.einsum('nfi,fi->nf',
        np.asarray(points, dtype=np.float64)[:, None, :] - origins, normals)))


def margin_reference(params):
    lesion = params.get('lesionType', 'unconfirmed')
    rule = params.get('marginRule', 'manual')
    diameter = float(params.get('lesionDiameter', 0.))
    target = float(params['minClearance'])
    output = dict(available=False, thresholdMm=None, strictGreater=False,
        suggestedMm=None, targetMeetsReference=None, sourceUrl='',
        clinicalStatus='PENDING_CONFIRMATION', clinicalText='临床条件待确认')
    if rule == 'manual':
        output['description'] = '手动切缘目标；由胸外科医生结合 CT、病理及手术条件确定。'
        return output
    if lesion == 'cystic':
        output['description'] = '囊性病灶没有可引用的切缘参考；请使用手动规则，由医生确定。'
        return output
    if lesion not in ('solid', 'mixed'):
        output['description'] = '请先由医生确认病灶类型（实性／混合）；囊性或其他病灶请使用手动规则。'
        return output
    if not math.isfinite(diameter) or diameter <= 0.:
        output['description'] = ('暂无病灶最大直径：请先加载 CT 标尺并只选一个病灶，'
                                 '或手动填写；STL 不能判断病灶类型。')
        return output
    if diameter > 20.:
        output['description'] = '当前参考面向经过筛选的 ≤20 mm 病灶；超出范围请由医生手动确定。'
        return output
    if rule == 'consensus_2023':
        threshold, strict = diameter, True
        output['sourceUrl'] = 'https://pmc.ncbi.nlm.nih.gov/articles/PMC10273154/'
        text = ('实性病灶：模型切缘参考 >病灶最大直径。' if lesion == 'solid' else
                '混合病灶按含实性成分处理：模型切缘参考 >病灶最大直径。')
        text += '适用性及冰冻病理切缘阴性需医生确认。'
    elif rule == 'nccn_reference':
        threshold, strict = max(20., diameter), False
        output['sourceUrl'] = 'https://pmc.ncbi.nlm.nih.gov/articles/PMC12541856/'
        text = '选定早期周围型 NSCLC 场景参考 ≥max(20 mm, 病灶最大直径)；依据 2025 综述，适用性需医生确认。'
    else:
        output['description'] = '未知参考规则，请重新选择。'
        return output
    # UI resolution is 0.1 mm. Do not round a strict > threshold down to =.
    suggested = ((math.floor(threshold * 10. + 1e-9) + 1) / 10. if strict else
                 math.ceil(threshold * 10. - 1e-9) / 10.)
    output.update(available=True, thresholdMm=threshold, strictGreater=strict,
        suggestedMm=suggested, targetMeetsReference=(target > threshold if strict else target >= threshold),
        description=text)
    return output


def constraint_report(params, tumor_margin, valid):
    reference = margin_reference(params)
    threshold = reference['thresholdMm']
    model_meets = (None if threshold is None else tumor_margin > threshold
                   if reference['strictGreater'] else tumor_margin >= threshold)
    return dict(constraint_version=CONSTRAINT_VERSION if separate_constraints(params) else 1,
        geometric_constraints_passed=bool(valid),
        clinical_status='PENDING_CONFIRMATION', clinical_status_text='临床条件待确认',
        lesion_type=params.get('lesionType', 'unconfirmed'),
        lesion_diameter_mm=params.get('lesionDiameter', 0.),
        margin_rule=params.get('marginRule', 'manual'), margin_reference=reference,
        model_margin_meets_reference=model_meets)
