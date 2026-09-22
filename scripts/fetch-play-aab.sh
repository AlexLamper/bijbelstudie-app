#!/usr/bin/env bash
# Waits for the "Android Build (signed AAB for Google Play)" run of a commit and
# drops the finished .aab into store-assets/google-play/builds/.
#
#   scripts/fetch-play-aab.sh            # for HEAD
#   scripts/fetch-play-aab.sh <sha>      # for a specific commit
#
# store-assets/ is gitignored, so the AAB only ever lives on this machine -- a
# 52 MB binary has no business in git history.
set -euo pipefail

REPO_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
OUT_DIR="$REPO_ROOT/store-assets/google-play/builds"
WORKFLOW="android-release.yml"
SHA="${1:-$(git -C "$REPO_ROOT" rev-parse HEAD)}"

# The workflow has paths-ignore for docs/markdown, so a run may never appear.
FIND_TIMEOUT=${FIND_TIMEOUT:-300}   # seconds to wait for the run to show up
POLL=${POLL:-15}

log() { printf '[fetch-play-aab] %s\n' "$*"; }

log "waiting for $WORKFLOW run on ${SHA:0:7}"

# RUN_ID=<id> skips the lookup and fetches that run directly.
RUN_ID="${RUN_ID:-}"
waited=0
while [ -z "$RUN_ID" ]; do
  RUN_ID="$(gh run list --repo "$(gh repo view --json nameWithOwner -q .nameWithOwner)" \
    --workflow "$WORKFLOW" --commit "$SHA" --limit 1 --json databaseId \
    -q '.[0].databaseId' 2>/dev/null || true)"
  [ -n "$RUN_ID" ] && break
  if [ "$waited" -ge "$FIND_TIMEOUT" ]; then
    log "no run found for ${SHA:0:7} after ${FIND_TIMEOUT}s (docs-only push?) - nothing to do"
    exit 0
  fi
  sleep "$POLL"
  waited=$((waited + POLL))
done

log "run $RUN_ID found; watching until it finishes"
gh run watch "$RUN_ID" --exit-status >/dev/null || {
  log "run $RUN_ID failed - see: gh run view $RUN_ID --log-failed"
  exit 1
}

TMP="$(mktemp -d)"
trap 'rm -rf "$TMP"' EXIT
gh run download "$RUN_ID" --dir "$TMP" >/dev/null

mkdir -p "$OUT_DIR"
found=0
while IFS= read -r aab; do
  cp -f "$aab" "$OUT_DIR/$(basename "$aab")"
  log "saved store-assets/google-play/builds/$(basename "$aab")"
  found=1
done < <(find "$TMP" -name '*.aab')

[ "$found" -eq 1 ] || { log "run $RUN_ID had no .aab artifact"; exit 1; }
