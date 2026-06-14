#!/usr/bin/env bash
# Build the SVF libraries PSTA links against: SvfLLVM (transitively SvfCore,
# SemSvfUtil, extapi.bc). Skips the analyze/replace tools (LLM pipeline) we don't need.
set -euo pipefail
source "$(dirname "${BASH_SOURCE[0]}")/../env.sh"
cd "$SVF_DIR"

TINFO=$(wrap_detect_lib tinfo); ZSTD=$(wrap_detect_lib zstd)
echo ">> tinfo=$TINFO  zstd=$ZSTD"

echo ">> configuring SVF (gcc, Release, assertions on, warn-as-error off)"
cmake -G "Unix Makefiles" \
  -DCMAKE_BUILD_TYPE=Release \
  -DCMAKE_C_COMPILER="$CC" -DCMAKE_CXX_COMPILER="$CXX" \
  -DSVF_ENABLE_ASSERTIONS=ON -DSVF_WARN_AS_ERROR=OFF -DBUILD_SHARED_LIBS=OFF \
  -DWRAP_TINFO_LIB="$TINFO" -DWRAP_ZSTD_LIB="$ZSTD" \
  -DCMAKE_PROJECT_TOP_LEVEL_INCLUDES="$WRAP_ROOT/toolchain/cmake_inject.cmake" \
  -S . -B Release-build

echo ">> building SvfLLVM with -j$JOBS (~15 min)"
cmake --build Release-build --target SvfLLVM -j"$JOBS"

mkdir -p Release-build/bin Release-build/lib   # find_package(SVF) checks these exist
echo ">> SVF artifacts:"; ls -la Release-build/lib/libSvf*.a Release-build/lib/extapi.bc
echo "SVF_BUILD_DONE"
