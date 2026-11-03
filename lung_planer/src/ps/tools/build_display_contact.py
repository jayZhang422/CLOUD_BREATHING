"""Build the PS-only display query library with strict float64 operations."""
import argparse
import hashlib
import json
from pathlib import Path
import platform
import subprocess


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument('--compiler', default='g++')
    args = parser.parse_args()
    root = Path(__file__).resolve().parents[1]
    folder = root / 'native/display_contact'
    source = folder / 'contact.cpp'
    target = folder / 'libdisplay_contact.so'
    temporary = target.with_suffix('.so.tmp')
    flags = ['-O3', '-std=c++17', '-fPIC', '-shared', '-fno-fast-math', '-ffp-contract=off']
    command = [args.compiler, *flags, str(source), '-o', str(temporary)]
    subprocess.run(command, check=True)
    temporary.replace(target)
    report = dict(command=command, compiler=subprocess.check_output(
        [args.compiler, '--version'], text=True).splitlines()[0], platform=platform.platform(),
        source_sha256=hashlib.sha256(source.read_bytes()).hexdigest(),
        library_sha256=hashlib.sha256(target.read_bytes()).hexdigest())
    (folder / 'build.json').write_text(json.dumps(report, indent=2)+'\n', encoding='utf-8')
    print(json.dumps(report))


if __name__ == '__main__':
    main()
