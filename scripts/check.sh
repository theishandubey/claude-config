#!/usr/bin/env bash
set -euo pipefail
cd "$(dirname "${BASH_SOURCE[0]}")/.."

for tool in jq python3; do
  command -v "$tool" >/dev/null 2>&1 || { echo "check: $tool is required" >&2; exit 1; }
done
echo "bash: $BASH_VERSION"

scripts=(install.sh hooks/*.sh scripts/*.sh)

for f in "${scripts[@]}"; do
  bash -n "$f"
done

if command -v shellcheck >/dev/null 2>&1; then
  shellcheck -S warning "${scripts[@]}"
else
  echo "check: shellcheck not installed, skipping lint" >&2
fi

for f in claude/settings.json skills-lock.json; do
  jq -e . "$f" >/dev/null || { echo "check: $f is not valid JSON" >&2; exit 1; }
done

forbidden="$(jq -r '[
  (select(.effortLevel != null) | "effortLevel"),
  (select(.modelSettings != null) | "modelSettings"),
  (select(.env.ANTHROPIC_SMALL_FAST_MODEL != null) | "env.ANTHROPIC_SMALL_FAST_MODEL"),
  (select(.env.CLAUDE_CODE_SUBAGENT_MODEL != null) | "env.CLAUDE_CODE_SUBAGENT_MODEL"),
  (select(.env.CLAUDE_CODE_PLUGIN_DIRS != null) | "env.CLAUDE_CODE_PLUGIN_DIRS")
] | .[]' claude/settings.json)"
if [ -n "$forbidden" ]; then
  echo "check: claude/settings.json must not set: $(printf '%s' "$forbidden" | tr '\n' ' ')" >&2
  exit 1
fi

unpinned="$(jq -r '
  ("fable", "opus", "sonnet", "haiku") as $family
  | ("ANTHROPIC_DEFAULT_" + ($family | ascii_upcase) + "_MODEL") as $key
  | (.env[$key] // null) as $value
  | select(($value | type) != "string" or ($value | test("^claude-" + $family + "-5(-[0-9]{1,2})?(-[0-9]{8})?\\z") | not))
  | "env.\($key)"
' claude/settings.json)"
if [ -n "$unpinned" ]; then
  echo "check: claude/settings.json must pin each model alias to a 5-series model of its own family: $(printf '%s' "$unpinned" | tr '\n' ' ')" >&2
  exit 1
fi

for h in hooks/*.sh; do
  [ -x "$h" ] || { echo "check: $h is not executable" >&2; exit 1; }
done

tracked="$(git ls-files -- ':(glob,icase)**/CLAUDE.md' ':(glob,icase)**/CLAUDE.local.md' ':(glob,icase)**/AGENTS.md')" \
  || { echo "check: not a git checkout, cannot verify tracked files" >&2; exit 1; }
while IFS= read -r f; do
  [ -n "$f" ] || continue
  case "$(printf '%s' "$f" | tr '[:upper:]' '[:lower:]')" in
    claude/claude.md|claude/agents.md) ;;
    *) echo "check: $f must not be tracked" >&2; exit 1 ;;
  esac
done <<< "$tracked"

for f in CLAUDE.md CLAUDE.local.md AGENTS.md CONTRIBUTING.md SECURITY.md .claude/CLAUDE.md; do
  if [ -e "$f" ] || [ -L "$f" ]; then echo "check: $f must not exist" >&2; exit 1; fi
done

python3 -I scripts/check-agents.py
"$BASH" scripts/test-memory-write-guard.sh
"$BASH" scripts/test-bash-guard.sh
"$BASH" scripts/test-install.sh
echo "check: ok"
