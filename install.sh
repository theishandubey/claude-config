#!/usr/bin/env bash
#
# agent-config bootstrap
#
# - Symlinks Claude Code configs into place
# - Installs all skills in this repo (own + vendored) globally via skills CLI
#
# Idempotent - re-run after every git pull.
#
# Usage: ./install.sh

set -euo pipefail

REPO_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
BACKUP_SUFFIX=".bak.$(date +%Y%m%d%H%M%S)"

info()  { printf '\033[1;34m==>\033[0m %s\n' "$*"; }
warn()  { printf '\033[1;33mwarn:\033[0m %s\n' "$*"; }

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
link "$REPO_DIR/AGENTS.md" "$HOME/.claude/AGENTS.md"

# ---------------------------------------------------------------------------
# 3. Config symlinks (Claude Code)
# ---------------------------------------------------------------------------
info "Linking Claude Code config"
link "$REPO_DIR/claude/settings.json" "$HOME/.claude/settings.json"
link "$REPO_DIR/claude/CLAUDE.md"     "$HOME/.claude/CLAUDE.md"
link "$REPO_DIR/claude/commands"      "$HOME/.claude/commands"
link "$REPO_DIR/agents"               "$HOME/.claude/agents"
# Agent frontmatter references hooks by absolute path ($HOME/.claude/hooks/...),
# so they must resolve on every machine, not just inside this repo.
link "$REPO_DIR/hooks"                "$HOME/.claude/hooks"
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

info "Done."
echo
echo "Reminders:"
echo "  - Authenticate each tool on this machine manually (credentials are not synced)."
echo "  - To vendor a new third-party skill:"
echo "      npx skills add <owner/repo> --skill <name> --copy -a claude-code -y && git add .agents && git commit"
echo "  - To update vendored skills: npx skills update -p, review diff, commit."
