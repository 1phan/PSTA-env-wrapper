#!/usr/bin/env bash
# Build the PSTA tool (`psta`) against the locally-built SVF.
set -euo pipefail
source "$(dirname "${BASH_SOURCE[0]}")/../env.sh"
cd "$PSTA_DIR"

echo ">> configuring PSTA (gcc, Release)"
cmake -G "Unix Makefiles" \
  -DCMAKE_BUILD_TYPE=Release \
  -DCMAKE_C_COMPILER="$CC" -DCMAKE_CXX_COMPILER="$CXX" \
  -DSVF_DIR="$SVF_DIR" -DLLVM_DIR="$LLVM_DIR" -DZ3_DIR="$Z3_DIR" \
  -S . -B Release-build

echo ">> building psta with -j$JOBS"
cmake --build Release-build --target psta -j"$JOBS"

echo ">> psta: $(ls -la Release-build/bin/psta)"
echo "PSTA_BUILD_DONE"
