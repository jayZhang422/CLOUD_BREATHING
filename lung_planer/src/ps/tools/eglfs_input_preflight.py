"""Inspect physical keyboard/mouse availability without consuming input events."""
import argparse
import json
import os
from pathlib import Path
import platform
import struct

SELFTEST_PREFIX = 'CloudBreathing Input Selftest '


def bitmap(text, word_bits=struct.calcsize('L') * 8):
    value = 0
    for word in text.split():
        value = (value << word_bits) | int(word, 16)
    return value


def classify(key, rel):
    return dict(keyboard=all(key & (1 << n) for n in (28, 30, 57)),
                mouse=bool(key & (1 << 272)) and all(rel & (1 << n) for n in (0, 1)))


def inspect(allow_selftest=False):
    report = dict(schema=1, ready=False, devices=[], blockers=[],
                  consumes_events=False, usb_roots=[], usb0_bound=False)
    blockers = report['blockers']
    if platform.system() != 'Linux':
        blockers.append('Native Linux input devices are required')
        return report
    report['usb_roots'] = sorted(p.name for p in Path('/sys/bus/usb/devices').glob('usb*'))
    report['usb0_bound'] = Path('/sys/bus/platform/devices/ff9d0000.usb/driver').exists()
    for event in sorted(Path('/sys/class/input').glob('event*')):
        source = event/'device'
        try:
            name = (source/'name').read_text().strip()
            kinds = classify(bitmap((source/'capabilities/key').read_text()),
                             bitmap((source/'capabilities/rel').read_text()))
            node = Path('/dev/input') / event.name
            selftest = name.startswith(SELFTEST_PREFIX)
            report['devices'].append(dict(path=str(node), name=name, **kinds,
                                          selftest=selftest, usable=allow_selftest or not selftest,
                                          current_user_rw=os.access(node, os.R_OK | os.W_OK)))
        except (OSError, ValueError) as exc:
            blockers.append(str(event) + ': ' + str(exc))
    for kind in ('keyboard', 'mouse'):
        if not any(row[kind] and row['usable'] for row in report['devices']):
            blockers.append('No ' + kind + ' detected by Linux evdev')
    if not report['usb_roots'] and not report['usb0_bound'] and not allow_selftest:
        blockers.append('USB0 host driver is unbound and no USB root hub exists; inspect kernel USB/firmware errors')
    try:
        from PySide6.QtCore import QLibraryInfo
        plugins = Path(QLibraryInfo.path(QLibraryInfo.PluginsPath)) / 'generic'
        report['plugins'] = {name: (plugins/name).is_file() for name in
                             ('libqevdevkeyboardplugin.so', 'libqevdevmouseplugin.so')}
        if not all(report['plugins'].values()):
            blockers.append('Missing Qt evdev keyboard/mouse plugins')
    except ImportError as exc:
        blockers.append('Qt inspection failed: ' + str(exc))
    report['ready'] = not blockers
    return report


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument('--output', type=Path, required=True)
    parser.add_argument('--allow-selftest', action='store_true', help='Diagnostic only; never counts as USB validation')
    args = parser.parse_args()
    report = inspect(args.allow_selftest)
    args.output.parent.mkdir(parents=True, exist_ok=True)
    args.output.write_text(json.dumps(report, indent=2), encoding='utf-8')
    print('EGLFS_INPUT', json.dumps(report), flush=True)
    return 0 if report['ready'] else 2


if __name__ == '__main__':
    raise SystemExit(main())
