"""Generate a per-launch KMS config from connected-display capabilities.

Only reads sysfs; does not modeset. Qt performs the eventual display switch.
Explicit QT_QPA_EGLFS_KMS_CONFIG still overrides this launch policy.
"""
import argparse
import json
from pathlib import Path


def select_mode(modes, policy):
    if policy == 'native':
        return 'preferred', 'Use monitor preferred mode'
    if policy == 'current':
        return 'current', 'Keep current scanout'
    if policy != '1080p':
        raise ValueError('Display policy must be 1080p, native or current')
    if '1920x1080' in modes:
        return '1920x1080@60', 'Request advertised 1080p60; verify actual scanout after launch'
    return 'preferred', '1080p not advertised; use monitor preferred mode without inventing timings'


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument('--policy', choices=('1080p', 'native', 'current'), default='1080p')
    parser.add_argument('--output', type=Path, required=True)
    parser.add_argument('--sysfs', type=Path, default=Path('/sys/class/drm'))
    args = parser.parse_args()
    connector = args.sysfs / 'card0-DP-1'
    if (connector / 'status').read_text().strip() != 'connected':
        parser.error('DP-1 is not connected; display remains untouched')
    modes = (connector / 'modes').read_text().splitlines()
    if not modes:
        parser.error('No advertised modes; display remains untouched')
    mode, reason = select_mode(modes, args.policy)
    config = dict(device='/dev/dri/card0', hwcursor=False, pbuffers=True,
                  outputs=[dict(name='DP1', mode=mode, format='argb8888', primary=True)])
    args.output.parent.mkdir(parents=True, exist_ok=True)
    args.output.write_text(json.dumps(config, indent=2) + '\n')
    report = dict(policy=args.policy, selected=mode, reason=reason,
                  advertised_sizes=list(dict.fromkeys(modes)), config=str(args.output))
    args.output.with_suffix('.selection.json').write_text(json.dumps(report, indent=2) + '\n')
    print('EGLFS_DISPLAY ' + json.dumps(report), flush=True)


if __name__ == '__main__':
    main()
