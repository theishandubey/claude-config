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
# Planning advisors pass `--allow-plans`, which also lets through markdown files
# directly inside `plans/` or `advisor-plans/` at the root of the git repository
# the session runs in - the handoff-plan location of the `improve` skill. Only
# `NNN-*.md` and `README.md` pass, which keeps most user docs out of reach; an
# unrelated `plans/README.md` is protected by the prompt only. Nested
# `plans/` directories elsewhere in the tree are project code and stay blocked.
#
# Contract: reads the PreToolUse JSON payload on stdin. Exit 0 allows the call;
# exit 2 blocks it and returns stderr to the agent.
#
# This runs on every Write/Edit an advisor makes, so it stays on the fast path:
# `jq` when available, `python3` only as a fallback for machines without it.

set -uo pipefail
# Segment splitting below is unquoted and must not glob-expand against the working directory.
set -o noglob

allow_plans=0
[ "${1:-}" = "--allow-plans" ] && allow_plans=1

payload="$(cat)"

if command -v jq >/dev/null 2>&1; then
  target="$(printf '%s' "$payload" | jq -r '.tool_input.file_path // empty' 2>/dev/null)"
  cwd="$(printf '%s' "$payload" | jq -r '.cwd // empty' 2>/dev/null)"
else
  target="$(printf '%s' "$payload" | python3 -c '
import json, sys
try:
    data = json.load(sys.stdin)
except Exception:
    sys.exit(0)
print(data.get("tool_input", {}).get("file_path", "") or "")
' 2>/dev/null)"
  cwd="$(printf '%s' "$payload" | python3 -c '
import json, sys
try:
    data = json.load(sys.stdin)
except Exception:
    sys.exit(0)
print(data.get("cwd", "") or "")
' 2>/dev/null)"
fi
cwd="${cwd:-$PWD}"

# No file path in the payload means this is not a file write - nothing to guard.
[ -z "$target" ] && exit 0

# Resolve relative paths against the session's working directory so the check can't be
# sidestepped with "./.claude/../../etc/passwd" style input.
case "$target" in
  /*) resolved="$target" ;;
  *)  resolved="$cwd/$target" ;;
esac

# Collapse "." and ".." lexically, matching python's os.path.normpath. Like
# normpath, this deliberately does not resolve symlinks.
normalized=""
depth=0
saved_ifs="$IFS"
IFS='/'
for segment in $resolved; do
  case "$segment" in
    ''|.)
      ;;
    ..)
      if [ "$depth" -gt 0 ]; then
        normalized="${normalized%/*}"
        depth=$((depth - 1))
      fi
      ;;
    *)
      normalized="$normalized/$segment"
      depth=$((depth + 1))
      ;;
  esac
done
IFS="$saved_ifs"
resolved="${normalized:-/}"

case "$resolved" in
  */.claude/agent-memory/*|*/.claude/agent-memory-local/*)
    exit 0
    ;;
esac

if [ "$allow_plans" -eq 1 ]; then
  plans_dir="${resolved%/*}"
  repo_dir="${plans_dir%/*}"
  name="${resolved##*/}"
  plan_name_re='^[0-9]{3,}-.+\.md$'
  case "${plans_dir##*/}" in
    plans|advisor-plans)
      if [ "$name" = "README.md" ] || [[ "$name" =~ $plan_name_re ]]; then
        root="$(git -C "$cwd" rev-parse --show-toplevel 2>/dev/null)"
        root_real="$(CDPATH='' cd -P -- "$root" 2>/dev/null && pwd -P)"
        repo_real="$(CDPATH='' cd -P -- "${repo_dir:-/}" 2>/dev/null && pwd -P)"
        if [ -n "$root" ] && [ -n "$root_real" ] && [ "$repo_real" = "$root_real" ] \
          && [ ! -L "$plans_dir" ] && [ ! -L "$resolved" ]; then
          exit 0
        fi
      fi
      ;;
  esac
  allowed="<project>/.claude/agent-memory/<agent-name>/**, <repo root>/plans/{NNN-*.md,README.md}, <repo root>/advisor-plans/{NNN-*.md,README.md}"
else
  allowed="<project>/.claude/agent-memory/<agent-name>/**"
fi

cat >&2 <<EOF
BLOCKED: advisors are read-only outside their allowed paths.

Attempted: $resolved
Allowed:   $allowed

You are an advisor. Do not write project files - emit the content in your answer
with its target path and let the main session or a worker agent persist it.
EOF
exit 2
