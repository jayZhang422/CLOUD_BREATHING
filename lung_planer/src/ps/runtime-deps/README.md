# Qt KMS/GBM support library

This directory adds only `libQt6EglFsKmsGbmSupport.so.6`, from the unmodified
official Qt 6.7.3 aarch64 qtbase binary archive. It does not replace PySide6,
system Qt, libMali, the kernel, or the desktop driver. The launcher uses it only
through its private process `LD_LIBRARY_PATH` and requires Qt exactly 6.7.3.
Private ABI compatibility still requires the board-side relocation/plugin checks.

Qt is copyright The Qt Company Ltd. and other contributors. This library is
available under LGPL-3.0-only (or the alternatives specified by upstream).
The LGPLv3 and GPLv3 texts are in `licenses/`. It is dynamically linked and may
be replaced with a compatible build; the application performs no signature or
hash enforcement against a user-built replacement.

Exact corresponding source (Qt tag `v6.7.3`):

- https://download.qt.io/archive/qt/6.7/6.7.3/submodules/qtbase-everywhere-src-6.7.3.tar.xz
- https://code.qt.io/cgit/qt/qtbase.git/tree/?h=v6.7.3
- Implementation: `src/plugins/platforms/eglfs/deviceintegration/eglfs_kms/`
- Build: Qt's CMake build with EGL, OpenGL ES2, DRM and GBM development headers;
  preserve the board runtime's Qt build configuration when rebuilding a private module.

Binary archive used:

https://download.qt.io/online/qtsdkrepository/linux_arm64/desktop/qt6_673/qt.qt6.673.linux_gcc_arm64/6.7.3-0-202409200836qtbase-Linux-Debian_11_6-GCC-Linux-Debian_11_6-AARCH64.7z

Archive SHA256:
`850f7d2b73c958ce80ef47a81c18f64d03d3be606637278d14acb8959e6dffe8c`

Extracted member: `6.7.3/gcc_arm64/lib/libQt6EglFsKmsGbmSupport.so.6.7.3`
(190,448 bytes), installed here under its SONAME `.so.6`.

Library SHA256:
`efc8cb7efc40a7a0e7217387f84f101a6cb4f9e883fc1197b0c9507925048ea8`

Having this file does not establish vendor EGL/GBM compatibility or working
physical display output. Never resume the failed fbdev test to bypass a check.
