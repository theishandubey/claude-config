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
| Status line | `statusline/statusline.js` | |

Do not confuse the two CLAUDE.md files: this one (repo root) is project instructions for working on this repo; `claude/CLAUDE.md` is the global config every session loads via `~/.claude/CLAUDE.md`.

## Rules

- `CLAUDE.md` and `AGENTS.md` changes are picked up live through the symlinks.
  `agents/**/*.md` are NOT: agent definitions are snapshotted when a session starts, so edits to frontmatter or an agent's prompt only take effect in the next session.
  Restart Claude Code before testing an agent change, or you will verify the old definition and conclude the edit failed.
- Re-run `./install.sh` for structural changes (new skills, new hooks, new symlink targets).
- The `statusLine` key in `claude/settings.json` is picked up live via the symlink.
  `statusline/` itself is a new symlink target, so `./install.sh` must be re-run once after first adding it.
- `agents/**/*.md` frontmatter (`name`, `description`, `tools`, `model`, `effort`) drives Claude Code agent behavior directly.
  Keep frontmatter accurate when adding agents.
  `effort` is `low`/`medium`/`high`/`xhigh`/`max`; in this roster it is always pinned explicitly on every agent - the floor is `high`, raised to `xhigh` only on the implementation workers (`implementer`, `parallel-implementer`), never lower; raise other agents per call via the `Agent` tool's `effort` parameter.
- `.claude/skills` is a committed relative symlink to `../.agents/skills`; never replace it with a real directory.
- `skills-lock.json` tracks vendored-skill provenance for `npx skills update -p`; do not hand-edit it except to reconcile after a CLI failure.
- `install.sh` must stay idempotent: re-runs must print `ok:` for existing links and create no duplicate backups.
  Test changes against a throwaway `HOME` before running for real: `mkdir -p /tmp/fake-home && HOME=/tmp/fake-home ./install.sh`.
- Never commit credentials or machine-local state (`~/.claude/projects`, session data, `.bak` files, lock files under `~/.agents`).

## Common workflows

- New skill of my own: `npx skills init skills/<name>`, then `./install.sh`.
- Vendor a third-party skill: `npx skills add <owner/repo> --skill <name> --copy -a claude-code -y`, then commit `.agents/` and `skills-lock.json`.
- New subagent: add `agents/<tier>/<name>.md` with frontmatter (`name`, `description`, `tools`, `model`), then restart Claude Code to pick it up.
  Valid `tools:` names in this build are `Read`, `Bash`, `Write`, `Edit`, `Skill`, `WebSearch`, `WebFetch`.
  There is no `Grep` or `Glob` tool - unresolvable names are silently dropped from the list, so an agent given only phantom names ends up with fewer tools than intended. Search via `grep`/`find` in Bash.
- Sync another machine: `git pull && ./install.sh`.
- Purge skills removed from the repo (or installed by other means): `./install.sh --clean` deletes any `~/.claude/skills` entry this repo does not provide.
