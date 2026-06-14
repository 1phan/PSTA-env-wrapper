#!/usr/bin/env bash
# Single source of truth: configuration + environment for the PSTA-env-wrapper.
# Every script does `source env.sh`. After bootstrap, source this to use `psta`.
#
# Everything is self-contained under $WORK (default ./work) — no system installs,
# nothing written outside this tree (the libtinfo lookups only READ system libs).

# ---- resolve locations -------------------------------------------------------
WRAP_ROOT="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" >/dev/null 2>&1 && pwd -P)"
export WRAP_ROOT
export WORK="${WORK:-$WRAP_ROOT/work}"          # clones + toolchain + builds live here

# ---- source repos (override via env if your auth/forks differ) ----------------
# The two Mem2019 repos are PRIVATE — the machine needs git access (SSH key or PAT).
export SEMSVF_URL="${SEMSVF_URL:-git@github.com:Mem2019/SemSVF.git}"
export SEMSVF_REF="${SEMSVF_REF:-f6c01405b8d4f71bd19fefa90e0b656c3ddf2e8d}"   # branch PSTA-16
export PSTA_URL="${PSTA_URL:-git@github.com:Mem2019/PSTA-16-SemSVF.git}"
export PSTA_REF="${PSTA_REF:-c7ce576bac693c35dbc8e0e3d260164874284ff8}"        # branch main
export MP4V2_URL="${MP4V2_URL:-https://github.com/TechSmith/mp4v2.git}"        # public
export MP4V2_REF="${MP4V2_REF:-6727d3c5faaf8b9db9214127f6e6d9e5e8cf95c1}"

# ---- toolchain versions (downloaded into $WORK/toolchain) ----------------------
# LLVM platform MUST be a gcc>=8 build (ubuntu-22.04 = gcc-11). The ubuntu-18.04
# build (gcc-7.5) passes std::optional by-memory and crashes SVF on modern
# libstdc++ (>=8, by-value). See README "Why 16.0.4 / ubuntu-22.04".
export CMAKE_VER="${CMAKE_VER:-3.28.1}"
export LLVM_VER="${LLVM_VER:-16.0.4}"
export LLVM_PLATFORM="${LLVM_PLATFORM:-x86_64-linux-gnu-ubuntu-22.04}"
export Z3_VER="${Z3_VER:-4.8.8}"

CMAKE_URL="https://github.com/Kitware/CMake/releases/download/v${CMAKE_VER}/cmake-${CMAKE_VER}-linux-x86_64.tar.gz"
LLVM_URL="https://github.com/llvm/llvm-project/releases/download/llvmorg-${LLVM_VER}/clang+llvm-${LLVM_VER}-${LLVM_PLATFORM}.tar.xz"
Z3_URL="https://github.com/Z3Prover/z3/releases/download/z3-${Z3_VER}/z3-${Z3_VER}-x64-ubuntu-16.04.zip"
export CMAKE_URL LLVM_URL Z3_URL

# ---- derived paths -------------------------------------------------------------
export TC="$WORK/toolchain"
export LLVM_DIR="$TC/llvm"
export Z3_DIR="$TC/z3"
export SVF_DIR="$WORK/SemSVF"
export PSTA_DIR="$WORK/PSTA-16-SemSVF"
export MP4V2_DIR="$WORK/mp4v2"
export REPORTS="$WORK/reports"

# Build SVF/PSTA with the system GCC (ABI-matched to the gcc-built prebuilt LLVM);
# clang from $LLVM_DIR is used ONLY to emit LLVM bitcode.
export CC="${CC:-gcc}"
export CXX="${CXX:-g++}"
export JOBS="${JOBS:-$(nproc 2>/dev/null || echo 4)}"

# ---- PATH / LD_LIBRARY_PATH (dirs may not exist yet during bootstrap; harmless) -
# Runtime libs (libtinfo/ncurses, libzstd) come from the SYSTEM — declared as
# dependencies and checked in 20-toolchain.sh, not shimmed.
export PATH="$TC/cmake/bin:$LLVM_DIR/bin:$Z3_DIR/bin:$PSTA_DIR/Release-build/bin:$PATH"
export LD_LIBRARY_PATH="$LLVM_DIR/lib:$Z3_DIR/bin:$SVF_DIR/Release-build/svf:$SVF_DIR/Release-build/svf-llvm:${LD_LIBRARY_PATH:-}"

# ---- helpers -------------------------------------------------------------------
# The prebuilt LLVM's exported LLVMSupport target links ncurses(libtinfo), zstd
# and zlib; LLVMConfig.cmake recreates the Terminfo::terminfo / zstd::libzstd_shared
# / ZLIB::ZLIB imported targets via find_package(), which need the -DEV packages
# (the lib<x>.so dev symlink + headers). We DECLARE these as build dependencies and
# check them the same way find_package does — by trying to link — rather than
# faking the targets. Returns the space-separated missing deps ("" = all present).
wrap_missing_build_deps() {
  local cc="${CC:-cc}" t miss=""
  t="$(mktemp 2>/dev/null || echo "/tmp/wrapdep.$$")"; printf 'int main(void){return 0;}\n' > "$t.c"
  { "$cc" "$t.c" -ltinfo -o /dev/null 2>/dev/null \
    || "$cc" "$t.c" -lncurses  -o /dev/null 2>/dev/null \
    || "$cc" "$t.c" -lncursesw -o /dev/null 2>/dev/null; } || miss="$miss ncurses/tinfo"
  "$cc" "$t.c" -lzstd -o /dev/null 2>/dev/null || miss="$miss zstd"
  "$cc" "$t.c" -lz    -o /dev/null 2>/dev/null || miss="$miss zlib"
  printf '#include <zstd.h>\nint main(void){return 0;}\n' > "$t.c"
  "$cc" -fsyntax-only "$t.c" 2>/dev/null || case " $miss " in *" zstd "*) :;; *) miss="$miss zstd-headers";; esac
  rm -f "$t" "$t.c"
  printf '%s' "${miss# }"
}

# Print the -dev package install command for this distro.
wrap_pkg_hint() {
  if   command -v apt-get >/dev/null; then echo "  sudo apt-get install -y libtinfo-dev libzstd-dev zlib1g-dev   # (libtinfo-dev may be 'libncurses-dev')"
  elif command -v dnf     >/dev/null; then echo "  sudo dnf install -y ncurses-devel libzstd-devel zlib-devel"
  elif command -v yum     >/dev/null; then echo "  sudo yum install -y ncurses-devel libzstd-devel zlib-devel"
  elif command -v pacman  >/dev/null; then echo "  sudo pacman -S --needed ncurses zstd zlib"
  elif command -v zypper  >/dev/null; then echo "  sudo zypper install -y ncurses-devel libzstd-devel zlib-devel"
  else echo "  install the -dev packages for ncurses(libtinfo), zstd and zlib"; fi
}
