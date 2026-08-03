# worknote

A live, two-level "what am I working on" display for [Claude Code](https://code.claude.com) and [Codex](https://developers.openai.com/codex/).

The two summary lines answer different questions:

- **🎯 Big picture — *why you're here.*** The overarching goal stays stable across many turns and changes only when the session moves to a genuinely different objective.
- **📌 Detail — *what you're doing right now.*** The specific step or latest outcome changes as the conversation moves.

## What it looks like

Claude Code renders Worknote directly in its status area, followed by local metadata:

```text
🎯 Build a per-session status-line summarizer
📌 Adding the worktree segment and refreshing the README
🌿 feat/worktree-seg  ·  🌳 worktree-seg  ·  21% ctx
```

Codex keeps its native footer inside the pane. Worknote appends two rows below the existing tmux status row:

```text
0:codex*                                      "dev" 14:32
🎯 Port Worknote to Codex
📌 Adding deterministic hook and tmux lifecycle tests.
```

## Claude Code

### How it works

The status-line script does two jobs on each render:

1. **Display** — reads this session's note file and draws the three lines, word-wrapped to the terminal width.
2. **Refresh** — only when the transcript gains a new user or assistant message, it detaches a cheap [Haiku](https://docs.claude.com/en/docs/about-claude/models) call to regenerate the note. If the recent window is too thin, the generator retries with 14, 40, then 120 messages.

Notes are keyed by `session_id` under `~/.claude/worknote/notes/`. There are no timers, idle redraws cost no tokens, and summary generation never delays the turn.

### Requirements

- Claude Code, with the `claude` CLI on `PATH`.
- `jq` and standard Unix tools (`git`, `sed`, `fold`, `find`).
- Linux or macOS with Bash 3.2 or newer.

### Install

```sh
git clone https://github.com/xu-hao/worknote.git
cd worknote
./install.sh
```

`install.sh` copies the scripts to `~/.claude/worknote/` and merges a `statusLine` entry into `~/.claude/settings.json`. The status line appears after the next Claude Code interaction.

### Configuration

Edit the scripts in your clone, then rerun `./install.sh`; the directory under `~/.claude/` is a generated copy.

- **Redraw cadence** — `statusLine.refreshInterval` in `~/.claude/settings.json`. The default is 10 seconds and affects rendering only, not model calls.
- **Model** — change `--model haiku` in `generate.sh`.
- **Context tiers** — edit `TIERS` in `generate.sh` to change the 14 → 40 → 120 message escalation.
- **Goal stability** — edit the `CHANGED:` instruction in `generate.sh`.
- **Layout** — edit `statusline.sh` to change metadata, wrapping, or emoji.

### Uninstall

```sh
./uninstall.sh
```

This removes Worknote and its `statusLine` entry without replacing the rest of your Claude settings.

## Codex + tmux

Codex's native status line exposes built-in fields but does not run arbitrary render commands. The Worknote plugin therefore uses [lifecycle hooks](https://learn.chatgpt.com/docs/hooks) for updates and tmux's multi-line status area for display.

### How it works

1. `SessionStart` adds two tmux rows while preserving the session's existing status configuration.
2. `UserPromptSubmit` remembers the current prompt. `Stop` combines it with Codex's final assistant message and starts a detached summarizer.
3. A small, tool-disabled `codex exec` call returns schema-checked JSON. Worknote keeps the big-picture goal unless the model marks it changed, saves the two lines per Codex session, and updates the originating tmux pane.
4. `SessionEnd` removes Worknote from that pane. When the last Worknote pane exits, the original tmux rows and height are restored.

The plugin deliberately uses documented hook fields instead of parsing Codex's unstable transcript format. Multiple Codex panes can run independently in one tmux session; the active pane's note is displayed. No summary call is made while idle or when Codex is running outside tmux.

### Requirements

- A recent Codex CLI with plugins and hooks (tested with `codex-cli 0.146.0`) and an active Codex login.
- tmux with multi-line status support. Worknote can append its rows when the existing status uses zero to three rows; tmux supports at most five.
- `jq` and Bash 3.2 or newer.

### Install

From this checkout:

```sh
codex plugin marketplace add .
codex plugin add worknote@personal
tmux new -s codex
codex
```

Or, after the repository is published, add it directly from GitHub:

```sh
codex plugin marketplace add xu-hao/worknote
codex plugin add worknote@personal
```

Start a new Codex session inside tmux after installation. Review and trust the Worknote commands in `/hooks` if Codex prompts you. No `.tmux.conf` changes are required.

### Configuration

Set these in the environment before starting Codex:

```sh
export WORKNOTE_CODEX_MODEL=gpt-5.6-luna
export WORKNOTE_REASONING_EFFORT=none
# export WORKNOTE_DEBUG=1
```

The defaults shown above favor a fast, inexpensive summary. Worknote makes one short call after each completed Codex turn inside tmux; it makes no calls while idle or outside tmux. The current user prompt and final assistant message are sent to that summarizer and notes are stored in the plugin's data directory.

If Codex is killed before `SessionEnd` can restore tmux, start and exit another Codex session normally or reset the rows from this checkout:

```sh
bash plugins/worknote/scripts/tmux-status.sh reset "$TMUX_PANE"
```

### Uninstall

```sh
codex plugin remove worknote@personal
codex plugin marketplace remove personal
```

The marketplace removal is optional if you want to keep the repository registered with Codex.

## License

MIT — see [LICENSE](LICENSE).
