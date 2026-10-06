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
# Usage: ./install.sh [--clean] [--no-skills]
#   --clean      also remove skills under ~/.claude/skills that are not part of
#                this repo (leftovers from previous installs or removed skills)
#   --no-skills  skip the skills CLI step (no network access)

set -euo pipefail

REPO_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
BACKUP_SUFFIX=".bak.$(date +%Y%m%d%H%M%S)"
LOCAL_DIR="${CLAUDE_CONFIG_LOCAL_DIR:-$REPO_DIR/local}"

info()  { printf '\033[1;34m==>\033[0m %s\n' "$*"; }
warn()  { printf '\033[1;33mwarn:\033[0m %s\n' "$*"; }

TMP_FILES=()
cleanup() {
  if [ "${#TMP_FILES[@]}" -gt 0 ]; then rm -f "${TMP_FILES[@]}"; fi
}
trap cleanup EXIT
trap 'exit 1' INT TERM HUP

command -v jq >/dev/null || { warn "jq is required"; exit 1; }

CLEAN=0
NO_SKILLS=0
for arg in "$@"; do
  case "$arg" in
    --clean) CLEAN=1 ;;
    --no-skills) NO_SKILLS=1 ;;
    *) warn "unknown argument: $arg"; echo "Usage: ./install.sh [--clean] [--no-skills]" >&2; exit 1 ;;
  esac
done

# link <source-in-repo> <target-path>
# Backs up an existing real file/dir/foreign symlink at target, then symlinks to repo.
link() {
  local src="$1" dst="$2" target

  if [ ! -e "$src" ]; then
    warn "skipping $dst - $src does not exist in repo"
    return 0
  fi

  mkdir -p "$(dirname "$dst")"

  # Already correctly linked? Nothing to do.
  if [ -L "$dst" ] && [ "$(readlink "$dst")" = "$src" ]; then
    info "ok: $dst"
    return 0
  fi

  # A symlink into this repo carries no user data, so it is replaced without a backup.
  target="$(readlink "$dst" 2>/dev/null || true)"
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

generate_settings() {
  local defaults="$REPO_DIR/claude/settings.json"
  local overlay="$LOCAL_DIR/settings.json"
  local live="$HOME/.claude/settings.json"
  local snapshot="$HOME/.claude/settings.generated.json"
  local overlay_src=/dev/null use_overlay adopt_base="" has_snapshot=0 backup=0 same=0
  local merged new_overlay="" snap_tmp live_sum removed="" p
  mkdir -p "$HOME/.claude"
  live_sum="$(fingerprint "$live")"
  [ ! -f "$overlay" ] || overlay_src="$overlay"
  use_overlay="$overlay_src"
  if [ -f "$snapshot" ]; then
    if jq -e 'type == "object"' "$snapshot" >/dev/null 2>&1; then
      has_snapshot=1
    else
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
  if [ -n "$adopt_base" ]; then
    mkdir -p "$LOCAL_DIR"
    new_overlay="$(mktemp "$LOCAL_DIR/.settings.XXXXXX")"
    TMP_FILES+=("$new_overlay")
    adopt_into_overlay "$live" "$adopt_base" "$defaults" "$overlay_src" > "$new_overlay" \
      || { warn "could not adopt $live into the overlay; nothing was changed"; exit 1; }
    if jq -e '. == {}' "$new_overlay" >/dev/null && [ ! -f "$overlay" ]; then
      new_overlay=""
    else
      use_overlay="$new_overlay"
    fi
    if [ "$adopt_base" = "$snapshot" ]; then
      removed="$(removed_messages "$live" "$snapshot" "$overlay")" \
        || { warn "could not compare $live with its snapshot; nothing was changed"; exit 1; }
    fi
  fi
  # Temp files live in ~/.claude so each mv below is an atomic same-filesystem rename.
  merged="$(mktemp "$HOME/.claude/.settings.XXXXXX")"
  TMP_FILES+=("$merged")
  merge_settings "$defaults" "$use_overlay" > "$merged" \
    || { warn "could not merge $defaults with $overlay; nothing was changed"; exit 1; }
  snap_tmp="$(mktemp "$HOME/.claude/.settings.XXXXXX")"
  TMP_FILES+=("$snap_tmp")
  cp "$merged" "$snap_tmp"
  if [ ! -L "$live" ] && [ -f "$live" ] && json_equal "$live" "$merged"; then
    same=1
    backup=0
  fi
  if [ "$(fingerprint "$live")" != "$live_sum" ]; then
    warn "$live changed while install.sh was running; nothing was written - close running Claude Code sessions and rerun"
    exit 1
  fi
  if [ -n "$new_overlay" ] && ! json_equal "$new_overlay" "$overlay_src"; then
    if [ "$adopt_base" = "$defaults" ] && [ "$overlay_src" = /dev/null ]; then
      info "seeded $overlay from the existing $live"
    else
      adopted_paths "$overlay_src" "$new_overlay" | while read -r p; do
        info "adopted into $overlay: $p"
      done
    fi
    mv "$new_overlay" "$overlay"
  fi
  if [ -n "$removed" ]; then
    printf '%s\n' "$removed" | while IFS= read -r p; do
      warn "$p"
    done
  fi
  if [ "$same" = 1 ]; then
    info "ok: $live"
  else
    if [ "$backup" = 1 ]; then
      warn "backing up existing $live -> ${live}${BACKUP_SUFFIX}"
      mv "$live" "${live}${BACKUP_SUFFIX}"
    elif [ -L "$live" ]; then
      warn "replacing symlink $live with a generated file"
    fi
    mv -f "$merged" "$live"
    info "generated: $live"
  fi
  mv "$snap_tmp" "$snapshot"
}

link_personal_instructions() {
  local src="$LOCAL_DIR/CLAUDE.md" dst="$HOME/.claude/CLAUDE.local.md"
  if [ -f "$src" ]; then
    link "$src" "$dst"
  elif [ -L "$dst" ] && [ ! -e "$dst" ]; then
    warn "removing dangling link: $dst"
    rm "$dst"
  fi
}

check_settings_inputs

# ---------------------------------------------------------------------------
# 1. Claude shared instructions: symlink AGENTS.md next to CLAUDE.md, which
#    imports it via "@~/.claude/AGENTS.md" (home-anchored: a relative import
#    would resolve against CLAUDE.md's realpath and break)
# ---------------------------------------------------------------------------
info "Linking shared instructions for Claude Code"
link "$REPO_DIR/claude/AGENTS.md" "$HOME/.claude/AGENTS.md"

# ---------------------------------------------------------------------------
# 2. Config symlinks (Claude Code)
# ---------------------------------------------------------------------------
info "Linking Claude Code config"
# Links this script no longer creates - remove them if they still point into this repo.
for retired in "$HOME/.claude/commands" "$HOME/.claude/statusline" "$HOME/.claude/mods"; do
  target="$(readlink "$retired" 2>/dev/null || true)"
  if [ -L "$retired" ] && [ "${target#"$REPO_DIR"/}" != "$target" ]; then
    warn "removing retired link: $retired"
    rm "$retired"
  fi
done
generate_settings
link "$REPO_DIR/claude/CLAUDE.md"     "$HOME/.claude/CLAUDE.md"
link_personal_instructions
link "$REPO_DIR/agents"               "$HOME/.claude/agents"
# Agent frontmatter references hooks by absolute path ($HOME/.claude/hooks/...),
# so they must resolve on every machine, not just inside this repo.
link "$REPO_DIR/hooks"                "$HOME/.claude/hooks"
link "$REPO_DIR/tmux/tmux.conf"       "$HOME/.tmux.conf"
chmod +x "$REPO_DIR"/hooks/*.sh 2>/dev/null || true

# ---------------------------------------------------------------------------
# 3. Install skills globally: this repo's own (skills/) and the third-party
#    skills listed in skills-lock.json, each from its upstream repo
# ---------------------------------------------------------------------------
if [ "$NO_SKILLS" = 1 ]; then
  info "Skipping skills (--no-skills)"
else
  info "Installing skills globally via skills CLI"
  cd "$REPO_DIR"
  # Target only agents that support global installs - the default "all detected
  # agents" includes project-scope-only targets (e.g. PromptScript), which emit
  # a spurious "does not support global skill installation" error per skill.
  if compgen -G "skills/*/SKILL.md" > /dev/null; then
    npx -y skills add ./skills -g -a claude-code -y
  fi
  manifest="$(jq -r '.skills | to_entries | group_by(.value.source)[] | "\(.[0].value.source) \(map(.key) | join(" "))"' "$REPO_DIR/skills-lock.json")"
  # The skills CLI reads stdin, which would otherwise be the manifest.
  while read -r source names; do
    args=()
    for name in $names; do args+=(-s "$name"); done
    npx -y skills add "$source" "${args[@]}" -g -a claude-code -y < /dev/null
  done <<< "$manifest"
fi

# ---------------------------------------------------------------------------
# 4. --clean: remove installed skills that this repo does not provide
#    (the skills CLI copies rather than symlinks, so skills deleted from the
#    repo - or installed by other means - linger in ~/.claude/skills forever)
# ---------------------------------------------------------------------------
if [ "$CLEAN" = 1 ]; then
  info "Removing skills not provided by this repo from $HOME/.claude/skills"
  removed=0
  for installed in "$HOME/.claude/skills"/*/; do
    [ -d "$installed" ] || continue
    name="$(basename "$installed")"
    # Claude Code owns ~/.claude/skills/synced (claude.ai skill sync) and .trash.
    case "$name" in synced|.trash) continue ;; esac
    if [ ! -f "$REPO_DIR/skills/$name/SKILL.md" ] \
      && ! jq -e --arg n "$name" '.skills[$n]' "$REPO_DIR/skills-lock.json" >/dev/null; then
      warn "removing stale skill: $name"
      rm -rf "$installed"
      removed=1
    fi
  done
  [ "$removed" = 0 ] && info "ok: no stale skills"
fi

info "Done."
echo
echo "Reminders:"
echo "  - Authenticate each tool on this machine manually (credentials are not synced)."
echo "  - To add a third-party skill: npx skills add <owner/repo> -s <name> -g -a claude-code -y, then add its entry to skills-lock.json."
echo "  - To update third-party skills: npx skills update -g"
