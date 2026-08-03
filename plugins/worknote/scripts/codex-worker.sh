#!/usr/bin/env bash
set -u

SCRIPT_DIR=$(cd "$(dirname "${BASH_SOURCE[0]}")" >/dev/null 2>&1 && pwd)
session_dir=${1:-}
[ -d "$session_dir" ] || exit 0

pending="$session_dir/pending.json"
lock="$session_dir/worker.lock"

while :; do
  if ! mkdir "$lock" 2>/dev/null; then
    exit 0
  fi
  owned=1
  cleanup() {
    if [ "${owned:-0}" = 1 ]; then
      rmdir "$lock" 2>/dev/null || true
    fi
  }
  trap cleanup EXIT HUP INT TERM

  while [ -f "$pending" ]; do
    job="$session_dir/job.$$.json"
    mv "$pending" "$job" 2>/dev/null || continue
    bash "$SCRIPT_DIR/codex-generate.sh" "$job" "$session_dir/note.md" || true
    rm -f "$job"
  done

  rmdir "$lock" 2>/dev/null || true
  owned=0
  trap - EXIT HUP INT TERM
  [ -f "$pending" ] || exit 0
done
