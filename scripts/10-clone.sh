#!/usr/bin/env bash
# Clone the three source repos at pinned commits into $WORK.
set -euo pipefail
source "$(dirname "${BASH_SOURCE[0]}")/../env.sh"
mkdir -p "$WORK"

clone_at() {
  local url="$1" ref="$2" dir="$WORK/$3"
  if [ ! -d "$dir/.git" ]; then
    echo ">> cloning $3 <- $url"
    git clone "$url" "$dir"
  else
    echo ">> $3 already present"
  fi
  # Make sure the pinned commit is available, then check it out (detached).
  git -C "$dir" fetch --all --tags --quiet || true
  if ! git -C "$dir" cat-file -e "${ref}^{commit}" 2>/dev/null; then
    echo "!! pinned commit $ref not found in $3 — fetching default branch tip instead" >&2
    ref="$(git -C "$dir" rev-parse HEAD)"
  fi
  git -C "$dir" -c advice.detachedHead=false checkout --quiet "$ref"
  echo "   $3 @ $(git -C "$dir" rev-parse --short HEAD)"
}

clone_at "$SEMSVF_URL" "$SEMSVF_REF" SemSVF
clone_at "$PSTA_URL"   "$PSTA_REF"   PSTA-16-SemSVF
clone_at "$MP4V2_URL"  "$MP4V2_REF"  mp4v2
echo "CLONE_DONE"
