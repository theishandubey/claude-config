# claude-config

A complete, installable Claude Code setup: a two-tier agent roster (advisors plan and review, workers implement), the orchestration playbook that drives it, safe permission defaults, a write-guard hook, a tmux config and a curated list of third-party skills.
`install.sh` links the config into `~/.claude` and generates `~/.claude/settings.json` from the committed defaults.
Your personal values live in a gitignored `local/` overlay, so the public defaults stay safe and your machine keeps its own model, theme and permission mode.

## What you get

Fourteen subagents, defined in `agents/`:

| Agent | Tier | Model | Effort | Role |
|---|---|---|---|---|
| `architect` | advisor | opus (fable on escalation) | high | Designs, ADRs, trade-offs and implementation plans |
| `backend-engineer` | advisor | opus | medium | APIs, services, databases, queues, auth, data modeling |
| `frontend-engineer` | advisor | opus | medium | Component architecture, state, rendering performance, accessibility |
| `sre` | advisor | opus | medium | Infrastructure, CI/CD, observability, deployment safety |
| `qa-lead` | advisor | opus | medium | End-to-end test strategy and coverage planning |
| `code-reviewer` | advisor | opus | medium | Reviews every code change before it lands |
| `security-reviewer` | advisor | opus | medium | Security review, only when you ask for one |
| `implementer` | worker | sonnet | high | Builds from a plan |
| `parallel-implementer` | worker | sonnet | high | Builds in its own git worktree, for parallel streams |
| `fixer` | worker | sonnet | high | Fixes bugs, failing tests and review findings |
| `test-writer` | worker | sonnet | high | Writes end-to-end tests from a test plan |
| `doc-writer` | worker | sonnet | high | Writes and updates standalone docs |
| `explorer` | explorer | sonnet | medium | Read-only codebase search |
| `web-researcher` | explorer | sonnet | medium | Read-only web research |

The main session acts as an orchestrator that routes work instead of doing it.
A triage ladder sends questions to explorers, bounded changes straight to a worker, and ambiguous work to an advisor for a plan first.
Advisors never edit project files: they hold `Write` and `Edit` only to keep their own memory and, for the planning advisors, to write plan files, and a hook blocks every other path.
Every code change goes through `code-reviewer`, and confirmed findings go to `fixer` until the review approves.
Independent parallel work runs through `parallel-implementer` worktrees, and agent teams are reserved for work whose contracts change mid-build.
`architect` escalates to Fable only for decisions that are hard to reverse.

The full playbook is in `claude/CLAUDE.md`, and the shared coding rules every agent follows are in `claude/AGENTS.md`.

## Prerequisites

- Claude Code 2.1.280 or later.
  Older builds fail the Opus 5.5 model pins instead of falling back.
- Access to Opus 5.5 and Sonnet 5.5.
  Fable 5.1 is optional: only `architect` escalation uses `model: fable`.
- macOS or Linux.
- `bash`, `git` and `jq`.
- Node.js with `npx`, which `install.sh` uses to run the [skills CLI](https://skills.sh).
- `tmux` is optional.
  `tmux/tmux.conf` turns on `allow-passthrough`, so desktop notifications and the progress bar leave tmux, `extended-keys`, so Shift+Enter inserts a newline instead of submitting, and mouse mode, so wheel scrolling reaches Claude Code's fullscreen renderer instead of tmux.

## Install

```bash
git clone https://github.com/theishandubey/claude-config.git ~/claude-config
cd ~/claude-config
[ -e local ] || cp -R local.example local
./install.sh --dry-run
./install.sh
```

The `cp` step is optional, and the `[ -e local ]` guard keeps it from nesting a second copy when `local/` already exists.
The template only shows the shape: edit `local/settings.json` and `local/instructions.md` first if you want your own values from the start (see [Your personal overlay](#your-personal-overlay)).
`--dry-run` prints every planned change and exits without touching anything.
Afterwards start `claude` and run `/memory` to see which instruction files loaded.

### What install.sh changes

| Target | Source |
|---|---|
| `~/.claude/AGENTS.md` | link to `claude/AGENTS.md` |
| `~/.claude/CLAUDE.md` | link to `claude/CLAUDE.md` |
| `~/.claude/CLAUDE.local.md` | link to `local/instructions.md`, only when that file exists |
| `~/.claude/agents` | link to `agents/` |
| `~/.claude/hooks` | link to `hooks/` |
| `~/.tmux.conf` | link to `tmux/tmux.conf` |
| `~/.claude/settings.json` | generated from `claude/settings.json` plus `local/settings.json`; the last output is kept as `~/.claude/settings.generated.json` |
| `~/.claude/skills/` | skills from `skills/` and `skills-lock.json`, installed through the skills CLI |

- A file, directory or foreign symlink already at a target is moved to `<path>.bak.<timestamp>` first and never overwritten.
  Links that already point into this repo are replaced without a backup.
- `install.sh` asks for confirmation only before changes to things it does not own: creating backups, replacing links that point outside the repo, `--clean` and `--uninstall`.
  Declining exits with status 1.
  A routine re-run needs no confirmation, prints `ok:` for everything that is already in place, writes nothing except reinstalling skills (skip with `--no-skills`) and exits 0.
- Without a terminal, pass `--yes` (or `-y`) for a run that needs confirmation; otherwise it refuses and exits 1.
- Skills come from the network: this repo's own skills are installed from `skills/`, the third-party ones from the upstream repositories recorded in `skills-lock.json`.
  `--no-skills` skips that step.
- `--clean` also removes `~/.claude/skills` entries that neither `skills/` nor `skills-lock.json` provides, except `synced/` and dot-entries.
- Set `NO_COLOR` to turn off colored output.

## Your personal overlay

`claude/settings.json` holds only safe defaults.
Everything personal goes into two gitignored files under `local/`:

- `local/settings.json` is merged over the defaults to produce `~/.claude/settings.json`.
- `local/instructions.md` holds personal instructions.
  It is linked to `~/.claude/CLAUDE.local.md`, which `claude/CLAUDE.md` imports after the shared playbook.
  If the file is missing, the import is silently skipped.

`local.example/` has a starting point for both.
Set `CLAUDE_CONFIG_LOCAL_DIR` to keep the overlay somewhere else.

The merge rules:

- Objects merge recursively.
- Arrays append your values without duplicates.
- Scalars replace the default.
- `null` keeps the default.

Because arrays only append, a committed default array element, such as a `permissions.allow` or `permissions.deny` rule, cannot be dropped through the overlay.
Dropping one means editing `claude/settings.json` in a fork.

A minimal overlay, which is also what `local.example/settings.json` contains:

```json
{
  "cleanupPeriodDays": 30,
  "permissions": {
    "deny": [
      "Bash(npm publish:*)"
    ]
  }
}
```

`cleanupPeriodDays` is not a committed default, so the scalar is simply added; a scalar that is a committed default would be replaced.
The `deny` entry is appended to the committed list.

The committed defaults never enable bypass permissions mode.
To opt in on your own machine, add this to `local/settings.json`:

```json
{
  "permissions": {
    "defaultMode": "bypassPermissions"
  },
  "skipDangerousModePermissionPrompt": true
}
```

This removes the permission prompts, so the model can run commands and edit files without asking; read [Security notes](#security-notes) first.

### Write-backs

Claude Code writes the results of `/model`, `/effort`, `/config`, `/tui`, `/theme`, `claude install <channel>` and `claude plugin` into `~/.claude/settings.json`.
On the next `./install.sh`, every changed value is adopted into `local/settings.json` and printed as `adopted into ...`, so the repo never gets dirty.

- A key Claude Code deleted is reported, and it comes back from the committed defaults or from your overlay, whichever set it.
  To remove a key your overlay sets, edit `local/settings.json`.
  `claude plugin disable` writes `false`, which is adopted into `local/settings.json` like any other change.
  Removing a plugin's entry, as plugin uninstall can, is a deletion, so the overlay's value returns until you edit `local/settings.json`.
- A write-back cannot remove a committed default key or array element.
  `install.sh` warns and restores it; override a scalar in `local/settings.json` instead, or edit `claude/settings.json` in a fork.
- If `~/.claude/settings.generated.json` is missing, `install.sh` cannot tell your edits from changed defaults.
  A live value that differs from the committed default wins over the overlay, shown as `adopted into` lines; a live value equal to the default does not, so the overlay's value stays.
  The old file is backed up first.
- With an existing `~/.claude/settings.json` and no `local/`, the first run seeds `local/settings.json` with the values in it that differ from the committed defaults.
- If `~/.claude/settings.json` is still a symlink into this repo (an older layout) and there is no overlay, `install.sh` stops with exit 1 and changes nothing.
  Copy `local/` from another machine, start from `local.example/`, or set `CLAUDE_CONFIG_NO_OVERLAY=1` to install the defaults only.

### Permissions

The committed allow list holds only `Edit` rules for the agent-memory directories and for `plans/*.md` and `advisor-plans/*.md`, so planning advisors can write plan files without prompting.
The committed deny list blocks force pushes, `git reset --hard` and `rm -rf`, and deny rules still apply in bypass mode: Claude Code 2.1.291 describes bypass as auto-approving every tool call except explicit deny rules.
The allow list has no `Bash` rules because Claude Code already auto-approves the safe forms of read-only commands, and an explicit rule such as `Bash(find:*)` would also approve dangerous forms like `find -delete`.

### Syncing the overlay

`local/` is gitignored and never leaves your machine through this repo.
Copy it to another machine by hand, or make `local/` a symlink into a private dotfiles repository.

## Layout

```
claude-config/
├── README.md
├── LICENSE
├── .github/workflows/check.yml # CI: runs scripts/check.sh on Linux and macOS
├── install.sh                  # installer: --dry-run, --yes, --uninstall, --clean, --no-skills
├── skills-lock.json            # third-party skills and their upstream repos, installed at install time
├── agents/                     # subagent definitions, linked to ~/.claude/agents
│   ├── advisors/
│   ├── workers/
│   └── explorers/
├── claude/                     # global Claude Code config
│   ├── AGENTS.md               # shared coding rules, linked to ~/.claude/AGENTS.md
│   ├── CLAUDE.md               # orchestration playbook, linked to ~/.claude/CLAUDE.md
│   └── settings.json           # committed defaults, merged into ~/.claude/settings.json
├── local.example/              # copy to local/ (gitignored) for your personal overlay
│   ├── settings.json
│   └── instructions.md
├── hooks/                      # PreToolUse guards, linked to ~/.claude/hooks
├── skills/                     # skills maintained in this repo
├── tmux/tmux.conf              # linked to ~/.tmux.conf
├── scripts/                    # check.sh and the tests it runs
└── docs/adr/                   # architecture decision records
```

## Customizing

- **Agents**: edit `agents/**/*.md`.
  The frontmatter needs `name`, `description`, `tools`, `model` and `effort`; `scripts/check.sh` validates it.
  Claude Code snapshots agent definitions when a session starts, so restart it to pick up a change.
- **Skills**: put your own in `skills/<name>/`.
  Third-party skills are listed in `skills-lock.json` and installed from their upstream repositories; their licenses are upstream's.
- **Hooks**: `hooks/memory-write-guard.sh` is wired per agent through its `hooks:` frontmatter.
- **Settings**: fork the repo to change the committed defaults, and use the overlay for personal values.
- **tmux**: edit `tmux/tmux.conf`; it is linked live.

## Updating

```bash
git pull && ./install.sh
```

`install.sh` reinstalls the third-party skills from upstream, so a re-run also brings them up to date.
`npx skills update -g` updates installed skills without it, and `claude plugin update <name>@claude-mods` updates a plugin.

## Uninstalling

```bash
./install.sh --uninstall --dry-run
./install.sh --uninstall
```

This removes the links and the settings snapshot, and restores the newest `.bak.<timestamp>` backup at each path.
The generated `~/.claude/settings.json` is replaced by its backup when there is one; with no backup it stays as a plain file, and an edited one is never removed.
`local/`, installed skills (`npx skills remove -g <name>`) and plugins (`claude plugin uninstall`) are left alone.

## Optional plugins

The public [`claude-mods`](https://github.com/theishandubey/claude-mods) marketplace has plugins that this setup works well with:

- `meter` draws a band above the prompt with context, prompt cache, usage limits and cost, and `/meter` opens a detailed metrics pane.
- `agent-graph` graphs running subagents: a card graph in the desktop app and an indented tree in the terminal, opened with `/agent-graph`.
- `auto-handoff` writes a handoff and the knowledge it names into `.auto-handoff/` when the context grows large, then clears the context and continues.

The committed defaults enable none of them.
Opt in through `local/settings.json`:

```json
{
  "enabledPlugins": {
    "meter@claude-mods": true,
    "agent-graph@claude-mods": true
  },
  "extraKnownMarketplaces": {
    "claude-mods": {
      "source": {
        "source": "git",
        "url": "https://github.com/theishandubey/claude-mods.git"
      }
    }
  }
}
```

The declaration does not fetch anything, so install each plugin once per machine:

```bash
claude plugin marketplace add https://github.com/theishandubey/claude-mods.git
claude plugin install meter@claude-mods --scope user
claude plugin install agent-graph@claude-mods --scope user
```

## Security notes

- The committed defaults never enable bypass permissions mode, and turning it on is your choice.
- `permissions.deny` rules are prefix matches, where `:*` means "starts with".
  `Bash(rm -rf:*)` does not match `rm -fr`, and `Bash(git push --force:*)` does not match `git push origin main --force` (flag after the refspec), `git push --force-with-lease` or a `+refspec` push.
  They guard against accidents, not against a hostile model or prompt injection.
- `hooks/memory-write-guard.sh` blocks `Write` and `Edit` outside agent memory and plan files for advisor agents.
  Those agents also hold `Bash`, so the guard enforces a workflow convention and is not a security boundary.
- Third-party skills are installed unpinned from the upstream repositories recorded in `skills-lock.json` when you run `install.sh`, and they run with the agent's full permissions.
  Review `~/.claude/skills/<name>/SKILL.md` and drop any you do not trust from the manifest.
- Nothing in `install.sh` runs with elevated privileges.
  `--dry-run` shows every change first, and `--uninstall` removes the links and restores backups.
- Report a vulnerability privately through GitHub's private vulnerability reporting on this repository (Security tab, "Report a vulnerability"), not in a public issue.

## Working on this repo

There is no `CONTRIBUTING.md`; this section is the contributor guide.

- Run `scripts/check.sh` before opening a pull request.
  It validates the JSON files, keeps personal keys out of the committed defaults, lints the shell scripts when `shellcheck` is installed, validates agent frontmatter, tests the memory-write guard, and runs `install.sh` end to end in a throwaway home directory.
  It ends with `check: ok`.
  CI runs the same check on Linux and on macOS under `/bin/bash` 3.2, so keep shell scripts compatible with bash 3.2.
- Test `install.sh` only with a throwaway `HOME` and `CLAUDE_CONFIG_LOCAL_DIR`, never against your real home directory:

  ```bash
  mkdir -p /tmp/fake-home /tmp/fake-local
  HOME=/tmp/fake-home CLAUDE_CONFIG_LOCAL_DIR=/tmp/fake-local ./install.sh --dry-run --no-skills
  ```

- Keep `install.sh` idempotent: a re-run prints `ok:` for everything already in place, creates no duplicate backups and writes nothing except reinstalling skills (skip with `--no-skills`).
- Keep the exit contract of `install.sh`: every successful exit sets `COMPLETED=1`, through `finish()` or the final assignment at the end of the script, and the EXIT trap turns any exit without it into a failure, because bash 3.2 reports status 0 for a `set -eu` abort once an EXIT trap is set.
- Make atomic commits: one logically complete change per commit, each passing `scripts/check.sh` on its own.
- Never commit personal values or anything under `local/`.
- The reasoning behind the settings overlay is in `docs/adr/0001-machine-local-overlay.md`.

## License

MIT, see `LICENSE`.
