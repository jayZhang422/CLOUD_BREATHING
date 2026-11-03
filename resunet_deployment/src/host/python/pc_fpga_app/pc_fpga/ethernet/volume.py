"""整卷DDR清单与控制；PC只生成描述符和整数坐标表，不执行模型。"""
import hashlib
from pathlib import Path
import struct
import time

import numpy as np

from .op_client import OpClient, STATUS
from ..files import check_file, read_json, write_json
from ..ct.prediction_io import file_sha256, validate_bits

ASSETS = Path(__file__).resolve().parents[2] / 'assets'
IMAGE_BASE, SCRIPT_BASE, MAP_BASE = 0x00400000, 0x08200000, 0x08800000
RESULT_BASE, DDR_LIMIT = 0x10000000, 0x1FFF0000
START, QUERY, RELEASE, ABORT = range(0x26, 0x2A)


def q16_coordinates(old, new):
    numerator = np.arange(new, dtype=np.int64) * (old - 1) * 65536
    denominator = max(new - 1, 1)
    q, r = np.divmod(numerator, denominator)
    q += (r * 2 > denominator) | ((r * 2 == denominator) & ((q & 1) != 0))
    return q.astype('<u4')


def nearest_coordinates(old, new):
    denominator = max(new - 1, 1)
    return ((2 * np.arange(new, dtype=np.int64) * (old - 1) + denominator) // (2 * denominator)).astype('<u4')


def transform(kind, orientation, channels, bit, source, destination, depth, width, height, xmap, ymap, neighbors=(0, 0, 0)):
    cmd = bytearray(64)
    struct.pack_into('<4B4I2H5I', cmd, 0, kind, orientation, channels, bit,
                     source, destination, depth, 0, width, height, xmap, ymap, *map(int, neighbors))
    return bytes(cmd)


def build_program(job, metadata, plans=None, contexts=None):
    plans = plans or read_json(ASSETS / 'volume_plans.json')
    depth = job['input']['shape'][0]
    compact = job.get('compact_bin')
    if compact is None:
        raise ValueError('VOL2 compact BIN metadata is required')
    if job['input']['ddr_base'] != IMAGE_BASE or not 1 <= depth <= 480:
        raise ValueError('整卷固件要求 --image-base 0x00400000、层数 1..480')
    if RESULT_BASE + depth * 524288 > DDR_LIMIT:
        raise ValueError('整卷结果超过 DDR 容量')
    affine = np.asarray(metadata['affine_z_y_x_to_lps_mm'], dtype=np.float64)
    spacing = np.linalg.norm(affine[:3, :3], axis=0)
    directions = affine[:3, :3] / spacing
    direction = metadata['anatomical_z_direction']
    if (direction not in (-1, 1) or not np.allclose(directions[:2], [[0, 0, 1], [0, 1, 0]], atol=1e-3)
            or not np.allclose(abs(directions[2]), [1, 0, 0], atol=1e-3)):
        raise ValueError('整卷模型要求已校验的轴向 DICOM L/P 平面与层序')
    maps, records, summaries = bytearray(), bytearray(), []

    def table(values):
        address = MAP_BASE + len(maps)
        payload = np.asarray(values, dtype='<u4').tobytes()
        maps.extend(payload + bytes((-len(payload)) % 32))
        return address

    def record(kind, payload, context=None):
        if len(payload) != 64:
            raise ValueError('DDR command payload must be 64 bytes')
        records.extend(bytes([kind]) + bytes(31) + payload)
        if contexts is not None:
            contexts.append(context)

    for task, channels, bit, orientation in (('lobe', 5, 0, 2), ('airway', 1, 5, 1),
                                             ('vessel', 2, 6, 0), ('tumor', 1, 8, 1)):
        shape = (np.maximum(2, np.rint((np.array([depth, 512, 512]) - 1) * spacing / 1.5).astype(int) + 1)
                 if task == 'lobe' else np.array([depth, 512, 512]))
        dz, height, width = map(int, shape)
        if max(height, width) > 512 or dz > 65535:
            raise ValueError(f'{task}: model grid exceeds FPGA limits: {shape}')
        restore_x = table(nearest_coordinates(width, 512) + (512 - width) // 2)
        restore_y = table(nearest_coordinates(height, 512) + (512 - height) // 2)
        native_z = nearest_coordinates(dz, depth)
        source_name = 'lobe' if task == 'lobe' else 'native'
        view = next(v for v in compact['views'] if v['name'] == source_name)
        # 朝向 1/2 的 gather 对 8 行缓存全未命中；若存在朝向等价的预转置视图，改用它并以朝向 0 读取。
        # classify（kind 3）仍使用原朝向：它读取的是模型输出 head，不受输入视图布局影响。
        gather_orientation = orientation
        derived = next((v for v in compact['views']
                        if v.get('source') == source_name and v.get('orientation') == orientation), None)
        if derived is not None:
            view, gather_orientation = derived, 0
        view_depth = view['planes']
        if (view_depth != dz and task == 'lobe') or (view_depth != depth and task != 'lobe'):
            raise ValueError(f'{task}: compact view depth does not match model grid')
        plan = plans[task]
        if plan['arena_end'] > RESULT_BASE or plan['input'] < 0x0A000000:
            raise ValueError(f'{task}: scratch/result overlap')
        before = len(records) // 96
        for z in range(dz):
            neighbors = np.clip(z + np.array([-1, 0, 1]) * (direction if task == 'lobe' else 1),
                                0, view_depth - 1)
            command = bytearray(64)
            struct.pack_into('<4B4I2H5I', command, 0, 4, gather_orientation | (4 if direction < 0 else 0),
                1 if task == 'lobe' else 0, 0, view['base'], plan['input'], view_depth,
                view['bytes'], view['width'], view['height'], view['row_stride'],
                view['plane_stride'], *map(int, neighbors))
            record(4, bytes(command), dict(model=task, slice=z, stage='gather', opcode=4))
            for stage in plan['stages']:
                desc = bytes.fromhex(stage['descriptor_hex'])
                record(1, desc, dict(model=task, slice=z, stage=stage['name'], opcode=desc[0]))
            for native in np.flatnonzero(native_z == z):
                record(3, transform(3, orientation, channels, bit, plan['head'],
                                    RESULT_BASE + int(native) * 524288, depth, 512, 512, restore_x, restore_y),
                       dict(model=task, slice=z, native_slice=int(native), stage='classify', opcode=3))
        summaries.append(dict(model=task, grid=list(map(int, shape)), commands=len(records) // 96 - before,
                              stages_per_slice=len(plan['stages']), contract_sha256=plan['contract_sha256']))
    record(255, bytes(64), dict(stage='END'))
    count = len(records) // 96
    if count > 65536 or SCRIPT_BASE + len(records) > MAP_BASE or MAP_BASE + len(maps) > 0x09000000:
        raise ValueError('执行清单或坐标表超出 DDR 保留区')
    header = struct.pack('<8I', 0x324C4F56, 2, SCRIPT_BASE, count, IMAGE_BASE, depth, RESULT_BASE, depth * 524288) + bytes(32)
    return bytes(records), bytes(maps), header, summaries


def upload_program(case_dir, job, host, port, bind, timeout=1., progress=lambda text: None, client_factory=OpClient):
    case = Path(case_dir)
    program, maps, header, summaries = build_program(job, read_json(case / 'input/metadata.json'))
    client = client_factory(host, port, timeout, bind=bind)
    try:
        if client.rpc(STATUS)['state'] != 0:
            raise RuntimeError('板端仍保留运行；请先完成回读或显式释放')
        receipt = read_json(case / 'handoff/send_receipt.json')
        if receipt.get('compact_sha256') != job['compact_bin']['sha256']:
            raise ValueError('已上传 VOL2 BIN 与程序清单的 compact SHA256 不匹配')
        for address, payload, name in ((0x08000000, (ASSETS / 'tumor.params.bin').read_bytes(), 'tumor parameters'),
                                       (SCRIPT_BASE, program, 'DDR execution list'), (MAP_BASE, maps, 'coordinate tables')):
            progress(f'Upload {name}: {len(payload):,} bytes')
            client.upload(address, payload, block_size=8 * 1024)
    finally:
        client.close()
    package = dict(format='pc-fpga-volume-program-v2', header_hex=header.hex(), commands=len(program) // 96,
                   schedule_sha256=hashlib.sha256(program).hexdigest(), maps_sha256=hashlib.sha256(maps).hexdigest(),
                   input_sha256=job['input']['sha256'], compact_sha256=job['compact_bin']['sha256'], models=summaries)
    write_json(case / 'handoff/program.json', package)
    return package


def reason_volume(case_dir, host, port, bind, timeout=1., run_timeout=7200., progress=lambda text: None, client_factory=OpClient, stall_timeout=120.):
    case = Path(case_dir)
    job, package, receipt = (read_json(case / name) for name in ('handoff/job.json', 'handoff/program.json', 'handoff/send_receipt.json'))
    if package['input_sha256'] != job['input']['sha256'] or receipt['input_sha256'] != job['input']['sha256']:
        raise ValueError('输入与DDR执行清单身份不匹配')
    if package.get('compact_sha256') != receipt.get('compact_sha256'):
        raise ValueError('VOL2 compact BIN 身份与已上传文件不匹配')
    contexts = []
    program, _, _, _ = build_program(job, read_json(case / 'input/metadata.json'), contexts=contexts)
    if hashlib.sha256(program).hexdigest() != package['schedule_sha256']:
        raise ValueError('本地算子清单已变化，不能用它诊断板端旧任务')
    identity, started = receipt['transfer_id'], time.monotonic()
    changed, last_saved, last_count = started, started - 1., None
    last_hardware_progress = None
    diagnostic_path = case / 'handoff/inference_status.json'
    diagnostic = dict(transfer_id=identity, total_commands=package['commands'], status='waiting', samples=[])
    client = client_factory(host, port, timeout, bind=bind)
    try:
        response = client.rpc(START, identity, bytes.fromhex(package['header_hex']))
        while True:
            now = time.monotonic()
            count = response['mac_bytes']
            if count != last_count:
                changed, last_count = now, count
            context = contexts[count] if 0 <= count < len(contexts) else None
            diagnostic.update(status='complete' if response['state'] == 2 else 'running',
                              state=response['state'], completed_commands=count,
                              elapsed_seconds=round(now-started, 3), no_progress_seconds=round(now-changed, 3),
                              current_command=context)
            raw_debug = response.get('data', b'')
            if len(raw_debug) >= 16:
                # QUERY appends VDG1 (32B) or a 64B VDG2/VDG3 snapshot.
                magic = struct.unpack_from('<I', raw_debug)[0]
                if magic == 0x31474456 and len(raw_debug) >= 16:
                    outputs, inputs, flags = struct.unpack_from('<3I', raw_debug, 4)
                    diagnostic['hardware'] = dict(engine_state=flags & 15, scheduler_state=(flags >> 4) & 15,
                        input_words=inputs, output_words=outputs, read_idle=bool(flags & 256),
                        memory_pending=bool(flags & 512), core_done=bool(flags & 1024), core_reset_n=bool(flags & 2048))
                    hardware_progress = (flags & 15, inputs, outputs)
                elif magic in (0x32474456, 0x33474456, 0x34474456) and len(raw_debug) >= 64:
                    words = struct.unpack_from('<16I', raw_debug)
                    # VDG4 的第三个 32B 字给出各计数高 32 位；旧版本保持 32 位回绕语义。
                    high = struct.unpack_from('<8I', raw_debug, 64) if magic == 0x34474456 and len(raw_debug) >= 96 else (0,) * 8
                    flags, reads, writes, request_stall, response_wait = words[1:6]
                    fetch, operator = words[6:8]
                    gather, classify = words[8:10]
                    fetch |= high[0] << 32; operator |= high[1] << 32
                    gather |= high[2] << 32; classify |= high[3] << 32
                    response_wait |= high[4] << 32; reads |= high[5] << 32; writes |= high[6] << 32
                    hardware = dict(engine_state=flags & 15, scheduler_state=(flags >> 4) & 15,
                        input_words=reads, output_words=writes, read_idle=bool(flags & 256),
                        memory_pending=bool(flags & 512), core_done=bool(flags & 1024), core_reset_n=bool(flags & 2048),
                        diagnostic_version={0x32474456: 2, 0x33474456: 3}.get(magic, 4),
                        gather_read_requests=reads, gather_write_requests=writes,
                        gather_request_stall_cycles=request_stall, gather_response_wait_cycles=response_wait,
                        gather_response_count=(words[15] | high[7] << 32) if magic != 0x32474456 else None,
                        gather_pending=words[14] & 15 if magic != 0x32474456 else None,
                        gather_pending_peak=(words[14] >> 4) & 15 if magic != 0x32474456 else None)
                    if magic != 0x32474456:
                        hardware.update(compact_cache_hits=words[12], compact_cache_misses=words[13])
                        kind4_cycles = words[10] | (words[11] << 32)
                        hardware['kind4_cycles'] = kind4_cycles
                        diagnostic['volume_cycles'] = dict(fetch=fetch, operator=operator,
                            gather=gather, classify=classify, kind4=kind4_cycles)
                        hardware_progress = (flags & 15, reads, writes, words[12], kind4_cycles)
                    else:
                        diagnostic['volume_cycles'] = dict(fetch=fetch, operator=operator,
                                                           gather=gather, classify=classify)
                        hardware_progress = (flags & 15, reads, writes, gather)
                    diagnostic['hardware'] = {key: value for key, value in hardware.items() if value is not None}
                else:
                    hardware_progress = None
                if diagnostic.get('hardware', {}).get('diagnostic_version') not in (2, 3, 4):
                    if hardware_progress != last_hardware_progress:
                        changed, last_hardware_progress = now, hardware_progress
                        diagnostic['no_progress_seconds'] = 0.
                    if len(raw_debug) >= 32:
                        fetch, operator, gather, classify = struct.unpack_from('<4I', raw_debug, 16)
                        diagnostic['volume_cycles'] = dict(fetch=fetch, operator=operator,
                                                           gather=gather, classify=classify)
                elif hardware_progress is not None and hardware_progress != last_hardware_progress:
                    changed, last_hardware_progress = now, hardware_progress
                    diagnostic['no_progress_seconds'] = 0.
            if now-last_saved >= 1. or response['state'] != 1:
                diagnostic['samples'] = (diagnostic['samples'] + [dict(elapsed_seconds=round(now-started, 3), completed_commands=count,
                    hardware=diagnostic.get('hardware'))])[-8:]
                write_json(diagnostic_path, diagnostic)
                last_saved = now
            if response['run_id'] != identity or response['bytes'] != job['result_contract']['bytes']:
                raise RuntimeError('整卷状态身份或结果长度不匹配')
            if response['state'] == 2:
                break
            if response['state'] != 1:
                raise RuntimeError(f'整卷失败或被中止：{response}')
            if now - changed >= stall_timeout:
                raise TimeoutError(f'FPGA命令进度连续 {stall_timeout:g}s 未变化：{count}/{package["commands"]}，当前 {context}；诊断：{diagnostic_path}；板端现场保留')
            if now - started > run_timeout:
                raise TimeoutError('整卷仍在运行，保留板端现场；重新 reasoning 可继续等待')
            location = f"{context.get('model', '')} slice {context.get('slice', '')} {context['stage']}" if context else 'finished'
            hardware = diagnostic.get('hardware')
            detail = f"; E{hardware['engine_state']} in/out={hardware['input_words']}/{hardware['output_words']}" if hardware else ''
            progress(f"FPGA {count:,}/{package['commands']:,}; {location}{detail}; {now-started:.1f}s")
            time.sleep(.25)
            response = client.rpc(QUERY, identity)
    except BaseException as exc:
        diagnostic.update(status='failed', error=str(exc) or type(exc).__name__)
        write_json(diagnostic_path, diagnostic)
        raise
    finally:
        client.close()
    ready = dict(format='pc-fpga-result-ready-v2', state='complete', transfer_id=identity,
                 input_sha256=job['input']['sha256'], tasks=job['models'], elapsed_seconds=time.monotonic()-started,
                 schedule_sha256=package['schedule_sha256'], result={**job['result_contract'], 'ddr_base':RESULT_BASE},
                 integrity='V1 CRC32 per READ frame; local SHA256 after complete readback')
    path = case / 'handoff/result_ready.json'
    write_json(path, ready)
    return path


def receive_result(case_dir, manifest, host, port, bind, timeout=1., progress=lambda text: None, client_factory=OpClient):
    case, ready = Path(case_dir), read_json(manifest)
    job, receipt = read_json(case / 'handoff/job.json'), read_json(case / 'handoff/send_receipt.json')
    identity = ready['transfer_id']
    if (ready.get('format') != 'pc-fpga-result-ready-v2' or ready.get('state') != 'complete'
            or ready['input_sha256'] != job['input']['sha256'] or identity != receipt['transfer_id']
            or ready['tasks'] != job['models'] or ready['result'] != {**job['result_contract'], 'ddr_base':RESULT_BASE}):
        raise ValueError('整卷结果身份或契约不匹配')
    folder = case / 'prediction'
    folder.mkdir(parents=True, exist_ok=True)
    published = folder / 'metadata.json'
    if published.exists():
        metadata = read_json(published)
        if metadata.get('provenance', {}).get('result_ready') != ready:
            raise FileExistsError('prediction 已发布且身份不匹配；请使用新 case')
        check_file(folder / metadata['file'], job['result_contract']['bytes'], metadata['sha256'])
        if not metadata.get('ddr_released', False):
            client = client_factory(host, port, timeout, bind=bind)
            try:
                client.rpc(RELEASE, identity)
            finally:
                client.close()
            metadata['ddr_released'] = True
            write_json(published, metadata)
        return metadata
    temporary = folder / 'segmentation_uint16.bin.tmp'
    client = client_factory(host, port, timeout, bind=bind)
    try:
        status = client.rpc(QUERY, identity)
        if status['state'] != 2 or status['run_id'] != identity or status['bytes'] != job['result_contract']['bytes']:
            raise RuntimeError('板端未完成整卷或身份已改变')
        with temporary.open('wb') as stream:
            for offset in range(0, status['bytes'], 1 << 20):
                count = min(1 << 20, status['bytes'] - offset)
                payload = client.read(identity, RESULT_BASE + offset, count)
                if len(payload) != count:
                    raise ValueError('结果回读被截断')
                validate_bits(np.frombuffer(payload, '<u2'))
                stream.write(payload)
                progress(f"{offset+count:,}/{status['bytes']:,} bytes")
        path = folder / 'segmentation_uint16.bin'
        temporary.replace(path)
        metadata = {**job['result_contract'], 'file':path.name, 'order':'C', 'sha256':file_sha256(path), 'ddr_released':False,
                    'semantics':'FPGA classification, native CT grid, no mesh processing applied',
                    'provenance':dict(result_ready=ready, input_sha256=job['input']['sha256'])}
        write_json(folder / 'metadata.json', metadata)
        client.rpc(RELEASE, identity)
        metadata['ddr_released'] = True
        write_json(published, metadata)
    finally:
        client.close()
    return metadata
