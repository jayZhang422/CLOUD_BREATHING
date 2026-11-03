#!/usr/bin/env bash
set -euo pipefail
app_dir="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)"
app_python="${CLOUD_BREATHING_PYTHON:-/home/ubuntu/cloud-breathing-venv/bin/python}"
if [[ ${1:-} == --gles-probe || ${QT_QPA_EGLFS_INTEGRATION:-} == none || -n ${CLOUD_BREATHING_MALI_FBDEV:-} ]]; then
    echo 'FBDEV_DISABLED: native framebuffer rendering triggered a kernel Oops. No display test started.' >&2
    exit 2
fi
driver="${CLOUD_BREATHING_MALI_KMS:-/usr/lib/aarch64-linux-gnu/mali/wayland/libMali.so.9.0}"
[[ -x "$app_python" ]] || { echo 'Missing Qt Python' >&2; exit 1; }
export CLOUD_BREATHING_MALI_KMS="$driver"
if [[ -z ${QT_QPA_EGLFS_KMS_CONFIG:-} ]]; then
    export QT_QPA_EGLFS_KMS_CONFIG="$app_dir/data/display-config/launch-$$.json"
    "$app_python" "$app_dir/tools/select_eglfs_display.py" \
        --policy "${CLOUD_BREATHING_DISPLAY_MODE:-1080p}" --output "$QT_QPA_EGLFS_KMS_CONFIG"
fi
"$app_python" "$app_dir/tools/eglfs_kms_preflight.py" --require-ready \
    --config "$QT_QPA_EGLFS_KMS_CONFIG" --output "$app_dir/data/kms-preflight-launch.json"
if systemctl is-active --quiet display-manager; then
    echo 'The display manager is active. Use tools/eglfs_session.sh start to reserve the physical display.' >&2
    exit 1
fi
# Private links select the inspected vendor GBM variant only for this process.
# Never rewrite system EGL/GLES symlinks or install a different GPU driver.
runtime="$app_dir/.runtime/mali-kms"
mkdir -p "$runtime"
for soname in libEGL.so.1 libGLESv2.so.2 libGLESv1_CM.so.1 libgbm.so.1 libMali.so.9 libMali.so.9.0; do
    ln -sfn -- "$driver" "$runtime/$soname"
done
qt_lib="$($app_python -c 'from PySide6.QtCore import QLibraryInfo; print(QLibraryInfo.path(QLibraryInfo.LibrariesPath))')"
export LD_LIBRARY_PATH="$app_dir/runtime-deps/qt-6.7.3-aarch64:$runtime:$qt_lib${LD_LIBRARY_PATH:+:$LD_LIBRARY_PATH}"
unset DISPLAY WAYLAND_DISPLAY QT_XCB_GL_INTEGRATION
export QT_QPA_PLATFORM=eglfs
# Load the shipped evdev plugins explicitly, with no duplicate built-in input
# handlers. Kernel HID/USB must already expose keyboard and pointer nodes.
export QT_QPA_EGLFS_DISABLE_INPUT=1
export QT_QPA_GENERIC_PLUGINS=evdevkeyboard,evdevmouse
export QT_QPA_EGLFS_HIDECURSOR=0
# No fallback to base EGLFS/fbdev. A missing plugin is a hard failure.
export QT_QPA_EGLFS_INTEGRATION=eglfs_kms
unset QT_QPA_EGLFS_FB QT_QPA_EGLFS_FORCE888
export QT_QPA_EGLFS_KMS_ATOMIC=0
export QT_QPA_EGLFS_SWAPINTERVAL=1
export CLOUD_BREATHING_SINGLE_WINDOW=1
export CLOUD_BREATHING_KV260=1
export CLOUD_BREATHING_PLANNER_BACKEND="${CLOUD_BREATHING_PLANNER_BACKEND:-pl}"
export CLOUD_BREATHING_PL_AUTH="${CLOUD_BREATHING_PL_AUTH:-sudo}"
export LUNG_PL_BIT="${LUNG_PL_BIT:-$app_dir/fpga/lung_planner.bit}"
[[ -f "$LUNG_PL_BIT" ]] || { echo "PL bitstream missing: $LUNG_PL_BIT" >&2; exit 1; }
export PYNQ_PYTHON="${PYNQ_PYTHON:-/usr/local/share/pynq-venv/bin/python}"
export PYNQ_SITE_PACKAGES="${PYNQ_SITE_PACKAGES:-/usr/lib/python3/dist-packages}"
export CLOUD_BREATHING_RENDER_SCALE="${CLOUD_BREATHING_RENDER_SCALE:-1.0}"
export CLOUD_BREATHING_SCENE_AA="${CLOUD_BREATHING_SCENE_AA:-none}"
export CLOUD_BREATHING_STL_LIGHTING="${CLOUD_BREATHING_STL_LIGHTING:-constant}"
export CLOUD_BREATHING_MSAA_SAMPLES="${CLOUD_BREATHING_MSAA_SAMPLES:-0}"
export QSG_RHI_BACKEND=opengl QT_OPENGL=es2 QSG_RENDER_LOOP="${CLOUD_BREATHING_QSG_RENDER_LOOP:-basic}" QSG_INFO=1
export OPENBLAS_NUM_THREADS=1 OMP_NUM_THREADS=1
export PYTHONFAULTHANDLER=1
export XDG_RUNTIME_DIR="${XDG_RUNTIME_DIR:-/run/user/$(id -u)}"
cd "$app_dir"
echo "EGLFS candidate: KMS/GBM; driver=$driver; render scale=$CLOUD_BREATHING_RENDER_SCALE AA=$CLOUD_BREATHING_SCENE_AA"
"$app_python" check_environment.py
exec "$app_python" main.py "$@"
