#!/usr/bin/env bash
#
# agent-config bootstrap
#
# - Symlinks Claude Code configs into place
# - Registers the sibling claude-mods marketplace and installs its plugins
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

info()  { printf '\033[1;34m==>\033[0m %s\n' "$*"; }
warn()  { printf '\033[1;33mwarn:\033[0m %s\n' "$*"; }

CLEAN=0
for arg in "$@"; do
  case "$arg" in
    --clean) CLEAN=1 ;;
    *) warn "unknown argument: $arg"; echo "Usage: ./install.sh [--clean]" >&2; exit 1 ;;
  esac
done

MODS_DIR="${CLAUDE_MODS_DIR:-$(dirname "$REPO_DIR")/claude-mods}"
if [ ! -f "$MODS_DIR/.claude-plugin/marketplace.json" ]; then
  echo "error: claude-mods marketplace not found at $MODS_DIR" >&2
  echo "Clone the claude-mods repo next to agent-config, or set CLAUDE_MODS_DIR to its path." >&2
  exit 1
fi
MODS_DIR="$(cd "$MODS_DIR" && pwd)"

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
# Links this script no longer creates - remove them if they still point into this repo.
for retired in "$HOME/.claude/commands" "$HOME/.claude/statusline" "$HOME/.claude/mods"; do
  target="$(readlink "$retired" 2>/dev/null || true)"
  if [ -L "$retired" ] && [ "${target#"$REPO_DIR"/}" != "$target" ]; then
    warn "removing retired link: $retired"
    rm "$retired"
  fi
done
link "$REPO_DIR/claude/settings.json" "$HOME/.claude/settings.json"
link "$REPO_DIR/claude/CLAUDE.md"     "$HOME/.claude/CLAUDE.md"
link "$REPO_DIR/agents"               "$HOME/.claude/agents"
# Agent frontmatter references hooks by absolute path ($HOME/.claude/hooks/...),
# so they must resolve on every machine, not just inside this repo.
link "$REPO_DIR/hooks"                "$HOME/.claude/hooks"
link "$REPO_DIR/tmux/tmux.conf"       "$HOME/.tmux.conf"
chmod +x "$REPO_DIR"/hooks/*.sh 2>/dev/null || true

# ---------------------------------------------------------------------------
# 4. Plugins: register the claude-mods marketplace and install every plugin it
#    lists. enabledPlugins is committed in claude/settings.json; the
#    marketplace registration is machine-local, so the claude-mods entry claude
#    writes into extraKnownMarketplaces is stripped again.
# ---------------------------------------------------------------------------
info "Installing plugins from $MODS_DIR"
failed=0
if command -v claude > /dev/null; then
  claude plugin marketplace add "$MODS_DIR"
  plugin_names="$(node -e '
    const fs = require("fs");
    const manifest = JSON.parse(fs.readFileSync(process.argv[1], "utf8"));
    for (const plugin of manifest.plugins) console.log(plugin.name);
  ' "$MODS_DIR/.claude-plugin/marketplace.json")"
  while IFS= read -r name; do
    [ -n "$name" ] || continue
    claude plugin install "$name@claude-mods" --scope user -y || { warn "plugin install failed: $name"; failed=1; }
  done <<< "$plugin_names"
  node -e '
    const fs = require("fs");
    const file = process.argv[1];
    const settings = JSON.parse(fs.readFileSync(file, "utf8"));
    if (settings.extraKnownMarketplaces?.["claude-mods"] !== undefined) {
      delete settings.extraKnownMarketplaces["claude-mods"];
      if (Object.keys(settings.extraKnownMarketplaces).length === 0) delete settings.extraKnownMarketplaces;
      fs.writeFileSync(file, JSON.stringify(settings, null, 2) + "\n");
      console.log("stripped claude-mods from extraKnownMarketplaces in " + file);
    }
  ' "$HOME/.claude/settings.json"
else
  warn "claude CLI not found - skipping plugin install; re-run after installing Claude Code"
fi

# ---------------------------------------------------------------------------
# 5. Install all skills in this repo globally, to all detected agents
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
# 6. --clean: remove installed skills that this repo does not provide
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

if [ "$failed" = 1 ]; then
  warn "one or more plugins failed to install - see the messages above"
  exit 1
fi
