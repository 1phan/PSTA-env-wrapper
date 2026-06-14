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
# Locate a system shared library by stem (e.g. tinfo, zstd) — prefers the dev
# symlink lib<stem>.so, else the highest versioned lib<stem>.so.N. Returns the
# resolved path (the '=> /path' field of ldconfig), which actually exists.
wrap_detect_lib() {
  local stem="$1" p
  p=$(ldconfig -p 2>/dev/null | awk -v s="lib${stem}.so" '$1==s {print $NF; exit}')
  [ -z "$p" ] && p=$(ldconfig -p 2>/dev/null | awk -v s="lib${stem}.so." 'index($1,s)==1 {print $NF}' | sort -V | tail -1)
  printf '%s' "$p"
}

# True if a shared library matching the given ldconfig pattern is installed.
wrap_have_lib() { ldconfig -p 2>/dev/null | grep -qE "$1"; }

# Print the package-install command for this distro for the required runtime libs
# (ncurses/libtinfo + zstd) that the prebuilt LLVM links against.
wrap_pkg_hint() {
  if   command -v apt-get >/dev/null; then echo "  sudo apt-get install -y libtinfo6 libncurses6 libzstd1"
  elif command -v dnf     >/dev/null; then echo "  sudo dnf install -y ncurses-libs libzstd"
  elif command -v yum     >/dev/null; then echo "  sudo yum install -y ncurses-libs libzstd"
  elif command -v pacman  >/dev/null; then echo "  sudo pacman -S --needed ncurses zstd"
  elif command -v zypper  >/dev/null; then echo "  sudo zypper install -y libncurses6 libzstd1"
  else echo "  install the ncurses (libtinfo) and zstd runtime libraries for your distro"; fi
}
