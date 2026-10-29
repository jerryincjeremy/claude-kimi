---
name: kimi
description: Delegate work to Kimi Code (Moonshot's coding agent, installed locally as `kimi`) running headless as Claude's subagent / assistant. Use when the user says "ask kimi", "use kimi", "let kimi do it", "delegate to kimi", "kimi as subagent", "get a second opinion", or when Claude itself would benefit from an extra independent worker - parallel independent subtasks, a cross-model second opinion or code review, token-heavy exploration of large codebases or long files (Kimi has a 1M context), web research, or bulk mechanical edits. Triggers - kimi, Kimi Code, moonshot, second opinion, cross-check, parallelize, offload, assistant agent.
---

# Kimi as a subagent

Kimi Code CLI (`kimi`, tested with v2.3.0) runs headless through `scripts/kimi-run.sh`. It is a separate model with its own tools (Read/Grep/Glob/Edit/Write/Bash/WebSearch/FetchURL). Treat it like a capable colleague who knows **nothing** about this conversation.

```
SKILL=~/.claude/skills/kimi
$SKILL/scripts/kimi-run.sh [-m ro|rw] [-C dir] [-M model] [-t secs] [-r session] [-f prompt.md | "prompt"]
```

| Flag | Meaning |
|---|---|
| `-m ro` (default) | Read-only: Write, Edit, Bash and sub-agents are removed from Kimi's toolset. Use for investigation, review, research. |
| `-m rw` | Kimi may edit files and run shell commands. **There is no sandbox and no approval prompt in headless mode.** |
| `-C DIR` | Working directory Kimi operates in (default: current dir). Always pass it explicitly. |
| `-f FILE` | Read the prompt from a file. Use it for any brief longer than a few lines; write the file in the scratchpad. |
| `-t SECS` | Hard timeout, default 900. Exit code 124 means it timed out. |
| `-r SESSION` | Continue an earlier Kimi session (follow-ups, "fix what I flagged"). The session keeps its original ro/rw profile. |
| `-M MODEL` | Model alias. Default from config is `kimi-code/k3.1-pro`. Faster: `kimi-code/k3.1-pro-highspeed` (2x usage cost), `kimi-code/kimi-for-coding-highspeed`. |
| `-a DIR` | Extra workspace dir (repeatable). |

The script prints a report: status line (ok / TIMEOUT / FAILED, elapsed, **session id**), Kimi's final answer, an **actions** list (every Edit/Write path and Bash command), counts of read/search calls, and the path to the full JSONL transcript.

## When to delegate

Good fits:
- **Parallel independent work**: several investigations or edits to *disjoint* files at once while you continue.
- **Second opinion**: an independent review of a diff, a design, or a bug hypothesis from a different model family. Give it the code, not your conclusion, so it isn't anchored.
- **Token-heavy reading**: sweeping a big repo, long logs, or huge files. Kimi reads; you get the summary.
- **Web research**: Kimi has WebSearch/FetchURL.
- **Bulk mechanical edits** with a clear spec and a verification command.

Do it yourself instead when it's a few tool calls (each Kimi run costs ≥10s startup), when it depends on nuanced conversation context, or when it touches secrets/credentials or outward-facing actions (push, deploy, publish).

## Writing the brief

Kimi only sees your prompt. Every brief should state:
1. **Goal**: what "done" looks like, in one or two sentences.
2. **Context**: relevant paths, what you already know or ruled out, and constraints (style, APIs not to touch).
3. **Scope**: the exact files or directories it may change (rw), or the question to answer (ro).
4. **Verification**: the command to run (tests, build, lint), for rw tasks.
5. **Output**: what you want in the final report (e.g. "list each finding with file:line").

Use absolute paths. Write the brief in English or Chinese; Kimi handles both.

## Running

- Run in the foreground with a Bash `timeout` above `-t` (e.g. Bash timeout 600000 for `-t 540`). For long tasks, run with `run_in_background: true` and keep working; you'll be notified when it exits.
- **Parallel**: send several Bash calls (each `run_in_background: true`) in one message. Only run several `rw` jobs concurrently when their file sets don't overlap.
- Prefer a git working tree for `rw` jobs so `git diff` shows exactly what changed. If the dir isn't a repo, snapshot first (e.g. `cp -r`) or keep the job read-only.

## Reviewing the result (mandatory)

Kimi's report is a claim, not a fact. Before telling the user something is done:
- Check the **actions** list against the scope you gave. Anything unexpected (files outside scope, odd commands) gets inspected or reverted.
- Read the actual diff (`git diff`, or Read the files), and re-run the verification command yourself.
- For ro findings, spot-check the cited file:line evidence before relying on it.
- If it's wrong or incomplete, send a follow-up with `-r <session>` naming the concrete problem, rather than starting over.
- When reporting to the user, say which parts Kimi did and what you verified.

## Examples

Read-only second opinion on uncommitted changes:
```sh
git -C /path/repo diff > "$SCRATCH/diff.patch"
cat > "$SCRATCH/brief.md" <<EOF
Review the patch at $SCRATCH/diff.patch (repo: /path/repo) for correctness bugs only:
logic errors, unhandled edge cases, broken callers. Read surrounding code as needed.
Report each issue as: file:line, problem, concrete failing input. No style nits.
EOF
~/.claude/skills/kimi/scripts/kimi-run.sh -C /path/repo -f "$SCRATCH/brief.md"
```

Implementation task with verification, then a follow-up:
```sh
~/.claude/skills/kimi/scripts/kimi-run.sh -m rw -C /path/repo -t 900 -f "$SCRATCH/task.md"
# ...review diff, tests fail on edge case...
~/.claude/skills/kimi/scripts/kimi-run.sh -r session_xxx -C /path/repo "test_parse_empty fails: parse('') raises IndexError at parser.py:42. Fix it and re-run pytest tests/test_parser.py."
```

## Notes

- Agent profiles live in `agents/kimi-readonly.md` and `agents/kimi-worker.md` (Kimi agent-file format: `disallowedTools` in the frontmatter, system prompt in the body). Edit them to change Kimi's standing instructions.
- Transcripts live in `~/.cache/kimi-subagent/runs/` (override with `KIMI_RUNS_DIR`). Each one is JSONL: `{"role":"assistant","tool_calls":[...]}`, `{"role":"tool",...}`, and a final `{"type":"session.resume_hint","session_id":...}`.
- `kimi --plan` cannot be combined with `-p`; read-only mode works by restricting tools instead.
- Kimi also loads the MCP servers configured in the user's Kimi config, so they're available to it.
- Auth problems show up as FAILED with a stderr tail. Ask the user to run `! kimi login`.
