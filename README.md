# claude-config

A complete, installable Claude Code setup: a two-tier agent roster (advisors plan and review, workers implement), the orchestration playbook that drives it, safe permission defaults, a write-guard hook, a tmux config and a curated list of third-party skills.
`install.sh` links the config into `~/.claude` and merges the committed settings defaults into your own `~/.claude/settings.json`.
That file stays yours: the installer adds what is missing and never overwrites a value you set, so your machine keeps its own model, theme and permission mode.

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
./install.sh --dry-run
./install.sh
```

`--dry-run` prints every planned change and exits without touching anything.
Afterwards start `claude` and run `/memory` to see which instruction files loaded.

### What install.sh changes

| Target | Source |
|---|---|
| `~/.claude/AGENTS.md` | link to `claude/AGENTS.md` |
| `~/.claude/CLAUDE.md` | link to `claude/CLAUDE.md` |
| `~/.claude/agents` | link to `agents/` |
| `~/.claude/hooks` | link to `hooks/` |
| `~/.tmux.conf` | link to `tmux/tmux.conf` |
| `~/.claude/settings.json` | your own file, with the defaults from `claude/settings.json` merged in (see [Your settings](#your-settings)) |
| `~/.claude/skills/` | skills from `skills/` and `skills-lock.json`, installed through the skills CLI |

- A file, directory or foreign symlink already at a target is moved to `<path>.bak.<timestamp>` first and never overwritten.
  Links that already point into this repo are replaced without a backup.
- `install.sh` asks for confirmation only before changes to things it does not own: creating backups, replacing links that point outside the repo (including a `settings.json` symlink that points elsewhere), `--clean` and `--uninstall`.
  Declining exits with status 1.
  A routine re-run needs no confirmation, prints `ok:` for everything that is already in place, writes nothing except reinstalling skills (skip with `--no-skills`) and exits 0.
- Without a terminal, pass `--yes` (or `-y`) for a run that needs confirmation; otherwise it refuses and exits 1.
- Skills come from the network: this repo's own skills are installed from `skills/`, the third-party ones from the upstream repositories recorded in `skills-lock.json`.
  `--no-skills` skips that step.
- `--clean` also removes `~/.claude/skills` entries that neither `skills/` nor `skills-lock.json` provides, except `synced/` and dot-entries.
- Set `NO_COLOR` to turn off colored output.

## Your settings

`claude/settings.json` holds only safe defaults.
Your personal settings live directly in `~/.claude/settings.json`, and you can edit that file, or let Claude Code write to it with `/model`, `/theme`, `/config` and `claude plugin`, as usual.

On every run `install.sh` computes the defaults merged with your file and writes the result only when it differs:

- If the file does not exist, it is created as a copy of the defaults.
- If it is a symlink into this repo (an older layout), it is replaced by a real file holding the defaults, and you re-add your personal values to it.
- If it is a symlink that points elsewhere, it is backed up after confirmation, and a file holding the defaults is written.
- Otherwise your file is merged with the defaults, and your values win:
  - Objects merge recursively.
  - A scalar you set is kept, and a key you do not have gets the default.
  - Arrays keep your elements in your order, then append the default elements you do not have.
- An empty or whitespace-only file counts as `{}`.
- If your file cannot be read, is not valid JSON, is not a single JSON object or holds more than one JSON document,
  `install.sh` prints an error, exits with status 1 and leaves the file untouched.
- If nothing would change, it prints `ok:` and writes nothing.
  Otherwise it writes the file atomically with mode 600 and lists what it added, for example `update: ~/.claude/settings.json (added: permissions.deny[...], env.X)`.

Deletions do not stick: there is no record of what a previous run wrote, so a default you removed from `~/.claude/settings.json` comes back on the next run.
To drop a committed default for good, edit `claude/settings.json` in a fork.

The committed defaults never enable bypass permissions mode.
To opt in on your own machine, add this to `~/.claude/settings.json`:

```json
{
  "permissions": {
    "defaultMode": "bypassPermissions"
  },
  "skipDangerousModePermissionPrompt": true
}
```

This removes the permission prompts, so the model can run commands and edit files without asking; read [Security notes](#security-notes) first.

### Permissions

The committed allow list holds only `Edit` rules for the agent-memory directories and for `plans/*.md` and `advisor-plans/*.md`, so planning advisors can write plan files without prompting.
The committed deny list blocks force pushes, `git reset --hard` and `rm -rf`, and deny rules still apply in bypass mode: Claude Code 2.1.291 describes bypass as auto-approving every tool call except explicit deny rules.
The allow list has no `Bash` rules because Claude Code already auto-approves the safe forms of read-only commands, and an explicit rule such as `Bash(find:*)` would also approve dangerous forms like `find -delete`.

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
│   └── settings.json           # committed defaults, merged into your ~/.claude/settings.json
├── hooks/                      # PreToolUse guards, linked to ~/.claude/hooks
├── skills/                     # skills maintained in this repo
├── tmux/tmux.conf              # linked to ~/.tmux.conf
└── scripts/                    # check.sh and the tests it runs
```

## Customizing

- **Agents**: edit `agents/**/*.md`.
  The frontmatter needs `name`, `description`, `tools`, `model` and `effort`; `scripts/check.sh` validates it.
  Claude Code snapshots agent definitions when a session starts, so restart it to pick up a change.
- **Skills**: put your own in `skills/<name>/`.
  Third-party skills are listed in `skills-lock.json` and installed from their upstream repositories; their licenses are upstream's.
- **Hooks**: `hooks/memory-write-guard.sh` is wired per agent through its `hooks:` frontmatter.
- **Settings**: fork the repo to change the committed defaults, and edit `~/.claude/settings.json` for personal values.
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

This removes the links and restores the newest `.bak.<timestamp>` backup at each path.
`~/.claude/settings.json` is your file and is never deleted; a legacy symlink into this repo is replaced by a copy of the defaults, or by its backup when there is one.
Installed skills (`npx skills remove -g <name>`) and plugins (`claude plugin uninstall`) are left alone.

## Optional plugins

The public [`claude-mods`](https://github.com/theishandubey/claude-mods) marketplace has plugins that this setup works well with:

- `meter` draws a band above the prompt with context, prompt cache, usage limits and cost, and `/meter` opens a detailed metrics pane.
- `agent-graph` graphs running subagents: a card graph in the desktop app and an indented tree in the terminal, opened with `/agent-graph`.
- `auto-handoff` writes a handoff and the knowledge it names into `.auto-handoff/` when the context grows large, then clears the context and continues.

The committed defaults enable none of them.
Opt in by adding this to `~/.claude/settings.json`, or skip it and run the `claude plugin` commands below, which write the same keys:

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

- The committed defaults never enable bypass permissions mode, and turning it on is your choice in your own `~/.claude/settings.json`.
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
- Test `install.sh` only with a throwaway `HOME`, never against your real home directory:

  ```bash
  mkdir -p /tmp/fake-home
  HOME=/tmp/fake-home ./install.sh --dry-run --no-skills
  ```

- Keep `install.sh` idempotent: a re-run prints `ok:` for everything already in place, creates no duplicate backups and writes nothing except reinstalling skills (skip with `--no-skills`).
- Keep the exit contract of `install.sh`: every successful exit sets `COMPLETED=1`, through `finish()` or the final assignment at the end of the script, and the EXIT trap turns any exit without it into a failure, because bash 3.2 reports status 0 for a `set -eu` abort once an EXIT trap is set.
- Make atomic commits: one logically complete change per commit, each passing `scripts/check.sh` on its own.
- Never commit personal values.

## License

MIT, see `LICENSE`.
