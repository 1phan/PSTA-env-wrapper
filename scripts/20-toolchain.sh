#!/usr/bin/env bash
# Download the in-folder toolchain (cmake + LLVM 16.0.4/ubuntu-22.04 + Z3 4.8.8)
# and verify the host provides the runtime libraries the prebuilt LLVM needs.
# We do NOT shim or fake any system library: if a dependency is missing we tell
# you exactly what to install and stop.
set -euo pipefail
source "$(dirname "${BASH_SOURCE[0]}")/../env.sh"
mkdir -p "$TC"

dl() { # url dest
  echo ">> downloading $(basename "$2")"
  if command -v curl >/dev/null; then curl -L --fail --retry 4 --retry-delay 3 -C - "$1" -o "$2"
  else wget -c "$1" -O "$2"; fi
}

# ---- cmake -------------------------------------------------------------------
if [ ! -x "$TC/cmake/bin/cmake" ]; then
  dl "$CMAKE_URL" "$TC/cmake.tgz"
  mkdir -p "$TC/cmake"; tar -xf "$TC/cmake.tgz" -C "$TC/cmake" --strip-components 1; rm -f "$TC/cmake.tgz"
fi
echo ">> cmake: $("$TC/cmake/bin/cmake" --version | head -1)"

# ---- LLVM 16.0.4 (ubuntu-22.04 / gcc-11 build) -------------------------------
if [ ! -x "$LLVM_DIR/bin/clang" ]; then
  dl "$LLVM_URL" "$TC/llvm.tar.xz"
  echo ">> extracting LLVM (~6GB unpacked)…"
  mkdir -p "$LLVM_DIR"; tar -xf "$TC/llvm.tar.xz" -C "$LLVM_DIR" --strip-components 1; rm -f "$TC/llvm.tar.xz"
fi

# ---- Z3 ----------------------------------------------------------------------
if [ ! -d "$Z3_DIR/bin" ]; then
  dl "$Z3_URL" "$TC/z3.zip"
  ( cd "$TC" && unzip -q -o z3.zip && rm -rf z3 && mv z3-"$Z3_VER"-* z3 && rm -f z3.zip )
fi

# ---- verify required SYSTEM runtime libraries are present --------------------
# The prebuilt LLVM (and thus psta, which links LLVMSupport) needs ncurses
# (libtinfo) and zstd. These are normal, packaged libraries — install them via
# your package manager; we ship NO substitutes. The clang binary is the arbiter:
# if it can't load, we surface the exact missing library and the install command.
missing=""
{ wrap_have_lib 'libtinfo\.so' || wrap_have_lib 'libncursesw?\.so'; } || missing="$missing ncurses/libtinfo"
wrap_have_lib 'libzstd\.so' || missing="$missing libzstd"
if ! "$LLVM_DIR/bin/clang" --version >/dev/null 2>&1; then
  echo "!! the prebuilt clang cannot start — missing system libraries:" >&2
  ldd "$LLVM_DIR/bin/clang" 2>/dev/null | awk '/not found/{print "     "$1}' >&2
  missing="$missing (see clang dynamic deps above)"
fi
if [ -n "$missing" ]; then
  echo "" >&2
  echo "!! Missing required system libraries:$missing" >&2
  echo "   Install them, then re-run bootstrap.sh. On this distro:" >&2
  wrap_pkg_hint >&2
  exit 1
fi

echo ">> clang: $(clang --version | head -1)"
echo ">> system libs OK (ncurses/libtinfo, libzstd present)"
echo "TOOLCHAIN_DONE"
