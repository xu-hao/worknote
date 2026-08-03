#!/usr/bin/env bash
set -euo pipefail

ROOT=$(cd "$(dirname "${BASH_SOURCE[0]}")/.." >/dev/null 2>&1 && pwd)
PLUGIN="$ROOT/plugins/worknote"
TEST_TMP=$(mktemp -d /tmp/worknote-test.XXXXXX)
trap 'rm -rf "$TEST_TMP"' EXIT
mkdir -p "$TEST_TMP/bin" "$TEST_TMP/tmux-state"

fail() {
  printf 'FAIL: %s\n' "$*" >&2
  exit 1
}

assert_eq() {
  local expected actual label
  expected=$1
  actual=$2
  label=$3
  [ "$expected" = "$actual" ] || fail "$label (expected '$expected', got '$actual')"
}

cat >"$TEST_TMP/bin/codex" <<'FAKE_CODEX'
#!/usr/bin/env bash
set -eu
out=
while [ "$#" -gt 0 ]; do
  if [ "$1" = "--output-last-message" ]; then
    out=$2
    shift 2
  else
    shift
  fi
done
[ -n "$out" ]
cat >"${FAKE_CODEX_PROMPT:?}"
printf '%s\n' "${FAKE_CODEX_OUTPUT:?}" >"$out"
printf 'call\n' >>"${FAKE_CODEX_CALLS:?}"
FAKE_CODEX

cat >"$TEST_TMP/bin/tmux" <<'FAKE_TMUX'
#!/usr/bin/env bash
set -eu
state=${FAKE_TMUX_STATE:?}
printf '%s\n' "$*" >>"$state/calls"
cmd=${1:-}
shift || true

key_for() {
  printf '%s' "$1" | tr -cd 'A-Za-z0-9_@-'
}

case "$cmd" in
  display-message)
    printf '$1\n'
    ;;
  show-options)
    include_inherited=0
    option=
    while [ "$#" -gt 0 ]; do
      case "$1" in
        -A) include_inherited=1; shift ;;
        -t) shift 2 ;;
        -*) shift ;;
        *) option=$1; shift ;;
      esac
    done
    key=$(key_for "$option")
    if [ -f "$state/opt.$key" ]; then
      cat "$state/opt.$key"
    elif [ "$option" = status ] && [ "$include_inherited" = 1 ]; then
      printf 'on\n'
    else
      exit 1
    fi
    ;;
  set-option)
    unset_value=0
    option=
    value=
    while [ "$#" -gt 0 ]; do
      case "$1" in
        -t) shift 2 ;;
        -u) unset_value=1; shift ;;
        -q|-p) shift ;;
        *)
          option=$1
          shift
          if [ "$#" -gt 0 ]; then
            value=$1
            shift
          fi
          ;;
      esac
    done
    key=$(key_for "$option")
    if [ "$unset_value" = 1 ]; then
      rm -f "$state/opt.$key"
    else
      printf '%s\n' "$value" >"$state/opt.$key"
    fi
    ;;
  list-panes)
    format=
    while [ "$#" -gt 0 ]; do
      case "$1" in
        -F) format=$2; shift 2 ;;
        -t) shift 2 ;;
        -*) shift ;;
        *) shift ;;
      esac
    done
    if [ "$format" = '#{pane_id}' ]; then
      printf '%%1\n'
    elif [ -f "$state/opt.@worknote_active" ]; then
      cat "$state/opt.@worknote_active"
    else
      printf '\n'
    fi
    ;;
  refresh-client) ;;
  *) exit 1 ;;
esac
FAKE_TMUX

chmod +x "$TEST_TMP/bin/codex" "$TEST_TMP/bin/tmux"

export PLUGIN_ROOT="$PLUGIN"
export PLUGIN_DATA="$TEST_TMP/data"
export TMUX_PANE=%1
export WORKNOTE_TMUX_BIN="$TEST_TMP/bin/tmux"
export WORKNOTE_CODEX_BIN="$TEST_TMP/bin/codex"
export WORKNOTE_SYNC=1
export FAKE_TMUX_STATE="$TEST_TMP/tmux-state"
export FAKE_CODEX_PROMPT="$TEST_TMP/model-prompt"
export FAKE_CODEX_CALLS="$TEST_TMP/model-calls"

hook="$PLUGIN/scripts/codex-hook.sh"

sanitized=$(bash -c '. "$1"; worknote_sanitize_line "$2"' _ \
  "$PLUGIN/scripts/lib.sh" 'Keep #[fg=red] #{pane_id} #(run-command) literal')
assert_eq 'Keep [fg=red] {pane_id} (run-command) literal' "$sanitized" 'tmux format sanitization'

session_start='{"session_id":"s1","hook_event_name":"SessionStart","cwd":"/repo","model":"gpt-test"}'
assert_eq '{}' "$(printf '%s' "$session_start" | bash "$hook")" 'SessionStart hook output'
grep -q 'status-format\[1\]' "$TEST_TMP/tmux-state/calls" || fail 'tmux BIG row was not configured'
grep -q 'status-format\[2\]' "$TEST_TMP/tmux-state/calls" || fail 'tmux NOW row was not configured'

prompt_one='{"session_id":"s1","turn_id":"t1","hook_event_name":"UserPromptSubmit","prompt":"Port Worknote to Codex."}'
assert_eq '{}' "$(printf '%s' "$prompt_one" | bash "$hook")" 'UserPromptSubmit hook output'

export FAKE_CODEX_OUTPUT='{"changed":true,"big":"Port Worknote to Codex","now":"Connecting Codex hooks to the tmux status rows."}'
stop_one='{"session_id":"s1","turn_id":"t1","hook_event_name":"Stop","cwd":"/repo","model":"gpt-test","last_assistant_message":"The hook design is ready."}'
assert_eq '{}' "$(printf '%s' "$stop_one" | bash "$hook")" 'Stop hook output'

note="$PLUGIN_DATA/sessions/s1/note.md"
assert_eq 'Port Worknote to Codex' "$(sed -n '1p' "$note")" 'initial BIG note'
assert_eq 'Connecting Codex hooks to the tmux status rows.' "$(sed -n '2p' "$note")" 'initial NOW note'
grep -q 'Port Worknote to Codex.' "$FAKE_CODEX_PROMPT" || fail 'captured user prompt was not sent to the summarizer'

prompt_two='{"session_id":"s1","turn_id":"t2","hook_event_name":"UserPromptSubmit","prompt":"Add tests."}'
printf '%s' "$prompt_two" | bash "$hook" >/dev/null
export FAKE_CODEX_OUTPUT='{"changed":false,"big":"Replace this incorrectly","now":"Adding deterministic hook and tmux integration tests."}'
stop_two='{"session_id":"s1","turn_id":"t2","hook_event_name":"Stop","cwd":"/repo","model":"gpt-test","last_assistant_message":"The tests now pass."}'
printf '%s' "$stop_two" | bash "$hook" >/dev/null

assert_eq 'Port Worknote to Codex' "$(sed -n '1p' "$note")" 'stable BIG note'
assert_eq 'Adding deterministic hook and tmux integration tests.' "$(sed -n '2p' "$note")" 'updated NOW note'
assert_eq 2 "$(wc -l <"$FAKE_CODEX_CALLS" | tr -d ' ')" 'model call count'

session_end='{"session_id":"s1","hook_event_name":"SessionEnd","cwd":"/repo","model":"gpt-test"}'
assert_eq '{}' "$(printf '%s' "$session_end" | bash "$hook")" 'SessionEnd hook output'
grep -q 'set-option -q -u -t \$1 status' "$TEST_TMP/tmux-state/calls" || fail 'inherited tmux status was not restored'

printf '2\n' >"$TEST_TMP/tmux-state/opt.status"
printf 'existing row two\n' >"$TEST_TMP/tmux-state/opt.status-format2"
printf 'existing row three\n' >"$TEST_TMP/tmux-state/opt.status-format3"
bash "$PLUGIN/scripts/tmux-status.sh" enable "$TMUX_PANE"
assert_eq 4 "$(cat "$TEST_TMP/tmux-state/opt.status")" 'expanded custom tmux status height'
bash "$PLUGIN/scripts/tmux-status.sh" disable "$TMUX_PANE"
assert_eq 2 "$(cat "$TEST_TMP/tmux-state/opt.status")" 'explicit tmux status height restore'
assert_eq 'existing row two' "$(cat "$TEST_TMP/tmux-state/opt.status-format2")" 'explicit tmux BIG slot restore'
assert_eq 'existing row three' "$(cat "$TEST_TMP/tmux-state/opt.status-format3")" 'explicit tmux NOW slot restore'

unset TMUX_PANE
before=$(wc -l <"$FAKE_CODEX_CALLS" | tr -d ' ')
printf '%s' "$stop_two" | bash "$hook" >/dev/null
after=$(wc -l <"$FAKE_CODEX_CALLS" | tr -d ' ')
assert_eq "$before" "$after" 'model calls outside tmux'

printf 'PASS: Codex hooks, summarizer, and tmux lifecycle\n'
