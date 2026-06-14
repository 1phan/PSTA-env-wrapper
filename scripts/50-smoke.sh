#!/usr/bin/env bash
# Validate the built psta on three tiny known-bug programs. ASSERTS one bug each
# (double-free / leak / use-after-free) and fails the script if detection breaks.
set -uo pipefail
source "$(dirname "${BASH_SOURCE[0]}")/../env.sh"
PSTA="$PSTA_DIR/Release-build/bin/psta"
D="$WORK/smoke"; mkdir -p "$D"; cd "$D"

cat > df.c   <<'EOF'
#include <stdlib.h>
int main(void){ char *p = malloc(16); free(p); free(p); return 0; }
EOF
cat > leak.c <<'EOF'
#include <stdlib.h>
int main(void){ char *p = malloc(16); p[0]=0; return 0; }
EOF
cat > uaf.c  <<'EOF'
#include <stdlib.h>
int main(void){ char *p = malloc(16); free(p); p[0]='x'; return (int)p[0]; }
EOF

compile() { clang -emit-llvm -c -g -O0 -fno-discard-value-names -Wno-everything "$1" -o "$2"; opt -p=mem2reg "$2" -o "$2"; }
compile df.c df.bc; compile leak.c leak.bc; compile uaf.c uaf.bc

check() { # "<detector flags>" <bcfile> "<expect regex>" <label>
  local flags="$1" bc="$2" expect="$3" label="$4" out
  echo "== $label =="
  out=$("$PSTA" $flags -report=true "$D/$bc" 2>&1 || true)
  echo "$out" | sed 's/\x1b\[[0-9;]*m//g' | grep -iE "$expect" | head -2 || true
  if echo "$out" | grep -qiE "$expect"; then echo "   PASS"; return 0
  else echo "   FAIL: expected /$expect/" >&2; return 1; fi
}

rc=0
check "-df"            df.bc   "DOUBLE_FREE"            "double-free"     || rc=1
check "-leak"          leak.bc "NeverFree|PartialLeak"  "leak"           || rc=1
check "-uaf -add-uses" uaf.bc  "USE_AFTER_FREE"         "use-after-free" || rc=1
if [ "$rc" -eq 0 ]; then echo "SMOKE_PASS"; else echo "SMOKE_FAIL" >&2; fi
exit $rc
