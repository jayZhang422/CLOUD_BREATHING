cmake_minimum_required(VERSION 3.16)
# VTK 的依赖查找（HDF5/NetCDF）会对 C 编译器做 try_compile，因此需要启用 C。
project(ctfpga LANGUAGES C CXX)

set(CMAKE_CXX_STANDARD 17)
set(CMAKE_CXX_STANDARD_REQUIRED ON)
set(CMAKE_CXX_EXTENSIONS OFF)
if(NOT CMAKE_BUILD_TYPE)
  set(CMAKE_BUILD_TYPE Release)
endif()
# 禁止 FMA 收缩与快速数学：CT 量化/VOL2 重采样必须与 numpy 逐位一致。
add_compile_options(-Wall -Wextra -Wno-unused-parameter -ffp-contract=off)

option(CTFPGA_WITH_GDCM "Build DICOM reader (GDCM)" ON)
option(CTFPGA_WITH_VTK  "Build mesh stages (VTK)"   ON)

find_package(nlohmann_json REQUIRED)
find_package(Threads REQUIRED)
find_package(ZLIB REQUIRED)
find_package(OpenMP)

# ---- 数据面：哈希、JSON、VOL2、执行清单、UDP RPC（无重依赖） ----
add_library(ctfpga_core STATIC
  src/common/util.cpp
  src/ct/vol2.cpp
  src/ct/convert.cpp
  src/net/protocol.cpp
  src/net/op_client.cpp
  src/net/volume_ctl.cpp
  src/common/case_flow.cpp)
target_include_directories(ctfpga_core PUBLIC src)
target_link_libraries(ctfpga_core PUBLIC nlohmann_json::nlohmann_json Threads::Threads)
if(OpenMP_CXX_FOUND)
  target_link_libraries(ctfpga_core PUBLIC OpenMP::OpenMP_CXX)
endif()

if(CTFPGA_WITH_GDCM)
  # 不用 find_package(GDCM)/UseGDCM：前者会引用未安装的命令行工具，后者会连带拉入 VTK 查找。
  find_path(GDCM_INCLUDE_DIR gdcmReader.h PATH_SUFFIXES gdcm-3.0 gdcm REQUIRED)
  set(_gdcm_libs "")
  foreach(_n gdcmMSFF gdcmDSED gdcmIOD gdcmDICT gdcmCommon)
    find_library(GDCM_${_n}_LIB ${_n} REQUIRED)
    list(APPEND _gdcm_libs ${GDCM_${_n}_LIB})
  endforeach()
  target_sources(ctfpga_core PRIVATE src/ct/dicom.cpp)
  target_include_directories(ctfpga_core PRIVATE ${GDCM_INCLUDE_DIR})
  target_compile_definitions(ctfpga_core PUBLIC CTFPGA_HAVE_GDCM=1)
  target_link_libraries(ctfpga_core PUBLIC ${_gdcm_libs} ZLIB::ZLIB)
endif()

# ---- 网格面：BIN→STL / 平滑 / 减面 ----
if(CTFPGA_WITH_VTK)
  find_package(VTK COMPONENTS CommonCore CommonDataModel CommonExecutionModel
               FiltersCore FiltersGeneral IOGeometry REQUIRED)
  add_library(ctfpga_mesh STATIC
    src/mesh/volume3d.cpp
    src/mesh/morph.cpp
    src/mesh/mesh_io.cpp
    src/mesh/repair.cpp
    src/mesh/surface.cpp
    src/mesh/decimate.cpp
    src/mesh/stages.cpp)
  target_include_directories(ctfpga_mesh PUBLIC src)
  target_link_libraries(ctfpga_mesh PUBLIC ctfpga_core ${VTK_LIBRARIES})
  target_compile_definitions(ctfpga_core PUBLIC CTFPGA_HAVE_VTK=1)
  vtk_module_autoinit(TARGETS ctfpga_mesh MODULES ${VTK_LIBRARIES})
endif()

# ---- 可执行文件 ----
add_executable(ctfpga src/app/main.cpp)
target_link_libraries(ctfpga PRIVATE ctfpga_core)
if(CTFPGA_WITH_VTK)
  target_link_libraries(ctfpga PRIVATE ctfpga_mesh)
  target_compile_definitions(ctfpga PRIVATE CTFPGA_HAVE_VTK=1)
  vtk_module_autoinit(TARGETS ctfpga MODULES ${VTK_LIBRARIES})
endif()

# 板端替身：仅用于 WSL 回环联调，不是交付物。
add_executable(mockboard tools/mockboard.cpp)
target_link_libraries(mockboard PRIVATE ctfpga_core)

# ---- 自测 ----
enable_testing()
foreach(t test_util test_vol2 test_protocol)
  add_executable(${t} tests/${t}.cpp)
  target_link_libraries(${t} PRIVATE ctfpga_core)
  add_test(NAME ${t} COMMAND ${t})
endforeach()
