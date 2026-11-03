#!/usr/bin/env bash
# 在 WSL/Linux 下构建 ctfpga。用法：scripts/build.sh [build_dir] [额外 cmake 参数...]
# 源码可放在 /mnt/e 下，构建目录默认在 ~/ctfpga_build（本地盘，编译更快）。
set -euo pipefail
HERE="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
BUILD="${1:-$HOME/ctfpga_build}"
[ $# -gt 0 ] && shift
cmake -S "$HERE" -B "$BUILD" -G Ninja "$@"
cmake --build "$BUILD" 2>&1 | grep -E "error|FAILED|warning:|Linking" || true
cmake --build "$BUILD" >/dev/null
echo "BUILD_OK: $BUILD"
