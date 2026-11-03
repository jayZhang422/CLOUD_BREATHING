#!/usr/bin/env python3
"""Check PYNQ's exact metadata generation command before loading an overlay."""
import json
import shutil
import subprocess
import sys
import tempfile
from pathlib import Path


def check_xclbinutil():
    from pynq.pl_server.embedded_device import BLANK_METADATA, _ip_to_topology

    executable = shutil.which('xclbinutil')
    if executable is None:
        raise RuntimeError('xclbinutil is missing from the PL service PATH')
    with tempfile.TemporaryDirectory(prefix='lung-xclbin-check-') as directory:
        root = Path(directory)
        (root / 'metadata.xml').write_text(BLANK_METADATA, encoding='utf-8')
        (root / 'mem.json').write_text(json.dumps(_ip_to_topology({})), encoding='utf-8')
        command = [executable, '--add-section=EMBEDDED_METADATA:RAW:metadata.xml',
                   '--add-section=MEM_TOPOLOGY:JSON:mem.json', '--output', 't.xclbin',
                   '--skip-bank-grouping']
        run = subprocess.run(command, cwd=root, stdout=subprocess.PIPE,
                             stderr=subprocess.STDOUT, timeout=15)
        output = run.stdout.decode('utf-8', errors='replace')
        target = root / 't.xclbin'
        valid = target.is_file() and target.stat().st_size > 0
        print('PL_XCLBINUTIL ' + json.dumps(dict(
            executable=executable, resolved=str(Path(executable).resolve()),
            returncode=run.returncode, output_created=valid,
            generated_files=sorted(path.name for path in root.iterdir()),
            output=output[-12000:])), file=sys.stderr, flush=True)
        if run.returncode != 0 or not valid:
            raise RuntimeError('xclbinutil failed to generate a nonempty t.xclbin '
                               '(tool=%s, returncode=%s, output_created=%s). '
                               'See PL_XCLBINUTIL in the startup log.' %
                               (executable, run.returncode, valid))


if __name__ == '__main__':
    check_xclbinutil()
