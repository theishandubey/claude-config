#!/usr/bin/env bash
#
# agent-config bootstrap
#
# - Symlinks Claude Code configs into place
# - Installs all skills in this repo (own + vendored) globally via skills CLI
#
# Idempotent - re-run after every git pull.
#
# Usage: ./install.sh [--clean]
#   --clean  also remove skills under ~/.claude/skills that are not part of
#            this repo (leftovers from previous installs or removed skills)

set -euo pipefail

REPO_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
BACKUP_SUFFIX=".bak.$(date +%Y%m%d%H%M%S)"
LOCAL_DIR="${CLAUDE_CONFIG_LOCAL_DIR:-$REPO_DIR/local}"

info()  { printf '\033[1;34m==>\033[0m %s\n' "$*"; }
warn()  { printf '\033[1;33mwarn:\033[0m %s\n' "$*"; }

CLEAN=0
for arg in "$@"; do
  case "$arg" in
    --clean) CLEAN=1 ;;
    *) warn "unknown argument: $arg"; echo "Usage: ./install.sh [--clean]" >&2; exit 1 ;;
  esac
done

# link <source-in-repo> <target-path>
# Backs up an existing real file/dir at target, then symlinks to repo.
link() {
  local src="$1" dst="$2"

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

  # Existing file/dir/wrong symlink - back it up.
  if [ -e "$dst" ] || [ -L "$dst" ]; then
    warn "backing up existing $dst -> ${dst}${BACKUP_SUFFIX}"
    mv "$dst" "${dst}${BACKUP_SUFFIX}"
  fi

  ln -s "$src" "$dst"
  info "linked: $dst -> $src"
}

json_equal() {
  diff -q <(jq -S . "$1") <(jq -S . "$2") >/dev/null 2>&1
}

merge_settings() {
  jq -n --slurpfile d "$1" --slurpfile o "$2" '
    def merge(a; b):
      if (a | type) == "object" and (b | type) == "object" then
        reduce (b | keys_unsorted[]) as $k (a; .[$k] = merge(a[$k]; b[$k]))
      elif (a | type) == "array" and (b | type) == "array" then a + (b - a)
      elif b == null then a
      else b end;
    merge($d[0]; $o[0])'
}

leaf_paths() {
  jq -c 'paths(type != "object") | select(all(.[]; type == "string"))' "$1"
}

adopt_drift() {
  local live="$1" snapshot="$2" overlay="$3" adopted removed
  adopted="$(jq -n --slurpfile l "$live" --slurpfile g "$snapshot" '
    [ $l[0] | paths(type != "object") | select(all(.[]; type == "string"))
      | select(. as $p | ($l[0] | getpath($p)) != ($g[0] | getpath($p))) ]')"
  removed="$(jq -n --slurpfile l "$live" --slurpfile g "$snapshot" '
    [ $g[0] | paths(type != "object") | select(all(.[]; type == "string"))
      | select(. as $p | ($l[0] | getpath($p)) == null) ]')"
  if [ "$(printf '%s' "$adopted" | jq 'length')" -gt 0 ]; then
    mkdir -p "$(dirname "$overlay")"
    [ -f "$overlay" ] || printf '{}\n' > "$overlay"
    jq --slurpfile l "$live" --argjson paths "$adopted" '
      reduce $paths[] as $p (.; setpath($p; $l[0] | getpath($p)))' "$overlay" > "$overlay.tmp"
    mv "$overlay.tmp" "$overlay"
    printf '%s' "$adopted" | jq -r '.[] | join(".")' | while read -r p; do
      info "adopted into $overlay: $p"
    done
  fi
  if [ "$(printf '%s' "$removed" | jq 'length')" -gt 0 ]; then
    printf '%s' "$removed" | jq -r '.[] | join(".")' | while read -r p; do
      warn "$p was removed from $live since the last run; the committed default is restored (remove it from $overlay too if that was intended)"
    done
  fi
}

generate_settings() {
  local defaults="$REPO_DIR/claude/settings.json"
  local overlay="$LOCAL_DIR/settings.json"
  local live="$HOME/.claude/settings.json"
  local snapshot="$HOME/.claude/settings.generated.json"
  local empty merged
  mkdir -p "$HOME/.claude"
  if [ -L "$live" ]; then
    warn "replacing symlink $live with a generated file"
    rm "$live"
  elif [ -f "$live" ] && [ ! -f "$snapshot" ]; then
    if [ ! -f "$overlay" ]; then
      mkdir -p "$LOCAL_DIR"
      cp "$live" "$overlay"
      info "seeded $overlay from the existing $live"
    fi
    warn "backing up existing $live -> ${live}${BACKUP_SUFFIX}"
    mv "$live" "${live}${BACKUP_SUFFIX}"
  elif [ -f "$live" ] && [ -f "$snapshot" ] && ! json_equal "$live" "$snapshot"; then
    adopt_drift "$live" "$snapshot" "$overlay"
  fi
  empty="$(mktemp)"
  printf '{}\n' > "$empty"
  merged="$(mktemp)"
  if [ -f "$overlay" ]; then
    merge_settings "$defaults" "$overlay" > "$merged"
  else
    merge_settings "$defaults" "$empty" > "$merged"
  fi
  if [ -f "$live" ] && json_equal "$live" "$merged"; then
    info "ok: $live"
  else
    mv "$merged" "$live"
    info "generated: $live"
  fi
  cp "$live" "$snapshot"
  rm -f "$empty" "$merged"
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

# ---------------------------------------------------------------------------
# 1. Repo-internal symlink: expose vendored skills to Claude Code project scope
#    (.claude/skills -> ../.agents/skills, relative so it survives git clone)
# ---------------------------------------------------------------------------
info "Setting up repo-internal symlinks"
mkdir -p "$REPO_DIR/.agents/skills" "$REPO_DIR/.claude"
if [ ! -L "$REPO_DIR/.claude/skills" ]; then
  if [ -e "$REPO_DIR/.claude/skills" ]; then
    warn "backing up $REPO_DIR/.claude/skills"
    mv "$REPO_DIR/.claude/skills" "$REPO_DIR/.claude/skills${BACKUP_SUFFIX}"
  fi
  ln -s ../.agents/skills "$REPO_DIR/.claude/skills"
  info "linked: .claude/skills -> ../.agents/skills"
else
  info "ok: .claude/skills"
fi

# ---------------------------------------------------------------------------
# 2. Claude shared instructions: symlink AGENTS.md next to CLAUDE.md, which
#    imports it via "@~/.claude/AGENTS.md" (home-anchored: a relative import
#    would resolve against CLAUDE.md's realpath and break)
# ---------------------------------------------------------------------------
info "Linking shared instructions for Claude Code"
link "$REPO_DIR/claude/AGENTS.md" "$HOME/.claude/AGENTS.md"

# ---------------------------------------------------------------------------
# 3. Config symlinks (Claude Code)
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
# 4. Install all skills in this repo globally, to all detected agents
#    Discovers both skills/ (own) and .agents/skills/ (vendored)
# ---------------------------------------------------------------------------
info "Installing skills globally via skills CLI"
cd "$REPO_DIR"
# Point at each skills dir explicitly: a bare "./" scan does not descend into
# the hidden .agents/ directory, so vendored skills would be missed.
# Target only agents that support global installs - the default "all detected
# agents" includes project-scope-only targets (e.g. PromptScript), which emit
# a spurious "does not support global skill installation" error per skill.
for skills_dir in skills .agents/skills; do
  if compgen -G "$skills_dir/*/SKILL.md" > /dev/null; then
    npx skills add "./$skills_dir" -g -a claude-code -y
  else
    info "no skills in $skills_dir/ - skipping"
  fi
done

# ---------------------------------------------------------------------------
# 5. --clean: remove installed skills that this repo does not provide
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
    if [ ! -f "$REPO_DIR/skills/$name/SKILL.md" ] && [ ! -f "$REPO_DIR/.agents/skills/$name/SKILL.md" ]; then
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
echo "  - To vendor a new third-party skill:"
echo "      npx skills add <owner/repo> --skill <name> --copy -a claude-code -y && git add .agents && git commit"
echo "  - To update vendored skills: npx skills update -p, review diff, commit."
