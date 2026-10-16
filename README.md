# claude-config

A complete, installable Claude Code setup: a three-tier agent roster (advisors plan and review, workers implement, explorers search), the orchestration playbook that drives it, the owner's personal Claude Code settings, two guard hooks, a tmux config and a curated list of third-party skills.
`install.sh` links the config into `~/.claude` and merges the committed settings defaults into your own `~/.claude/settings.json`.
The installer never overwrites a value you already set, but it adds every default you do not have, and those defaults run Claude Code in bypass permissions mode (see the warning under [Install](#install)).

## What you get

Fourteen subagents, defined in `agents/`:

| Agent | Tier | Model | Effort | Role |
|---|---|---|---|---|
| `architect` | advisor | opus | high | Designs, ADRs, trade-offs and implementation plans |
| `backend-engineer` | advisor | opus | medium | APIs, services, databases, queues, auth, data modeling |
| `frontend-engineer` | advisor | opus | medium | Component architecture, state, rendering performance, accessibility |
| `sre` | advisor | opus | medium | Infrastructure, CI/CD, observability, deployment safety |
| `qa-lead` | advisor | opus | medium | End-to-end test strategy, coverage planning and the coverage audit after `test-writer` |
| `code-reviewer` | advisor | opus | medium | Reviews every code change before it lands |
| `security-reviewer` | advisor | opus | medium | Security review, only when you ask for one; fixes are re-reviewed until its verdict is ADVISORY ONLY |
| `implementer` | worker | sonnet | high | Builds from a plan; writes new tests only where the plan assigns them |
| `parallel-implementer` | worker | sonnet | high | Builds in its own git worktree, for parallel streams |
| `fixer` | worker | sonnet | high | Fixes bugs, failing tests and review findings |
| `test-writer` | worker | sonnet | high | Owns new end-to-end tests, written from a test plan |
| `doc-writer` | worker | sonnet | high | Writes and updates standalone docs |
| `explorer` | explorer | sonnet | medium | Read-only codebase search |
| `web-researcher` | explorer | sonnet | medium | Read-only web research |

The main session acts as an orchestrator that routes work instead of doing it.
A triage ladder sends questions to explorers, bounded changes straight to a worker, and ambiguous work to an advisor for a plan first.
Advisors never edit project files: they hold `Write` and `Edit` only to keep their own memory and, for the planning advisors, to write plan files, and a hook blocks every other path.
Advisors and explorers are read-only by instruction: the hook and the tool lists cover `Write` and `Edit`, not `Bash` (see [Security notes](#security-notes)).
Every code change goes through `code-reviewer`, and confirmed findings go to `fixer` until the review approves.
The orchestrator commits once the review passes: in-place workers never commit, and only `parallel-implementer` commits, on its own worktree branch.
Independent parallel work runs through `parallel-implementer` worktrees, and agent teams are reserved for work whose contracts change mid-build.
No agent runs on Fable unless you ask for it.
Security review runs only when you ask for one, and always in its own sub-agent so the main session's transcript stays clear of it.
Its findings come in confirmed and plausible groups, and fixes are re-reviewed until its verdict is ADVISORY ONLY.

The full playbook, together with the shared coding rules the agents follow, is in `claude/CLAUDE.md`.
The two explorers skip `CLAUDE.md` (`omitClaudeMd: true`) and restate the one rule they need.

## Prerequisites

- Claude Code 2.1.293 or later.
  Builds before 2.1.280 fail the Opus 5.5 model pins instead of falling back, and builds before 2.1.293 do not support Haiku 5.5.
- Access to Opus 5.5, Sonnet 5.5 and Haiku 5.5 through the Anthropic API.
  Fable 5.1 is optional: an agent uses `model: fable` only when you ask for it.
  The model pins in `env` are Anthropic API model IDs.
  On Amazon Bedrock, Google Vertex AI or Microsoft Foundry, set the four `ANTHROPIC_DEFAULT_*_MODEL` values in `~/.claude/settings.json` to your provider's model IDs; values you set there are kept on every later install.
  Set them before running `./install.sh`, because install adds any pin that is missing, including `ANTHROPIC_DEFAULT_HAIKU_MODEL` for existing installs that left `haiku` unpinned.
- macOS or Linux.
- `bash`, `git` and `jq`.
- `python3`, which `scripts/check.sh` requires and `hooks/bash-guard.sh` needs.
  Without it the Bash guard fails open and checks nothing.
- Node.js with `npx`, which `install.sh` uses to run the [skills CLI](https://skills.sh).
- `tmux` is optional.
  `tmux/tmux.conf` needs tmux 3.3 or later: `allow-passthrough` is new in 3.3, and `extended-keys` and `terminal-features` need 3.2.
  It turns on `allow-passthrough`, so desktop notifications and the progress bar leave tmux, `extended-keys`, so Shift+Enter inserts a newline instead of submitting, and mouse mode, so wheel scrolling reaches Claude Code's fullscreen renderer instead of tmux.

## Install

> **Warning: installing applies bypass permissions mode and a broad allow list.**
> The committed defaults in `claude/settings.json` are the owner's personal settings, not conservative ones.
> They set `permissions.defaultMode` to `bypassPermissions` and `skipDangerousModePermissionPrompt` to `true`, so Claude Code runs commands and edits files without asking, and they allow `Read(*)` and a long list of `Bash` commands.
> Any of these that your `~/.claude/settings.json` does not already set are added to it.
> Review `claude/settings.json` before running `install.sh`.
> To get prompts back afterwards, set `permissions.defaultMode` (for example to `default`) and `skipDangerousModePermissionPrompt` to `false` in `~/.claude/settings.json`; scalar values you set there stick on every later run.
> Default allow entries come back on the next install even if you remove them, so dropping them for good needs a fork that edits `claude/settings.json`.
> See [Your settings](#your-settings).

```bash
git clone https://github.com/theishandubey/claude-config.git ~/claude-config
cd ~/claude-config
./install.sh --dry-run
./install.sh
```

`--dry-run` prints every planned change and exits without touching anything.
Afterwards start `claude` and run `/memory` to see which instruction files loaded.

### Cloud sessions

Cloud sessions on claude.ai/code do not see your local `~/.claude`, so without this config they add Claude attribution to commits and PRs and run without the agent roster.
To install the config in every cloud session, open your cloud environment's settings at claude.ai/code and paste this into **Setup script**:

```bash
set -euo pipefail
command -v jq >/dev/null || { apt-get update && apt-get install -y jq; }
if [ -d /opt/claude-config/.git ]; then
  git -C /opt/claude-config pull --ff-only
else
  git clone --depth 1 https://github.com/theishandubey/claude-config.git /opt/claude-config
fi
/opt/claude-config/install.sh --yes
```

The setup script runs as root before Claude Code starts, so the config lands in `/root/.claude`.
Clone to a fixed path: the installer links into the clone, so the clone must stay in place.
Leave out `--clean`, because a fresh container has nothing stale to remove.
The installer needs network access to `github.com` and `registry.npmjs.org`; if the environment's network level blocks either, allow them with a custom domain list or pass `--no-skills` to skip the skills.
Cloud environments cache the setup result, so changes pushed to this repo reach cloud sessions only after the setup script runs again.

The cloud docs confirm that a setup script can add `~/.claude/CLAUDE.md`, but not that cloud sessions read a user-level `~/.claude/settings.json`.
After the first setup, have a cloud session make a commit and check `git log -1 --format=%B` for `Co-Authored-By` and `Claude-Session` lines, and run `/agents` to confirm the roster loaded.

### What install.sh changes

| Target | Source |
|---|---|
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

`claude/settings.json` holds the owner's own settings as the defaults:

- Bypass permissions mode, with the dangerous-mode prompt skipped.
- A broad allow list and a short deny list (see [Permissions](#permissions)).
- A `PreToolUse` hook on `Bash` that blocks destructive commands (see [Permissions](#permissions)).
- The `opus` model, the dark theme, the fullscreen TUI, the `latest` update channel and notifications turned on.
- The `fable`, `opus`, `sonnet` and `haiku` model alias pins, the agent teams flag and `CLAUDE_AUTOCOMPACT_PCT_OVERRIDE` set to `50` (auto-compact at half the auto-compact window instead of near the context limit) in `env`, and `switchModelsOnFlag` set to `false`.
- `plansDirectory` set to `./plans/mode`, so plan mode writes its plan files into `plans/mode/` in each project, apart from the numbered advisor plans in `plans/`.
- Empty commit and pull request attribution, with the session URL off.
- The worktree and teammate settings the agent roster relies on.
- The `claude-mods` marketplace and the `meter`, `agent-graph` and `statusline` plugins, enabled (see [Plugins](#plugins)).

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
- If your file cannot be read, is not valid JSON, is not a single JSON object or holds more than one JSON document, `install.sh` prints an error, exits with status 1 and leaves the file untouched.
- If nothing would change, it prints `ok:` and writes nothing.
  Otherwise it writes the file atomically with mode 600 and lists what it added, for example `update: ~/.claude/settings.json (added: permissions.deny[...], env.X)`.

Deletions do not stick: there is no record of what a previous run wrote, so a default you removed from `~/.claude/settings.json` comes back on the next run.
This includes `permissions.allow` and `permissions.deny` entries.
To drop a committed default for good, edit `claude/settings.json` in a fork.

Because your values win, a `permissions.defaultMode` you already set is kept, and so are your own `model`, `theme` and the rest.
To leave bypass mode on a machine that has already installed the defaults, set `permissions.defaultMode` to another mode and `skipDangerousModePermissionPrompt` to `false` in `~/.claude/settings.json`.
Set values instead of deleting keys: a default you delete comes back on the next run.
Read [Security notes](#security-notes) before keeping bypass mode.

### Permissions

The committed allow list approves:

- `Edit` on the agent-memory directories and on `plans/*.md` and `advisor-plans/*.md`, so planning advisors can write plan files.
- `Read(*)`.
- `Bash(mkdir:*)`.
- `Bash` prefixes for common toolchains: `node`, `npm run`, `npm test`, `npx`, `pnpm`, `yarn`, `python`, `pytest`, `pip install`, `cargo`, `go` and `make`.
- `Bash` prefixes for `git branch`, `git add`, `git commit`, `git checkout` and `git worktree`.

Read-only commands such as `ls`, `cat`, `grep`, `find`, `git status`, `git diff` and `git log` are left off on purpose: Claude Code approves their read-only invocations itself, while a prefix rule like `Bash(find:*)` would also approve `find -delete`.

The committed deny list blocks force pushes, `git reset --hard` and `rm -rf`.
A `PreToolUse` hook on `Bash`, `hooks/bash-guard.sh`, backs it up as a second layer.
It blocks the following wherever the flags appear, including inside compound commands such as `cd x && rm -rf y`:

- `rm` with both a recursive and a force flag, in any order and spelling (`-rf`, `-fr`, `-r -f`, `/bin/rm -Rf`).
- `git push` with `--force`, `-f`, `--force-with-lease`, `--force-if-includes`, `--mirror` or a `+refspec`, unless `-n` or `--dry-run` is also given.
- `git reset --hard`.
- `git clean -f`, unless `-n` or `--dry-run` is also given.
- `git checkout` with `.`, with paths after `--`, with `--pathspec-from-file` or with `-f`/`--force`, `git switch` with `-f`, `--force` or `--discard-changes`, and `git restore` that is not staged-only.
- `find` with `-delete`, or with `-exec`, `-execdir`, `-ok` or `-okdir` running any command above (`rm`, `bash -c "..."` and so on).

It unwraps `sudo`, `doas`, `env`, `xargs`, `timeout`, `nice`, `ionice`, `time`, `nohup`, `exec` and `command`, and it looks inside `bash -c "..."` (also `sh`, `zsh` and `dash`, with options such as `-o pipefail` or `-ec`), here-strings and heredocs fed to a shell, `$(...)` and backticks.
It does not inspect `eval`, variables, scripts written to disk, commands piped into a shell (`... | bash`), `env -S` or heredocs for commands other than a shell, including substitutions inside their bodies.
`-h` and `--help` on a git subcommand are allowed when given as flags.
The hook needs `python3` and allows every command without it, so the deny rules are then the only guard.
`install.sh` re-adds the committed hook entry on every run, because arrays merge by exact match.
To drop it for good, fork the repo and remove it from `claude/settings.json`, the same as for allow entries.
It is an accident guard, not a security boundary.
In bypass mode the allow list adds nothing for tool calls, so it matters when you switch to a mode that prompts.
Allow and deny rules are prefix matches, and deny rules still apply in bypass mode; see [Security notes](#security-notes).

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
│   ├── CLAUDE.md               # shared coding rules and orchestration playbook, linked to ~/.claude/CLAUDE.md
│   └── settings.json           # committed defaults, merged into your ~/.claude/settings.json
├── hooks/                      # PreToolUse guards (memory-write-guard.sh, bash-guard.sh), linked to ~/.claude/hooks
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
- **Hooks**: `hooks/memory-write-guard.sh` is wired per agent through its `hooks:` frontmatter, and `hooks/bash-guard.sh` is wired session-wide through the `hooks` key in `claude/settings.json`.
- **Settings**: fork the repo to change the committed defaults, and edit `~/.claude/settings.json` for values that win over them on your machine.
- **tmux**: edit `tmux/tmux.conf`; it is linked live.

## Updating

```bash
git pull && ./install.sh
```

`install.sh` reinstalls the third-party skills from upstream, so a re-run also brings them up to date.
`npx skills update -g` updates installed skills without it, and `claude plugin update <name>@claude-mods` updates a plugin.
Updating an existing install merges in bypass mode and the allow list unless you already set those values; see the warning under [Install](#install).

## Uninstalling

```bash
./install.sh --uninstall --dry-run
./install.sh --uninstall
```

This removes the links and restores the newest `.bak.<timestamp>` backup at each path.
`~/.claude/settings.json` is your file and is kept as it is.
The kept `hooks` entry for the Bash guard becomes a no-op once the `~/.claude/hooks` link is gone.
A legacy symlink into this repo is the exception: it is replaced by the newest backup if there is one, otherwise by a copy of the file it points to, and a dangling one is removed.
Installed skills (`npx skills remove -g <name>`) and plugins (`claude plugin uninstall`) are left alone.

## Plugins

The committed defaults enable three plugins from the public [`claude-mods`](https://github.com/theishandubey/claude-mods) marketplace:

- `meter` draws a band above the prompt with context, prompt cache, usage limits and cost, and `/meter` opens a detailed metrics pane.
- `agent-graph` graphs running subagents: a card graph in the desktop app and an indented tree in the terminal, opened with `/agent-graph`.
- `statusline` draws a status line under the prompt in the terminal with the model and effort, the working directory and the git state.

`claude/settings.json` declares the marketplace in `extraKnownMarketplaces` and turns the plugins on in `enabledPlugins`, and `install.sh` merges both into your settings.
The declaration does not fetch anything, so each machine runs these once:

```bash
claude plugin marketplace add https://github.com/theishandubey/claude-mods.git
claude plugin install meter@claude-mods --scope user
claude plugin install agent-graph@claude-mods --scope user
claude plugin install statusline@claude-mods --scope user
```

To run without a plugin, set its `enabledPlugins` entry to `false` in `~/.claude/settings.json`.

## Security notes

- The committed defaults enable bypass permissions mode and skip its confirmation prompt, so installing them removes the permission prompts on your machine.
  Review `claude/settings.json` first, and change the values in `~/.claude/settings.json` if you want prompts back.
- The allow list is broad, and allow rules are prefix matches too: `Bash(npx:*)`, `Bash(python:*)` and `Bash(node:*)` approve arbitrary code.
- Deny rules still apply in bypass mode: Claude Code 2.1.291 describes bypass as auto-approving every tool call except explicit deny rules.
- `permissions.deny` rules are prefix matches, where `:*` means "starts with".
  `Bash(rm -rf:*)` does not match `rm -fr`, and `Bash(git push --force:*)` does not match `git push origin main --force` (flag after the refspec), `git push --force-with-lease` or a `+refspec` push.
  They guard against accidents, not against a hostile model or prompt injection.
- `hooks/bash-guard.sh` is a session-wide `PreToolUse` hook on `Bash` that closes those gaps: it checks every segment of a compound command and blocks destructive `rm`, `git push`, `git reset`, `git clean`, `git checkout`, `git switch`, `git restore` and `find` invocations whatever the order of their flags.
  It fails open without `python3` and on commands it cannot parse, and it does not inspect `eval`, variables, encoded strings, scripts written to disk, commands piped into a shell, `env -S` or heredoc bodies of commands other than a shell, so it is an accident guard and not a security boundary.
- `hooks/memory-write-guard.sh` blocks `Write` and `Edit` outside agent memory and plan files for advisor agents.
  Those agents also hold `Bash`, so the guard enforces a workflow convention and is not a security boundary.
  `explorer` holds `Bash` too, with `Write` and `Edit` disabled, so it is read-only by instruction as well; `web-researcher` has no `Bash`.
- Third-party skills are installed unpinned from the upstream repositories recorded in `skills-lock.json` when you run `install.sh`, and they run with the agent's full permissions.
  Review `~/.claude/skills/<name>/SKILL.md` and drop any you do not trust from the manifest.
- Nothing in `install.sh` runs with elevated privileges.
  `--dry-run` shows every change first, and `--uninstall` removes the links and restores backups.
- Report a vulnerability privately through GitHub's private vulnerability reporting on this repository (Security tab, "Report a vulnerability"), not in a public issue.

## Working on this repo

There is no `CONTRIBUTING.md`; this section is the contributor guide.

- Run `scripts/check.sh` before opening a pull request.
  It validates the JSON files, lints the shell scripts when `shellcheck` is installed, validates agent frontmatter, tests the memory-write and Bash guards, and runs `install.sh` end to end in a throwaway home directory.
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
- Never commit credentials or machine-local state.

## License

MIT, see `LICENSE`.
