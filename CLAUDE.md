# Working on agent-config

This repo syncs my Claude Code setup across machines.
Configs are symlinked into `~/.claude` by `install.sh`, so files here are LIVE - editing them changes the active config on this machine immediately.

## Source-of-truth map

| To change | Edit | Never edit |
|---|---|---|
| Shared agent instructions | `AGENTS.md` (root) | `~/.claude/AGENTS.md` (symlink) |
| Claude-only global rules | `claude/CLAUDE.md` | `~/.claude/CLAUDE.md` (symlink) |
| Subagent definitions | `agents/**/*.md` | |
| My own skills | `skills/<name>/` | |
| Vendored skills | never by hand - use the skills CLI | `.agents/skills/**` (fork into `skills/` to customize) |

Do not confuse the two CLAUDE.md files: this one (repo root) is project instructions for working on this repo; `claude/CLAUDE.md` is the global config every session loads via `~/.claude/CLAUDE.md`.

## Rules

- Claude Code sees markdown changes live through symlinks; re-run `./install.sh` only for structural changes (new skills, new symlink targets).
- `agents/**/*.md` frontmatter (`name`, `description`, `tools`, `model`) drives Claude Code agent behavior directly.
  Keep frontmatter accurate when adding agents.
- `.claude/skills` is a committed relative symlink to `../.agents/skills`; never replace it with a real directory.
- `skills-lock.json` tracks vendored-skill provenance for `npx skills update -p`; do not hand-edit it except to reconcile after a CLI failure.
- `install.sh` must stay idempotent: re-runs must print `ok:` for existing links and create no duplicate backups.
  Test changes against a throwaway `HOME` before running for real: `mkdir -p /tmp/fake-home && HOME=/tmp/fake-home ./install.sh`.
- Never commit credentials or machine-local state (`~/.claude/projects`, session data, `.bak` files, lock files under `~/.agents`).

## Common workflows

- New skill of my own: `npx skills init skills/<name>`, then `./install.sh`.
- Vendor a third-party skill: `npx skills add <owner/repo> --skill <name> --copy -a claude-code -y`, then commit `.agents/` and `skills-lock.json`.
- New subagent: add `agents/<tier>/<name>.md` with frontmatter (`name`, `description`, `tools`, `model`); Claude Code picks it up live via the `~/.claude/agents` symlink.
- Sync another machine: `git pull && ./install.sh`.
