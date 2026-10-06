#!/usr/bin/env bash
set -uo pipefail

REPO="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd -P)"
HOOK="$REPO/hooks/memory-write-guard.sh"
TMP="$(mktemp -d)"
trap 'rm -rf "$TMP"' EXIT
TMP="$(cd "$TMP" && pwd -P)"

command -v jq >/dev/null || { echo "guard: jq is required" >&2; exit 1; }

PROJ="$TMP/proj"
mkdir -p "$PROJ/plans" "$PROJ/advisor-plans" "$PROJ/src/plans" "$TMP/plain/plans"
git init -q "$PROJ"

NOJQ="$TMP/nojq-bin"
mkdir -p "$NOJQ"
ln -s "$(command -v cat)" "$NOJQ/cat"
ln -s "$(command -v git)" "$NOJQ/git"
ln -s "$(python3 -c 'import sys; print(sys.executable)')" "$NOJQ/python3"

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
run_raw "empty object payload" '{}' 2
run_raw "non-JSON payload" 'not json' 2
run_raw "empty payload" '' 2
run_raw "empty file_path" '{"tool_input":{"file_path":""}}' 2
run_raw_nojq "empty object payload without jq" '{}' 2
run_raw_nojq "non-JSON payload without jq" 'not json' 2
run_raw_nojq "memory path without jq" "{\"tool_input\":{\"file_path\":\"$REPO/.claude/agent-memory/x/a.md\"},\"cwd\":\"$REPO\"}" 0
run_raw_notools "memory path without jq or python3 fails closed" "{\"tool_input\":{\"file_path\":\"$REPO/.claude/agent-memory/x/a.md\"},\"cwd\":\"$REPO\"}" 2

if [ "$failures" -gt 0 ]; then
  exit 1
fi
echo "guard: $n cases ok"
