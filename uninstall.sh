#!/usr/bin/env bash
# worknote uninstaller — removes the statusLine entry (only if it points at
# worknote) and deletes ~/.claude/worknote/. Leaves the rest of settings.json alone.
set -euo pipefail

DEST="$HOME/.claude/worknote"
SETTINGS="$HOME/.claude/settings.json"

if command -v jq >/dev/null 2>&1 && [ -f "$SETTINGS" ]; then
  tmp="$(mktemp)"
  jq 'if ((.statusLine.command // "") | test("worknote/statusline.sh$"))
      then del(.statusLine) else . end' \
     "$SETTINGS" > "$tmp" && mv "$tmp" "$SETTINGS"
  echo "✓ Removed worknote statusLine from $SETTINGS (other settings untouched)"
fi

rm -rf "$DEST"
echo "✓ Removed $DEST"
