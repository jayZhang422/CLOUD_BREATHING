#!/usr/bin/env bash
# Full-screen planner: dual-plane mesh core, PL centerline distance and branch intersections.
set -euo pipefail

app_dir="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")/.." && pwd)"
app_python="${CLOUD_BREATHING_PYTHON:-/home/ubuntu/cloud-breathing-venv/bin/python}"
release_dir="$app_dir/fpga"

"$app_python" - "$app_dir" "$release_dir" <<'PY'
import sys
sys.path.insert(0, sys.argv[1])
from tools.verify_deployment import verify
verify(sys.argv[1], sys.argv[2], bit_name='lung_planner.bit')
print('DEPLOYMENT_PASS')
PY
if [[ "${1:-}" == "--check" ]]; then
    exit 0
fi

export CLOUD_BREATHING_EGLFS_SECONDS=3600
export CLOUD_BREATHING_RENDER_SCALE=1.0
export CLOUD_BREATHING_SCENE_AA=none
export CLOUD_BREATHING_PLANNER_BACKEND=pl
export CLOUD_BREATHING_PL_AUTH=sudo
export LUNG_CENTERLINE_BACKEND=pl
export LUNG_PL_ENABLE=1
export LUNG_PL_BIT="$release_dir/lung_planner.bit"
export DUAL_PLANE_MESH_ENABLE=1
export DUAL_PLANE_MESH_ACCEPTANCE="$release_dir/mesh-full.json"

if pgrep -u "$(id -u)" -x gnome-shell >/dev/null; then
    if ! zenity --question \
        --title='Start full-screen Cloud Breathing' \
        --width=430 \
        --text='This will log out the GNOME desktop and close its applications. Save any open work first. Cloud Breathing will take over the display and run for at most one hour, then return to the login screen.'; then
        echo 'EGLFS launch cancelled.'
        exit 0
    fi
fi

exec bash "$app_dir/tools/eglfs_session.sh" start --desktop-takeover
