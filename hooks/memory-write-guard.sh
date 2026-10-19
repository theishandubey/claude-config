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
# Planning advisors pass `--allow-plans`, which also lets through plan files in
# `plans/` and `advisor-plans/`, the handoff-plan location of the `improve` skill.
# These directories must sit directly under the root of the git repository the
# session runs in, or directly under the session's project root (`CLAUDE_PROJECT_DIR`)
# when that root is a multi-repo workspace: a folder that is not inside any
# repository (no `.git` entry in it or any ancestor, checked without running git)
# and has a direct child with a `.git` entry (a directory or a file, so
# submodules and linked worktrees count, and so does a child that is a symlink
# to a repository).
# A project root of `/`, a project root that is itself a repository or inside one
# (including a workspace nested in a repository), and a folder without a child
# repository are never trusted as the project root.
# A plan file is `README.md` or `<digits>-*.md` with three or more digits, so
# `001-x.md` and `1000-x.md` pass and `12-x.md` does not; other markdown files
# in those directories are blocked, but an unrelated `plans/README.md` is
# protected by the prompt only.
# The `plans/` directory and the plan file themselves must not be symlinks;
# hard links and symlinks above the repository or project root are not detected.
# Nested `plans/` directories elsewhere in the tree are project code and stay blocked.
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
    sys.exit(2)
print(data.get("tool_input", {}).get("file_path", "") or "")
' 2>/dev/null)"
  cwd="$(printf '%s' "$payload" | python3 -c '
import json, sys
try:
    data = json.load(sys.stdin)
except Exception:
    sys.exit(2)
print(data.get("cwd", "") or "")
' 2>/dev/null)"
fi
cwd="${cwd:-$PWD}"

# Write and Edit always carry a file path, so a payload without one is malformed: fail closed.
if [ -z "$target" ]; then
  echo "BLOCKED: Write/Edit payload has no tool_input.file_path; refusing to guess." >&2
  exit 2
fi

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

realdir() {
  CDPATH='' cd -P -- "$1" 2>/dev/null && pwd -P
}

if [ "$allow_plans" -eq 1 ]; then
  plans_dir="${resolved%/*}"
  repo_dir="${plans_dir%/*}"
  name="${resolved##*/}"
  plan_name_re='^[0-9]{3,}-.+\.md$'
  case "${plans_dir##*/}" in
    plans|advisor-plans)
      if { [ "$name" = "README.md" ] || [[ "$name" =~ $plan_name_re ]]; } \
        && [ ! -L "$plans_dir" ] && [ ! -L "$resolved" ]; then
        repo_real="$(realdir "${repo_dir:-/}")"
        if [ -n "$repo_real" ] && [ "$repo_real" != "/" ]; then
          root="$(git -C "$cwd" rev-parse --show-toplevel 2>/dev/null)"
          root_real=""
          [ -z "$root" ] || root_real="$(realdir "$root")"
          [ "$repo_real" != "$root_real" ] || exit 0
          project_real=""
          [ -z "${CLAUDE_PROJECT_DIR:-}" ] || project_real="$(realdir "$CLAUDE_PROJECT_DIR")"
          if [ "$repo_real" = "$project_real" ]; then
            ancestor="$project_real"
            while [ ! -e "$ancestor/.git" ] && [ "$ancestor" != "/" ]; do
              ancestor="${ancestor%/*}"
              ancestor="${ancestor:-/}"
            done
            if [ ! -e "$ancestor/.git" ]; then
              set +o noglob
              for child in "$project_real"/*/; do
                if [ -e "${child}.git" ]; then
                  exit 0
                fi
              done
              set -o noglob
            fi
          fi
        fi
      fi
      ;;
  esac
  allowed="<project>/.claude/agent-memory{,-local}/<agent-name>/**, <repo root or project root>/plans/{NNN-*.md,README.md}, <repo root or project root>/advisor-plans/{NNN-*.md,README.md}"
else
  allowed="<project>/.claude/agent-memory{,-local}/<agent-name>/**"
fi

cat >&2 <<EOF
BLOCKED: advisors are read-only outside their allowed paths.

Attempted: $resolved
Allowed:   $allowed

You are an advisor. Do not write project files - emit the content in your answer
with its target path and let the main session or a worker agent persist it.
EOF
exit 2
