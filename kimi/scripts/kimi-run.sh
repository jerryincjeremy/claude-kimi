#!/bin/sh
# Run Kimi Code headless as a subagent and print a compact, reviewable report.
#
# Usage: kimi-run.sh [options] [PROMPT...]
#   -m, --mode ro|rw        ro = read-only (default), rw = may edit files and run commands
#   -C, --cwd DIR           working directory for Kimi (default: current directory)
#   -M, --model ALIAS       Kimi model alias, e.g. kimi-code/k3.1-pro-highspeed
#   -r, --resume SESSION    continue an earlier Kimi session (follow-up / fix request)
#   -t, --timeout SECONDS   hard time limit (default: 900)
#   -f, --prompt-file FILE  read the prompt from FILE ("-" = stdin)
#   -a, --add-dir DIR       extra workspace directory (repeatable)
#   -o, --out DIR           where transcripts are kept (default: ~/.cache/kimi-subagent/runs)
# Prompt comes from -f, else the remaining arguments, else stdin.

set -u
SKILL_DIR=$(cd "$(dirname "$0")/.." && pwd)
MODE=ro CWD=$(pwd) MODEL= RESUME= TIMEOUT=900 PROMPT_FILE= ADD_DIRS=
OUT_DIR=${KIMI_RUNS_DIR:-$HOME/.cache/kimi-subagent/runs}

die() { echo "kimi-run: $*" >&2; exit 2; }

while [ $# -gt 0 ]; do
  case $1 in
    -m|--mode) MODE=$2; shift 2 ;;
    -C|--cwd) CWD=$2; shift 2 ;;
    -M|--model) MODEL=$2; shift 2 ;;
    -r|--resume) RESUME=$2; shift 2 ;;
    -t|--timeout) TIMEOUT=$2; shift 2 ;;
    -f|--prompt-file) PROMPT_FILE=$2; shift 2 ;;
    -a|--add-dir) ADD_DIRS="$ADD_DIRS
$2"; shift 2 ;;
    -o|--out) OUT_DIR=$2; shift 2 ;;
    -h|--help) sed -n '2,15p' "$0"; exit 0 ;;
    --) shift; break ;;
    -*) die "unknown option: $1" ;;
    *) break ;;
  esac
done

command -v kimi >/dev/null 2>&1 || die "kimi not found on PATH"
[ -d "$CWD" ] || die "no such directory: $CWD"
case $MODE in
  ro) AGENT_FILE=$SKILL_DIR/agents/kimi-readonly.md ;;
  rw) AGENT_FILE=$SKILL_DIR/agents/kimi-worker.md ;;
  *) die "--mode must be ro or rw" ;;
esac

if [ -n "$PROMPT_FILE" ]; then
  if [ "$PROMPT_FILE" = - ]; then PROMPT=$(cat); else PROMPT=$(cat "$PROMPT_FILE") || die "cannot read $PROMPT_FILE"; fi
elif [ $# -gt 0 ]; then
  PROMPT=$*
else
  PROMPT=$(cat)
fi
[ -n "$PROMPT" ] || die "empty prompt"

mkdir -p "$OUT_DIR" || die "cannot create $OUT_DIR"
RUN_ID=$(date +%Y%m%d-%H%M%S)-$$
JSONL=$OUT_DIR/$RUN_ID.jsonl
ERRLOG=$OUT_DIR/$RUN_ID.stderr.log

# Build argv. --agent-file cannot be combined with --session: a resumed
# session keeps the profile it was started with.
set -- -p "$PROMPT" --output-format stream-json
if [ -n "$RESUME" ]; then
  set -- "$@" -S "$RESUME"
  MODE="resumed"
else
  set -- "$@" --agent-file "$AGENT_FILE"
fi
[ -n "$MODEL" ] && set -- "$@" -m "$MODEL"
if [ -n "$ADD_DIRS" ]; then
  OLDIFS=$IFS IFS='
'
  for d in $ADD_DIRS; do [ -n "$d" ] && set -- "$@" --add-dir "$d"; done
  IFS=$OLDIFS
fi

START=$(date +%s)
(cd "$CWD" && timeout -k 10 "$TIMEOUT" kimi "$@" </dev/null >"$JSONL" 2>"$ERRLOG")
STATUS=$?
END=$(date +%s)
ELAPSED=$((END - START))

python3 -I - "$JSONL" "$ERRLOG" "$STATUS" "$ELAPSED" "$MODE" "$CWD" <<'PY'
import json, re, sys
jsonl, errlog, status, elapsed, mode, cwd = sys.argv[1:7]
status = int(status)

events = []
with open(jsonl, encoding="utf-8", errors="replace") as f:
    for line in f:
        line = line.strip()
        if not line:
            continue
        try:
            events.append(json.loads(line))
        except ValueError:
            events.append({"role": "raw", "content": line})

def text_of(content):
    if isinstance(content, str):
        return content
    if isinstance(content, list):
        return "".join(p.get("text", "") for p in content if isinstance(p, dict))
    return ""

session = None
actions, final, last_tool_idx, other = [], [], -1, {}
for i, ev in enumerate(events):
    if ev.get("type") == "session.resume_hint":
        session = ev.get("session_id")
    if ev.get("role") == "tool":
        last_tool_idx = i
    for call in ev.get("tool_calls") or []:
        fn = call.get("function", {})
        name = fn.get("name", "?")
        try:
            args = json.loads(fn.get("arguments") or "{}")
        except ValueError:
            args = {}
        if name in ("Write", "Edit"):
            actions.append(f"{name:5} {args.get('path') or args.get('file_path') or '?'}")
        elif name == "Bash":
            cmd = " ".join(str(args.get("command", "")).split())
            actions.append(f"Bash  {cmd[:160]}")
        elif name == "Agent":
            actions.append(f"Agent {str(args.get('description') or args.get('prompt', ''))[:100]}")
        else:
            other[name] = other.get(name, 0) + 1
# Final answer = assistant text after the last tool result.
for ev in events[last_tool_idx + 1:]:
    if ev.get("role") == "assistant":
        t = text_of(ev.get("content")).strip()
        if t:
            final.append(t)

if session is None:
    try:
        m = re.findall(r"session_[0-9a-f-]+", open(errlog, encoding="utf-8", errors="replace").read())
        session = m[-1] if m else None
    except OSError:
        pass

state = {0: "ok", 124: "TIMEOUT", 137: "KILLED"}.get(status, f"FAILED (exit {status})")
print(f"=== KIMI {state} | mode={mode} | {elapsed}s | session={session or '?'} ===")
print(f"cwd: {cwd}")
print()
print("\n\n".join(final) if final else "(no final answer produced)")
print()
if actions:
    print(f"--- actions ({len(actions)}) ---")
    for a in actions[:60]:
        print(a)
    if len(actions) > 60:
        print(f"... {len(actions) - 60} more (see transcript)")
if other:
    print("--- other tool calls: " + ", ".join(f"{k} x{v}" for k, v in sorted(other.items())))
if status != 0:
    print("--- stderr tail ---")
    try:
        lines = open(errlog, encoding="utf-8", errors="replace").read().splitlines()
        print("\n".join(lines[-15:]))
    except OSError:
        pass
print(f"--- transcript: {jsonl}")
if session:
    print(f"--- follow up: kimi-run.sh -r {session} -C {cwd} \"...\"")
PY
exit $STATUS
