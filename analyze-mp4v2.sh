#!/usr/bin/env bash
# Generate mp4v2 bitcode and run the detectors on it. Run AFTER bootstrap.sh.
# See scripts/70-run-mp4v2.sh for memory/timeout tunables (TIMEOUT, RSS_CEIL_GB, BOUND, DETECTORS).
set -euo pipefail
HERE="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" >/dev/null 2>&1 && pwd -P)"
bash "$HERE/scripts/60-gen-mp4v2-bc.sh"
bash "$HERE/scripts/70-run-mp4v2.sh"
