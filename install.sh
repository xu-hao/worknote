#!/usr/bin/env bash
# worknote installer — copies the scripts to ~/.claude/worknote/ and wires the
# status line into ~/.claude/settings.json (merging, not clobbering).
set -euo pipefail

SRC="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
DEST="$HOME/.claude/worknote"
SETTINGS="$HOME/.claude/settings.json"

command -v jq >/dev/null 2>&1   || { echo "error: jq is required (e.g. 'brew install jq' or 'apt install jq')"; exit 1; }
command -v claude >/dev/null 2>&1 || echo "warning: the 'claude' CLI isn't on PATH — notes won't generate until it is."

mkdir -p "$DEST/notes"
cp "$SRC/statusline.sh" "$SRC/generate.sh" "$DEST/"
chmod +x "$DEST/statusline.sh" "$DEST/generate.sh"

mkdir -p "$(dirname "$SETTINGS")"
[ -f "$SETTINGS" ] || echo '{}' > "$SETTINGS"

tmp="$(mktemp)"
jq --arg cmd "$DEST/statusline.sh" \
   '.statusLine = {type: "command", command: $cmd, refreshInterval: 10}' \
   "$SETTINGS" > "$tmp" && mv "$tmp" "$SETTINGS"

echo "✓ Installed worknote to $DEST"
echo "✓ Wired statusLine into $SETTINGS (existing settings preserved)"
echo "  It appears on your next interaction with Claude Code."
