#!/usr/bin/env bash
set -u

SCRIPT_DIR=$(cd "$(dirname "${BASH_SOURCE[0]}")" >/dev/null 2>&1 && pwd)
# shellcheck source=lib.sh
. "$SCRIPT_DIR/lib.sh"

action=${1:-}
pane=${2:-${TMUX_PANE:-}}
TMUX_BIN=${WORKNOTE_TMUX_BIN:-tmux}

case "$pane" in
  %*) ;;
  *) exit 0 ;;
esac

command -v "$TMUX_BIN" >/dev/null 2>&1 || exit 0
session=$("$TMUX_BIN" display-message -p -t "$pane" '#{session_id}' 2>/dev/null) || exit 0
[ -n "$session" ] || exit 0

set_session_option() {
  "$TMUX_BIN" set-option -q -t "$session" "$1" "$2" >/dev/null 2>&1
}

set_pane_option() {
  "$TMUX_BIN" set-option -q -p -t "$pane" "$1" "$2" >/dev/null 2>&1
}

unset_session_option() {
  "$TMUX_BIN" set-option -q -u -t "$session" "$1" >/dev/null 2>&1 || true
}

unset_pane_option() {
  "$TMUX_BIN" set-option -q -u -p -t "$pane" "$1" >/dev/null 2>&1 || true
}

get_session_option() {
  "$TMUX_BIN" show-options -q -v -t "$session" "$1" 2>/dev/null
}

get_effective_session_option() {
  "$TMUX_BIN" show-options -A -q -v -t "$session" "$1" 2>/dev/null
}

save_option() {
  local option key value
  option=$1
  key=$2
  if value=$("$TMUX_BIN" show-options -v -t "$session" "$option" 2>/dev/null); then
    set_session_option "@worknote_prev_${key}_present" 1
    set_session_option "@worknote_prev_${key}" "$value"
  else
    set_session_option "@worknote_prev_${key}_present" 0
  fi
}

enable_status() {
  local managed previous_status base_lines big_index now_index new_lines
  set_pane_option @worknote_active 1

  managed=$(get_session_option @worknote_managed || true)
  [ "$managed" = 1 ] && return 0

  previous_status=$(get_effective_session_option status || true)
  [ -n "$previous_status" ] || previous_status=on
  case "$previous_status" in
    off) base_lines=0 ;;
    on) base_lines=1 ;;
    2|3) base_lines=$previous_status ;;
    *)
      worknote_debug "tmux status already uses $previous_status rows; two Worknote rows will not fit"
      return 0
      ;;
  esac

  big_index=$base_lines
  now_index=$((base_lines + 1))
  new_lines=$((base_lines + 2))

  save_option status status
  save_option "status-format[$big_index]" "format_${big_index}"
  save_option "status-format[$now_index]" "format_${now_index}"
  set_session_option @worknote_big_index "$big_index"
  set_session_option @worknote_now_index "$now_index"
  set_session_option "status-format[$big_index]" '#[align=left]#[fg=colour214]🎯 #[default]#{@worknote_big}'
  set_session_option "status-format[$now_index]" '#[align=left]#[fg=colour75]📌 #[default]#{@worknote_now}'
  set_session_option status "$new_lines"
  set_session_option @worknote_managed 1
}

restore_option() {
  local option key present value
  option=$1
  key=$2
  present=$(get_session_option "@worknote_prev_${key}_present" || true)
  if [ "$present" = 1 ]; then
    value=$(get_session_option "@worknote_prev_${key}" || true)
    set_session_option "$option" "$value"
  else
    unset_session_option "$option"
  fi
  unset_session_option "@worknote_prev_${key}_present"
  unset_session_option "@worknote_prev_${key}"
}

disable_status() {
  local active managed big_index now_index pane_id
  unset_pane_option @worknote_active
  unset_pane_option @worknote_big
  unset_pane_option @worknote_now

  active=$("$TMUX_BIN" list-panes -s -t "$session" -F '#{@worknote_active}' 2>/dev/null \
    | grep -c '^1$' || true)
  [ "${active:-0}" -eq 0 ] || return 0

  managed=$(get_session_option @worknote_managed || true)
  [ "$managed" = 1 ] || return 0
  big_index=$(get_session_option @worknote_big_index || true)
  now_index=$(get_session_option @worknote_now_index || true)

  [ -n "$big_index" ] && restore_option "status-format[$big_index]" "format_${big_index}"
  [ -n "$now_index" ] && restore_option "status-format[$now_index]" "format_${now_index}"
  restore_option status status

  for pane_id in $("$TMUX_BIN" list-panes -s -t "$session" -F '#{pane_id}' 2>/dev/null); do
    "$TMUX_BIN" set-option -q -u -p -t "$pane_id" @worknote_active >/dev/null 2>&1 || true
    "$TMUX_BIN" set-option -q -u -p -t "$pane_id" @worknote_big >/dev/null 2>&1 || true
    "$TMUX_BIN" set-option -q -u -p -t "$pane_id" @worknote_now >/dev/null 2>&1 || true
  done

  unset_session_option @worknote_big_index
  unset_session_option @worknote_now_index
  unset_session_option @worknote_managed
  "$TMUX_BIN" refresh-client -S >/dev/null 2>&1 || true
}

case "$action" in
  enable)
    enable_status
    ;;
  update)
    enable_status
    big=$(worknote_sanitize_line "${3:-}" 120)
    now=$(worknote_sanitize_line "${4:-}" 220)
    set_pane_option @worknote_big "$big"
    set_pane_option @worknote_now "$now"
    "$TMUX_BIN" refresh-client -S >/dev/null 2>&1 || true
    ;;
  disable)
    disable_status
    ;;
  reset)
    for target in $("$TMUX_BIN" list-panes -s -t "$session" -F '#{pane_id}' 2>/dev/null); do
      "$TMUX_BIN" set-option -q -u -p -t "$target" @worknote_active >/dev/null 2>&1 || true
    done
    disable_status
    ;;
  *)
    printf 'usage: %s {enable|update|disable|reset} [%%pane] [big] [now]\n' "$0" >&2
    exit 2
    ;;
esac
