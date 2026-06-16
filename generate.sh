#!/usr/bin/env bash
# worknote — generator. Summarizes a session transcript into a two-level note via
# Haiku, ESCALATING to a larger transcript window if the model says it needs more.
#   line 1 = BIG (stable; changes only when the model judges the goal changed)
#   line 2 = NOW (live; preserved if a call returns empty)
# Usage (also invoked detached by statusline.sh):  generate.sh <transcript.jsonl> <out.md>
# Set WORKNOTE_DEBUG=1 to trace tier selection on stderr.
set -u
transcript="${1:-}"
OUT="${2:-$HOME/.claude/worknote/notes/default.md}"
[ -f "$transcript" ] || exit 0
mkdir -p "$(dirname "$OUT")"

dbg() { [ -n "${WORKNOTE_DEBUG:-}" ] && printf 'worknote: %s\n' "$*" >&2; return 0; }

# A value that means "no real BIG" — empty, or a leaked prompt placeholder. Such a
# value must never be treated as a goal (that was the "stuck on (none yet…)" bug).
is_placeholder() {
  case "$1" in
    ""|"(none)"|none|"N/A"|"n/a"|*"none yet"*|*"first summary"*|*"no goal"*) return 0;;
    *) return 1;;
  esac
}

# Current note: feed BIG back so the model knows what it was; keep NOW as fallback.
existing_big=""; existing_now=""
if [ -f "$OUT" ]; then
  existing_big=$(sed -n '1p' "$OUT")
  existing_now=$(sed -n '2p' "$OUT")
fi
# Self-heal: a previously-leaked placeholder counts as "no BIG yet" so we regenerate.
is_placeholder "$existing_big" && existing_big=""

extract() { # $1=maxmsgs $2=maxchars
  jq -r 'select(.type=="user" or .type=="assistant")
         | (.message.content) as $c
         | (if ($c|type)=="array" then ($c|map(select(.type=="text")|.text)|join(" ")) else ($c|tostring) end) as $t
         | ($t|gsub("^[[:space:]]+|[[:space:]]+$";"")) as $t
         | select(($t|length)>0)
         | "\(.message.role): \($t)"' "$transcript" 2>/dev/null \
    | tail -n "$1" | tail -c "$2"
}

build_prompt() { # $1=convo  $2=allow_more(1/0)
  local more="" bigblock
  [ "$2" = "1" ] && more="If the TRANSCRIPT below is INSUFFICIENT to confidently identify what the developer is currently working on — for example the latest messages are terse ('yes', 'ok', 'do it') and the real task is not shown — reply with EXACTLY the single word:
NEED_MORE
and nothing else; you will then be shown more of the conversation. Otherwise:
"
  if [ -n "$existing_big" ]; then
    bigblock="The developer's current big-picture goal is given as CURRENT BIG below. In the BIG line, reproduce it character-for-character UNLESS CHANGED is yes.

CURRENT BIG: $existing_big"
  else
    bigblock="There is no recorded big-picture goal yet — infer a fresh one from the transcript and set CHANGED to yes. Never output placeholder text such as 'none' or 'first summary' as the goal."
  fi
  printf '%s' "Below is the recent transcript of a developer's coding session with an AI assistant. As a neutral observer, summarize the work and judge whether the OVERARCHING GOAL has changed.

${more}Output EXACTLY three lines and nothing else:
CHANGED: <yes or no. Say 'yes' when the focus has moved to a different feature, component, or objective than CURRENT BIG — not merely the next small step within it. Say 'no' only when CURRENT BIG still broadly names the current work (e.g. the difference is just wording or minor progress).>
BIG: <the overarching goal as one terse phrase, at most 8 words.>
NOW: <the specific thing being worked on right now, one sentence, ~15-25 words.>

Write in the third person and describe the task; do NOT reply to or continue the conversation; do NOT address anyone; no first or second person; no quotes; no markdown.

$bigblock

TRANSCRIPT:
$1"
}

run_haiku() { # $1=prompt
  WORKNOTE_GEN=1 claude -p "$1" \
    --model haiku \
    --settings '{"disableAllHooks":true}' \
    --tools "" \
    --no-session-persistence 2>/dev/null | tr -d '\r'
}

is_need_more() { printf '%s\n' "$1" | grep -qiE '^[[:space:]]*need[ _]?more[[:space:]]*$'; }

TIERS=("14:4000" "40:14000" "120:40000")
ntiers=${#TIERS[@]}
raw=""
for i in "${!TIERS[@]}"; do
  tier="${TIERS[$i]}"; mm="${tier%%:*}"; cc="${tier##*:}"
  convo=$(extract "$mm" "$cc")
  [ -z "$convo" ] && { dbg "no transcript text; nothing to do"; exit 0; }
  if [ "$i" -eq $((ntiers-1)) ]; then allow_more=0; else allow_more=1; fi
  raw=$(run_haiku "$(build_prompt "$convo" "$allow_more")")
  if [ "$allow_more" -eq 1 ] && is_need_more "$raw"; then
    dbg "tier $((i+1)) ($mm msgs/$cc chars): model asked for more → escalating"
    continue
  fi
  dbg "answered at tier $((i+1)) ($mm msgs/$cc chars)"
  break
done

trim() { sed -E 's/^["[:space:]]+//; s/["[:space:]]+$//'; }
field() { printf '%s\n' "$raw" | grep -iE "^[[:space:]]*$1:" | head -1 | sed -E 's/^[^:]*:[[:space:]]*//' | trim; }
changed=$(field CHANGED | tr '[:upper:]' '[:lower:]')
big_new=$(field BIG | cut -c1-120)
now_new=$(field NOW | cut -c1-220)
is_placeholder "$big_new" && big_new=""   # never let a placeholder become the BIG
if [ -z "$big_new" ] && [ -z "$now_new" ]; then
  now_new=$(printf '%s\n' "$raw" | grep -viE '^[[:space:]]*need[ _]?more' | grep -v '^[[:space:]]*$' | head -1 | trim | cut -c1-220)
fi

# Keep BIG verbatim unless the model says the goal actually changed (or none yet).
if [ -z "$existing_big" ]; then
  big_out="$big_new"                       # establish a real BIG (never the placeholder)
elif printf '%s' "$changed" | grep -q '^y'; then
  big_out="${big_new:-$existing_big}"
else
  big_out="$existing_big"
fi
now_out="${now_new:-$existing_now}"

if [ -n "$big_out" ] || [ -n "$now_out" ]; then
  printf '%s\n%s\n' "$big_out" "$now_out" > "$OUT"
fi
