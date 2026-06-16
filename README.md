# worknote

A live, two-level "what am I working on" status line for [Claude Code](https://code.claude.com), summarized by Haiku.

It keeps a per-session note pinned to the bottom of Claude Code, so after a long turn (or a coffee break) you can glance down and instantly re-anchor on what you're doing:

```
🎯 Build a per-session status-line summarizer for Claude Code
📌 Adding the worktree segment to the metadata row and refreshing the README
🌿 feat/worktree-seg  ·  🌳 worktree-seg  ·  21% ctx
```

Each line answers a different question:

- **🎯 Big picture — *why you're here.*** The session's overarching goal, the thing that stays true across many turns (`Build a per-session status-line summarizer`). It moves slowly — only when your focus shifts to a genuinely different objective — so it's the anchor you glance at to remember what you're ultimately doing.
- **📌 Detail — *what you're doing right now.*** The specific step in front of you (`Adding the worktree segment…`), rewritten as the conversation moves. This is the line that changes turn to turn.
- **🌿 Metadata — *where you are.*** Your current git branch, the `🌳` worktree when you're inside one (hidden in the main checkout), and how full the context window is.

## How it works

The status line script does two jobs on each render:

1. **Display** — reads this session's note file and draws the three lines, word-wrapped to your terminal width.
2. **Refresh (event-driven)** — *only when the transcript has gained a new user/assistant message* since the last refresh, it detaches a cheap [Haiku](https://docs.claude.com/en/docs/about-claude/models) call to regenerate the note in the background. If the recent window is too thin to tell what you're doing, the model replies `NEED_MORE` and the generator re-runs with a larger slice of the transcript (escalating 14 → 40 → 120 messages), so the summary can reach back for context only when it actually needs to.

Design properties:

- **Per-session** — the note is keyed by `session_id` (`~/.claude/worknote/notes/<id>.md`), so several Claude Code sessions running at once never share or clobber each other's note.
- **No timers** — regeneration triggers on a *new message*, not a clock. Idle redraws and tool activity cost **zero** tokens.
- **Non-blocking** — the Haiku call runs detached, so it never delays your turn.
- **Two cadences, one stable, one live** — the big-picture line is held steady; the detail line tracks recent activity.

## Requirements

- Claude Code, with the `claude` CLI on your `PATH` (the note is generated via `claude -p --model haiku`).
- `jq`, plus standard Unix tools (`git`, `sed`, `fold`, `find`). Works on Linux and macOS (bash 3.2+).

## Install

```sh
git clone https://github.com/xu-hao/worknote.git
cd worknote
./install.sh
```

`install.sh` copies the scripts to `~/.claude/worknote/` and adds a `statusLine` entry to `~/.claude/settings.json` (merging into your existing settings, not replacing them). The status line appears on your next interaction with Claude Code.

## Configuration

Edit the scripts **in your clone**, then re-run `./install.sh` to redeploy — `~/.claude/worknote/` is a generated copy and is overwritten on install.

- **Redraw cadence** — `statusLine.refreshInterval` in `~/.claude/settings.json` (seconds; cosmetic only — it does not trigger Haiku calls). Default `10`.
- **Model** — change `--model haiku` in `generate.sh`.
- **Context tiers** — `TIERS` in `generate.sh` controls how much transcript the summarizer may request (default `14 → 40 → 120` messages). It escalates only when the model reports the window is insufficient, so wider tiers cost nothing on the common path.
- **Goal-line stability** — the `🎯` line is held steady by feeding the model its current value and replacing it only when the model judges the focus has shifted to a different feature or objective. Loosen or tighten that by editing the `CHANGED:` instruction in `generate.sh`.
- **Layout / segments** — edit `statusline.sh` (e.g. drop a segment, change an emoji, or change how the detail line wraps).

## Uninstall

```sh
./uninstall.sh
```

Removes `~/.claude/worknote/` and the `statusLine` entry (only if it still points at worknote). The rest of your settings are left untouched.

## Notes

- **Why an install script rather than a Claude Code plugin?** Plugins can ship hooks, commands, agents, and MCP servers — but **not a `statusLine`**, which is what this tool fundamentally is. Since the status line both displays the note and drives its refresh, a small install script is the natural, fully-working fit.
- **Cost** — one short Haiku call per *new message*; nothing while idle. Typical summaries are a few thousand input tokens and a handful of output tokens.

## License

MIT — see [LICENSE](LICENSE).
