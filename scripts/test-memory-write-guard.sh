#!/usr/bin/env bash
set -uo pipefail

REPO="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd -P)"
HOOK="$REPO/hooks/memory-write-guard.sh"
TMP="$(mktemp -d)"
trap 'rm -rf "$TMP"' EXIT
TMP="$(cd "$TMP" && pwd -P)"

command -v jq >/dev/null || { echo "guard: jq is required" >&2; exit 1; }

unset CLAUDE_PROJECT_DIR

PROJ="$TMP/proj"
mkdir -p "$PROJ/plans" "$PROJ/advisor-plans" "$PROJ/src/plans" "$TMP/plain/plans"
git init -q "$PROJ"

LINKED="$TMP/linked"
mkdir -p "$LINKED/advisor-plans" "$TMP/elsewhere"
git init -q "$LINKED"
ln -s "$TMP/elsewhere" "$LINKED/plans"
ln -s "$TMP/elsewhere/real.md" "$PROJ/plans/003-link.md"

WS="$TMP/ws"
mkdir -p "$WS/plans" "$WS/advisor-plans" "$WS/sub/plans" "$WS/repo/plans"
git init -q "$WS/repo"
ln -s "$WS" "$TMP/ws-link"

MONO="$TMP/mono"
mkdir -p "$MONO/pkg/plans" "$MONO/pkg/subm"
git init -q "$MONO"
printf 'gitdir: ../../.git/modules/subm\n' > "$MONO/pkg/subm/.git"

LONE="$TMP/lone"
mkdir -p "$LONE/plans" "$LONE/notrepo/plans"

WSL="$TMP/wslinked"
mkdir -p "$WSL"
ln -s "$TMP/elsewhere" "$WSL/plans"

NOJQ="$TMP/nojq-bin"
mkdir -p "$NOJQ"
ln -s "$(command -v cat)" "$NOJQ/cat"
ln -s "$(command -v git)" "$NOJQ/git"
ln -s "$(python3 -c 'import sys; print(sys.executable)')" "$NOJQ/python3"

WSSYM="$TMP/wssym"
mkdir -p "$WSSYM/plans"
ln -s "$WS/repo" "$WSSYM/linkrepo"

WSFILE="$TMP/wsfile"
mkdir -p "$WSFILE/plans" "$WSFILE/child"
printf 'gitdir: elsewhere\n' > "$WSFILE/child/.git"

WSHID="$TMP/wshidden"
mkdir -p "$WSHID/plans"
git init -q "$WSHID/.r"

WSSP="$TMP/ws space"
mkdir -p "$WSSP/plans"
git init -q "$WSSP/my repo"

TOPREPO="$TMP/toprepo"
mkdir -p "$TOPREPO/plans"
git init -q "$TOPREPO"
git init -q "$TOPREPO/child"

NOGIT="$TMP/nogit-bin"
mkdir -p "$NOGIT"
ln -s "$(command -v cat)" "$NOGIT/cat"
ln -s "$(command -v jq)" "$NOGIT/jq"

NOTOOLS="$TMP/notools-bin"
mkdir -p "$NOTOOLS"
ln -s "$(command -v cat)" "$NOTOOLS/cat"

n=0
failures=0

check() {
  local label="$1" expected="$2" got="$3"
  n=$((n + 1))
  if [ "$got" != "$expected" ]; then
    echo "case $n ($label): expected $expected got $got"
    failures=$((failures + 1))
  fi
}

run() {
  local flags="$1" file_path="$2" cwd="$3" expected="$4" got
  # shellcheck disable=SC2086
  jq -n --arg f "$file_path" --arg c "$cwd" '{tool_name:"Write",tool_input:{file_path:$f},cwd:$c}' \
    | "$BASH" "$HOOK" $flags >/dev/null 2>&1
  got=$?
  check "${flags:-no flags} $file_path" "$expected" "$got"
}

run_proj() {
  local project="$1" flags="$2" file_path="$3" cwd="$4" expected="$5" got
  # shellcheck disable=SC2086
  jq -n --arg f "$file_path" --arg c "$cwd" '{tool_name:"Write",tool_input:{file_path:$f},cwd:$c}' \
    | CLAUDE_PROJECT_DIR="$project" "$BASH" "$HOOK" $flags >/dev/null 2>&1
  got=$?
  check "project ${project:-unset} ${flags:-no flags} $file_path" "$expected" "$got"
}

run_raw() {
  local label="$1" payload="$2" expected="$3" got
  printf '%s' "$payload" | "$BASH" "$HOOK" >/dev/null 2>&1
  got=$?
  check "$label" "$expected" "$got"
}

run_raw_nojq() {
  local label="$1" payload="$2" expected="$3" got
  printf '%s' "$payload" | env PATH="$NOJQ" /bin/bash "$HOOK" >/dev/null 2>&1
  got=$?
  check "$label" "$expected" "$got"
}

run_proj_nojq() {
  local label="$1" project="$2" payload="$3" expected="$4" got
  printf '%s' "$payload" | env PATH="$NOJQ" CLAUDE_PROJECT_DIR="$project" /bin/bash "$HOOK" --allow-plans >/dev/null 2>&1
  got=$?
  check "$label" "$expected" "$got"
}

run_proj_nogit() {
  local label="$1" project="$2" payload="$3" expected="$4" got
  printf '%s' "$payload" | env PATH="$NOGIT" CLAUDE_PROJECT_DIR="$project" /bin/bash "$HOOK" --allow-plans >/dev/null 2>&1
  got=$?
  check "$label" "$expected" "$got"
}

run_proj_baddir() {
  local label="$1" project="$2" payload="$3" expected="$4" got
  printf '%s' "$payload" | env GIT_DIR=/nonexistent CLAUDE_PROJECT_DIR="$project" "$BASH" "$HOOK" --allow-plans >/dev/null 2>&1
  got=$?
  check "$label" "$expected" "$got"
}

run_raw_notools() {
  local label="$1" payload="$2" expected="$3" got
  printf '%s' "$payload" | env PATH="$NOTOOLS" /bin/bash "$HOOK" >/dev/null 2>&1
  got=$?
  check "$label" "$expected" "$got"
}

run ""              "$REPO/.claude/agent-memory/architect/x.md"       "$REPO" 0
run ""              "$REPO/.claude/agent-memory-local/a/x.md"         "$REPO" 0
run ""              "$REPO/install.sh"                                "$REPO" 2
run ""              ".claude/agent-memory/../../install.sh"           "$REPO" 2
run ""              "$PROJ/plans/001-x.md"                            "$PROJ" 2
run "--allow-plans" "$PROJ/plans/001-x.md"                            "$PROJ" 0
run "--allow-plans" "plans/README.md"                                 "$PROJ" 0
run "--allow-plans" "$PROJ/advisor-plans/002-y.md"                    "$PROJ" 0
run "--allow-plans" "$PROJ/plans/notes.md"                            "$PROJ" 2
run "--allow-plans" "$PROJ/src/plans/001-x.md"                        "$PROJ" 2
run "--allow-plans" "$TMP/plain/plans/001-x.md"                       "$TMP/plain" 2
run ""              "$PROJ/plans/README.md"                           "$PROJ" 2
run ""              "$PROJ/advisor-plans/001-x.md"                    "$PROJ" 2
run ""              "$PROJ/advisor-plans/README.md"                   "$PROJ" 2
run "--allow-plans" "$PROJ/advisor-plans/README.md"                   "$PROJ" 0
run "--allow-plans" "$PROJ/advisor-plans/001-x.md"                    "$PROJ" 0
run "--allow-plans" "$PROJ/plans/1-x.md"                              "$PROJ" 2
run "--allow-plans" "$PROJ/plans/12-x.md"                             "$PROJ" 2
run "--allow-plans" "$PROJ/plans/123-x.md"                            "$PROJ" 0
run "--allow-plans" "$PROJ/plans/1000-x.md"                           "$PROJ" 0
run "--allow-plans" "$LINKED/plans/001-x.md"                          "$LINKED" 2
run "--allow-plans" "$LINKED/plans/README.md"                         "$LINKED" 2
run "--allow-plans" "$PROJ/plans/003-link.md"                         "$PROJ" 2
run "--allow-plans" "$LINKED/advisor-plans/001-x.md"                  "$LINKED" 0
run "--allow-plans" "$PROJ/.claude/agent-memory-local/a/x.md"         "$PROJ" 0
run_raw "empty object payload" '{}' 2
run_raw "non-JSON payload" 'not json' 2
run_raw "empty payload" '' 2
run_raw "empty file_path" '{"tool_input":{"file_path":""}}' 2
run_raw_nojq "empty object payload without jq" '{}' 2
run_raw_nojq "non-JSON payload without jq" 'not json' 2
run_raw_nojq "memory path without jq" "{\"tool_input\":{\"file_path\":\"$REPO/.claude/agent-memory/x/a.md\"},\"cwd\":\"$REPO\"}" 0
run_raw_notools "memory path without jq or python3 fails closed" "{\"tool_input\":{\"file_path\":\"$REPO/.claude/agent-memory/x/a.md\"},\"cwd\":\"$REPO\"}" 2
run_proj "$WS"      "--allow-plans" "$WS/plans/001-x.md"                  "$WS"      0
run_proj "$WS"      "--allow-plans" "plans/README.md"                     "$WS"      0
run_proj "$WS"      "--allow-plans" "$WS/advisor-plans/002-y.md"          "$WS"      0
run_proj "$WS"      "--allow-plans" "$WS/plans/notes.md"                  "$WS"      2
run_proj "$WS"      "--allow-plans" "$WS/plans/12-x.md"                   "$WS"      2
run_proj "$WS"      "--allow-plans" "$WS/plans/002-x.md"                  "$WS/repo" 0
run_proj "$WS"      "--allow-plans" "$WS/plans/README.md"                 "$WS/repo" 0
run_proj "$WS"      "--allow-plans" "$WS/repo/plans/002-x.md"             "$WS/repo" 0
run_proj "$WS"      "--allow-plans" "$WS/sub/plans/001-x.md"              "$WS/repo" 2
run_proj "$WS"      "--allow-plans" "$WS/sub/plans/001-x.md"              "$WS"      2
run_proj "$WS"      "--allow-plans" "$WS/repo/src/plans/001-x.md"         "$WS/repo" 2
run_proj "$TMP/ws-link" "--allow-plans" "$WS/plans/001-x.md"              "$WS"      0
run_proj ""         "--allow-plans" "$WS/plans/001-x.md"                  "$WS"      2
run_proj ""         "--allow-plans" "$WS/plans/001-x.md"                  "$WS/repo" 2
run_proj "$TMP/missing" "--allow-plans" "$WS/plans/001-x.md"              "$WS"      2
run_proj "$WSL"     "--allow-plans" "$WSL/plans/001-x.md"                 "$WSL"     2
run_proj "$WSL"     "--allow-plans" "$WSL/plans/README.md"                "$WSL"     2
run_proj "$WS"      "--allow-plans" "$PROJ/plans/003-link.md"             "$WS"      2
run_proj "$WS"      ""              "$WS/plans/001-x.md"                  "$WS"      2
run_proj "$WS"      ""              "$WS/plans/README.md"                 "$WS/repo" 2
run_proj "$WS"      "--allow-plans" "$WS/.claude/agent-memory/a/x.md"     "$WS"      0
run_proj "$MONO/pkg" "--allow-plans" "$MONO/pkg/plans/001-x.md"          "$MONO/pkg" 2
run_proj "$MONO/pkg" "--allow-plans" "$MONO/pkg/plans/001-x.md"          "$TMP"     2
run_proj "/"        "--allow-plans" "/plans/001-x.md"                     "$TMP"     2
run_proj "/"        "--allow-plans" "/plans/README.md"                    "/"        2
run_proj "$LONE"    "--allow-plans" "$LONE/plans/001-x.md"                "$LONE"    2
run_proj "$LONE"    "--allow-plans" "$LONE/plans/README.md"               "$TMP"     2
run_proj "$PROJ"    "--allow-plans" "$PROJ/plans/001-x.md"                "$TMP"     2
run_proj "$PROJ"    "--allow-plans" "$PROJ/advisor-plans/README.md"       "$TMP/plain" 2
run_proj "$WSSYM"   "--allow-plans" "$WSSYM/plans/001-x.md"               "$TMP"     0
run_proj "$WSFILE"  "--allow-plans" "$WSFILE/plans/001-x.md"              "$TMP"     0
run_proj "$WSHID"   "--allow-plans" "$WSHID/plans/001-x.md"               "$TMP"     2
run_proj "$WSSP"    "--allow-plans" "$WSSP/plans/001-x.md"                "$TMP"     0
run_proj "$TOPREPO" "--allow-plans" "$TOPREPO/plans/001-x.md"            "$TMP"     2
run_proj_nojq "project-root plan without jq" "$WS" "{\"tool_input\":{\"file_path\":\"$WS/plans/001-x.md\"},\"cwd\":\"$WS/repo\"}" 0
run_proj_nojq "project-root notes.md without jq" "$WS" "{\"tool_input\":{\"file_path\":\"$WS/plans/notes.md\"},\"cwd\":\"$WS/repo\"}" 2
run_proj_nojq "project-root plan without jq and project dir" "" "{\"tool_input\":{\"file_path\":\"$WS/plans/001-x.md\"},\"cwd\":\"$WS\"}" 2
run_proj_nogit "nested project dir without git" "$MONO/pkg" "{\"tool_input\":{\"file_path\":\"$MONO/pkg/plans/001-x.md\"},\"cwd\":\"$TMP\"}" 2
run_proj_nogit "workspace without git" "$WS" "{\"tool_input\":{\"file_path\":\"$WS/plans/001-x.md\"},\"cwd\":\"$TMP\"}" 0
run_proj_baddir "nested project dir with unusable GIT_DIR" "$MONO/pkg" "{\"tool_input\":{\"file_path\":\"$MONO/pkg/plans/001-x.md\"},\"cwd\":\"$TMP\"}" 2
run_proj_baddir "workspace with unusable GIT_DIR" "$WS" "{\"tool_input\":{\"file_path\":\"$WS/plans/001-x.md\"},\"cwd\":\"$TMP\"}" 0

if [ "$failures" -gt 0 ]; then
  exit 1
fi
echo "guard: $n cases ok"
