#!/usr/bin/env bash
# worknote — Claude Code status line: a per-session, two-level "what am I working
# on" summary, refreshed only when a new message arrives (no timers, no idle spend).
#   🎯 <big picture: the overarching goal — stable>
#   📌 <detail: what's happening right now, word-wrapped>
#   🌿 <git branch>  ·  <context %>
#
# Installed to ~/.claude/worknote/statusline.sh by install.sh and wired into
# settings.json as the statusLine command. It renders the note AND, only when the
# transcript has gained a user/assistant text message since last time, detaches a
# cheap Haiku call (generate.sh) to refresh this session's note.

input=$(cat)

DIR_BASE="$HOME/.claude/worknote"
NOTES="$DIR_BASE/notes"
GEN="$DIR_BASE/generate.sh"

# Per-session key — both render and refresh use the same session_id.
sid=$(printf '%s' "$input" | jq -r '.session_id // "default"')
PIN_FILE="$NOTES/${sid}.md"

# Coordinates from the session JSON on stdin (local; no tokens).
dir=$(printf '%s' "$input" | jq -r '.workspace.current_dir // .cwd // empty')
pct=$(printf '%s' "$input" | jq -r '.context_window.used_percentage // empty')
branch=$(git -C "${dir:-.}" branch --show-current 2>/dev/null)
wt=$(printf '%s' "$input" | jq -r '.workspace.git_worktree // .worktree.name // empty')

# Metadata row.
meta=()
[ -n "$branch" ] && meta+=("🌿 $branch")
[ -n "$wt" ]     && meta+=("🌳 $wt")
[ -n "$pct" ]    && meta+=("${pct%%.*}% ctx")
metaline=""
for s in "${meta[@]}"; do
  [ -n "$metaline" ] && metaline+="  ·  "
  metaline+="$s"
done
[ -z "$metaline" ] && metaline="📂 ${dir##*/}"

# Terminal width — Claude Code sets COLUMNS (v2.1.153+); fall back if absent/odd.
maxw=${COLUMNS:-100}
case "$maxw" in (*[!0-9]*) maxw=100;; esac
[ "$maxw" -lt 24 ] && maxw=100

# ---- render -------------------------------------------------------------
if [ -s "$PIN_FILE" ]; then
  big=$(sed -n '1p' "$PIN_FILE")
  now=$(sed -n '2p' "$PIN_FILE")
  if [ -n "$big" ]; then
    bl="🎯 $big"
    [ "${#bl}" -gt "$maxw" ] && bl="${bl:0:$((maxw-1))}…"
    printf '%s\n' "$bl"
  fi
  [ -n "$now" ] && printf '📌 %s\n' "$now" | fold -s -w "$maxw"
  printf '%s' "$metaline"
else
  printf '%s' "$metaline"
fi

# ---- refresh ONLY on a new message (event-driven, no timers) -------------
transcript=$(printf '%s' "$input" | jq -r '.transcript_path // empty')
if [ -n "$transcript" ] && [ -f "$transcript" ] && [ -x "$GEN" ]; then
  mkdir -p "$NOTES"
  SEEN="$NOTES/${sid}.seen"
  # Count real user/assistant TEXT messages (excludes tool_use / tool_result).
  cur=$(jq -r 'select(.type=="user" or .type=="assistant")
               | (.message.content) as $c
               | (((($c|type)=="string") and (($c|length)>0))
                  or ((($c|type)=="array") and (([ $c[] | select(.type=="text") ]|length)>0)))
               | select(.) | "x"' "$transcript" 2>/dev/null | wc -l | tr -d ' ')
  seen=0; [ -f "$SEEN" ] && seen=$(cat "$SEEN" 2>/dev/null || echo 0)
  if [ "${cur:-0}" -gt "${seen:-0}" ]; then
    echo "$cur" > "$SEEN"
    find "$NOTES" -type f -mtime +7 -delete 2>/dev/null   # housekeeping only
    # Detach so the render never waits on the LLM call. setsid (Linux) or nohup (macOS).
    if command -v setsid >/dev/null 2>&1; then
      setsid bash "$GEN" "$transcript" "$PIN_FILE" </dev/null >/dev/null 2>&1 &
    else
      nohup bash "$GEN" "$transcript" "$PIN_FILE" </dev/null >/dev/null 2>&1 &
    fi
    disown 2>/dev/null || true
  fi
fi

exit 0   # never let a skipped refresh blank the status line
