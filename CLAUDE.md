# Working on agent-config

This repo syncs my Claude Code setup across machines.
Configs are symlinked into `~/.claude` by `install.sh`, so files here are LIVE - editing them changes the active config on this machine (see the reload rules below for what needs a restart).

## Source-of-truth map

| To change | Edit | Never edit |
|---|---|---|
| Shared agent instructions | `AGENTS.md` (root) | `~/.claude/AGENTS.md` (symlink) |
| Claude-only global rules | `claude/CLAUDE.md` | `~/.claude/CLAUDE.md` (symlink) |
| Subagent definitions | `agents/**/*.md` | |
| My own skills | `skills/<name>/` | |
| Vendored skills | never by hand - use the skills CLI | `.agents/skills/**` (fork into `skills/` to customize) |
| Mods (function-hooks plugins: bands, panes) | the sibling `claude-mods` repo, `plugins/<name>/` | `~/.claude/plugins/**` (machine-local install state) |
| tmux | `tmux/tmux.conf` | `~/.tmux.conf` (symlink) |

Do not confuse the two CLAUDE.md files: this one (repo root) is project instructions for working on this repo; `claude/CLAUDE.md` is the global config every session loads via `~/.claude/CLAUDE.md`.

## Rules

- `CLAUDE.md` and `AGENTS.md` changes are picked up live through the symlinks.
  `agents/**/*.md` are NOT: agent definitions are snapshotted when a session starts, so edits to frontmatter or an agent's prompt only take effect in the next session.
  Restart Claude Code before testing an agent change, or you will verify the old definition and conclude the edit failed.
- Re-run `./install.sh` for structural changes (new skills, new hooks, new symlink targets).
- There is no status line: the `meter` plugin draws context, prompt cache, usage limits and cost in a band above the prompt.
  `meter` draws in the terminal and the desktop app; `agent-graph` draws only in the desktop app.
  `/meter` opens a detailed metrics pane beside the band.
- Mods are plugins in the sibling `claude-mods` repo, not in this repo.
  `install.sh` finds that repo at `$CLAUDE_MODS_DIR` or at `../claude-mods` and fails before changing anything if it is missing.
  It registers the repo as the `claude-mods` marketplace, installs every plugin listed in its `marketplace.json` at user scope, and removes the retired `~/.claude/mods` link.
  `enabledPlugins` in `claude/settings.json` is committed deliberately, so a new plugin needs a `<name>@claude-mods` entry there.
  `install.sh` strips its `claude-mods` entry; any other entry there is also machine-local, so revert that hunk.
  Do not add `CLAUDE_CODE_PLUGIN_DIRS` back.
  Installed plugins load in place from the `claude-mods` checkout, so edits take effect after `/reload-plugins` or a restart.
  Develop and test them in that repo; see its `CLAUDE.md`.
- Claude Code writes some keys back into user settings, which is the live-symlinked `claude/settings.json`: `/effort` and the `/model` effort slider save `modelSettings.<model>.effortLevel` (since 2.1.251), and `/config`, `/tui`, `/theme` and `claude install <channel>` save keys such as `theme`, `tui`, `autoUpdatesChannel` and `skipDangerousModePermissionPrompt`.
  A saved `modelSettings` level silently overrides the top-level `effortLevel`.
  After any of these, either commit the written key deliberately or revert only that hunk with `git checkout -p claude/settings.json`.
  `claude plugin` commands write the same way: keep the `enabledPlugins` lines, revert any `extraKnownMarketplaces` hunk.
- `agents/**/*.md` frontmatter (`name`, `description`, `tools`, `model`, `effort`) drives Claude Code agent behavior directly.
  Keep frontmatter accurate when adding agents.
  `effort` is `low`/`medium`/`high`/`xhigh`/`max`; in this roster every agent is pinned explicitly to its model's API default (`high` for Sonnet 5.5 agents, `medium` for Opus 5.5 agents), except `architect`, which is pinned to `high` on Opus 5.5.
  The pin stays explicit because an agent without `effort` inherits the session level rather than the model default, so a session-level `/effort` change would silently move it.
  The pin is the baseline: effort sweeps run per dispatch through the `Agent` tool's `effort` parameter, and only a measured quality gain changes a pin.
- Agents use only 5-series models.
  The `env` block in `claude/settings.json` pins what the `fable`, `opus`, and `sonnet` aliases resolve to (`ANTHROPIC_DEFAULT_FABLE_MODEL`, `ANTHROPIC_DEFAULT_OPUS_MODEL`, `ANTHROPIC_DEFAULT_SONNET_MODEL`), so agent frontmatter keeps the plain `fable`/`opus`/`sonnet` aliases.
  `haiku` is deliberately left unpinned: do not add `ANTHROPIC_DEFAULT_HAIKU_MODEL`.
  It resolves to Haiku 4.5, which the `claude-code-guide` built-in and background helper requests (titles, compaction, summaries) use.
  The `Explore` and `Plan` built-ins inherit the session model, capped at `opus`.
  Opus 5.5 requires Claude Code 2.1.280 or later; an older build fails the pinned requests instead of falling back.
  Do not set a top-level `effortLevel` or any `modelSettings` effort in `claude/settings.json`: every model runs at its API default effort, and `effortLevel` does not apply to Opus 5.5 anyway.
- `.claude/skills` is a committed relative symlink to `../.agents/skills`; never replace it with a real directory.
- `skills-lock.json` tracks vendored-skill provenance for `npx skills update -p`; do not hand-edit it except to reconcile after a CLI failure.
- `install.sh` must stay idempotent: re-runs must print `ok:` for existing links and create no duplicate backups.
  Test changes against a throwaway `HOME` before running for real: `mkdir -p /tmp/fake-home && HOME=/tmp/fake-home ./install.sh`.
- Never commit credentials or machine-local state (`~/.claude/projects`, session data, `.bak` files, lock files under `~/.agents`).

## Common workflows

- New skill of my own: `npx skills init skills/<name>`, then `./install.sh`.
- Vendor a third-party skill: `npx skills add <owner/repo> --skill <name> --copy -a claude-code -y`, then commit `.agents/` and `skills-lock.json`.
- New subagent: add `agents/<tier>/<name>.md` with frontmatter (`name`, `description`, `tools`, `model`), then restart Claude Code to pick it up.
  Valid `tools:` names in this build are `Read`, `Bash`, `Write`, `Edit`, `Skill`, `WebSearch`, `WebFetch`, `Grep`, `Glob`.
  `Glob` and `Grep` are real tools but are absent from the default tool set on macOS, Linux and WSL; Claude searches with `find` and `grep` through Bash instead.
  A subagent gets `Glob`/`Grep` back only when it lists them in `tools:` and leaves out `Bash`.
  Every agent in this roster except `web-researcher` carries `Bash`, so they search via `grep`/`find` in Bash.
  `web-researcher` has neither `Bash` nor `Grep`/`Glob`; it reads named paths only and never searches the filesystem.
- Sync another machine: `git pull && ./install.sh`.
- Purge skills removed from the repo (or installed by other means): `./install.sh --clean` deletes any `~/.claude/skills` entry this repo does not provide, except `synced/` and `.trash/`, which Claude Code owns for claude.ai skill sync.
