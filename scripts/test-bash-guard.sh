#!/usr/bin/env bash
set -uo pipefail

REPO="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd -P)"
HOOK="$REPO/hooks/bash-guard.sh"
TMP="$(mktemp -d)"
trap 'rm -rf "$TMP"' EXIT

command -v jq >/dev/null || { echo "bash-guard: jq is required" >&2; exit 1; }

NOPYTHON="$TMP/nopython-bin"
mkdir -p "$NOPYTHON"
ln -s "$(command -v cat)" "$NOPYTHON/cat"
ln -s "$(command -v dirname)" "$NOPYTHON/dirname"

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
  local command="$1" expected="$2" got
  jq -n --arg c "$command" '{tool_name:"Bash",tool_input:{command:$c}}' \
    | "$BASH" "$HOOK" >/dev/null 2>&1
  got=$?
  check "$command" "$expected" "$got"
}

run_raw() {
  local label="$1" payload="$2" expected="$3" got
  printf '%s' "$payload" | "$BASH" "$HOOK" >/dev/null 2>&1
  got=$?
  check "$label" "$expected" "$got"
}

run_nopython() {
  local label="$1" payload="$2" expected="$3" got
  printf '%s' "$payload" | env PATH="$NOPYTHON" /bin/bash "$HOOK" >/dev/null 2>&1
  got=$?
  check "$label" "$expected" "$got"
}

blocked=(
  'rm -rf x'
  'rm -fr x'
  'rm -r -f x'
  'rm -Rf x'
  'rm --recursive --force x'
  'rm -rfv x'
  '/bin/rm -Rf x'
  '\rm -rf x'
  'sudo rm -rf /tmp/x'
  'sudo -u root rm -rf /tmp/x'
  'env FOO=1 rm -rf x'
  'FOO=1 rm -rf x'
  'nohup rm -rf x'
  'time rm -rf x'
  'cd a && rm -rf b'
  'true; rm -rf b'
  'false || rm -rf b'
  'echo a | rm -rf b'
  'sleep 1 & rm -rf b'
  $'echo a\nrm -rf b'
  '(cd a && rm -rf b)'
  'if true; then rm -rf b; fi'
  'echo $(rm -rf b)'
  'echo "$(rm -rf b)"'
  'echo `rm -rf b`'
  'bash -c "rm -rf x"'
  'sh -c '"'"'cd a && rm -rf b'"'"
  'zsh -lc "git reset --hard"'
  'rm -rf x 2>&1'
  'git push --force'
  'git push origin main --force'
  'git push -f origin main'
  'git push -uf origin main'
  'git push --force-with-lease'
  'git push --force-with-lease=main origin main'
  'git push --force-if-includes'
  'git push origin +main'
  'git push origin +HEAD:main'
  'git -C repo push --force'
  'git -c user.name=x push --force'
  'git --git-dir /r/.git --no-pager push -f'
  '/usr/bin/git push --force'
  'git reset --hard'
  'git reset --hard HEAD~1'
  'git -C repo reset --hard'
  'git clean -fdx'
  'git clean -f'
  'git clean --force'
  'git clean -xf'
  'git checkout -- .'
  'git checkout -- src/a.py'
  'git checkout main -- src/a.py'
  'git checkout .'
  'git restore .'
  'git restore src/a.py'
  'git restore --worktree a'
  'git restore --staged --worktree a'
  'git restore -SW a'
  'find . -delete'
  'find . -name '"'"'*.tmp'"'"' -exec rm {} +'
  'find . -exec /bin/rm -f {} \;'
  'find . -execdir rm {} +'
  'find . -ok rm {} \;'
  'git commit -m "x" && git push --force'
  'bash -o pipefail -c '"'"'rm -rf x'"'"
  'sh -o errexit -c '"'"'rm -rf x'"'"
  'bash +o history -c '"'"'rm -rf x'"'"
  'bash -O extglob -c '"'"'rm -rf x'"'"
  'bash +O extglob -c '"'"'rm -rf x'"'"
  'bash --rcfile rc -c '"'"'rm -rf x'"'"
  'bash --init-file rc -c '"'"'rm -rf x'"'"
  'bash --norc -c '"'"'rm -rf x'"'"
  'bash +x -c '"'"'rm -rf x'"'"
  'bash -ec '"'"'rm -rf x'"'"
  'bash -xc '"'"'rm -rf x'"'"
  'bash -eo pipefail -c '"'"'rm -rf x'"'"
  $'echo $((1<<3))\nrm -rf x'
  $'echo $(( 1 << 3 ))\nrm -rf x'
  $'echo "$((1<<3))"\nrm -rf x'
  $'(( x <<= 1 ))\nrm -rf x'
  $'((x<<=1)); rm -rf x'
  $'if (( x << 1 )); then rm -rf x; fi'
  'git clean -xdf -e -n'
  'git clean -fd --exclude=keep'
  'git clean -f --exclude -n'
  'git clean -xdfe pattern'
  'git clean -xdf -e keep'
  'git restore -s HEAD~1 a'
  'git restore --staged --worktree -s HEAD a'
  'find . -name '"'"'*.o'"'"' | xargs rm -rf'
  'xargs -0 rm -rf < list'
  'xargs -n 1 rm -rf'
  'xargs -I{} rm -rf {}'
  'xargs -I {} rm -rf {}'
  'xargs -0n1 rm -rf'
  'xargs --max-args 1 rm -rf'
  'xargs --max-args=1 rm -rf'
  'timeout 10 rm -rf x'
  'timeout -s KILL 10 rm -rf x'
  'timeout --kill-after=5 10 rm -rf x'
  'nice -n 5 rm -rf x'
  'nice rm -rf x'
  'ionice -c 3 rm -rf x'
  'ionice -c3 -n 7 rm -rf x'
  'doas -u root rm -rf x'
  'time -p rm -rf x'
  'exec -a foo rm -rf x'
  'exec -c rm -rf x'
  'exec -l rm -rf x'
  'sudo timeout 5 nice -n 1 xargs rm -rf'
  'bash <<< '"'"'rm -rf x'"'"
  'bash <<<'"'"'rm -rf x'"'"
  'sh <<< "git push --force"'
  $'bash <<EOF\nrm -rf x\nEOF'
  $'bash <<-EOF\n\trm -rf x\n\tEOF'
  $'sh <<\'EOF\'\ncd a\nrm -rf x\nEOF'
  'git checkout -f'
  'git checkout --force main'
  'git checkout main -f'
  'git checkout -fb feature'
  'git switch -f main'
  'git switch --force main'
  'git switch --discard-changes main'
  'git switch -fc feature'
  $'cat <<EOF\n  EOF\nEOF\nrm -rf x'
  'rm -rf x; echo "unterminated'
  $'git reset --hard\necho \'unterminated'
  'git clean -e -h -f'
  'git push -o -h --force'
  'git restore -s -h file'
  'git restore --source -h file'
  'git clean -fh'
  'git push --force -- --dry-run'
  'git clean -f -- -h'
  'sudo --user root rm -rf x'
  'sudo --group wheel rm -rf x'
  'sudo --prompt p rm -rf x'
  'sudo --chdir /tmp rm -rf x'
  'sudo --user=root rm -rf x'
  'env --unset FOO rm -rf x'
  'env --chdir d rm -rf x'
  'env --unset=FOO rm -rf x'
  'env --chdir=d rm -rf x'
  'git clean -f -- --dry-run'
  'git push --mirror'
  'git push --mirror origin'
  'git checkout --pathspec-from-file=list'
  'git checkout --pathspec-from-file list'
  'git checkout main --pathspec-from-file=list'
  'find . -exec sh -c '"'"'rm -rf {}'"'"' \;'
  'find . -exec bash -c "git reset --hard" {} +'
  'find . -execdir sudo rm {} \;'
  'find . -exec git clean -fd {} \;'
  'find . -exec ls {} \; -exec rm {} +'
  'bash -s arg <<< '"'"'rm -rf x'"'"
  'bash - <<< '"'"'rm -rf x'"'"
  'bash -s <<< '"'"'rm -rf x'"'"
  'bash -es arg <<< '"'"'rm -rf x'"'"
  'bash -s -- arg <<< '"'"'rm -rf x'"'"
  'bash -- - <<< '"'"'rm -rf x'"'"
  $'bash -s arg <<EOF\nrm -rf x\nEOF'
  $'bash - <<EOF\nrm -rf x\nEOF'
  $'bash -s a b c <<EOF\ncd a\nrm -rf x\nEOF'
)

allowed=(
  'rm file'
  'rm -r dir'
  'rm -f file'
  'rm -f -- -r'
  'rm -f -- a -r'
  'ls -rf'
  'git push'
  'git push origin main'
  'git push -u origin feature'
  'git push origin --delete feature'
  'git reset HEAD~1'
  'git reset --soft HEAD~1'
  'git reset --mixed HEAD~1'
  'git clean -n'
  'git clean -fdn'
  'git clean --dry-run -f'
  'git checkout main'
  'git checkout -b feature'
  'git checkout --'
  'git restore --staged a.py'
  'git restore -S a.py'
  'find . -name '"'"'*.py'"'"
  'find . -exec grep x {} +'
  'echo "rm -rf /"'
  "echo 'git push --force'"
  'git commit -m "git reset --hard"'
  $'git commit -m "$(cat <<\'EOF\'\nDon\'t run git reset --hard or rm -rf\nEOF\n)"'
  'grep -rf patterns.txt .'
  'cat file | grep "rm -rf"'
  'cmd 2>&1 | tee out.log'
  'echo oops # rm -rf x'
  'echo "oops'
  "echo 'oops"
  'bash -c "echo hi"'
  'bash script.sh'
  'git status && git diff'
  ''
  'bash -o pipefail script.sh'
  'bash -o pipefail -c '"'"'echo hi'"'"
  'bash -ec '"'"'echo hi'"'"
  'bash +x script.sh'
  'bash --rcfile rc script.sh'
  $'echo $((1<<3))\necho ok'
  'echo $((1<<3))'
  'echo "$((1<<3))"'
  'x=$(( 1 << 3 )); echo $x'
  '(( x <<= 1 ))'
  'git clean -nxd -e keep'
  'git restore --staged -s HEAD~1 a'
  'git restore --staged -s -W a'
  'git restore -S --source=HEAD~1 a'
  'git push -o ci.skip origin main'
  'git push --push-option=ci.skip origin main'
  'git push -o -f origin main'
  'git push --repo origin main'
  'xargs grep foo'
  'xargs -0 -n 1 grep foo'
  'ls | xargs wc -l'
  'timeout 10 sleep 1'
  'nice -n 5 make'
  'time -p make'
  'exec -a foo server'
  'bash <<< '"'"'echo hi'"'"
  $'bash <<EOF\necho hi\nEOF'
  $'cat <<\'EOF\'\nrm -rf x\nEOF'
  $'cat <<EOF\nrm -rf x\nEOF'
  $'cat <<EOF\n  EOF\nrm -rf x\nEOF'
  $'cat <<-EOF\n\tEOF\nEOF'
  $'cat <<EOF\nEOF \nrm -rf x\nEOF'
  'bash script.sh <<< '"'"'rm -rf x'"'"
  'git checkout feature'
  'git checkout -b feature'
  'git switch feature'
  'git switch -c feature'
  'git restore -h'
  'git restore --help'
  'git clean -f -h'
  'git push --force --help'
  'git checkout -f --help'
  'git push --force --dry-run'
  'git push --dry-run --force origin main'
  'git push -n --force'
  'git push -nf'
  'git push -fn origin main'
  'git push -n origin +main'
  'git push --force-with-lease --dry-run'
  'bash script.sh <<< '"'"'rm -rf x'"'"
  $'bash script.sh <<EOF\nrm -rf x\nEOF'
  'bash -s arg <<< '"'"'echo hi'"'"
  'bash - <<< '"'"'echo hi'"'"
  $'bash -s arg <<EOF\necho hi\nEOF'
  $'bash - <<EOF\necho hi\nEOF'
  $'bash script.sh arg <<EOF\nrm -rf x\nEOF'
  'sudo --user root ls'
  'env --unset FOO ls'
  'env --chdir d make'
  'git reset -- --hard'
  'git clean -f --dry-run'
  'git push --mirror --dry-run'
  'git push -n --mirror'
  'find . -exec sh -c '"'"'echo {}'"'"' \;'
  'find . -exec ls {} \; -exec grep x {} +'
  'find . -execdir git status \;'
  $'git commit -m "$(cat <<\'EOF\'\nx\nEOF\n)"'
  'git restore -h file'
  'git clean -n -f -h'
)

for c in "${blocked[@]}"; do run "$c" 2; done
for c in "${allowed[@]}"; do run "$c" 0; done

run_raw "invalid JSON payload" 'not json' 0
run_raw "empty payload" '' 0
run_raw "empty object payload" '{}' 0
run_raw "payload with no command" '{"tool_name":"Bash","tool_input":{}}' 0
run_raw "non-string command" '{"tool_name":"Bash","tool_input":{"command":["rm","-rf","x"]}}' 0
run_raw "non-object payload" '[1,2]' 0
run_nopython "rm -rf without python3 fails open" '{"tool_name":"Bash","tool_input":{"command":"rm -rf x"}}' 0

run_raw "heredoc terminated by a tab-indented <<- delimiter" "$(jq -n --arg c $'cat <<-EOF\n\tEOF\nrm -rf x' '{tool_name:"Bash",tool_input:{command:$c}}')" 2

mkdir -p "$TMP/orphan"
cp "$HOOK" "$TMP/orphan/bash-guard.sh"
printf '%s' '{"tool_name":"Bash","tool_input":{"command":"rm -rf x"}}' | "$BASH" "$TMP/orphan/bash-guard.sh" >/dev/null 2>&1
check "missing bash-guard.py fails open" 0 "$?"

mkdir -p "$TMP/fakepy"
printf '#!/bin/sh\ncat >/dev/null\nexit 1\n' >"$TMP/fakepy/python3"
chmod +x "$TMP/fakepy/python3"
printf '%s' '{"tool_name":"Bash","tool_input":{"command":"rm -rf x"}}' | env PATH="$TMP/fakepy:$PATH" "$BASH" "$HOOK" >/dev/null 2>&1
check "checker crash (status 1) fails open" 0 "$?"
printf '#!/bin/sh\ncat >/dev/null\nexit 2\n' >"$TMP/fakepy/python3"
printf '%s' '{"tool_name":"Bash","tool_input":{"command":"ls"}}' | env PATH="$TMP/fakepy:$PATH" "$BASH" "$HOOK" >/dev/null 2>&1
check "checker status 2 blocks" 2 "$?"

settings_command="$(jq -r '.hooks.PreToolUse[] | select(.matcher == "Bash") | .hooks[0].command' "$REPO/claude/settings.json")"
payload='{"tool_name":"Bash","tool_input":{"command":"rm -rf x"}}'
mkdir -p "$TMP/home-empty" "$TMP/home-linked/.claude"
printf '%s' "$payload" | env HOME="$TMP/home-empty" sh -c "$settings_command" >/dev/null 2>&1
check "settings command is a no-op when the hooks link is gone" 0 "$?"
ln -s "$REPO/hooks" "$TMP/home-linked/.claude/hooks"
printf '%s' "$payload" | env HOME="$TMP/home-linked" sh -c "$settings_command" >/dev/null 2>&1
check "settings command runs the linked guard" 2 "$?"

stderr="$(jq -n '{tool_name:"Bash",tool_input:{command:"cd a && git push origin main --force"}}' | "$BASH" "$HOOK" 2>&1 >/dev/null)"
n=$((n + 1))
case "$stderr" in
  *"git push"*"--force"*) ;;
  *) echo "case $n (stderr names the segment): got: $stderr"; failures=$((failures + 1)) ;;
esac
n=$((n + 1))
if [ "$(printf '%s\n' "$stderr" | wc -l | tr -d ' ')" != 1 ]; then
  echo "case $n (stderr is one line): got: $stderr"
  failures=$((failures + 1))
fi

if [ "$failures" -gt 0 ]; then
  exit 1
fi
echo "bash-guard: $n cases ok"
