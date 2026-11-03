"""Inspect EGLFS/KMS prerequisites without initializing EGL or opening DRM.

Vendor libraries are queried in separate bounded processes. No EGL context,
surface, GBM device, framebuffer write, modeset or GPU draw is performed.
A PASS permits a separate smoke test; it does not validate presentation.
"""
import argparse
import ctypes
import hashlib
import json
import os
from pathlib import Path
import platform
import subprocess
import sys
import tempfile

ROOT = Path(__file__).resolve().parents[1]
VENDOR_ROOT = Path('/usr/lib/aarch64-linux-gnu/mali')
DEFAULT_DRIVER = VENDOR_ROOT / 'wayland/libMali.so.9.0'
EXTRA_LIB = ROOT / 'runtime-deps/qt-6.7.3-aarch64'
VENDOR_ALIASES = ('libEGL.so.1', 'libGLESv2.so.2', 'libGLESv1_CM.so.1',
                  'libgbm.so.1', 'libMali.so.9', 'libMali.so.9.0')
REQUIRED_SYMBOLS = (
    'eglQueryString', 'eglGetProcAddress', 'eglGetDisplay', 'eglInitialize',
    'eglCreateWindowSurface', 'eglSwapBuffers', 'glGetString',
    'gbm_create_device', 'gbm_surface_create', 'gbm_surface_lock_front_buffer',
    'gbm_bo_get_handle', 'gbm_bo_get_stride', 'gbm_surface_release_buffer',
    'gbm_device_destroy',
)


def command(argv, env=None):
    try:
        run = subprocess.run(argv, capture_output=True, text=True, timeout=8, env=env)
        return dict(code=run.returncode, stdout=run.stdout, stderr=run.stderr)
    except (OSError, subprocess.TimeoutExpired) as exc:
        return dict(code=-1, error=str(exc))


def query_vendor(path):
    """Child process only: never mix Mali variants in one address space."""
    library = ctypes.CDLL(str(path))
    query = library.eglQueryString
    query.restype = ctypes.c_char_p
    query.argtypes = [ctypes.c_void_p, ctypes.c_int]
    raw = query(None, 0x3055)  # EGL_NO_DISPLAY, EGL_EXTENSIONS
    getproc = library.eglGetProcAddress
    getproc.restype = ctypes.c_void_p
    getproc.argtypes = [ctypes.c_char_p]
    return dict(path=str(path), extensions=raw.decode('ascii', 'replace').split() if raw else [],
                platform_display_ext=bool(getproc(b'eglGetPlatformDisplayEXT')),
                missing_symbols=[name for name in REQUIRED_SYMBOLS if not hasattr(library, name)])


def vendor_blockers(vendor):
    reasons = []
    if vendor.get('query_failed'):
        return ['Vendor client-extension query failed: ' + str(vendor['query_failed'])]
    if not set(vendor.get('extensions', [])).intersection({'EGL_KHR_platform_gbm', 'EGL_MESA_platform_gbm'}):
        reasons.append('EGL GBM platform not advertised; implicit eglGetDisplay fallback is not attempted')
    if not vendor.get('platform_display_ext'):
        reasons.append('eglGetPlatformDisplayEXT is unavailable')
    if vendor.get('missing_symbols'):
        reasons.append('Missing vendor GBM/EGL symbols: ' + ', '.join(vendor['missing_symbols']))
    return reasons


def vendor_environment(driver, runtime, qtlib):
    """Match the launcher's private links without altering system libraries."""
    for name in VENDOR_ALIASES:
        (runtime / name).symlink_to(driver)
    env = dict(os.environ)
    env['LD_LIBRARY_PATH'] = ':'.join((str(EXTRA_LIB), str(runtime), str(qtlib),
                                       os.environ.get('LD_LIBRARY_PATH', '')))
    return env


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument('--output', type=Path)
    parser.add_argument('--driver', type=Path, default=Path(os.environ.get('CLOUD_BREATHING_MALI_KMS', DEFAULT_DRIVER)))
    parser.add_argument('--config', type=Path, default=ROOT / 'config/eglfs-kms.json')
    parser.add_argument('--require-ready', action='store_true')
    parser.add_argument('--query-vendor', type=Path, help=argparse.SUPPRESS)
    parser.add_argument('--load-plugin', type=Path, help=argparse.SUPPRESS)
    args = parser.parse_args()
    if args.load_plugin:
        from PySide6.QtCore import QPluginLoader
        loader = QPluginLoader(str(args.load_plugin))
        loaded = loader.load()  # No instance(), QGuiApplication or display initialization.
        mapped = sorted({line.split()[-1] for line in Path('/proc/self/maps').read_text().splitlines()
                         if '/mali/' in line and 'libMali' in line})
        print(json.dumps(dict(loaded=loaded, error=loader.errorString(), mapped_mali=mapped)))
        return 0 if loaded else 2
    if args.query_vendor:
        print(json.dumps(query_vendor(args.query_vendor)))
        return 0
    report = dict(schema=1, rendering_attempted=False, ready_for_smoke_test=False,
                  presentation_validated=False, kernel=platform.platform(),
                  selected_driver=str(args.driver), vendor_variants={}, blockers=[])
    blockers = report['blockers']
    if sys.platform != 'linux' or platform.machine().lower() not in ('aarch64', 'arm64'):
        blockers.append('This check requires native aarch64 Linux on KV260')
    else:
        report['boot_id'] = Path('/proc/sys/kernel/random/boot_id').read_text().strip()
        for path in sorted(VENDOR_ROOT.glob('*/libMali.so.9.0')):
            result = command([sys.executable, str(Path(__file__).resolve()), '--query-vendor', str(path)])
            try:
                vendor = json.loads(result['stdout']) if result['code'] == 0 else dict(query_failed=result)
            except (KeyError, ValueError):
                vendor = dict(query_failed=result)
            vendor['sha256'] = hashlib.sha256(path.read_bytes()).hexdigest()
            report['vendor_variants'][str(path)] = vendor
        if 'fbdev' in args.driver.parts:
            blockers.append('The fbdev driver is disabled after a kernel Oops')
        vendor = report['vendor_variants'].get(str(args.driver))
        if vendor is None:
            blockers.append('Selected driver is not an inspected installed Mali variant')
        else:
            blockers.extend(vendor_blockers(vendor))
        try:
            config = json.loads(args.config.read_text(encoding='utf-8'))
            report['kms_config'] = config
            device = Path(config['device'])
            if str(device) != '/dev/dri/card0' or not device.is_char_device():
                blockers.append('Expected physical display controller /dev/dri/card0 is unavailable')
            if not os.access(device, os.R_OK | os.W_OK):
                blockers.append('Current user cannot read/write the DRM display controller')
            if not os.access('/dev/mali', os.R_OK | os.W_OK):
                blockers.append('Current user cannot read/write /dev/mali')
            report['drm_driver'] = Path('/sys/class/drm/card0/device/driver').resolve().name
            if report['drm_driver'] != 'zynqmp-display':
                blockers.append('card0 is not zynqmp-display; reinspect device mapping')
            for output in config['outputs']:
                # Qt KMS names this output DP1; Linux sysfs calls it DP-1.
                sysfs_name = 'DP-1' if output['name'] == 'DP1' else output['name']
                status = Path('/sys/class/drm') / ('card0-' + sysfs_name) / 'status'
                if not status.exists() or status.read_text().strip() != 'connected':
                    blockers.append('Configured connector is not connected: ' + output['name'])
        except (OSError, KeyError, TypeError, ValueError) as exc:
            blockers.append('Invalid/unreadable KMS config: ' + str(exc))
        try:
            from PySide6.QtCore import QLibraryInfo, qVersion
            report['qt'] = qVersion()
            if qVersion() != '6.7.3':
                blockers.append('Private KMS support library requires Qt exactly 6.7.3')
            qtlib = QLibraryInfo.path(QLibraryInfo.LibrariesPath)
            plugin = Path(QLibraryInfo.path(QLibraryInfo.PluginsPath)) / 'egldeviceintegrations/libqeglfs-kms-integration.so'
            if not (EXTRA_LIB / 'libQt6EglFsKmsGbmSupport.so.6').is_file():
                blockers.append('Missing application-private Qt KMS/GBM support library')
            with tempfile.TemporaryDirectory(prefix='cloud-breathing-kms-') as temp:
                dependency_env = vendor_environment(args.driver, Path(temp), qtlib)
                report['kms_plugin_relocations'] = command(['ldd', '-r', str(plugin)], env=dependency_env)
                imports = report['kms_plugin_relocations']
                import_log = imports.get('stdout', '') + imports.get('stderr', '')
                if imports['code'] or 'not found' in import_log or 'undefined symbol' in import_log:
                    blockers.append('KMS dependencies/private Qt ABI unresolved; see relocation log')
                else:
                    load = command([sys.executable, str(Path(__file__).resolve()), '--load-plugin', str(plugin)],
                                   env=dependency_env)
                    report['kms_plugin_load'] = load
                    if load['code']:
                        blockers.append('Qt rejected the KMS plugin; see load log')
                    else:
                        evidence = json.loads(load['stdout'])
                        if evidence['mapped_mali'] != [str(args.driver.resolve())]:
                            blockers.append('Qt plugin did not map exactly the selected Mali variant')
        except (ImportError, OSError) as exc:
            blockers.append('Qt runtime inspection failed: ' + str(exc))
    report['ready_for_smoke_test'] = not blockers
    if args.output:
        args.output.parent.mkdir(parents=True, exist_ok=True)
        args.output.write_text(json.dumps(report, indent=2), encoding='utf-8')
    print(json.dumps(report, indent=2), flush=True)
    return 2 if args.require_ready and blockers else 0


if __name__ == '__main__':
    raise SystemExit(main())
