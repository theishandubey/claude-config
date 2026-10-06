#!/usr/bin/env bash
set -euo pipefail
cd "$(dirname "${BASH_SOURCE[0]}")/.."

scripts=(install.sh hooks/*.sh scripts/*.sh)

for f in "${scripts[@]}"; do
  bash -n "$f"
done

if command -v shellcheck >/dev/null 2>&1; then
  shellcheck -S warning "${scripts[@]}"
else
  echo "check: shellcheck not installed, skipping lint" >&2
fi

for f in claude/settings.json local.example/settings.json skills-lock.json; do
  jq -e . "$f" >/dev/null || { echo "check: $f is not valid JSON" >&2; exit 1; }
done

personal_keys='[.permissions.defaultMode, .skipDangerousModePermissionPrompt, .model, .theme, .enabledPlugins, .extraKnownMarketplaces] | map(select(. != null)) | length == 0'
jq -e "$personal_keys" claude/settings.json >/dev/null \
  || { echo "check: claude/settings.json carries a personal or unsafe key (defaultMode, model, theme, enabledPlugins, extraKnownMarketplaces, skipDangerousModePermissionPrompt)" >&2; exit 1; }

for h in hooks/*.sh; do
  [ -x "$h" ] || { echo "check: $h is not executable" >&2; exit 1; }
done

python3 -I scripts/check-agents.py
"$BASH" scripts/test-memory-write-guard.sh
"$BASH" scripts/test-install.sh
echo "check: ok"
