"""Validate the existing KV260 application environment without modifying it."""

import importlib
import importlib.metadata
import platform
import os
import shutil
import sys
from pathlib import Path


EXPECTED = {
    "PySide6": "6.7.3",
    "numpy": "1.26.4",
    "pydicom": "3.0.2",
    "Pillow": "11.3.0",
    "psutil": "7.2.2",
    "manifold3d": "3.5.4",
}


def validate():
    errors = []
    if platform.machine().lower() not in ("aarch64", "arm64"):
        errors.append("This package targets KV260 ARM64, not " + platform.machine())
    if sys.version_info[:2] != (3, 10):
        errors.append("Expected Python 3.10; got " + sys.version.split()[0])

    for name, expected in EXPECTED.items():
        try:
            version = importlib.metadata.version(name)
            print(f"{name}: {version}")
            if version != expected:
                errors.append(f"{name} {version} != tested installation {expected}")
        except importlib.metadata.PackageNotFoundError:
            errors.append(f"Missing package: {name}")

    for module in (
        "PySide6.QtCore", "PySide6.QtQml", "PySide6.QtQuick",
        "PySide6.QtQuick3D", "PySide6.QtQuickControls2", "PySide6.QtWidgets",
        "numpy", "pydicom", "PIL", "psutil", "manifold3d",
    ):
        try:
            importlib.import_module(module)
        except (ImportError, OSError) as exc:
            errors.append(f"Cannot import {module}: {exc}")

    # Use the same dependency bridge as the application and actually import
    # PYNQ: find_spec alone missed missing cffi and other transitive imports.
    try:
        from cas_frontend.pl_metrics import _import_pynq
        _import_pynq()
        print("PYNQ_IMPORT_OK (hardware not tested; use tools/check_pl_worker.py)")
    except Exception as exc:
        errors.append(f"Cannot import PYNQ: {type(exc).__name__}: {exc}")
    if sys.platform == 'linux' and os.geteuid() != 0:
        authorization = os.environ.get('CLOUD_BREATHING_PL_AUTH', 'pkexec')
        if authorization == 'sudo':
            if shutil.which('sudo') is None:
                errors.append('CLOUD_BREATHING_PL_AUTH=sudo requires sudo')
            else:
                print('PL_ACCESS: sudo -n; requires existing passwordless sudo authorization')
        elif authorization != 'pkexec':
            errors.append('Unsupported CLOUD_BREATHING_PL_AUTH: ' + authorization)
        elif shutil.which('pkexec') is None:
            errors.append('FPGA root access requires pkexec: install policykit-1')
        else:
            print('PL_ACCESS: authorized helper; first FPGA job requests desktop authentication')

    base = Path(__file__).resolve().parent
    for relative in ("main.py", "qml/Main.qml", "qml/components/AnnotationBar.qml",
                     "tools/pl_service.py", "tools/start_pl_service.sh",
                     "tools/check_xclbinutil.py"):
        if not (base / relative).is_file():
            errors.append("Missing application file: " + relative)

    # The only shipped firmware is fpga/lung_planner.bit (tools/start_desktop.sh). Without
    # DUAL_PLANE_MESH_ENABLE the application runs its CPU paths and needs no bitstream.
    hardware_pair = ()
    if os.environ.get('DUAL_PLANE_MESH_ENABLE') == '1':
        try:
            bit = Path(os.environ['LUNG_PL_BIT']).resolve()
            directory = bit.parent
            if bit.name != 'lung_planner.bit':
                raise ValueError('Unsupported dual-plane desktop firmware')
            receipt = Path(os.environ['DUAL_PLANE_MESH_ACCEPTANCE']).resolve()
            if receipt != directory / 'mesh-full.json':
                raise ValueError('Dual-plane admission path differs from the deployment receipt')
            from tools.verify_deployment import verify
            verify(base, directory, bit_name=bit.name)
            hardware_pair = (str(bit.relative_to(base)),)
        except (OSError, ValueError, KeyError, TypeError, SystemExit) as exc:
            errors.append('Dual-plane deployment verification failed: ' + str(exc))
    for relative in hardware_pair:
        if not (base / relative).is_file():
            errors.append("Missing application file: " + relative)

    if errors:
        for error in errors:
            print("ERROR:", error, file=sys.stderr)
        return 1
    print("Dependency check passed. Graphics rendering still requires a board-side test.")
    return 0


if __name__ == "__main__":
    raise SystemExit(validate())
