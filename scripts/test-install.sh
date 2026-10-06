#!/usr/bin/env bash
set -uo pipefail

REPO="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd -P)"

unset CLAUDE_CONFIG_NO_OVERLAY NO_COLOR CLAUDE_CONFIG_LOCAL_DIR NPX_FAIL_SOURCE

command -v jq >/dev/null || { echo "install: jq is required" >&2; exit 1; }
command -v python3 >/dev/null || { echo "install: python3 is required" >&2; exit 1; }

REAL_HOME="$(cd "$(eval echo "~$(id -un)")" 2>/dev/null && pwd -P)"
[ -n "$REAL_HOME" ] || { echo "install: cannot resolve the real home directory" >&2; exit 1; }

WORK="$(mktemp -d "${TMPDIR:-/tmp}/agent-config-test.XXXXXX")"
WORK="$(cd "$WORK" && pwd -P)"
trap 'rm -rf "$WORK"' EXIT

SB_N=0
FAILURES=0
CHECKS=0
SCENARIO=""
OUT=""
RC=0

fail() {
  echo "FAIL [$SCENARIO]: $*"
  FAILURES=$((FAILURES + 1))
}

scenario() {
  SCENARIO="$1"
  echo "-- $SCENARIO"
}

assert_eq() {
  CHECKS=$((CHECKS + 1))
  if [ "$2" != "$3" ]; then fail "$1: expected '$2' got '$3'"; fi
}

assert_match() {
  CHECKS=$((CHECKS + 1))
  if ! printf '%s\n' "$3" | grep -Eq -- "$2"; then
    fail "$1: output does not match /$2/"
    printf '%s\n' "$3" | sed 's/^/    | /'
  fi
}

assert_nomatch() {
  CHECKS=$((CHECKS + 1))
  if printf '%s\n' "$3" | grep -Eq -- "$2"; then
    fail "$1: output unexpectedly matches /$2/"
    printf '%s\n' "$3" | sed 's/^/    | /'
  fi
}

assert_true() {
  local desc="$1"
  shift
  CHECKS=$((CHECKS + 1))
  if ! "$@"; then fail "$desc"; fi
}

assert_false() {
  local desc="$1"
  shift
  CHECKS=$((CHECKS + 1))
  if "$@"; then fail "$desc"; fi
}

count_entries() {
  find "$1" -maxdepth 1 -name "$2" 2>/dev/null | wc -l | tr -d ' '
}

tree_sum() {
  (
    cd "$1" || exit 1
    find . -path ./.git -prune -o -print | LC_ALL=C sort | while IFS= read -r p; do
      if [ -L "$p" ]; then
        printf 'L %s %s\n' "$p" "$(readlink "$p")"
      elif [ -d "$p" ]; then
        printf 'D %s\n' "$p"
      else
        printf 'F %s %s\n' "$p" "$(cksum < "$p")"
      fi
    done | cksum
  )
}

mark_time() {
  : > "$SB/marker"
  sleep 1
}

assert_untouched() {
  local touched
  touched="$(find "$SB_HOME" "$SB_LOCAL" "$SB_REPO" -newer "$SB/marker" 2>/dev/null | LC_ALL=C sort)"
  assert_eq "$1: no file or directory was written" "" "$touched"
}

state_sum() {
  printf '%s %s %s' "$(tree_sum "$SB_HOME")" "$(tree_sum "$SB_LOCAL")" "$(tree_sum "$SB_REPO")"
}

new_sandbox() {
  SB_N=$((SB_N + 1))
  SB="$WORK/sb$SB_N"
  SB_HOME="$SB/home"
  SB_LOCAL="$SB/local"
  SB_REPO="$SB/repo"
  SB_STUB="$SB/stub"
  SB_NPX_LOG="$SB/npx.log"
  mkdir -p "$SB_HOME" "$SB_LOCAL" "$SB_REPO" "$SB_STUB"
  local item
  for item in install.sh claude agents hooks tmux skills skills-lock.json; do
    cp -R "$REPO/$item" "$SB_REPO/$item"
  done
  : > "$SB_NPX_LOG"
  cat > "$SB_STUB/npx" <<'STUB'
#!/usr/bin/env bash
printf '%s\n' "$*" >> "$NPX_LOG"
if [ -n "${NPX_FAIL_SOURCE:-}" ]; then
  case " $* " in *" $NPX_FAIL_SOURCE "*) exit 1 ;; esac
fi
exit 0
STUB
  chmod +x "$SB_STUB/npx"
}

assert_sandboxed() {
  local home local_dir
  home="$(cd "$SB_HOME" && pwd -P)" || { echo "install: sandbox home missing" >&2; exit 1; }
  local_dir="$(cd "$SB_LOCAL" && pwd -P)" || { echo "install: sandbox local dir missing" >&2; exit 1; }
  if [ "$home" = "$REAL_HOME" ] || [ "${home#"$WORK"/}" = "$home" ] \
    || [ "$local_dir" = "$REAL_HOME" ] || [ "${local_dir#"$WORK"/}" = "$local_dir" ]; then
    echo "install: refusing to run install.sh outside the throwaway sandbox (HOME=$home)" >&2
    exit 1
  fi
}

ienv() {
  assert_sandboxed
  env HOME="$SB_HOME" CLAUDE_CONFIG_LOCAL_DIR="$SB_LOCAL" NPX_LOG="$SB_NPX_LOG" \
    PATH="$SB_STUB:$PATH" "$@"
}

inst() {
  ienv "$BASH" "$SB_REPO/install.sh" "$@"
}

capture() {
  assert_sandboxed
  OUT="$(inst "$@" 2>&1 < /dev/null)"
  RC=$?
}

DECLINE_PY='
import os, pty, signal, sys
pid, fd = pty.fork()
if pid == 0:
    os.execvp(sys.argv[1], sys.argv[1:])
buf = b""


def on_timeout(signum, frame):
    os.kill(pid, signal.SIGKILL)
    os.waitpid(pid, 0)
    sys.stdout.write(buf.decode("utf-8", "replace"))
    sys.stderr.write("timed out waiting for the installer\n")
    os._exit(1)


signal.signal(signal.SIGALRM, on_timeout)
signal.alarm(60)
answered = False
while True:
    try:
        data = os.read(fd, 4096)
    except OSError:
        break
    if not data:
        break
    buf += data
    if not answered and b"Proceed?" in buf:
        os.write(fd, b"n\n")
        answered = True
signal.alarm(0)
_, status = os.waitpid(pid, 0)
sys.stdout.write(buf.decode("utf-8", "replace"))
sys.exit(os.WEXITSTATUS(status) if os.WIFEXITED(status) else 1)
'

capture_declined() {
  assert_sandboxed
  OUT="$(NO_COLOR=1 ienv python3 -I -c "$DECLINE_PY" "$BASH" "$SB_REPO/install.sh" "$@" 2>&1)"
  RC=$?
}

original_files() {
  printf 'old' > "$SB_HOME/.tmux.conf"
  mkdir -p "$SB_HOME/.claude"
  printf '{"theme":"solarized","model":"sonnet"}\n' > "$SB_HOME/.claude/settings.json"
}

link_target() {
  readlink "$1" 2>/dev/null || true
}

live_json() {
  jq -S . "$SB_HOME/.claude/settings.json"
}

lifecycle() {
  scenario "lifecycle: dry-run writes nothing"
  new_sandbox
  original_files
  local before after
  before="$(state_sum)"
  mark_time
  capture --dry-run --no-skills
  assert_eq "dry-run exit status" 0 "$RC"
  assert_match "dry-run plans a tmux backup" '^backup .*\.tmux\.conf -> .*\.tmux\.conf\.bak\.' "$OUT"
  assert_match "dry-run plans a settings backup" '^backup .*/\.claude/settings\.json -> ' "$OUT"
  assert_match "dry-run plans seeding the overlay" "^seed $SB_LOCAL/settings\.json from " "$OUT"
  assert_match "dry-run plans generating settings" '^generate .*/\.claude/settings\.json' "$OUT"
  assert_match "dry-run plans links" "^link $SB_HOME/\.claude/agents -> $SB_REPO/agents" "$OUT"
  after="$(state_sum)"
  assert_eq "dry-run leaves HOME, overlay and repo untouched" "$before" "$after"

  scenario "lifecycle: dry-run with skills does not call npx"
  capture --dry-run
  assert_eq "dry-run with skills exit status" 0 "$RC"
  assert_match "dry-run plans skills" '^install skills ' "$OUT"
  assert_eq "dry-run made no npx call" "" "$(cat "$SB_NPX_LOG")"
  assert_eq "dry-run with skills leaves state untouched" "$before" "$(state_sum)"

  scenario "lifecycle: non-interactive run that needs backups is refused"
  capture --no-skills
  assert_eq "refusal exit status" 1 "$RC"
  assert_match "refusal message" 'Refusing to change files without --yes' "$OUT"
  assert_eq "refusal leaves state untouched" "$before" "$(state_sum)"

  scenario "lifecycle: declining the prompt exits 1 and changes nothing"
  capture_declined --no-skills
  assert_eq "declined exit status" 1 "$RC"
  assert_match "declined message" 'Aborted\.' "$OUT"
  assert_eq "declined leaves state untouched" "$before" "$(state_sum)"
  assert_untouched "dry-run, refused and declined runs"

  scenario "lifecycle: --yes installs, backs up and seeds the overlay"
  capture --yes --no-skills
  assert_eq "install exit status" 0 "$RC"
  assert_match "seeded overlay" 'seeded .*/settings\.json from the existing' "$OUT"
  assert_match "generated settings" 'generated: ' "$OUT"
  assert_false "settings.json is a generated file, not a link" test -L "$SB_HOME/.claude/settings.json"
  assert_eq "overlay seeded with the user's keys" '{"model":"sonnet","theme":"solarized"}' \
    "$(jq -Sc . "$SB_LOCAL/settings.json")"
  assert_eq "live settings are defaults plus overlay" \
    "$(jq -S -s '.[0] * .[1]' "$SB_REPO/claude/settings.json" "$SB_LOCAL/settings.json")" "$(live_json)"
  assert_eq "agents link" "$SB_REPO/agents" "$(link_target "$SB_HOME/.claude/agents")"
  assert_eq "AGENTS.md link" "$SB_REPO/claude/AGENTS.md" "$(link_target "$SB_HOME/.claude/AGENTS.md")"
  assert_eq "CLAUDE.md link" "$SB_REPO/claude/CLAUDE.md" "$(link_target "$SB_HOME/.claude/CLAUDE.md")"
  assert_eq "hooks link" "$SB_REPO/hooks" "$(link_target "$SB_HOME/.claude/hooks")"
  assert_eq "tmux link" "$SB_REPO/tmux/tmux.conf" "$(link_target "$SB_HOME/.tmux.conf")"
  assert_eq "one tmux backup" 1 "$(count_entries "$SB_HOME" '.tmux.conf.bak.*')"
  assert_eq "tmux backup keeps the old content" old \
    "$(cat "$SB_HOME"/.tmux.conf.bak.* 2>/dev/null)"
  assert_eq "one settings backup" 1 "$(count_entries "$SB_HOME/.claude" 'settings.json.bak.*')"
  assert_eq "settings backup keeps the original" '{"model":"sonnet","theme":"solarized"}' \
    "$(jq -Sc . "$SB_HOME"/.claude/settings.json.bak.* 2>/dev/null)"
  assert_true "settings snapshot written" test -f "$SB_HOME/.claude/settings.generated.json"
  local guard="$SB_HOME/.claude/hooks/memory-write-guard.sh"
  printf '{"tool_input":{"file_path":"%s/x.md"},"cwd":"%s"}' "$SB_HOME" "$SB_HOME" | "$BASH" "$guard" >/dev/null 2>&1
  assert_eq "linked guard blocks a project write" 2 "$?"
  printf '{"tool_input":{"file_path":"%s/p/.claude/agent-memory/a/x.md"},"cwd":"%s"}' "$SB_HOME" "$SB_HOME" \
    | "$BASH" "$guard" >/dev/null 2>&1
  assert_eq "linked guard allows a memory write" 0 "$?"

  scenario "lifecycle: second run is quiet and unattended"
  before="$(state_sum)"
  mark_time
  capture --no-skills
  assert_eq "second run exit status" 0 "$RC"
  assert_nomatch "second run reports no changes" 'linked:|generated:|backing up|backup |adopted|seeded|warn:|removing|replacing|Plan' "$OUT"
  assert_eq "second run leaves state untouched" "$before" "$(state_sum)"
  assert_untouched "second run"
  mark_time
  capture --dry-run --no-skills
  assert_eq "dry-run after install exit status" 0 "$RC"
  assert_nomatch "dry-run after install plans no change" '^(link|backup|generate|adopt|seed|remove) ' "$OUT"
  assert_eq "dry-run after install leaves state untouched" "$before" "$(state_sum)"
  assert_untouched "dry-run after install"

  scenario "lifecycle: edits made in the live settings are adopted into the overlay"
  jq '.theme="light"' "$SB_HOME/.claude/settings.json" > "$SB_HOME/.claude/tmp.json" \
    && mv "$SB_HOME/.claude/tmp.json" "$SB_HOME/.claude/settings.json"
  capture --no-skills
  assert_eq "adopt exit status" 0 "$RC"
  assert_match "adoption reported" 'adopted into .*/settings\.json: theme' "$OUT"
  assert_eq "overlay holds the edit" light "$(jq -r .theme "$SB_LOCAL/settings.json")"
  assert_eq "live settings keep the edit" light "$(jq -r .theme "$SB_HOME/.claude/settings.json")"
  assert_eq "snapshot matches the live settings after adoption" "$(live_json)" \
    "$(jq -S . "$SB_HOME/.claude/settings.generated.json")"
  assert_eq "committed defaults stay clean" 0 "$(jq -S . "$SB_REPO/claude/settings.json" | grep -c light)"
  before="$(state_sum)"
  mark_time
  capture --no-skills
  assert_nomatch "run after adoption is quiet" 'adopted|seeded|warn:' "$OUT"
  assert_eq "run after adoption leaves state untouched" "$before" "$(state_sum)"
  assert_untouched "run after a completed adoption"

  scenario "lifecycle: personal instructions are linked"
  printf '# Personal rules\n' > "$SB_LOCAL/instructions.md"
  capture --no-skills
  assert_eq "personal instructions exit status" 0 "$RC"
  assert_eq "CLAUDE.local.md link" "$SB_LOCAL/instructions.md" "$(link_target "$SB_HOME/.claude/CLAUDE.local.md")"

  scenario "lifecycle: --uninstall removes links and restores backups"
  capture --uninstall --dry-run
  assert_eq "uninstall dry-run exit status" 0 "$RC"
  assert_match "uninstall dry-run plans unlinking" '^unlink ' "$OUT"
  assert_match "uninstall dry-run plans restoring" '^restore ' "$OUT"
  before="$(state_sum)"
  mark_time
  capture --uninstall --dry-run
  assert_eq "uninstall dry-run leaves state untouched" "$before" "$(state_sum)"
  assert_untouched "uninstall dry-run"
  capture --uninstall --yes
  assert_eq "uninstall exit status" 0 "$RC"
  assert_eq "no links remain under HOME" 0 "$(find "$SB_HOME" -type l | wc -l | tr -d ' ')"
  assert_eq "tmux.conf restored" old "$(cat "$SB_HOME/.tmux.conf")"
  assert_eq "settings.json restored" '{"model":"sonnet","theme":"solarized"}' "$(jq -Sc . "$SB_HOME/.claude/settings.json")"
  assert_false "snapshot removed" test -e "$SB_HOME/.claude/settings.generated.json"
  assert_true "overlay untouched" test -f "$SB_LOCAL/settings.json"
  assert_eq "overlay keeps the adopted edit" light "$(jq -r .theme "$SB_LOCAL/settings.json")"
  assert_true "personal instructions file untouched" test -f "$SB_LOCAL/instructions.md"
  capture --uninstall --yes
  assert_eq "second uninstall exit status" 0 "$RC"
  assert_match "second uninstall has nothing to do" 'Nothing to uninstall' "$OUT"
}

uninstall_without_backup() {
  scenario "uninstall: a fresh install with no prior settings leaves a regular settings.json"
  new_sandbox
  capture --yes --no-skills
  assert_eq "fresh install exit status" 0 "$RC"
  assert_true "fresh install generated settings.json" test -f "$SB_HOME/.claude/settings.json"
  capture --uninstall --yes
  assert_eq "uninstall exit status" 0 "$RC"
  assert_true "settings.json exists" test -e "$SB_HOME/.claude/settings.json"
  assert_true "settings.json is a regular file" test -f "$SB_HOME/.claude/settings.json"
  assert_false "settings.json is not a symlink" test -L "$SB_HOME/.claude/settings.json"
  assert_true "settings.json is valid JSON" jq -e . "$SB_HOME/.claude/settings.json" > /dev/null
  assert_false "snapshot removed" test -e "$SB_HOME/.claude/settings.generated.json"
}

settings_array_merge() {
  scenario "settings: a pulled removal and a user write-back in the same array adopt only the user's element"
  new_sandbox
  capture --yes --no-skills
  assert_eq "initial install exit status" 0 "$RC"
  local removed='Edit(advisor-plans/*.md)' added='Bash(make test:*)'
  assert_eq "fixture element is among the committed defaults" true \
    "$(jq --arg r "$removed" '.permissions.allow | index($r) != null' "$SB_REPO/claude/settings.json")"
  jq --arg r "$removed" '.permissions.allow -= [$r]' "$SB_REPO/claude/settings.json" > "$SB_REPO/defaults.tmp" \
    && mv "$SB_REPO/defaults.tmp" "$SB_REPO/claude/settings.json"
  jq --arg a "$added" '.permissions.allow += [$a]' "$SB_HOME/.claude/settings.json" > "$SB_HOME/.claude/tmp.json" \
    && mv "$SB_HOME/.claude/tmp.json" "$SB_HOME/.claude/settings.json"
  capture --no-skills
  assert_eq "merge run exit status" 0 "$RC"
  assert_eq "overlay adopts only the user's element" "[\"$added\"]" "$(jq -c '.permissions.allow' "$SB_LOCAL/settings.json")"
  assert_eq "live allow list has the user's element" true \
    "$(jq --arg a "$added" '.permissions.allow | index($a) != null' "$SB_HOME/.claude/settings.json")"
  assert_eq "live allow list drops the removed default" true \
    "$(jq --arg r "$removed" '.permissions.allow | index($r) == null' "$SB_HOME/.claude/settings.json")"
  assert_eq "live allow list keeps the other defaults" true \
    "$(jq '.permissions.allow | index("Edit(plans/*.md)") != null' "$SB_HOME/.claude/settings.json")"
}

settings_legacy_link() {
  scenario "settings: a legacy symlinked settings.json needs an overlay or an explicit opt-out"
  new_sandbox
  mkdir -p "$SB_HOME/.claude"
  ln -s "$SB_REPO/claude/settings.json" "$SB_HOME/.claude/settings.json"
  local before
  before="$(state_sum)"
  capture --no-skills
  assert_eq "missing overlay exit status" 1 "$RC"
  assert_match "missing overlay message" 'no personal overlay found' "$OUT"
  assert_eq "missing overlay leaves state untouched" "$before" "$(state_sum)"
  CLAUDE_CONFIG_NO_OVERLAY=1 capture --no-skills
  assert_eq "opt-out exit status" 0 "$RC"
  assert_false "settings.json is now a generated file" test -L "$SB_HOME/.claude/settings.json"
  assert_eq "generated settings equal the defaults" "$(jq -S . "$SB_REPO/claude/settings.json")" "$(live_json)"
}

stale_skills_fixture() {
  mkdir -p "$SB_HOME/.claude/skills/stale-skill" "$SB_HOME/.claude/skills/parallel-build" \
    "$SB_HOME/.claude/skills/synced" "$SB_HOME/.claude/skills/.trash" "$SB_HOME/.claude/skills/$LOCK_SKILL" \
    "$SB_HOME/.claude/skills/spare/nested"
  printf 'keep' > "$SB_HOME/.claude/skills/stale-skill/SKILL.md"
  mkdir -p "$SB/outside"
  printf 'precious' > "$SB/outside/sentinel"
  ln -s "$SB/outside" "$SB_HOME/.claude/skills/linked-skill"
}

clean_skills() {
  LOCK_SKILL="$(jq -r '.skills | keys[0]' "$REPO/skills-lock.json")"

  scenario "clean: --clean removes stale skills and only the link of a symlinked skill"
  new_sandbox
  stale_skills_fixture
  capture --no-skills --clean
  assert_eq "unconfirmed --clean exit status" 1 "$RC"
  assert_match "unconfirmed --clean is planned" '^clean stale skills ' "$OUT"
  assert_true "unconfirmed --clean deletes nothing" test -d "$SB_HOME/.claude/skills/stale-skill"
  capture --no-skills --clean --yes
  assert_eq "--clean exit status" 0 "$RC"
  assert_false "stale skill removed" test -e "$SB_HOME/.claude/skills/stale-skill"
  assert_false "symlinked skill link removed" test -L "$SB_HOME/.claude/skills/linked-skill"
  assert_true "symlink target untouched" test -f "$SB/outside/sentinel"
  assert_eq "symlink target content intact" precious "$(cat "$SB/outside/sentinel")"
  assert_true "repo skill kept" test -d "$SB_HOME/.claude/skills/parallel-build"
  assert_true "locked skill kept" test -d "$SB_HOME/.claude/skills/$LOCK_SKILL"
  assert_true "synced directory kept" test -d "$SB_HOME/.claude/skills/synced"
  assert_true ".trash kept" test -d "$SB_HOME/.claude/skills/.trash"

  scenario "clean: an unreadable lock deletes nothing and exits 1"
  new_sandbox
  stale_skills_fixture
  printf 'not json' > "$SB_REPO/skills-lock.json"
  capture --no-skills --clean --yes
  assert_eq "unreadable lock exit status" 1 "$RC"
  assert_match "unreadable lock message" 'skills-lock\.json unreadable' "$OUT"
  assert_true "unreadable lock keeps the stale skill" test -d "$SB_HOME/.claude/skills/stale-skill"
  assert_true "unreadable lock keeps the symlinked skill" test -L "$SB_HOME/.claude/skills/linked-skill"
  assert_true "unreadable lock keeps the synced directory" test -d "$SB_HOME/.claude/skills/synced"
  printf '{"version":1}' > "$SB_REPO/skills-lock.json"
  capture --no-skills --clean --yes
  assert_eq "lock without a skills object exit status" 1 "$RC"
  assert_true "lock without a skills object keeps the stale skill" test -d "$SB_HOME/.claude/skills/stale-skill"
}

write_fixture_lock() {
  cat > "$SB_REPO/skills-lock.json" <<'LOCK'
{
  "version": 1,
  "skills": {
    "alpha": {"source": "owner/one", "sourceType": "github"},
    "beta": {"source": "owner/two", "sourceType": "github"},
    "gamma": {"source": "owner/two", "sourceType": "github"},
    "delta": {"source": "owner/three", "sourceType": "github"}
  }
}
LOCK
}

skills_install() {
  scenario "skills: every source is installed through npx"
  new_sandbox
  write_fixture_lock
  capture
  assert_eq "skills install exit status" 0 "$RC"
  local log
  log="$(cat "$SB_NPX_LOG")"
  assert_match "own skills installed" '^-y skills add \./skills -g -a claude-code -y$' "$log"
  assert_match "owner/one installed" '^-y skills add owner/one -s alpha -g -a claude-code -y$' "$log"
  assert_match "owner/two installed with both skills" '^-y skills add owner/two -s beta -s gamma -g -a claude-code -y$' "$log"
  assert_match "owner/three installed" '^-y skills add owner/three -s delta -g -a claude-code -y$' "$log"

  scenario "skills: one failing upstream source does not stop the others"
  new_sandbox
  write_fixture_lock
  stale_skills_fixture
  NPX_FAIL_SOURCE=owner/one capture --clean --yes
  assert_eq "failing source exit status" 1 "$RC"
  assert_match "failing source reported" 'failed to install from owner/one: alpha' "$OUT"
  assert_match "failure summary" 'finished with errors' "$OUT"
  assert_match "later sources still installed" 'owner/three -s delta' "$(cat "$SB_NPX_LOG")"
  assert_match "middle source still installed" 'owner/two -s beta -s gamma' "$(cat "$SB_NPX_LOG")"
  assert_match "--clean skipped after a failure" 'skipping --clean' "$OUT"
  assert_true "--clean after a failure deletes nothing" test -d "$SB_HOME/.claude/skills/stale-skill"

  scenario "skills: an unreadable lock installs nothing from upstream and exits 1"
  new_sandbox
  printf 'not json' > "$SB_REPO/skills-lock.json"
  capture
  assert_eq "unreadable lock exit status" 1 "$RC"
  assert_match "unreadable lock message" 'skills-lock\.json unreadable' "$OUT"
  assert_nomatch "nothing was fetched from upstream" 'owner/' "$(cat "$SB_NPX_LOG")"
}

exit_trap() {
  scenario "exit status: a set -u abort exits non-zero"
  new_sandbox
  awk '{ if ($0 == "banner") print ": \"${UNBOUND_VARIABLE_FOR_TEST}\""; print }' "$SB_REPO/install.sh" > "$SB_REPO/install.tmp" \
    && mv "$SB_REPO/install.tmp" "$SB_REPO/install.sh"
  capture --no-skills
  assert_eq "unbound variable abort exit status" 1 "$RC"
  assert_match "abort reason shown" 'unbound variable' "$OUT"
  assert_nomatch "aborted run does not claim success" '==> Done\.' "$OUT"
  assert_false "aborted run installed nothing" test -e "$SB_HOME/.claude"

  scenario "exit status: an empty-array abort exits non-zero where the shell treats it as an error"
  new_sandbox
  awk '{ if ($0 == "banner") print "EMPTY_FOR_TEST=(); : \"${EMPTY_FOR_TEST[@]}\""; print }' "$SB_REPO/install.sh" > "$SB_REPO/install.tmp" \
    && mv "$SB_REPO/install.tmp" "$SB_REPO/install.sh"
  capture --no-skills
  if printf '%s\n' "$OUT" | grep -q 'unbound variable'; then
    assert_eq "empty array abort exit status" 1 "$RC"
    assert_nomatch "aborted run does not claim success" '==> Done\.' "$OUT"
  else
    echo "   (this bash does not abort on an empty array expansion; nothing to assert)"
  fi
}

arguments() {
  scenario "arguments: help, unknown flags and conflicting flags"
  new_sandbox
  capture --help
  assert_eq "--help exit status" 0 "$RC"
  assert_eq "--help first line" 'Usage: ./install.sh [--dry-run] [--yes] [--no-skills] [--clean]' "$(printf '%s\n' "$OUT" | head -1)"
  capture --bogus
  assert_eq "unknown flag exit status" 1 "$RC"
  assert_match "unknown flag message" 'unknown argument: --bogus' "$OUT"
  capture --uninstall --clean
  assert_eq "--uninstall with --clean exit status" 1 "$RC"
  assert_false "bad arguments touch nothing" test -e "$SB_HOME/.claude"
}

lifecycle
uninstall_without_backup
settings_array_merge
settings_legacy_link
clean_skills
skills_install
exit_trap
arguments

if [ "$FAILURES" -gt 0 ]; then
  echo "install: $FAILURES of $CHECKS assertions failed" >&2
  exit 1
fi
echo "install: ok"
