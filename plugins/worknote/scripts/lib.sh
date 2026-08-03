#!/usr/bin/env bash

# Shared helpers for the Codex plugin scripts. Keep this compatible with the
# Bash 3.2 shipped by macOS.

worknote_plugin_root() {
  if [ -n "${PLUGIN_ROOT:-}" ]; then
    printf '%s\n' "$PLUGIN_ROOT"
  else
    cd "$(dirname "${BASH_SOURCE[0]}")/.." >/dev/null 2>&1 && pwd
  fi
}

worknote_data_dir() {
  if [ -n "${PLUGIN_DATA:-}" ]; then
    printf '%s\n' "$PLUGIN_DATA"
  else
    printf '%s\n' "${XDG_STATE_HOME:-$HOME/.local/state}/worknote-codex"
  fi
}

worknote_safe_id() {
  local value safe
  value=${1:-}
  safe=$(printf '%s' "$value" | LC_ALL=C tr -cd 'A-Za-z0-9._-')
  [ -n "$safe" ] || safe=unknown
  printf '%s\n' "$safe"
}

worknote_sanitize_line() {
  local value limit
  value=${1:-}
  limit=${2:-220}
  printf '%s' "$value" \
    | tr '\r\n\t' '   ' \
    | LC_ALL=C tr -d '\000-\010\013\014\016-\037\177' \
    | sed -E 's/#[[]/[/g; s/#[{]/{/g; s/#[(]/(/g; s/[[:space:]]+/ /g; s/^ //; s/ $//' \
    | cut -c1-"$limit"
}

worknote_atomic_write() {
  local target dir tmp
  target=$1
  dir=$(dirname "$target")
  mkdir -p "$dir" || return 1
  tmp=$(mktemp "$dir/.worknote.XXXXXX") || return 1
  if cat >"$tmp" && mv "$tmp" "$target"; then
    return 0
  fi
  rm -f "$tmp"
  return 1
}

worknote_debug() {
  [ -n "${WORKNOTE_DEBUG:-}" ] || return 0
  printf 'worknote: %s\n' "$*" >&2
}
