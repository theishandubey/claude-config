#!/usr/bin/env bash
#
# agent-config bootstrap
#
# - Symlinks Claude Code configs into place
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
LOCAL_DIR="${CLAUDE_CONFIG_LOCAL_DIR:-$REPO_DIR/local}"

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
generates ~/.claude/settings.json from claude/settings.json plus local/settings.json,
and installs the skills listed in skills/ and skills-lock.json.

  --dry-run    print the planned changes and exit without touching anything
  --yes, -y    do not ask for confirmation; needed when stdin is not a terminal and the run
               would back up or remove something this repo does not own (backups, --clean,
               --uninstall)
  --no-skills  skip the skills CLI (no network)
  --clean      also remove ~/.claude/skills entries this repo does not provide
  --uninstall  remove the links and generated settings, restoring the newest backups
  --help, -h   show this help

Environment: CLAUDE_CONFIG_LOCAL_DIR overrides the overlay directory (default: <repo>/local).
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
    if [ -L "$dst" ] && [ "${target#"$REPO_DIR"/}" != "$target" ]; then
      :
    elif [ -e "$dst" ] || [ -L "$dst" ]; then
      plan_add "backup $dst -> ${dst}${BACKUP_SUFFIX}"
    fi
    plan_sync "link $dst -> $src"
    return 0
  fi

  mkdir -p "$(dirname "$dst")"
  if [ -L "$dst" ] && [ "${target#"$REPO_DIR"/}" != "$target" ]; then
    rm "$dst"
  elif [ -e "$dst" ] || [ -L "$dst" ]; then
    warn "backing up existing $dst -> ${dst}${BACKUP_SUFFIX}"
    mv "$dst" "${dst}${BACKUP_SUFFIX}"
  fi

  ln -s "$src" "$dst"
  info "linked: $dst -> $src"
}

JQ_LIB='
def merge($a; $b):
  if ($a | type) == "object" and ($b | type) == "object" then
    reduce ($b | keys_unsorted[]) as $k ($a;
      if $b[$k] == null and ($a | has($k) | not) then .
      else .[$k] = merge($a[$k]; $b[$k]) end)
  elif ($b | type) == "object" then merge({}; $b)
  elif ($a | type) == "array" and ($b | type) == "array" then $a + ($b - $a)
  elif $b == null then $a
  else $b end;

def adopt($o; $l; $b; $d):
  if $l == $b then $o
  elif ($l | type) == "object" and ($b | type) == "object" then
    reduce ($l | keys_unsorted[]) as $k ($o | if type == "object" then . else {} end;
      if $l[$k] == $b[$k] then .
      else
        adopt(.[$k]; $l[$k]; $b[$k]; ($d | if type == "object" then .[$k] else null end)) as $v
        | if $v == null or ($v == {} and .[$k] == null) then . else .[$k] = $v end
      end)
  elif ($l | type) == "array" and ($d | type) == "array" then
    ($o | if type == "array" then . else [] end) as $oa
    | ($b | if type == "array" then . else [] end) as $ba
    | ((($l - $ba) - $d) - $oa) as $new
    | if ($new | length) == 0 then $o else $oa + $new end
  else $l end;

def lost($l; $b; $p):
  if ($b | type) == "object" then
    if ($l | type) == "object" then
      ($b | keys_unsorted[]) as $k | lost($l[$k]; $b[$k]; $p + [$k])
    elif $l == null then {path: $p}
    else empty end
  elif $l == null then {path: $p}
  elif ($b | type) == "array" and ($l | type) == "array" then
    ($b - $l) | select(length > 0) | {path: $p, elements: .}
  else empty end;
'

json_equal() {
  jq -en --slurpfile a "$1" --slurpfile b "$2" '$a == $b' >/dev/null 2>&1
}

fingerprint() {
  if [ -e "$1" ]; then cksum < "$1"; fi
}

is_repo_settings_link() {
  [ -L "$1" ] && [ "$(readlink "$1")" = "$REPO_DIR/claude/settings.json" ]
}

merge_settings() {
  jq -n --slurpfile d "$1" --slurpfile o "$2" "$JQ_LIB"'merge($d[0]; $o[0])'
}

adopt_into_overlay() {
  jq -n --slurpfile o "$4" --slurpfile l "$1" --slurpfile b "$2" --slurpfile d "$3" "$JQ_LIB"'
    adopt($o[0] // {}; $l[0]; $b[0]; $d[0])'
}

adopted_paths() {
  jq -nr --slurpfile o "$1" --slurpfile n "$2" '
    $n[0] | paths(type != "object") | select(all(.[]; type == "string"))
    | select(. as $p | (($o[0] // {}) | try getpath($p) catch null) != ($n[0] | getpath($p)))
    | join(".")'
}

removed_messages() {
  jq -nr --arg live "$1" --arg overlay "$3" --slurpfile l "$1" --slurpfile b "$2" "$JQ_LIB"'
    lost($l[0]; $b[0]; [])
    | (.path | join(".")) as $p
    | if .elements then
        "\($p): removing array elements through write-back is not supported; restored: \(.elements | tojson)"
      else
        "\($p) was removed from \($live); it is restored from the defaults or the overlay (removing a committed default key is not supported - edit \($overlay) to override its value instead)"
      end'
}

check_settings_inputs() {
  local defaults="$REPO_DIR/claude/settings.json"
  local overlay="$LOCAL_DIR/settings.json"
  local live="$HOME/.claude/settings.json"
  if ! jq -e 'type == "object"' "$defaults" >/dev/null 2>&1; then
    warn "$defaults is not a valid JSON object; nothing was changed"
    exit 1
  fi
  if [ -f "$overlay" ] && ! jq -e 'type == "object"' "$overlay" >/dev/null 2>&1; then
    warn "$overlay is not a valid JSON object; fix or remove it; nothing was changed"
    exit 1
  fi
  if is_repo_settings_link "$live"; then
    if [ ! -f "$overlay" ] && [ "${CLAUDE_CONFIG_NO_OVERLAY:-}" != 1 ]; then
      warn "no personal overlay found at $overlay; copy your local/ from another machine or start from local.example/, or rerun with CLAUDE_CONFIG_NO_OVERLAY=1 to install defaults only; nothing was changed"
      exit 1
    fi
  elif [ -e "$live" ] && ! jq -e 'type == "object"' "$live" >/dev/null 2>&1; then
    warn "$live is not a valid JSON object; fix or remove it; nothing was changed"
    exit 1
  fi
}

# Sets has_snapshot, adopt_base and backup in the calling function's scope.
settings_state() {
  has_snapshot=0
  adopt_base=""
  backup=0
  if [ -f "$snapshot" ]; then
    if jq -e 'type == "object"' "$snapshot" >/dev/null 2>&1; then
      has_snapshot=1
    elif [ "$MODE" = apply ]; then
      warn "ignoring unreadable $snapshot"
    fi
  fi
  if is_repo_settings_link "$live"; then
    :
  elif [ -e "$live" ]; then
    if [ "$has_snapshot" = 1 ]; then
      json_equal "$live" "$snapshot" || adopt_base="$snapshot"
    else
      backup=1
      adopt_base="$defaults"
    fi
    [ ! -L "$live" ] || backup=1
  elif [ -L "$live" ]; then
    backup=1
  fi
}

# Computes everything generate_settings needs without writing anything; results go to S_* globals.
compute_settings() {
  local defaults="$REPO_DIR/claude/settings.json"
  local overlay="$LOCAL_DIR/settings.json"
  local live="$HOME/.claude/settings.json"
  local snapshot="$HOME/.claude/settings.generated.json"
  local overlay_src=/dev/null adopt_base="" has_snapshot=0 backup=0 same=0
  [ ! -f "$overlay" ] || overlay_src="$overlay"
  S_NEW_OVERLAY=""
  S_REMOVED=""
  S_ADOPT_PATHS=""
  S_SEEDED=0
  S_OVERLAY_CHANGED=0
  S_REFRESH=0
  settings_state
  if [ -n "$adopt_base" ]; then
    S_NEW_OVERLAY="$(adopt_into_overlay "$live" "$adopt_base" "$defaults" "$overlay_src")" \
      || { warn "could not adopt $live into the overlay; nothing was changed"; exit 1; }
    if printf '%s\n' "$S_NEW_OVERLAY" | jq -e '. == {}' >/dev/null && [ ! -f "$overlay" ]; then
      S_NEW_OVERLAY=""
    fi
    if [ "$adopt_base" = "$snapshot" ]; then
      S_REMOVED="$(removed_messages "$live" "$snapshot" "$overlay")" \
        || { warn "could not compare $live with its snapshot; nothing was changed"; exit 1; }
    fi
  fi
  if [ -n "$S_NEW_OVERLAY" ]; then
    S_MERGED="$(merge_settings "$defaults" <(printf '%s\n' "$S_NEW_OVERLAY"))" \
      || { warn "could not merge $defaults with $overlay; nothing was changed"; exit 1; }
  else
    S_MERGED="$(merge_settings "$defaults" "$overlay_src")" \
      || { warn "could not merge $defaults with $overlay; nothing was changed"; exit 1; }
  fi
  if [ ! -L "$live" ] && [ -f "$live" ] && json_equal "$live" <(printf '%s\n' "$S_MERGED"); then
    same=1
    backup=0
  fi
  if [ -n "$S_NEW_OVERLAY" ] && ! json_equal <(printf '%s\n' "$S_NEW_OVERLAY") "$overlay_src"; then
    S_OVERLAY_CHANGED=1
    S_ADOPT_PATHS="$(adopted_paths "$overlay_src" <(printf '%s\n' "$S_NEW_OVERLAY"))"
    if [ "$adopt_base" = "$defaults" ] && [ "$overlay_src" = /dev/null ]; then S_SEEDED=1; fi
  fi
  if [ "$same" = 1 ]; then
    if [ "$has_snapshot" = 0 ] || ! json_equal "$snapshot" <(printf '%s\n' "$S_MERGED"); then
      S_REFRESH=1
    fi
  fi
  S_SAME=$same
  S_BACKUP=$backup
}

generate_settings() {
  local overlay="$LOCAL_DIR/settings.json"
  local live="$HOME/.claude/settings.json"
  local snapshot="$HOME/.claude/settings.generated.json"
  local merged="" new_overlay="" snap_tmp="" live_sum p
  if [ "$MODE" = plan ]; then
    compute_settings
    if [ "$S_SEEDED" = 1 ]; then
      plan_sync "seed $overlay from $live"
    else
      while IFS= read -r p; do
        if [ -n "$p" ]; then plan_sync "adopt $p -> $overlay"; fi
      done < <(printf '%s\n' "$S_ADOPT_PATHS")
    fi
    if [ "$S_SAME" = 1 ]; then
      plan_ok "$live"
      if [ "$S_REFRESH" = 1 ]; then plan_note "ok: $snapshot (refresh snapshot)"; fi
    else
      if [ "$S_BACKUP" = 1 ]; then plan_add "backup $live -> ${live}${BACKUP_SUFFIX}"; fi
      plan_sync "generate $live"
    fi
    return 0
  fi
  mkdir -p "$HOME/.claude"
  live_sum="$(fingerprint "$live")"
  compute_settings
  if [ "$S_OVERLAY_CHANGED" = 1 ]; then
    mkdir -p "$LOCAL_DIR"
    new_overlay="$(mktemp "$LOCAL_DIR/.settings.XXXXXX")"
    TMP_FILES+=("$new_overlay")
    printf '%s\n' "$S_NEW_OVERLAY" > "$new_overlay"
  fi
  # Temp files live in ~/.claude so each mv below is an atomic same-filesystem rename.
  # A run with nothing to write creates none, so ~/.claude is not touched at all.
  if [ "$S_SAME" != 1 ]; then
    merged="$(mktemp "$HOME/.claude/.settings.XXXXXX")"
    TMP_FILES+=("$merged")
    printf '%s\n' "$S_MERGED" > "$merged"
  fi
  if [ "$S_SAME" != 1 ] || [ "$S_REFRESH" = 1 ]; then
    snap_tmp="$(mktemp "$HOME/.claude/.settings.XXXXXX")"
    TMP_FILES+=("$snap_tmp")
    printf '%s\n' "$S_MERGED" > "$snap_tmp"
  fi
  if [ "$(fingerprint "$live")" != "$live_sum" ]; then
    warn "$live changed while install.sh was running; nothing was written - close running Claude Code sessions and rerun"
    exit 1
  fi
  if [ -n "$new_overlay" ]; then
    if [ "$S_SEEDED" = 1 ]; then
      info "seeded $overlay from the existing $live"
    else
      while IFS= read -r p; do
        if [ -n "$p" ]; then info "adopted into $overlay: $p"; fi
      done < <(printf '%s\n' "$S_ADOPT_PATHS")
    fi
    mv "$new_overlay" "$overlay"
  fi
  if [ -n "$S_REMOVED" ]; then
    while IFS= read -r p; do
      warn "$p"
    done < <(printf '%s\n' "$S_REMOVED")
  fi
  if [ "$S_SAME" = 1 ]; then
    info "ok: $live"
  else
    if [ "$S_BACKUP" = 1 ]; then
      warn "backing up existing $live -> ${live}${BACKUP_SUFFIX}"
      mv "$live" "${live}${BACKUP_SUFFIX}"
    elif [ -L "$live" ]; then
      warn "replacing symlink $live with a generated file"
    fi
    mv -f "$merged" "$live"
    info "generated: $live"
  fi
  if [ -n "$snap_tmp" ]; then mv "$snap_tmp" "$snapshot"; fi
}

link_personal_instructions() {
  local src="$LOCAL_DIR/CLAUDE.md" dst="$HOME/.claude/CLAUDE.local.md"
  if [ -f "$src" ]; then
    link "$src" "$dst"
  elif [ -L "$dst" ] && [ ! -e "$dst" ]; then
    if [ "$MODE" = plan ]; then
      plan_sync "remove dangling link $dst"
    else
      warn "removing dangling link: $dst"
      rm "$dst"
    fi
  fi
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
  link_personal_instructions
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
  [ "${1#"$REPO_DIR"/}" != "$1" ] || [ "${1#"$LOCAL_DIR"/}" != "$1" ]
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
  local snapshot="$HOME/.claude/settings.generated.json"
  local has_snap=0 free=0 target="" bak tmp
  if [ -f "$snapshot" ] && [ ! -L "$snapshot" ]; then has_snap=1; fi
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
  elif [ "$has_snap" = 1 ]; then
    if [ ! -e "$live" ] && [ ! -L "$live" ]; then
      free=1
    elif [ -f "$live" ] && [ ! -L "$live" ] && json_equal "$live" "$snapshot"; then
      if [ -n "$bak" ]; then
        free=1
        if [ "$MODE" = plan ]; then
          plan_add "remove $live"
        else
          rm "$live"
          info "removed: $live"
        fi
      elif [ "$MODE" = plan ]; then
        plan_note "keep $live (no backup to restore; left as an unmanaged file)"
      fi
    elif [ "$MODE" = plan ]; then
      plan_note "keep $live (edited since generation; not removed)"
    fi
  fi
  if [ "$has_snap" = 1 ]; then
    if [ "$MODE" = plan ]; then
      plan_add "remove $snapshot"
    else
      rm "$snapshot"
      info "removed: $snapshot"
    fi
  fi
  if [ "$free" = 1 ]; then restore_backup "$live"; fi
}

uninstall_all() {
  step "Removing links and generated settings"
  uninstall_link "$HOME/.claude/AGENTS.md"
  uninstall_link "$HOME/.claude/CLAUDE.md"
  uninstall_link "$HOME/.claude/CLAUDE.local.md"
  uninstall_link "$HOME/.claude/agents"
  uninstall_link "$HOME/.claude/hooks"
  uninstall_link "$HOME/.tmux.conf"
  uninstall_settings
  if [ "$MODE" = plan ]; then
    plan_note "Skills under $HOME/.claude/skills are left in place; remove with: npx skills remove -g <name>"
  fi
}

settings_sums() {
  printf '%s|%s|%s|%s' "$(fingerprint "$HOME/.claude/settings.json")" \
    "$(fingerprint "$LOCAL_DIR/settings.json")" \
    "$(fingerprint "$HOME/.claude/settings.generated.json")" \
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
