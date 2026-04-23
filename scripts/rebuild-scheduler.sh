#!/usr/bin/env bash
#
# Wave 0.6 — Local daily-rebuild scheduler simulation.
#
# Validates the scheduler logic (upstream-change detection + rebuild
# dispatch) before it becomes a real service in Wave 2. Runs entirely on
# the developer machine; no external infra.
#
# Two modes:
#
#   once      Run one scheduling pass and exit. Useful for cron integration
#             (add `*/15 * * * * .../rebuild-scheduler.sh once` to crontab)
#             and for CI smoke-testing the scheduler logic.
#
#   watch     Run in a loop, every INTERVAL seconds. Useful for developer
#             demos where you want to see rebuilds trigger live as packages
#             change upstream.
#
# Usage:
#   rebuild-scheduler.sh once [--spec <spec-file>] [--force]
#   rebuild-scheduler.sh watch [--interval 900] [--spec <spec-file>]
#
# State is kept in /tmp/distill-scheduler-state/ (or $DISTILL_STATE_DIR):
#
#   <stack>.last-rebuild     ISO8601 timestamp of last successful rebuild
#   <stack>.last-base-digest Last-seen source image digest (for change
#                             detection)
#   <stack>.rebuild-log      Append-only log of rebuild outcomes

set -euo pipefail

here=$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)
repo=$(cd "$here/.." && pwd)
cd "$repo"

# ── Defaults ───────────────────────────────────────────────────────────────
state_dir=${DISTILL_STATE_DIR:-/tmp/distill-scheduler-state}
spec=$repo/specs/base-ubi9.distill.yaml
interval=900   # 15 minutes
force=0
mode=""

# ── Args ───────────────────────────────────────────────────────────────────
if (( $# == 0 )); then
  cat >&2 <<EOF
Wave 0 local rebuild scheduler (simulation).

Usage:
  $(basename "$0") once  [--spec <file>] [--force]
  $(basename "$0") watch [--interval <sec>] [--spec <file>]

Env:
  DISTILL_STATE_DIR  state directory (default: /tmp/distill-scheduler-state)
EOF
  exit 2
fi

mode=$1; shift || true
while (( $# )); do
  case $1 in
    --spec)     spec=$2; shift 2 ;;
    --interval) interval=$2; shift 2 ;;
    --force)    force=1; shift ;;
    *) echo "unknown arg: $1" >&2; exit 2 ;;
  esac
done

if ! [[ -f $spec ]]; then
  echo "spec not found: $spec" >&2
  exit 1
fi

mkdir -p "$state_dir"

# ── Helpers ────────────────────────────────────────────────────────────────
log() {
  local ts
  ts=$(date -u +"%Y-%m-%dT%H:%M:%SZ")
  printf '%s  %s\n' "$ts" "$*"
}

stack_name() {
  # Derive the stack name from the spec's destination image.
  # "localhost:5555/base-ubi9" → "base-ubi9"
  yq -r '.destination.image | split("/") | .[-1]' "$spec"
}

source_image() {
  yq -r '.source.image' "$spec"
}

# Check whether the upstream source image has changed since our last
# rebuild. Uses `skopeo inspect` when available; falls back to `docker
# manifest inspect`. Returns the digest string (empty if unreachable).
current_source_digest() {
  local src; src=$(source_image)
  if command -v skopeo >/dev/null 2>&1; then
    skopeo inspect --raw "docker://$src" 2>/dev/null \
      | jq -r '.digest // ""' 2>/dev/null \
      || docker manifest inspect "$src" 2>/dev/null \
           | jq -r '.manifests[0].digest // .config.digest // ""' 2>/dev/null \
      || echo ""
  else
    docker manifest inspect "$src" 2>/dev/null \
      | jq -r '.manifests[0].digest // .config.digest // ""' 2>/dev/null \
      || echo ""
  fi
}

# Has the last rebuild happened within the daily fallback window (24h)?
within_daily_window() {
  local stack=$1
  local last_file="$state_dir/${stack}.last-rebuild"
  [[ ! -f $last_file ]] && return 1
  local last; last=$(cat "$last_file")
  local last_epoch now_epoch diff
  last_epoch=$(date -u -j -f "%Y-%m-%dT%H:%M:%SZ" "$last" +%s 2>/dev/null \
    || date -u -d "$last" +%s 2>/dev/null \
    || echo 0)
  now_epoch=$(date -u +%s)
  diff=$(( now_epoch - last_epoch ))
  (( diff < 86400 ))
}

# Determine whether a rebuild is warranted. Returns one of:
#   reason=upstream-change   new source image digest seen
#   reason=daily-fallback    last rebuild > 24h ago, safety net
#   reason=force             --force flag set
#   reason=none              no rebuild needed
decide() {
  local stack=$1

  if (( force )); then
    echo "reason=force"
    return
  fi

  local current; current=$(current_source_digest)
  local last_digest_file="$state_dir/${stack}.last-base-digest"
  local last=""
  [[ -f $last_digest_file ]] && last=$(cat "$last_digest_file")

  if [[ -n $current && $current != "$last" ]]; then
    echo "reason=upstream-change"
    echo "current=$current"
    echo "previous=$last"
    return
  fi

  if ! within_daily_window "$stack"; then
    echo "reason=daily-fallback"
    return
  fi

  echo "reason=none"
}

# ── One scheduling pass ────────────────────────────────────────────────────
run_once() {
  local stack; stack=$(stack_name)
  log "pass: stack=$stack spec=$(basename "$spec")"

  local decision
  decision=$(decide "$stack")
  local reason
  reason=$(echo "$decision" | grep '^reason=' | cut -d= -f2)

  log "  decision: $reason"

  case $reason in
    none)
      log "  → no action"
      return 0
      ;;
    force|daily-fallback|upstream-change)
      log "  → triggering rebuild"
      ;;
    *)
      log "  unexpected reason: $reason" >&2
      return 1
      ;;
  esac

  # Record what we saw so next pass has a baseline.
  local current; current=$(current_source_digest)
  [[ -n $current ]] && echo "$current" > "$state_dir/${stack}.last-base-digest"

  # Dispatch. In production this is a GitHub Actions `repository_dispatch`
  # call. Here we invoke the local publish pipeline directly so the
  # scheduler's behavior is observable end-to-end.
  local build_log="$state_dir/${stack}.rebuild.$(date -u +%Y%m%dT%H%M%SZ).log"
  log "  build log: $build_log"

  if DISTILL_CONTAINER_CLI=docker distill publish --spec "$spec" \
       --platform "${DISTILL_PLATFORM:-linux/amd64}" \
       > "$build_log" 2>&1; then
    local ts; ts=$(date -u +"%Y-%m-%dT%H:%M:%SZ")
    echo "$ts" > "$state_dir/${stack}.last-rebuild"
    echo "$ts  success  reason=$reason" >> "$state_dir/${stack}.rebuild-log"
    log "  ✓ rebuild succeeded"
    return 0
  fi

  local ts; ts=$(date -u +"%Y-%m-%dT%H:%M:%SZ")
  echo "$ts  failure  reason=$reason" >> "$state_dir/${stack}.rebuild-log"
  log "  ✗ rebuild failed — see $build_log"
  return 1
}

# ── Watch loop ─────────────────────────────────────────────────────────────
run_watch() {
  log "watch mode: interval=${interval}s state=$state_dir"
  while true; do
    run_once || log "pass failed; continuing"
    log "sleeping ${interval}s until next pass"
    sleep "$interval"
  done
}

case $mode in
  once)  run_once ;;
  watch) run_watch ;;
  *)     echo "unknown mode: $mode" >&2; exit 2 ;;
esac
