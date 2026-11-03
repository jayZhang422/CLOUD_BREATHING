#!/usr/bin/env bash
# PolicyKit removes loader variables. Restore the board runtime before Python
# starts: PYNQ 3.0 registers EmbeddedDevice only when XILINX_XRT is present.
pl_python="$1"
pl_service="$2"
xrt_hint="$3"
shift 3

if [[ -r /etc/profile ]]; then
    source /etc/profile >&2 || printf 'PL_ENV: system profile returned an error\n' >&2
fi
set -eo pipefail

xrt_root=""
for candidate in "$xrt_hint" "${XILINX_XRT:-}" /usr /opt/xilinx/xrt /usr/local/xrt; do
    if [[ -n "$candidate" && -f "$candidate/lib/libxrt_core.so" ]]; then
        xrt_root="$candidate"
        break
    fi
done
if [[ -z "$xrt_root" ]]; then
    printf 'PL_ENV_FAILED: XRT lib/libxrt_core.so not found. Check the board XRT installation.\n' >&2
    exit 1
fi
if [[ -r "$xrt_root/setup.sh" ]]; then
    source "$xrt_root/setup.sh" >&2
fi
export XILINX_XRT="$xrt_root"
export VIRTUAL_ENV="$(dirname "$(dirname "$pl_python")")"
export PATH="$(dirname "$pl_python"):$xrt_root/bin:/usr/local/bin:$PATH"
export LD_LIBRARY_PATH="$xrt_root/lib${LD_LIBRARY_PATH:+:$LD_LIBRARY_PATH}"
export OPENBLAS_NUM_THREADS=1
export OMP_NUM_THREADS=1
unset XCL_EMULATION_MODE
printf 'PL_ENV: XILINX_XRT=%s\n' "$XILINX_XRT" >&2
exec "$pl_python" -u "$pl_service" "$@"
