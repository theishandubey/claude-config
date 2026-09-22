# agent-config

Single repo to keep my Claude Code setup in sync across machines. Configs are symlinked, shared instructions are single-sourced, and skills (own + vendored third-party) are installed via the [skills CLI](https://skills.sh).

For Codex, this repo carries nothing - [codex-plugin-cc](https://github.com/openai/codex-plugin-cc) handles that side.

## Repo structure

```
agent-config/
├── AGENTS.md                     # Shared instructions - single source of truth
│                                 #   the agent-agnostic standard file, imported
│                                 #   by Claude via @~/.claude/AGENTS.md
│
├── CLAUDE.md                     # Project instructions for working on THIS repo
│                                 #   (source-of-truth map, install.sh workflow)
│
├── agents/                       # Custom agent definitions - single source of truth
│   │                             #   consumed directly via ~/.claude/agents symlink
│   ├── advisors/
│   ├── workers/
│   └── explorers/
│
├── skills/                       # MY OWN skills - I edit these
│   └── <skill-name>/
│       └── SKILL.md
│
├── .agents/
│   └── skills/                   # THIRD-PARTY skills, vendored via skills CLI
│       └── <skill-name>/         #   committed to git, treated as read-only
│           └── SKILL.md          #   (edits = fork it and move to skills/)
│
├── .claude/
│   └── skills -> ../.agents/skills   # relative symlink, committed - exposes
│                                     # vendored skills to Claude Code project scope
│
├── hooks/                        # PreToolUse guards, linked to ~/.claude/hooks
├── statusline/                   # statusline/*.js, linked to ~/.claude/statusline
├── skills-lock.json              # vendored-skill provenance for npx skills update
├── tmux/                         # tmux.conf, linked to ~/.tmux.conf
│
├── claude/                       # Claude Code global config
│   ├── CLAUDE.md                 #   imports shared AGENTS.md, then Claude-only rules
│   └── settings.json             #   permissions, model, preferences
│
└── install.sh                    # bootstrap - idempotent, re-run anytime
```

## What install.sh does

1. **Repo-internal symlink** - ensures `.claude/skills -> ../.agents/skills` exists
2. **Claude shared instructions** - symlinks repo `AGENTS.md` → `~/.claude/AGENTS.md`
   (which `CLAUDE.md` imports via `@~/.claude/AGENTS.md`; a bare relative import
   would resolve against the symlink's REAL path, `claude/`, and silently break)
3. **Config symlinks** -
   | Repo file | Target |
   |---|---|
   | `claude/settings.json` | `~/.claude/settings.json` |
   | `statusline/` | `~/.claude/statusline` |
   | `claude/CLAUDE.md` | `~/.claude/CLAUDE.md` |
   | `agents/` | `~/.claude/agents` |
   | `hooks/` | `~/.claude/hooks` |
   | `tmux/tmux.conf` | `~/.tmux.conf` |
4. **Skills install** - `npx skills add` discovers everything in `skills/`
   and `.agents/skills/` and installs globally to Claude Code only
   (targeting all detected agents would spam errors from project-scope-only
   targets like PromptScript)

Existing files at target locations are backed up with a timestamped `.bak` suffix,
never overwritten.

## Workflows

### New machine

```bash
git clone <repo-url> ~/agent-config
cd ~/agent-config
./install.sh
# then authenticate manually - credentials are never synced
```

### Sync changes to another machine

```bash
git pull && ./install.sh
```

### Edit shared instructions

Edit root `AGENTS.md` - Claude sees the symlink live.
Commit + push; pull on the other machine.

### Vendor a third-party skill

```bash
npx skills add <owner/repo> --skill <name> --copy -a claude-code -y
git add .agents && git commit -m "vendor <name>" && git push
```

- `--copy` (not symlink) so real files land in the repo
- single agent target to avoid duplicate copies; files land in `.agents/skills/`
- the global install step later targets **all** agents regardless

### Update vendored skills

```bash
npx skills update -p     # updates project-scope skills in .agents/skills/
git diff                 # review upstream changes before committing
git add .agents && git commit && git push
```

### Create my own skill

```bash
npx skills init skills/<name>
```

### Remove a skill

Delete its folder from the repo, commit, then on each machine:
`npx skills remove <name> -g`

## Design decisions

- **AGENTS.md at repo root** - the standard, agent-agnostic location; any agent
  working *on this repo* picks it up automatically as project instructions.
- **CLAUDE.md wraps AGENTS.md** - Claude Code doesn't read AGENTS.md natively, but
  supports `@path` imports. Shared rules live once; Claude-only rules go below the
  import. AGENTS.md itself stays self-contained - agents without an import
  mechanism must be able to read it as a single file. Don't split it.
- **Own vs vendored skills are separated** - `skills/` is editable, `.agents/skills/`
  is overwritable by the CLI. Editing a vendored skill means forking it into `skills/`.
- **Third-party skills are committed, not referenced** - pinned, reviewable via git
  diff, installable offline. Trade-off: updates are deliberate (`skills update -p`)
  instead of automatic.
- **`.agents/skills/` uses the CLI's native path** - so project-scope install and
  update tracking work without custom tooling; the `.claude/skills` symlink bridges
  Claude Code's different project path.
- **No credentials in the repo** - auth files (`.credentials.json`, tokens) stay
  machine-local; re-authenticate per machine.
- **Machine-specific overrides** - use `~/.claude/settings.local.json` etc., kept
  out of the repo.
