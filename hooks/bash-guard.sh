#!/usr/bin/env bash
#
# Session-wide PreToolUse guard for the Bash tool.
#
# The deny rules in settings.json are prefix matches, so they miss `rm -fr`,
# `/bin/rm -r -f`, `git push origin main --force` and `cd x && rm -rf y`. This hook
# is the second layer: bash-guard.py splits the command into segments and blocks
# recursive forced rm, force pushes, `git reset --hard`, `git clean -f`,
# working-tree-discarding `git checkout`, `git switch` and `git restore`, and
# `find -delete`, `find -exec rm` or a `find -exec` of any other blocked command,
# wherever their flags appear. It looks through `sudo`, `env`, `xargs`, `timeout`, `nice`
# and similar wrappers, `bash -c`, and here-strings and heredocs fed to a shell.
#
# Contract: reads the PreToolUse JSON payload on stdin. Exit 0 allows the call;
# exit 2 blocks it and returns stderr to the model.
#
# Fails open: without python3 or bash-guard.py, when the checker crashes (any status
# other than its deliberate 2), or when the payload or the command cannot be parsed,
# the call is allowed and the deny rules remain the only guard.
#
# This guards against accidents, not a hostile model: `eval`, variables, encoded
# strings, scripts written to disk, commands piped into a shell (`... | bash`), `env -S`
# and heredocs for non-shell commands, including substitutions inside their bodies, are
# not inspected.

set -uo pipefail

command -v python3 >/dev/null 2>&1 || exit 0

py="$(dirname "$0")/bash-guard.py"
[ -r "$py" ] || exit 0

python3 -I "$py"
rc=$?
[ "$rc" = 2 ] && exit 2
exit 0
