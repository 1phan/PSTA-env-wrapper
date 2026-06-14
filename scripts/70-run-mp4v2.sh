#!/usr/bin/env bash
# Run the path-sensitive detectors on the whole-program mp4v2 module.
#
# ⚠ MEMORY: on a ~100-TU whole-program module the path-sensitive solve is
# memory-hungry. On a 22 GB box it OOM-killed at ~10 min. Give it plenty of RAM
# (this is the main reason to run on a server). A watchdog kills psta if its RSS
# crosses RSS_CEIL_GB so a runaway can't take the machine down.
#
# Tunables (env):  TIMEOUT=3600  RSS_CEIL_GB=0(off)  BOUND=0   DETECTORS="leak df uaf"
set -uo pipefail
source "$(dirname "${BASH_SOURCE[0]}")/../env.sh"
PSTA="$PSTA_DIR/Release-build/bin/psta"
BC="$MP4V2_DIR/bc-build/mp4v2_mp4info.bc"
mkdir -p "$REPORTS"
TIMEOUT="${TIMEOUT:-3600}"
RSS_CEIL_GB="${RSS_CEIL_GB:-0}"          # 0 = no ceiling; set e.g. 60 to cap
BOUND="${BOUND:-0}"                       # 1 = add -layer/-src-limit/-snk-limit caps
DETECTORS="${DETECTORS:-leak df uaf}"

[ -f "$BC" ] || { echo "missing $BC — run 60-gen-mp4v2-bc.sh first" >&2; exit 1; }
bargs=(); [ "$BOUND" = "1" ] && bargs=(-layer=2 -src-limit=3 -snk-limit=3)

flags_for() { case "$1" in leak) echo "-leak";; df) echo "-df";; uaf) echo "-uaf -add-uses";; esac; }

for det in $DETECTORS; do
  log="$REPORTS/mp4v2_$det.txt"; flags=$(flags_for "$det")
  echo "==== [$(date +%H:%M:%S)] psta $flags ${bargs[*]} (timeout ${TIMEOUT}s, ceil ${RSS_CEIL_GB}G) ===="
  timeout "$TIMEOUT" "$PSTA" $flags "${bargs[@]}" -report=true "$BC" > "$log" 2>&1 &
  pid=$!
  while kill -0 "$pid" 2>/dev/null; do
    if [ "$RSS_CEIL_GB" != "0" ]; then
      rss=$(ps -o rss= -p "$pid" 2>/dev/null | tr -d ' '); gb=$(( ${rss:-0} / 1048576 ))
      if [ "$gb" -ge "$RSS_CEIL_GB" ]; then echo "   !! RSS ${gb}G >= ${RSS_CEIL_GB}G — killing"; kill -9 "$pid"; break; fi
    fi
    sleep 10
  done
  wait "$pid" 2>/dev/null; ec=$?
  n=$(grep -E '^Bug Num' "$log" | tail -1 | awk '{print $NF}')
  case $ec in
    0)   echo "   DONE  Bug Num=${n:-?}";;
    124) echo "   TIMEOUT after ${TIMEOUT}s (no result)";;
    137) echo "   KILLED (OOM or RSS ceiling) — needs more RAM or scope down";;
    139) echo "   SEGFAULT";;
    *)   echo "   exit=$ec";;
  esac
  grep -iE 'NeverFree|PartialLeak|DOUBLE_FREE|USE_AFTER_FREE' "$log" | sed 's/\x1b\[[0-9;]*m//g' | sort -u | head -40
  echo
done
echo "MP4V2_RUN_DONE  (reports in $REPORTS)"
