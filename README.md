# dotclaude

An installable Claude Code setup: a three-tier agent roster, the orchestrator playbook that drives it, shared coding rules, two guard hooks, vendored skills, personal settings defaults and a tmux config.
`install.sh` links it into `~/.claude` and merges the settings defaults into your own `~/.claude/settings.json`.

## What you get

Twelve subagents in `agents/`:

| Agent | Tier | Model | Effort | Role |
|---|---|---|---|---|
| `architect` | advisor | opus | high | Designs, ADRs, trade-offs and cross-cutting implementation plans |
| `backend-engineer` | advisor | opus | medium | APIs, services, databases, queues, auth, data modeling |
| `frontend-engineer` | advisor | opus | medium | Components, state, rendering performance, accessibility, motion |
| `sre` | advisor | opus | medium | Infrastructure, CI/CD, observability, deployment safety, incidents |
| `qa-lead` | advisor | opus | medium | End-to-end test plans and coverage audits |
| `implementer` | worker | sonnet | high | Builds from a plan, in place |
| `parallel-implementer` | worker | sonnet | high | Builds in its own git worktree, for parallel streams |
| `fixer` | worker | sonnet | high | Bugs, failing tests, merge conflicts and review findings you pass on |
| `test-writer` | worker | sonnet | high | End-to-end tests from a test plan |
| `doc-writer` | worker | sonnet | high | Standalone docs |
| `explorer` | explorer | sonnet | medium | Read-only codebase search |
| `web-researcher` | explorer | sonnet | medium | Read-only web research |

Advisors plan and never edit project files.
Workers implement.
Explorers search, and keep search output out of the main session.

The main session is the orchestrator.
Its playbook, `claude/orchestrator.md`, reaches only the main session: a `SessionStart` hook prints it, so subagents never pay for it.
It routes each request through a triage ladder and commits the work itself.
Code and security review are yours: run `/code-review` and `/security-review` when you want them, and pass on the findings you want fixed.

`claude/CLAUDE.md` holds the shared rules every session and agent follows (the two explorers skip it with `omitClaudeMd` and restate the one rule they need).

Shared agent instructions live in skills instead of being copied into each agent:
- `plan-handoff`: how planning advisors write plans, with the plan template.
- `plan-execution`: how workers execute a plan.
- `e2e-testing`: what an end-to-end test is; the roster never writes unit tests.
- `parallel-build`: the orchestrator's procedure for parallel worktree builds.

## Requirements

- Claude Code 2.1.295 or later (hooks use `onFailure: "block"`).
- Access to Opus 5.5 and Sonnet 5.5; Fable 5.1 is used only when you ask for it.
  On Bedrock, Vertex AI or Foundry, set the `ANTHROPIC_DEFAULT_*_MODEL` values in `~/.claude/settings.json` to your provider's model IDs; values you change are kept on later installs.
- macOS or Linux with `git` and `python3` 3.8 or later.
  The hooks run on `python3` and fail closed: without it, Bash and advisor writes are blocked.
- `tmux` 3.3 or later, optional.

## Install

> **Warning: the settings defaults run Claude Code in bypass permissions mode.**
> `claude/settings.json` sets `permissions.defaultMode` to `bypassPermissions` and skips the dangerous-mode prompt, so Claude Code runs commands and edits files without asking.
> The Bash guard below is an accident guard for catastrophic commands, not a sandbox.
> Read `claude/settings.json` before installing.

```bash
git clone https://github.com/theishandubey/dotclaude.git ~/dotclaude
```

```bash
~/dotclaude/install.sh --dry-run
```

```bash
~/dotclaude/install.sh
```

`--dry-run` prints every planned change and touches nothing.
Changes marked `confirm` (backing up a file you own, or editing your tmux config) ask first; pass `--yes` to skip the question, which is required when not run from a terminal.
A re-run with nothing to do changes nothing.

| Target | What install does |
|---|---|
| `~/.claude/CLAUDE.md` | link to `claude/CLAUDE.md` |
| `~/.claude/agents/<name>.md` | a link per agent in `agents/` |
| `~/.claude/hooks/<name>.py` | a link per hook in `hooks/` |
| `~/.claude/skills/<name>` | a link per skill in `skills/` |
| `~/.claude/settings.json` | your file, with the defaults merged in |
| `~/.tmux.conf` | a link to `tmux/tmux.conf`, or a `source-file` line added to your existing tmux config |

`agents`, `hooks` and `skills` stay real directories, so your own agents, hooks and skills can live next to the linked ones.
An older install that linked a whole directory into a checkout of this repo, including from when it was named claude-config, is converted, and any files of yours that the checkout's git does not track are copied over.
Anything else already at a target is moved to `~/.dotclaude-backups/<timestamp>/` first, never overwritten.
Links into this repo that it no longer provides are removed.

`./install.sh --uninstall` removes the links, restores the newest backups, removes the defaults you did not change from `settings.json`, and removes the tmux line.

### How settings are merged

The installer records the defaults it applied in `~/.claude/dotclaude-state.json` and does a three-way merge on every run, between the previously applied defaults, your file and the new defaults:
- A value you never changed follows the repo, including removal when the repo drops it.
- A value you changed or removed stays as you left it.
- List entries merge one by one, so your own allow rules and hooks survive while the repo's entries are added, updated or retired.

## Guards

`hooks/bash-guard.py` runs before every `Bash` call and blocks only catastrophic, unrecoverable commands:
- recursive `rm`, `find -delete`, `chmod -R` or `chown -R` on the filesystem root, a top-level system directory, a mounted volume, your home directory or its top-level folders, the project, the working directory, or a git repository;
- formatting or overwriting a disk (`mkfs`, `wipefs`, `dd` or a redirect to a raw disk, `diskutil erase*`);
- dropping a database (`DROP DATABASE`, `DROP SCHEMA`, `dropdb`, Redis `FLUSHALL`, `dropDatabase()`, `prisma migrate reset`, `rails db:drop`, and similar);
- destroying infrastructure (`terraform destroy`, `pulumi destroy`, `kubectl delete namespace`, deleting cloud databases, buckets or projects, `gh repo delete`);
- force-pushing or deleting `main` or `master`.

It looks through quoting, `sudo`, `env`, `xargs` and other wrappers, `sh -c` and nested shells, `eval`, command substitution and heredocs fed to a shell or database client.
Everything else, such as `git reset --hard` or `rm -rf build`, runs.
A blocked command is never worked around: the agent asks you to run it.

`hooks/write-guard.py` runs in every advisor before `Write`, `Edit` and `NotebookEdit`.
It allows only the advisor's memory under `.claude/agent-memory/` and, for planning advisors, `plans/NNN-<slug>.md` and `plans/README.md`, after resolving symlinks.
Advisors' `Bash` is read-only by instruction only.

Both guards fail closed: if a hook cannot run, the call is blocked.

The settings also disable the built-in `Explore` and `Plan` agents, which run on the main session's model, so searches go to `explorer` and planning to the advisors.

## Agent memory in worktrees

Advisors keep project memory in `.claude/agent-memory/`.
A session running in a git worktree would otherwise write that memory into the worktree, where it is lost when the worktree goes.
The `SessionStart` hook therefore links the worktree's memory directories to the main checkout's, merging anything already there (an older conflicting file is kept as `*.before-worktree-merge`).
Projects that commit `.claude/agent-memory` to git are left alone.

## Skills

`skills/` holds this repo's own skills and vendored third-party skills, all committed.
`skills-lock.json` records where each vendored skill came from, and `.claude/skills` links to `skills/` so the [skills CLI](https://skills.sh) manages them in place:

```bash
npx skills add <owner/repo> -s <skill> -a claude-code -y
```

```bash
npx skills update -p -y
```

Review the diff before committing an update: vendored skills run with full permissions.

Vendored skills are committed unmodified first, and any adaptation to this setup lands as a separate commit on top, so an update is merged against a visible local diff rather than overwriting it.
These are adapted locally: `verification-before-completion`, `receiving-code-review`, `diagnosing-bugs`, `supabase-postgres-best-practices`, `vercel-react-best-practices`, and every skill vendored from poteto's pstack (the `principle-*` skills, `benchmark-checklist`, `create-verification-skill`, `maintain-verification-skill` and `unslop`).

| Agent | Preloaded vendored skills | Invoked on demand |
|---|---|---|
| `architect` | `codebase-design`, `domain-modeling`, principle: attack-the-premise | |
| `backend-engineer` | `supabase-postgres-best-practices` | `benchmark-checklist` |
| `sre` | principle: fix-root-causes | `diagnosing-bugs`, `supabase-postgres-best-practices`, `benchmark-checklist` |
| `frontend-engineer` | | design, motion and UI skills, `vercel-react-best-practices` |
| `qa-lead` | principle: test-behavior-not-implementation | `create-verification-skill`, `maintain-verification-skill` |
| `fixer` | `verification-before-completion`, `diagnosing-bugs`, `receiving-code-review`, principle: fix-root-causes | |
| `implementer`, `parallel-implementer` | `verification-before-completion` | |
| `test-writer` | `verification-before-completion`, principle: test-behavior-not-implementation | `create-verification-skill`, `maintain-verification-skill` |
| `doc-writer` | `verification-before-completion`, `unslop` | |

The orchestrator writes prose for people through `unslop`.

## Cleanup

`scripts/cleanup.py` removes git worktrees and build caches that are safe to lose.
It only reports what it would do unless you pass `--yes`:

```bash
scripts/cleanup.py --repo ~/code/app --caches ~/code
```

```bash
scripts/cleanup.py --repo ~/code/app --caches ~/code --yes
```

A worktree is removed only when all of these hold:
- it is unlocked, is not the one you run from, and contains no other worktree;
- it has been idle for `--min-age` days (default 7);
- it has no uncommitted or untracked changes, and its only ignored files are build caches, `node_modules`, `.venv`, `.DS_Store` or symlinks, so a local `.env` or database keeps it;
- its HEAD and every commit in its HEAD reflog are merged into the base branch (`origin/HEAD`, then `main`, then `master`, or `--base`).

Its branch is then deleted with `git branch -d`, which refuses unmerged work.
Worktree records whose directory is gone are pruned once they are older than `--min-age`, unless one of them is on an unmounted volume.
Idleness is read from the worktree directory and its git metadata, so a long session that only edits files in subdirectories can look idle; raise `--min-age` if you keep sessions open that long.
Without `--repo` it cleans the repository you run it from.

A build cache is a directory named `.next`, `.nuxt`, `.turbo`, `.parcel-cache`, `.svelte-kit`, `.vite`, `__pycache__`, `.pytest_cache`, `.mypy_cache` or `.ruff_cache`, or a `target` next to a `Cargo.toml`, found under a `--caches` path.
It is removed only when it is inside a git repository, ignored by git, holds no tracked files and has been idle for `--min-age` days.
`node_modules` is never touched.

## Development

```bash
scripts/check.sh
```

It runs the end-to-end tests for both guards, the installer (in a throwaway `HOME`) and the session hook, and checks the agent definitions against this README, the skills they reference, and the playbook.

## Settings defaults

Besides permissions and hooks, `claude/settings.json` sets the owner's preferences: model aliases pinned to the 5-series models, the `opus` model, agent teams, auto-compaction at 50%, empty commit and PR attribution, `plans/mode` as the plan-mode directory, the `claude-mods` plugins, the `latest` update channel, the fullscreen TUI, the dark theme and notifications.
Change any of them in `~/.claude/settings.json`; your values are kept.
