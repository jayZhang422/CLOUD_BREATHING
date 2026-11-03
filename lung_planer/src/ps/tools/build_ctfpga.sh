#!/usr/bin/env bash
# Build ctfpga (CT -> inference FPGA -> STL, C++/OpenMP) into ctfpga/build-$(uname -m).
# KV260 has no internet: cmake/ninja/headers come from debs unpacked into a private
# prefix ($CTFPGA_TOOLCHAIN); the VTK 9.1 and GDCM runtimes are the system ones.
# Nothing is installed with apt/dpkg. On a PC (WSL/Ubuntu) with the README
# dependencies installed, the system cmake is used and no toolchain is needed.
set -euo pipefail

app_dir="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")/.." && pwd)"
src="$app_dir/ctfpga"
build="$src/build-$(uname -m)"
toolchain="${CTFPGA_TOOLCHAIN:-$HOME/ctfpga-toolchain}"
debs="${CTFPGA_DEBS:-$toolchain/debs}"
lib="$toolchain/usr/lib/aarch64-linux-gnu"
sys_lib=/usr/lib/aarch64-linux-gnu
cmake_args=()

if command -v cmake >/dev/null && command -v ninja >/dev/null; then
    :
elif [[ "$(uname -m)" == aarch64 ]]; then
    if [[ ! -x "$toolchain/usr/bin/cmake" ]]; then
        compgen -G "$debs/*.deb" >/dev/null || {
            echo "no cmake and no toolchain debs in $debs" >&2; exit 1; }
        mkdir -p "$toolchain"
        for deb in "$debs"/*.deb; do dpkg-deb -x "$deb" "$toolchain"; done
    fi
    # libvtk9-dev ships only CMake files and .so links; point them at the system runtime.
    for f in "$sys_lib"/libvtk*-9.1.so.1 "$sys_lib"/libvtk*-9.1.so.9.1.0; do
        [[ -e "$lib/$(basename "$f")" ]] || ln -s "$f" "$lib/"
    done
    for f in "$lib"/libvtk*-9.1.so; do
        [[ -e "$f" ]] || ln -sf "$sys_lib/$(readlink "$f")" "$f"
    done
    ln -sf "$sys_lib/libjsoncpp.so.25" "$lib/libjsoncpp.so"
    # The Python/Java VTK wrappers are not installed on the board.
    sed -i -e 's/_WRAP_PYTHON" "ON"/_WRAP_PYTHON" "OFF"/' \
           -e 's/_WRAP_JAVA" "ON"/_WRAP_JAVA" "OFF"/' "$lib/cmake/vtk-9.1/vtk-config.cmake"
    export PATH="$toolchain/usr/bin:$PATH" LD_LIBRARY_PATH="$lib${LD_LIBRARY_PATH:+:$LD_LIBRARY_PATH}"
    cmake_args=(-DCMAKE_PREFIX_PATH="$toolchain/usr;$lib/cmake"
                -DVTK_DIR="$lib/cmake/vtk-9.1"
                -Dnlohmann_json_DIR="$toolchain/usr/share/cmake/nlohmann_json")
else
    echo "cmake and ninja are required (see ctfpga/README.md)" >&2
    exit 1
fi

cmake -S "$src" -B "$build" -G Ninja "${cmake_args[@]}" "$@" >/dev/null
cmake --build "$build"
for t in "$build"/test_*; do "$t" >/dev/null; done
echo "CTFPGA_BUILD_OK $build/ctfpga"
