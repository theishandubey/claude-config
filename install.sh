#!/usr/bin/env bash
set -euo pipefail
dir="$(cd -P "$(dirname "${BASH_SOURCE[0]}")" && pwd -P)"
if ! command -v python3 >/dev/null 2>&1 || ! python3 -c 'import sys; sys.exit(sys.version_info < (3, 8))'; then
  echo "install.sh needs python3 3.8 or later" >&2
  exit 1
fi
exec python3 "$dir/scripts/install.py" "$@"
