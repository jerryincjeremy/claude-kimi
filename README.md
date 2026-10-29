# claude-kimi

A [Claude Code](https://claude.com/claude-code) skill that turns [Kimi Code](https://moonshotai.github.io/kimi-code/) into Claude's subagent. Claude writes a self-contained brief, Kimi runs it headless, and Claude gets back a compact report to review.

## What it does

- **Read-only mode** (default): Kimi can read, search, and use the web, but its Write, Edit, Bash, and sub-agent tools are removed. Good for reviews, research, and second opinions.
- **Write mode** (`-m rw`): Kimi edits files and runs commands, then reports what it changed and how it verified it.
- **Report** for every run: status, elapsed time, session ID, Kimi's final answer, every file it edited and command it ran, and the path to the full JSONL transcript.
- **Follow-ups**: `-r <session>` continues the same Kimi session.
- **Timeouts**: `-t <seconds>`, default 900.

## Requirements

- Kimi Code CLI on `PATH` as `kimi`, logged in (`kimi login`). Tested with v2.3.0.
- `python3` and `timeout` (coreutils).

## Install

```sh
git clone https://github.com/jerryincjeremy/claude-kimi.git
cp -r claude-kimi/kimi ~/.claude/skills/kimi
```

Start a new Claude Code session and say something like "ask kimi to review my last change".

## Direct use

```sh
~/.claude/skills/kimi/scripts/kimi-run.sh -C /path/to/repo "Where is the retry logic for HTTP requests?"
~/.claude/skills/kimi/scripts/kimi-run.sh -m rw -C /path/to/repo -f task.md
~/.claude/skills/kimi/scripts/kimi-run.sh -r session_xxx -C /path/to/repo "The test still fails; fix it."
```

Run `kimi-run.sh --help` for all options.

## Layout

```
kimi/
├── SKILL.md                 # instructions Claude follows: when to delegate, briefs, review
├── scripts/kimi-run.sh      # headless wrapper + report formatter
└── agents/
    ├── kimi-readonly.md     # Kimi agent profile: no write/exec tools
    └── kimi-worker.md       # Kimi agent profile: scoped implementation worker
```

## Caveat

In headless (`-p`) mode Kimi runs shell commands without asking for approval, so write mode has no sandbox. Use it in a git working tree so changes are easy to inspect and revert.
