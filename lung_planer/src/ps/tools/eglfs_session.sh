#!/usr/bin/env bash
# Reserve one physical VT, run Qt as the invoking user, then restore the seat.
# No boot-target/driver/sudoers changes. The independent ExecStopPost cleanup
# also runs after a crashed application or systemd deadline.
set -euo pipefail
app_dir="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")/.." && pwd)"
unit=cloud-breathing-eglfs
state=/run/cloud-breathing-eglfs

case "${1:-help}" in
start)
    shift
    desktop_takeover=0
    if [[ ${1:-} == --desktop-takeover ]]; then
        desktop_takeover=1
        shift
    fi
    if [[ ${1:-} == --gles-probe ]]; then
        echo 'FBDEV_PROBE_DISABLED: no display session started.' >&2
        exit 2
    fi
    seconds="${CLOUD_BREATHING_EGLFS_SECONDS:-180}"
    [[ "$seconds" =~ ^[0-9]+$ && "$seconds" -ge 15 && "$seconds" -le 3600 ]] || { echo 'EGLFS seconds must be 15..3600'; exit 2; }
    if systemctl is-active --quiet "$unit.service"; then
        echo 'An EGLFS session is already running. Use status or stop.' >&2
        exit 1
    fi
    for command in openvt runuser setfacl getfacl systemd-run; do
        command -v "$command" >/dev/null || { echo "Missing system tool: $command"; exit 1; }
    done
    gnome_active=0
    if pgrep -u "$(id -u)" -x gnome-shell >/dev/null; then
        gnome_active=1
    fi
    if [[ $gnome_active == 1 && $desktop_takeover != 1 ]]; then
        echo 'A user GNOME desktop is logged in. Log out before reserving the physical display.' >&2
        exit 2
    fi
    # Inspect as the GUI user before reserving a VT or stopping the desktop.
    app_python="${CLOUD_BREATHING_PYTHON:-/home/ubuntu/cloud-breathing-venv/bin/python}"
    if [[ -z ${QT_QPA_EGLFS_KMS_CONFIG:-} ]]; then
        export QT_QPA_EGLFS_KMS_CONFIG="$app_dir/data/display-config/session-$$.json"
        "$app_python" "$app_dir/tools/select_eglfs_display.py" \
            --policy "${CLOUD_BREATHING_DISPLAY_MODE:-1080p}" --output "$QT_QPA_EGLFS_KMS_CONFIG"
    fi
    input_args=()
    if [[ ${1:-} == --input-test ]]; then input_args+=(--allow-selftest); fi
    if [[ ${1:-} != --probe ]]; then
        "$app_python" "$app_dir/tools/eglfs_input_preflight.py" "${input_args[@]}" \
            --output "$app_dir/data/input-preflight-session.json" \
            || echo "EGLFS_INPUT_WARNING: keyboard/mouse check failed; starting anyway" >&2
    fi
    "$app_python" "$app_dir/tools/eglfs_kms_preflight.py" --require-ready \
        --config "${QT_QPA_EGLFS_KMS_CONFIG:-$app_dir/config/eglfs-kms.json}" \
        --output "$app_dir/data/kms-preflight-session.json"
    run_dir="$app_dir/data/eglfs-sessions/$(date -u +%Y%m%dT%H%M%S)-$$"
    mkdir -p "$run_dir"
    session_entry=_run
    if [[ $gnome_active == 1 ]]; then
        session_entry=_wait_for_logout
    fi
    # sudo -n uses only existing authority; never prompts or stores passwords.
    sudo -n systemd-run --unit="$unit" --collect \
        --property="RuntimeMaxSec=$seconds" --property=TimeoutStopSec=8 \
        --setenv="CLOUD_BREATHING_RENDER_SCALE=${CLOUD_BREATHING_RENDER_SCALE:-1.0}" \
        --setenv="CLOUD_BREATHING_SCENE_AA=${CLOUD_BREATHING_SCENE_AA:-ssaa}" \
        --setenv="CLOUD_BREATHING_STL_LIGHTING=${CLOUD_BREATHING_STL_LIGHTING:-constant}" \
        --setenv="CLOUD_BREATHING_PLANNER_BACKEND=${CLOUD_BREATHING_PLANNER_BACKEND:-pl}" \
        --setenv="CLOUD_BREATHING_DISPLAY_BVH_CACHE=${CLOUD_BREATHING_DISPLAY_BVH_CACHE:-1}" \
        --setenv="CLOUD_BREATHING_DISPLAY_BATCH_POINTS=${CLOUD_BREATHING_DISPLAY_BATCH_POINTS:-1024}" \
        --setenv="CLOUD_BREATHING_DISPLAY_PARALLEL=${CLOUD_BREATHING_DISPLAY_PARALLEL:-1}" \
        --setenv="CLOUD_BREATHING_PL_AUTH=${CLOUD_BREATHING_PL_AUTH:-sudo}" \
        --setenv="LUNG_CENTERLINE_BACKEND=${LUNG_CENTERLINE_BACKEND:-legacy}" \
        --setenv="LUNG_PL_ENABLE=${LUNG_PL_ENABLE:-0}" \
        --setenv="LUNG_PL_BIT=${LUNG_PL_BIT:-$app_dir/fpga/lung_planner.bit}" \
        --setenv="DUAL_PLANE_MESH_ENABLE=${DUAL_PLANE_MESH_ENABLE:-0}" \
        --setenv="DUAL_PLANE_MESH_ACCEPTANCE=${DUAL_PLANE_MESH_ACCEPTANCE:-}" \
        --setenv="CLOUD_BREATHING_PYTHON=$app_python" \
        --setenv="CLOUD_BREATHING_MALI_KMS=${CLOUD_BREATHING_MALI_KMS:-/usr/lib/aarch64-linux-gnu/mali/wayland/libMali.so.9.0}" \
        --setenv="QT_QPA_EGLFS_KMS_CONFIG=${QT_QPA_EGLFS_KMS_CONFIG:-$app_dir/config/eglfs-kms.json}" \
        --property=KillMode=control-group \
        --property="ExecStopPost=/bin/bash $app_dir/tools/eglfs_session.sh _restore" \
        /bin/bash "$app_dir/tools/eglfs_session.sh" "$session_entry" "$(id -un)" "$run_dir" "$@"
    if [[ $gnome_active == 1 ]]; then
        gnome-session-quit --logout --no-prompt
        echo "GNOME logout requested. EGLFS will take over the display; logs: $run_dir"
    fi
    echo "EGLFS session: $unit.service; deadline: $seconds seconds; logs: $run_dir"
    ;;
stop)
    sudo -n systemctl stop "$unit.service"
    ;;
status)
    systemctl status "$unit.service" --no-pager -l || true
    sudo -n journalctl -u "$unit.service" --no-pager -n 40
    ;;
_wait_for_logout)
    [[ $(id -u) == 0 ]] || exit 1
    shift
    app_user="$1"; run_dir="$2"; shift 2
    [[ "$app_user" =~ ^[a-z_][a-z0-9_-]*$ ]] || exit 2
    for _ in $(seq 1 120); do
        if ! pgrep -u "$app_user" -x gnome-shell >/dev/null; then
            exec /bin/bash "$app_dir/tools/eglfs_session.sh" _run "$app_user" "$run_dir" "$@"
        fi
        sleep 1
    done
    echo 'Timed out waiting for the GNOME user session to exit.' >&2
    exit 1
    ;;
_run)
    [[ $(id -u) == 0 ]] || exit 1
    shift
    app_user="$1"; run_dir="$2"; shift 2
    [[ "$app_user" =~ ^[a-z_][a-z0-9_-]*$ ]] || exit 2
    # Recover an interrupted prior session before recording new seat state.
    if [[ -d "$state" ]]; then bash "$app_dir/tools/eglfs_session.sh" _restore; fi
    install -d -m 700 "$state"
    systemctl is-active --quiet display-manager && touch "$state/desktop-was-active"
    cat /sys/class/tty/tty0/active > "$state/vt"
    printf '%s\n' "$run_dir" > "$state/run-dir"
    trap 'bash "$app_dir/tools/eglfs_session.sh" _restore' EXIT
    trap 'exit 143' TERM INT
    if [[ -f "$state/desktop-was-active" ]]; then systemctl stop display-manager; fi
    # Scope device permissions to this session; restore the exact prior ACLs.
    touch "$state/input.acl"
    # Ensure tty8 exists before granting its temporary ACL.
    test -c /dev/tty8
    for dev in /dev/input/event* /dev/input/mice /dev/tty0 /dev/tty8; do
        [[ -e "$dev" ]] || continue
        getfacl -p "$dev" >> "$state/input.acl"
        setfacl -m "u:$app_user:rw" "$dev"
    done
    printf 'RUNNING\n' > "$run_dir/status"
    set +e
    openvt --console=8 --switch --wait -- \
        runuser -u "$app_user" -- env \
        "CLOUD_BREATHING_RENDER_SCALE=${CLOUD_BREATHING_RENDER_SCALE:-1.0}" \
        "CLOUD_BREATHING_SCENE_AA=${CLOUD_BREATHING_SCENE_AA:-ssaa}" \
        "CLOUD_BREATHING_STL_LIGHTING=${CLOUD_BREATHING_STL_LIGHTING:-constant}" \
        "CLOUD_BREATHING_PLANNER_BACKEND=${CLOUD_BREATHING_PLANNER_BACKEND:-pl}" \
        "CLOUD_BREATHING_DISPLAY_BVH_CACHE=${CLOUD_BREATHING_DISPLAY_BVH_CACHE:-1}" \
        "CLOUD_BREATHING_DISPLAY_BATCH_POINTS=${CLOUD_BREATHING_DISPLAY_BATCH_POINTS:-1024}" \
        "CLOUD_BREATHING_DISPLAY_PARALLEL=${CLOUD_BREATHING_DISPLAY_PARALLEL:-1}" \
        "CLOUD_BREATHING_PL_AUTH=${CLOUD_BREATHING_PL_AUTH:-sudo}" \
        "LUNG_CENTERLINE_BACKEND=${LUNG_CENTERLINE_BACKEND:-legacy}" \
        "LUNG_PL_ENABLE=${LUNG_PL_ENABLE:-0}" \
        "LUNG_PL_BIT=${LUNG_PL_BIT:-$app_dir/fpga/lung_planner.bit}" \
        "DUAL_PLANE_MESH_ENABLE=${DUAL_PLANE_MESH_ENABLE:-0}" \
        "DUAL_PLANE_MESH_ACCEPTANCE=${DUAL_PLANE_MESH_ACCEPTANCE:-}" \
        "CLOUD_BREATHING_PYTHON=$CLOUD_BREATHING_PYTHON" \
        "CLOUD_BREATHING_MALI_KMS=$CLOUD_BREATHING_MALI_KMS" \
        "QT_QPA_EGLFS_KMS_CONFIG=$QT_QPA_EGLFS_KMS_CONFIG" \
        "CLOUD_BREATHING_EGLFS_LOG_PATH=$run_dir/application.log" \
        bash -c 'exec bash "$@" > "$CLOUD_BREATHING_EGLFS_LOG_PATH" 2>&1' \
        eglfs-launch "$app_dir/launch_eglfs.sh" "$@" > "$run_dir/session.log" 2>&1
    result=$?
    set -e
    printf '%s\n' "$result" > "$run_dir/exit-code"
    if [[ $result == 0 ]]; then printf 'COMPLETE\n' > "$run_dir/status"; else printf 'FAILED\n' > "$run_dir/status"; fi
    chown -R "$app_user:$(id -gn "$app_user")" "$run_dir"
    exit "$result"
    ;;
_restore)
    [[ $(id -u) == 0 ]] || exit 1
    [[ -d "$state" ]] || exit 0
    if [[ -s "$state/input.acl" ]]; then setfacl --restore="$state/input.acl" || true; fi
    if [[ -s "$state/vt" ]]; then
        original_vt="$(cat "$state/vt")"
        if [[ "$original_vt" =~ ^tty[0-9]+$ ]]; then chvt "${original_vt#tty}" || true; fi
    fi
    if [[ -f "$state/desktop-was-active" ]]; then systemctl start display-manager || true; fi
    # Remove only these known bookkeeping files, never application/user data.
    for name in input.acl vt desktop-was-active run-dir; do
        if [[ -f "$state/$name" ]]; then rm -- "$state/$name"; fi
    done
    rmdir "$state" || true
    ;;
*)
    echo 'Usage: bash tools/eglfs_session.sh start [--desktop-takeover]'
    echo '       bash tools/eglfs_session.sh status | stop'
    echo 'Default lifetime 180 seconds. CLOUD_BREATHING_EGLFS_SECONDS=3600 for a review session.'
    ;;
esac
