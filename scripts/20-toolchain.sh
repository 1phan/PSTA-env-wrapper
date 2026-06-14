#!/usr/bin/env bash
# Download the in-folder toolchain (cmake + LLVM 16.0.4/ubuntu-22.04 + Z3 4.8.8)
# and make sure the prebuilt clang actually RUNS on this host (libtinfo shim).
set -euo pipefail
source "$(dirname "${BASH_SOURCE[0]}")/../env.sh"
mkdir -p "$TC" "$TC/compat"

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

# ---- make clang runnable (libtinfo) ------------------------------------------
# The ubuntu-22.04 build needs libtinfo.so.6, present on virtually all modern
# Linux. If a host is missing the exact soname clang wants, shim it from whatever
# libtinfo the system has; the versioned-symbol stub is a last resort (the .so.5 case).
ensure_clang_runs() {
  "$LLVM_DIR/bin/clang" --version >/dev/null 2>&1 && return 0
  local missing sys
  missing=$(ldd "$LLVM_DIR/bin/clang" 2>/dev/null | awk '/libtinfo.*not found/{print $1; exit}')
  [ -z "$missing" ] && return 1
  echo ">> clang needs $missing — building a compat shim"
  sys=$(ldconfig -p 2>/dev/null | grep -oE '/[^ ]*/libtinfo\.so\.[0-9]+' | sort -V | tail -1)
  if [ -n "$sys" ]; then
    ln -sf "$sys" "$TC/compat/$missing"
    LD_LIBRARY_PATH="$TC/compat:${LD_LIBRARY_PATH:-}" "$LLVM_DIR/bin/clang" --version >/dev/null 2>&1 && return 0
  fi
  # symlink failed (e.g. needs versioned NCURSES_TINFO_5 symbols) -> build a stub
  if [ "$missing" = "libtinfo.so.5" ]; then
    gcc -shared -fPIC -O2 \
        -Wl,--version-script="$WRAP_ROOT/toolchain/tinfo5.map" \
        -Wl,-soname,libtinfo.so.5 \
        -o "$TC/compat/libtinfo.so.5" "$WRAP_ROOT/toolchain/tinfo5_stub.c"
    LD_LIBRARY_PATH="$TC/compat:${LD_LIBRARY_PATH:-}" "$LLVM_DIR/bin/clang" --version >/dev/null 2>&1 && return 0
  fi
  return 1
}
if ensure_clang_runs; then
  echo ">> clang: $(clang --version | head -1)"
else
  echo "!! clang from the prebuilt LLVM will not run on this host." >&2
  echo "   ldd output:"; ldd "$LLVM_DIR/bin/clang" 2>&1 | grep -i 'not found' >&2 || true
  exit 1
fi
echo "TOOLCHAIN_DONE"
