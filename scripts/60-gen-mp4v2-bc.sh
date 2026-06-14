#!/usr/bin/env bash
# Compile mp4v2 to LLVM bitcode for analysis. mp4v2 commits libplatform/config.h,
# so no ./configure is needed. SVF doesn't link modules, so we llvm-link all TUs
# into one whole-program module.
set -euo pipefail
source "$(dirname "${BASH_SOURCE[0]}")/../env.sh"
cd "$MP4V2_DIR"
OUT="$MP4V2_DIR/bc-build"; OBJ="$OUT/objs"
rm -rf "$OUT"; mkdir -p "$OBJ"

CXXF=(-emit-llvm -c -g -O0 -fno-discard-value-names -Wno-everything
      -std=c++11 -Iinclude -I. -DMP4V2_EXPORTS)

# All library TUs except Windows variants and the excluded FreeformBox.
shopt -s globstar nullglob
libtus=()
for f in src/**/*.cpp libplatform/**/*.cpp libutil/**/*.cpp; do
  case "$f" in *_win32.cpp|*FreeformBox.cpp) continue;; esac
  libtus+=("$f")
done

echo ">> compiling ${#libtus[@]} library TUs to bitcode"
libbcs=(); fails=0
for f in "${libtus[@]}"; do
  bc="$OBJ/$(echo "$f" | tr '/' '_').bc"
  if clang++ "${CXXF[@]}" "$f" -o "$bc" 2>>"$OUT/compile_errors.log"; then libbcs+=("$bc")
  else fails=$((fails+1)); echo "   !! failed: $f"; fi
done
echo ">> compiled $(( ${#libtus[@]} - fails ))/${#libtus[@]} TUs ($fails failed; see compile_errors.log)"

echo ">> linking library -> mp4v2_lib.bc"
llvm-link "${libbcs[@]}" -o "$OUT/mp4v2_lib.bc"; opt -p=mem2reg "$OUT/mp4v2_lib.bc" -o "$OUT/mp4v2_lib.bc"

echo ">> compiling driver util/mp4info.cpp and linking whole program -> mp4v2_mp4info.bc"
clang++ "${CXXF[@]}" util/mp4info.cpp -o "$OBJ/util_mp4info.bc"
llvm-link "${libbcs[@]}" "$OBJ/util_mp4info.bc" -o "$OUT/mp4v2_mp4info.bc"; opt -p=mem2reg "$OUT/mp4v2_mp4info.bc" -o "$OUT/mp4v2_mp4info.bc"

ls -la "$OUT"/*.bc
echo "MP4V2_BC_DONE"
