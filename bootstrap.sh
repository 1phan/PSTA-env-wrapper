#!/usr/bin/env bash
# One-shot setup: preflight -> clone -> toolchain -> build SVF -> build PSTA -> smoke.
# Idempotent: re-running skips finished steps. After this, `source env.sh` and use psta.
set -euo pipefail
HERE="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" >/dev/null 2>&1 && pwd -P)"
source "$HERE/env.sh"

echo "================= preflight ================="
miss=0
for c in git tar xz unzip make "$CC" "$CXX"; do
  command -v "$c" >/dev/null 2>&1 || { echo "  MISSING: $c"; miss=1; }
done
command -v curl >/dev/null 2>&1 || command -v wget >/dev/null 2>&1 || { echo "  MISSING: curl or wget"; miss=1; }
# Required SYSTEM runtime libraries the prebuilt LLVM links against (no shims).
libmiss=""
{ wrap_have_lib 'libtinfo\.so' || wrap_have_lib 'libncursesw?\.so'; } || libmiss="$libmiss ncurses/libtinfo"
wrap_have_lib 'libzstd\.so' || libmiss="$libmiss libzstd"
if [ -n "$libmiss" ]; then
  echo "  MISSING system libraries:$libmiss — install them first:"; wrap_pkg_hint; miss=1
fi
# gcc must be >= 8 (C++17 + std::optional pass-by-value, matching the prebuilt LLVM)
gv=$("$CXX" -dumpfullversion -dumpversion 2>/dev/null | cut -d. -f1)
if [ -n "$gv" ] && [ "$gv" -lt 8 ] 2>/dev/null; then
  echo "  WARNING: $CXX major version $gv < 8 — std::optional ABI may mismatch the prebuilt LLVM."
fi
# disk space where $WORK will live
avail=$(df -P "$(dirname "$WORK")" 2>/dev/null | awk 'NR==2{print int($4/1048576)}')
echo "  compiler: $($CXX --version | head -1)"
echo "  cores: $JOBS   free disk near \$WORK: ${avail:-?} GB (need ~30)"
echo "  WORK = $WORK"
[ "$miss" -eq 1 ] && { echo "Install the missing tools and retry."; exit 1; }
[ -n "${avail:-}" ] && [ "$avail" -lt 25 ] 2>/dev/null && echo "  WARNING: low disk (<25 GB)."

echo "================= 1/5 clone =================";      bash "$HERE/scripts/10-clone.sh"
echo "================= 2/5 toolchain =============";      bash "$HERE/scripts/20-toolchain.sh"
echo "================= 3/5 build SVF (~15 min) ===";      bash "$HERE/scripts/30-build-svf.sh"
echo "================= 4/5 build PSTA ============";      bash "$HERE/scripts/40-build-psta.sh"
echo "================= 5/5 smoke test ============";      bash "$HERE/scripts/50-smoke.sh"

cat <<EOF

========================================================
 Bootstrap complete. psta is built and validated.

   source $HERE/env.sh
   psta -df -report=true <file.bc>

 To analyze mp4v2 (memory-heavy — see README):
   bash $HERE/analyze-mp4v2.sh
========================================================
EOF
