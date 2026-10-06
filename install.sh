#!/usr/bin/env bash
#
# claude-config bootstrap
#
# - Symlinks Claude Code configs into place and merges the committed settings
#   defaults into ~/.claude/settings.json without overwriting the user's values
# - Installs this repo's own skills and the third-party skills listed in
#   skills-lock.json (from their upstream repos) globally via skills CLI
#
# Idempotent - re-run after every git pull.
#
# Usage: ./install.sh [--dry-run] [--yes] [--no-skills] [--clean]
#        ./install.sh --uninstall [--dry-run] [--yes]
# Run ./install.sh --help for the flags.

set -euo pipefail

REPO_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
BACKUP_SUFFIX=".bak.$(date +%Y%m%d%H%M%S)"

USE_COLOR=0
if [ -t 1 ] && [ -z "${NO_COLOR:-}" ]; then USE_COLOR=1; fi

info() {
  if [ "$USE_COLOR" = 1 ]; then printf '\033[1;34m==>\033[0m %s\n' "$*"; else printf '==> %s\n' "$*"; fi
}
warn() {
  if [ "$USE_COLOR" = 1 ]; then printf '\033[1;33mwarn:\033[0m %s\n' "$*"; else printf 'warn: %s\n' "$*"; fi
}

COMPLETED=0
FAILED=0
TMP_FILES=()
# bash 3.2 (macOS /bin/bash) reports status 0 for a set -u abort once an EXIT trap is set,
# so a run that did not reach COMPLETED=1 is forced to a non-zero status here.
cleanup() {
  local rc=$?
  if [ "${#TMP_FILES[@]}" -gt 0 ]; then rm -f "${TMP_FILES[@]}"; fi
  if [ "$rc" = 0 ] && [ "$COMPLETED" != 1 ]; then rc=1; fi
  trap - EXIT
  exit "$rc"
}
trap cleanup EXIT
trap 'exit 1' INT TERM HUP

finish() { COMPLETED=1; exit "${1:-0}"; }

usage_lines() {
  echo "Usage: ./install.sh [--dry-run] [--yes] [--no-skills] [--clean]"
  echo "       ./install.sh --uninstall [--dry-run] [--yes]"
}

usage() {
  usage_lines
  cat <<'EOF'

Links this repo's Claude Code config into ~/.claude (and tmux.conf into ~),
merges the defaults in claude/settings.json into ~/.claude/settings.json (your values
always win, missing keys and array elements are added), and installs the skills listed in skills/ and skills-lock.json.

  --dry-run    print the planned changes and exit without touching anything
  --yes, -y    do not ask for confirmation; needed when stdin is not a terminal and the run
               would back up or remove something this repo does not own (backups, --clean,
               --uninstall)
  --no-skills  skip the skills CLI (no network)
  --clean      also remove ~/.claude/skills entries this repo does not provide
  --uninstall  remove the links, restoring the newest backups; ~/.claude/settings.json is kept
  --help, -h   show this help

Environment:
  NO_COLOR  set to any non-empty value to turn off colored output
EOF
}

CLEAN=0
NO_SKILLS=0
DRY_RUN=0
ASSUME_YES=0
UNINSTALL=0
for arg in "$@"; do
  case "$arg" in
    --clean) CLEAN=1 ;;
    --no-skills) NO_SKILLS=1 ;;
    --dry-run) DRY_RUN=1 ;;
    --yes|-y) ASSUME_YES=1 ;;
    --uninstall) UNINSTALL=1 ;;
    --help|-h) usage; finish 0 ;;
    *) warn "unknown argument: $arg"; usage_lines >&2; exit 1 ;;
  esac
done
if [ "$UNINSTALL" = 1 ] && [ "$CLEAN$NO_SKILLS" != 00 ]; then
  warn "--uninstall cannot be combined with --clean or --no-skills"
  usage_lines >&2
  exit 1
fi

command -v jq >/dev/null || { warn "jq is required"; exit 1; }

banner() {
  [ -t 1 ] || return 0
  if [ "$USE_COLOR" = 1 ]; then printf '\033[1;34m'; fi
  cat <<'EOF'
 #### #      ###  #   # ####  #####        ####  ###  #   # ##### ###  ####
#     #     #   # #   # #   # #           #     #   # ##  # #      #  #
#     #     ##### #   # #   # ####   ###  #     #   # # # # ####   #  #  ##
#     #     #   # #   # #   # #           #     #   # #  ## #      #  #   #
 #### ##### #   #  ###  ####  #####        ####  ###  #   # #     ###  ###

Claude Code config installer
EOF
  if [ "$USE_COLOR" = 1 ]; then printf '\033[0m'; fi
  echo
}

MODE=apply
PLAN_LINES=()
NEEDS_CONFIRM=0
PLAN_SUMS=""

# plan_add: an action that touches something this repo does not own, so it needs confirmation.
# plan_sync: routine sync of state this repo owns; listed in the plan but never prompts.
plan_add()  { PLAN_LINES+=("$*"); NEEDS_CONFIRM=$((NEEDS_CONFIRM + 1)); }
plan_sync() { PLAN_LINES+=("$*"); }
plan_ok()   { PLAN_LINES+=("ok: $*"); }
plan_note() { PLAN_LINES+=("$*"); }

print_plan() {
  local line
  info "Plan"
  if [ "${#PLAN_LINES[@]}" -gt 0 ]; then
    for line in "${PLAN_LINES[@]}"; do printf '%s\n' "$line"; done
  fi
}

step() { if [ "$MODE" = apply ]; then info "$*"; fi; }

confirm() {
  local reply=""
  if [ "$ASSUME_YES" = 1 ]; then return 0; fi
  if [ ! -t 0 ]; then
    echo "Refusing to change files without --yes when not interactive." >&2
    exit 1
  fi
  read -r -p 'Proceed? [y/N] ' reply || reply=""
  case "$reply" in
    y|Y|yes) return 0 ;;
  esac
  echo "Aborted."
  exit 1
}

# link <source-in-repo> <target-path>
# Backs up an existing real file/dir/foreign symlink at target, then symlinks to repo.
link() {
  local src="$1" dst="$2" target

  if [ ! -e "$src" ]; then
    if [ "$MODE" = apply ]; then warn "skipping $dst - $src does not exist in repo"; fi
    return 0
  fi

  # Already correctly linked? Nothing to do.
  if [ -L "$dst" ] && [ "$(readlink "$dst")" = "$src" ]; then
    if [ "$MODE" = plan ]; then plan_ok "$dst"; else info "ok: $dst"; fi
    return 0
  fi

  # A symlink into this repo carries no user data, so it is replaced without a backup.
  target="$(readlink "$dst" 2>/dev/null || true)"
  if [ "$MODE" = plan ]; then
    if [ -L "$dst" ] && points_into_repo "$target"; then
      :
    elif [ -e "$dst" ] || [ -L "$dst" ]; then
      plan_add "backup $dst -> ${dst}${BACKUP_SUFFIX}"
    fi
    plan_sync "link $dst -> $src"
    return 0
  fi

  mkdir -p "$(dirname "$dst")"
  if [ -L "$dst" ] && points_into_repo "$target"; then
    rm "$dst"
  elif [ -e "$dst" ] || [ -L "$dst" ]; then
    warn "backing up existing $dst -> ${dst}${BACKUP_SUFFIX}"
    mv "$dst" "${dst}${BACKUP_SUFFIX}"
  fi

  ln -s "$src" "$dst"
  info "linked: $dst -> $src"
}

JQ_LIB='
def fill($d; $u):
  if ($d | type) == "object" and ($u | type) == "object" then
    reduce ($d | keys_unsorted[]) as $k ($u;
      .[$k] = (if has($k) then fill($d[$k]; $u[$k]) else $d[$k] end))
  elif ($d | type) == "array" and ($u | type) == "array" then $u + ($d - $u)
  else $u end;

def added($d; $u; $p):
  if ($d | type) == "object" and ($u | type) == "object" then
    ($d | keys_unsorted[]) as $k
    | if $u | has($k) then added($d[$k]; $u[$k]; $p + [$k]) else ($p + [$k] | join(".")) end
  elif ($d | type) == "array" and ($u | type) == "array" then
    ($d - $u) | select(length > 0) | ($p | join(".")) + "[...]"
  else empty end;
'

fingerprint() {
  if [ -f "$1" ]; then cksum < "$1"; else ls -ld "$1" 2>/dev/null || true; fi
}

check_settings_inputs() {
  local defaults="$REPO_DIR/claude/settings.json"
  local live="$HOME/.claude/settings.json"
  if ! jq -e 'type == "object"' "$defaults" >/dev/null 2>&1; then
    warn "$defaults is not a valid JSON object; nothing was changed"
    finish 1
  fi
  if [ -f "$live" ] && [ ! -L "$live" ]; then
    if [ ! -r "$live" ]; then
      warn "cannot read $live; nothing was changed"
      finish 1
    fi
    if [ -n "$(tr -d '[:space:]' < "$live")" ] \
      && ! jq -s -e 'length == 1 and (.[0] | type) == "object"' "$live" >/dev/null 2>&1; then
      warn "$live is not a valid JSON object; fix it; nothing was changed"
      finish 1
    fi
  fi
}

# Computes everything generate_settings needs without writing anything; results go to S_* globals.
compute_settings() {
  local defaults="$REPO_DIR/claude/settings.json"
  local live="$HOME/.claude/settings.json"
  local user_src=/dev/null result detail
  S_BACKUP=0
  S_ACTION=create
  if [ -L "$live" ]; then
    if points_into_repo "$(readlink "$live")"; then
      S_ACTION=replace
    else
      S_ACTION=foreign
      S_BACKUP=1
    fi
  elif [ -f "$live" ]; then
    S_ACTION=update
    user_src="$live"
  elif [ -e "$live" ]; then
    S_ACTION=foreign
    S_BACKUP=1
  fi
  result="$(jq -n --slurpfile d "$defaults" --slurpfile u "$user_src" "$JQ_LIB"'
    ($u[0] // {}) as $u
    | fill($d[0]; $u) as $m
    | {merged: $m, same: ($m == $u), added: [added($d[0]; $u; [])]}')" \
    || { warn "could not merge $defaults into $live; nothing was changed"; exit 1; }
  S_MERGED="$(printf '%s\n' "$result" | jq '.merged')"
  detail="$(printf '%s\n' "$result" | jq -r '.added | join(", ")')"
  S_DETAIL=""
  if [ "$S_ACTION" = update ]; then
    if [ -n "$detail" ]; then S_DETAIL="added: $detail"; fi
  fi
  if [ "$S_ACTION" = update ] && [ "$(printf '%s\n' "$result" | jq -r '.same')" = true ]; then
    S_ACTION=ok
  fi
  if [ -n "$S_DETAIL" ]; then S_DETAIL=" ($S_DETAIL)"; fi
}

generate_settings() {
  local live="$HOME/.claude/settings.json"
  local merged live_sum
  if [ "$MODE" = plan ]; then
    compute_settings
    case "$S_ACTION" in
      ok) plan_ok "$live" ;;
      create) plan_sync "create: $live$S_DETAIL" ;;
      replace) plan_sync "replace: $live (link into this repo) with a file holding the defaults$S_DETAIL" ;;
      foreign)
        plan_add "backup $live -> ${live}${BACKUP_SUFFIX}"
        plan_sync "create: $live$S_DETAIL"
        ;;
      update) plan_sync "update: $live$S_DETAIL" ;;
    esac
    return 0
  fi
  mkdir -p "$HOME/.claude"
  live_sum="$(fingerprint "$live")"
  compute_settings
  if [ "$S_ACTION" = ok ]; then
    info "ok: $live"
    return 0
  fi
  # The temp file lives in ~/.claude so the final mv is an atomic same-filesystem rename.
  merged="$(mktemp "$HOME/.claude/.settings.XXXXXX")"
  TMP_FILES+=("$merged")
  printf '%s\n' "$S_MERGED" > "$merged"
  if [ "$(fingerprint "$live")" != "$live_sum" ]; then
    warn "$live changed while install.sh was running; nothing was written - close running Claude Code sessions and rerun"
    exit 1
  fi
  if [ "$S_BACKUP" = 1 ]; then
    warn "backing up existing $live -> ${live}${BACKUP_SUFFIX}"
    mv "$live" "${live}${BACKUP_SUFFIX}"
  fi
  mv -f "$merged" "$live"
  case "$S_ACTION" in
    update) info "update: $live$S_DETAIL" ;;
    replace) info "replace: $live (link into this repo) with a file holding the defaults$S_DETAIL" ;;
    *) info "create: $live$S_DETAIL" ;;
  esac
}

read_lock_names() {
  jq -e '.skills | type == "object"' "$REPO_DIR/skills-lock.json" >/dev/null \
    && jq -r '.skills | keys[]' "$REPO_DIR/skills-lock.json"
}

retire_links() {
  local retired target
  # Links this script no longer creates - remove them if they still point into this repo.
  for retired in "$HOME/.claude/commands" "$HOME/.claude/statusline" "$HOME/.claude/mods"; do
    target="$(readlink "$retired" 2>/dev/null || true)"
    if [ -L "$retired" ] && [ "${target#"$REPO_DIR"/}" != "$target" ]; then
      if [ "$MODE" = plan ]; then
        plan_sync "remove retired link $retired"
      else
        warn "removing retired link: $retired"
        rm "$retired"
      fi
    fi
  done
}

# Claude shared instructions: AGENTS.md is symlinked next to CLAUDE.md, which
# imports it via "@~/.claude/AGENTS.md" (home-anchored: a relative import
# would resolve against CLAUDE.md's realpath and break).
install_config() {
  step "Linking shared instructions for Claude Code"
  link "$REPO_DIR/claude/AGENTS.md" "$HOME/.claude/AGENTS.md"
  step "Linking Claude Code config"
  retire_links
  generate_settings
  link "$REPO_DIR/claude/CLAUDE.md"     "$HOME/.claude/CLAUDE.md"
  link "$REPO_DIR/agents"               "$HOME/.claude/agents"
  # Agent frontmatter references hooks by absolute path ($HOME/.claude/hooks/...),
  # so they must resolve on every machine, not just inside this repo.
  link "$REPO_DIR/hooks"                "$HOME/.claude/hooks"
  link "$REPO_DIR/tmux/tmux.conf"       "$HOME/.tmux.conf"
  if [ "$MODE" = apply ]; then chmod +x "$REPO_DIR"/hooks/*.sh 2>/dev/null || true; fi
}

# Install skills globally: this repo's own (skills/) and the third-party
# skills listed in skills-lock.json, each from its upstream repo.
install_skills() {
  local manifest source names name args
  if [ "$NO_SKILLS" = 1 ]; then
    step "Skipping skills (--no-skills)"
    return 0
  fi
  if [ "$MODE" = plan ]; then
    plan_sync "install skills from ./skills and skills-lock.json"
    return 0
  fi
  info "Installing skills globally via skills CLI"
  cd "$REPO_DIR"
  # Target only agents that support global installs - the default "all detected
  # agents" includes project-scope-only targets (e.g. PromptScript), which emit
  # a spurious "does not support global skill installation" error per skill.
  if compgen -G "skills/*/SKILL.md" > /dev/null; then
    npx -y skills add ./skills -g -a claude-code -y < /dev/null \
      || { warn "failed to install from ./skills"; FAILED=1; }
  fi
  read_lock_names > /dev/null || { warn "skills-lock.json unreadable; nothing was installed from upstream"; exit 1; }
  manifest="$(jq -r '.skills | to_entries | group_by(.value.source)[] | "\(.[0].value.source) \(map(.key) | join(" "))"' "$REPO_DIR/skills-lock.json")"
  # The skills CLI reads stdin, which would otherwise be the manifest.
  while read -r source names; do
    [ -n "$source" ] && [ -n "$names" ] || continue
    args=()
    set -f
    for name in $names; do args+=(-s "$name"); done
    set +f
    npx -y skills add "$source" "${args[@]}" -g -a claude-code -y < /dev/null \
      || { warn "failed to install from $source: $names"; FAILED=1; }
  done <<< "$manifest"
}

# --clean: remove installed skills that this repo does not provide
# (the skills CLI copies rather than symlinks, so skills deleted from the
# repo - or installed by other means - linger in ~/.claude/skills forever).
clean_skills() {
  local lock_names removed installed name
  if [ "$MODE" = plan ]; then
    plan_add "clean stale skills under $HOME/.claude/skills"
    return 0
  fi
  if [ "$FAILED" = 1 ]; then
    warn "skipping --clean: some skills failed to install"
    return 0
  fi
  lock_names="$(read_lock_names)" || { warn "skills-lock.json unreadable; skipping --clean"; exit 1; }
  info "Removing skills not provided by this repo from $HOME/.claude/skills"
  removed=0
  for installed in "$HOME/.claude/skills"/*; do
    [ -d "$installed" ] || [ -L "$installed" ] || continue
    name="$(basename "$installed")"
    # Claude Code owns ~/.claude/skills/synced (claude.ai skill sync) and .trash.
    case "$name" in synced|.*|*..*|*/*) continue ;; esac
    if [ ! -f "$REPO_DIR/skills/$name/SKILL.md" ] && ! printf '%s\n' "$lock_names" | grep -qxF -- "$name"; then
      warn "removing stale skill: $name"
      if [ -L "$installed" ]; then rm "$installed"; else rm -rf "$installed"; fi
      removed=1
    fi
  done
  if [ "$removed" = 0 ]; then info "ok: no stale skills"; fi
}

install_all() {
  install_config
  install_skills
  if [ "$CLEAN" = 1 ]; then clean_skills; fi
}

points_into_repo() {
  [ "${1#"$REPO_DIR"/}" != "$1" ]
}

newest_backup() {
  local f ts newest=""
  for f in "$1".bak.*; do
    [ -e "$f" ] || [ -L "$f" ] || continue
    ts="${f##*.bak.}"
    case "$ts" in *[!0-9]*|"") continue ;; esac
    [ "${#ts}" = 14 ] || continue
    newest="$f"
  done
  printf '%s' "$newest"
}

# restore_backup <path>: moves the newest backup back; never overwrites anything.
restore_backup() {
  local path="$1" bak
  bak="$(newest_backup "$path")"
  [ -n "$bak" ] || return 0
  if [ "$MODE" = plan ]; then
    plan_add "restore $bak -> $path"
  elif [ ! -e "$path" ] && [ ! -L "$path" ]; then
    mv "$bak" "$path"
    info "restored: $bak -> $path"
  fi
}

uninstall_link() {
  local path="$1" free=0
  if [ -L "$path" ] && points_into_repo "$(readlink "$path" 2>/dev/null || true)"; then
    free=1
    if [ "$MODE" = plan ]; then
      plan_add "unlink $path"
    else
      rm "$path"
      info "unlinked: $path"
    fi
  elif [ -e "$path" ] || [ -L "$path" ]; then
    if [ "$MODE" = plan ]; then plan_note "keep $path (not a link into this repo; not removed)"; fi
  else
    free=1
  fi
  if [ "$free" = 1 ]; then restore_backup "$path"; fi
}

uninstall_settings() {
  local live="$HOME/.claude/settings.json"
  local target="" free=0 bak tmp
  bak="$(newest_backup "$live")"
  if [ -L "$live" ] && points_into_repo "$(readlink "$live" 2>/dev/null || true)"; then
    target="$(readlink "$live")"
    if [ -n "$bak" ] || [ ! -f "$target" ]; then
      free=1
      if [ "$MODE" = plan ]; then
        plan_add "unlink $live"
      else
        rm "$live"
        info "unlinked: $live"
      fi
    elif [ "$MODE" = plan ]; then
      plan_add "replace $live with a copy of $target (no backup to restore)"
    else
      tmp="$(mktemp "$HOME/.claude/.settings.XXXXXX")"
      TMP_FILES+=("$tmp")
      cp "$target" "$tmp"
      mv -f "$tmp" "$live"
      info "replaced: $live with a copy of $target"
    fi
  elif [ -e "$live" ] || [ -L "$live" ]; then
    if [ "$MODE" = plan ]; then plan_note "keep $live (your settings file; not removed)"; fi
  fi
  if [ "$free" = 1 ]; then restore_backup "$live"; fi
}

uninstall_all() {
  step "Removing links"
  uninstall_link "$HOME/.claude/AGENTS.md"
  uninstall_link "$HOME/.claude/CLAUDE.md"
  uninstall_link "$HOME/.claude/agents"
  uninstall_link "$HOME/.claude/hooks"
  uninstall_link "$HOME/.tmux.conf"
  uninstall_settings
  if [ "$MODE" = plan ]; then
    plan_note "Skills under $HOME/.claude/skills are left in place; remove with: npx skills remove -g <name>"
  fi
}

settings_sums() {
  printf '%s|%s' "$(fingerprint "$HOME/.claude/settings.json")" \
    "$(fingerprint "$REPO_DIR/claude/settings.json")"
}

# run <function>: plan pass first, then confirmation when needed, then the apply pass.
run() {
  MODE=plan
  PLAN_SUMS="$(settings_sums)"
  "$1"
  if [ "$DRY_RUN" = 1 ] || [ "$NEEDS_CONFIRM" -gt 0 ] || [ "$UNINSTALL" = 1 ]; then print_plan; fi
  if [ "$DRY_RUN" = 1 ]; then finish 0; fi
  if [ "$UNINSTALL" = 1 ] && [ "$NEEDS_CONFIRM" -eq 0 ]; then
    info "Nothing to uninstall."
    finish 0
  fi
  if [ "$NEEDS_CONFIRM" -gt 0 ]; then confirm; fi
  if [ "$(settings_sums)" != "$PLAN_SUMS" ]; then
    warn "settings changed since the plan was shown; rerun install.sh"
    exit 1
  fi
  MODE=apply
  "$1"
}

banner

if [ "$UNINSTALL" = 1 ]; then
  run uninstall_all
  info "Done."
  finish 0
fi

check_settings_inputs
run install_all

if [ "$FAILED" = 1 ]; then
  warn "finished with errors: some skills failed to install"
  exit 1
fi
COMPLETED=1
info "Done."
echo
echo "Reminders:"
echo "  - Authenticate each tool on this machine manually (credentials are not synced)."
echo "  - To add a third-party skill: npx skills add <owner/repo> -s <name> -g -a claude-code -y, then add its entry to skills-lock.json."
echo "  - To update third-party skills: re-run ./install.sh to reinstall the latest upstream versions."
