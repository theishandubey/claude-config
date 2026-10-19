#!/usr/bin/env bash
set -euo pipefail
cd "$(dirname "${BASH_SOURCE[0]}")/.."
python3 -m py_compile hooks/*.py scripts/*.py tests/*.py
if command -v shellcheck >/dev/null 2>&1; then
  shellcheck install.sh scripts/check.sh
else
  echo "shellcheck not installed; skipping shell lint" >&2
fi
python3 -W error::ResourceWarning -m unittest discover -s tests "$@"
