#!/usr/bin/env bash
#
# PreToolUse guard for read-only advisor agents.
#
# Advisors need Write/Edit so they can persist their agent memory, but they must
# never touch project files. Tool-level bans can't express that: `disallowedTools:
# Write` removes the tool entirely (breaking memory), and settings.json permission
# rules are session-wide, so denying Write there would break every worker agent too.
#
# This hook is wired per-agent via `hooks:` frontmatter, so it constrains only the
# advisor that declares it: writes inside an agent-memory directory pass, everything
# else is blocked.
#
# Contract: reads the PreToolUse JSON payload on stdin. Exit 0 allows the call;
# exit 2 blocks it and returns stderr to the agent.

set -uo pipefail

payload="$(cat)"

target="$(printf '%s' "$payload" | python3 -c '
import json, sys
try:
    data = json.load(sys.stdin)
except Exception:
    sys.exit(0)
print(data.get("tool_input", {}).get("file_path", "") or "")
' 2>/dev/null)"

# No file path in the payload means this is not a file write - nothing to guard.
[ -z "$target" ] && exit 0

# Resolve relative paths against the invocation directory so the check can't be
# sidestepped with "./.claude/../../etc/passwd" style input.
case "$target" in
  /*) resolved="$target" ;;
  *)  resolved="$PWD/$target" ;;
esac
resolved="$(python3 -c 'import os,sys; print(os.path.normpath(sys.argv[1]))' "$resolved")"

case "$resolved" in
  */.claude/agent-memory/*|*/.claude/agent-memory-local/*|*/.claude/agent-memory/*/*)
    exit 0
    ;;
esac

cat >&2 <<EOF
BLOCKED: advisors are read-only and may only write agent memory.

Attempted: $resolved
Allowed:   <project>/.claude/agent-memory/<agent-name>/**

You are an advisor. Do not write project files - emit the content in your answer
with its target path and let the main session or a worker agent persist it.
EOF
exit 2
