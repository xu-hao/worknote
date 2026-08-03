#!/usr/bin/env bash
set -u

SCRIPT_DIR=$(cd "$(dirname "${BASH_SOURCE[0]}")" >/dev/null 2>&1 && pwd)
# shellcheck source=lib.sh
. "$SCRIPT_DIR/lib.sh"

payload=$(cat)

# A nested `codex exec` used by the generator must never trigger another note.
if [ -n "${WORKNOTE_GENERATING:-}" ]; then
  printf '{}\n'
  exit 0
fi

if ! command -v jq >/dev/null 2>&1; then
  printf '{}\n'
  exit 0
fi

event=$(printf '%s' "$payload" | jq -r '.hook_event_name // ""' 2>/dev/null)
session_id=$(printf '%s' "$payload" | jq -r '.session_id // "unknown"' 2>/dev/null)
turn_id=$(printf '%s' "$payload" | jq -r '.turn_id // "latest"' 2>/dev/null)
sid=$(worknote_safe_id "$session_id")
tid=$(worknote_safe_id "$turn_id")
DATA=$(worknote_data_dir)
session_dir="$DATA/sessions/$sid"
pane=${TMUX_PANE:-}

# There is no visible renderer outside tmux, so avoid an invisible model call.
case "$pane" in
  %*) ;;
  *)
    printf '{}\n'
    exit 0
    ;;
esac

mkdir -p "$session_dir/prompts"

show_existing_note() {
  local big now
  [ -s "$session_dir/note.md" ] || return 0
  big=$(sed -n '1p' "$session_dir/note.md")
  now=$(sed -n '2p' "$session_dir/note.md")
  bash "$SCRIPT_DIR/tmux-status.sh" update "$pane" "$big" "$now" || true
}

start_worker() {
  if [ -n "${WORKNOTE_SYNC:-}" ]; then
    bash "$SCRIPT_DIR/codex-worker.sh" "$session_dir"
  elif command -v setsid >/dev/null 2>&1; then
    setsid bash "$SCRIPT_DIR/codex-worker.sh" "$session_dir" </dev/null >/dev/null 2>&1 &
  else
    nohup bash "$SCRIPT_DIR/codex-worker.sh" "$session_dir" </dev/null >/dev/null 2>&1 &
  fi
}

case "$event" in
  SessionStart)
    bash "$SCRIPT_DIR/tmux-status.sh" enable "$pane" || true
    show_existing_note
    ;;
  UserPromptSubmit)
    bash "$SCRIPT_DIR/tmux-status.sh" enable "$pane" || true
    prompt=$(printf '%s' "$payload" | jq -r '.prompt // ""' 2>/dev/null)
    jq -n --arg prompt "$prompt" '{prompt: $prompt}' \
      | worknote_atomic_write "$session_dir/prompts/$tid.json"
    ;;
  Stop)
    bash "$SCRIPT_DIR/tmux-status.sh" enable "$pane" || true
    prompt=
    if [ -f "$session_dir/prompts/$tid.json" ]; then
      prompt=$(jq -r '.prompt // ""' "$session_dir/prompts/$tid.json" 2>/dev/null)
    fi
    assistant=$(printf '%s' "$payload" | jq -r '.last_assistant_message // ""' 2>/dev/null)
    cwd=$(printf '%s' "$payload" | jq -r '.cwd // ""' 2>/dev/null)
    model=$(printf '%s' "$payload" | jq -r '.model // ""' 2>/dev/null)
    if [ -n "$prompt$assistant" ]; then
      jq -n \
        --arg session_id "$session_id" \
        --arg turn_id "$turn_id" \
        --arg prompt "$prompt" \
        --arg assistant "$assistant" \
        --arg cwd "$cwd" \
        --arg model "$model" \
        --arg tmux_pane "$pane" \
        '{session_id: $session_id, turn_id: $turn_id, prompt: $prompt, assistant: $assistant, cwd: $cwd, model: $model, tmux_pane: $tmux_pane}' \
        | worknote_atomic_write "$session_dir/pending.json"
      rm -f "$session_dir/prompts/$tid.json"
      start_worker
    fi
    ;;
  SessionEnd)
    bash "$SCRIPT_DIR/tmux-status.sh" disable "$pane" || true
    ;;
esac

printf '{}\n'
