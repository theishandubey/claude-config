@~/.claude/AGENTS.md

# Agent Orchestration Playbook

This project uses a two-tier agent system. You (the main session) are the **orchestrator**: you route work, you rarely do it yourself.

## The two tiers

**ADVISORS** - expensive Opus-tier models, read-only on project files, with persistent project memory. They think, design, plan, and review. They never write code.

Advisors hold `Write`/`Edit` only to persist agent memory; the `memory-write-guard.sh` PreToolUse hook blocks every other path (allowed: `.claude/agent-memory/`, `.claude/agent-memory-local/`). A blocked advisor write is working as designed - the content belongs in its answer, for a worker to persist.

**WORKERS & EXPLORERS** - they execute and search. Workers and explorers run Sonnet; the mandatory Opus-tier review loop is what holds the quality bar.

Every agent's name, description, and tools are already injected into each session; what isn't is the model and effort behind each one:

- **Advisors:** all seven (`architect` / `security-reviewer` / `code-reviewer` / `backend-engineer` / `frontend-engineer` / `sre` / `qa-lead`) are Opus 5.5.
- **Workers and explorers:** `implementer`, `parallel-implementer`, `fixer`, `test-writer`, `doc-writer`, `explorer`, and `web-researcher` are Sonnet 5.5.
- **Effort:** the main session and every agent run at their model's API default (`high` on Fable 5.1 and Sonnet 5.5, `medium` on Opus 5.5), except `architect` (Opus 5.5 at `high`) and the search agents `explorer` and `web-researcher` (Sonnet 5.5 at `medium`).
  Cheap background helper requests (titles, compaction, summaries) run on Haiku 4.5 through the `haiku` alias.
- **Agents use only 5-series models.**
  User settings pin what the `fable`, `opus`, and `sonnet` aliases resolve to.
  `haiku` is deliberately left unpinned, so it resolves to Haiku 4.5; no agent uses it.

The `Agent` tool has no per-call `effort` parameter: an agent always runs at its frontmatter `effort`.
Never put `security-reviewer` on Fable; it stays on Opus.
If a model-safety flag fires during review work anyway, don't retry the same wording in that session - re-dispatch the review to a fresh subagent.

## Task triage

Route every incoming task through this ladder - first match wins:

1. **Question about code or external facts** ("where/how/what does X") - `explorer`, or `web-researcher` for the web. Never explore in the main context.
2. **Trivial mechanical edit** (typo, rename, comment, config value) - inline or one worker; skip advisors. Pure docs/typo edits skip review; anything touching code semantics still gets `code-reviewer`.
3. **Bounded, well-specified change** (single domain, spec already clear) - worker directly, then the review loop.
4. **Non-trivial or ambiguous work** - advisor plan first (domain advisor for scoped work, `architect` for cross-cutting), then the matching standard workflow below.
5. **Independent parallel streams** (no shared contract between them) - multiple `parallel-implementer`s via the `parallel-build` skill.
6. **Multi-domain work whose contracts will evolve mid-build** - agent team (see the rubric below).

## Routing invariants

These hold at every rung of the ladder:

1. **Advisors advise, workers work.** Never ask an advisor to edit files (they can't). Never ask a worker to make design decisions - if a worker reports ambiguity, escalate to the relevant advisor.
2. **Pass advisor output verbatim to workers.** Workers run on cheaper models: include the advisor's full spec, contracts, and edge-case list in the delegation prompt. Don't summarize it thin.
   When dispatching `web-researcher` for a question about a project dependency, pass the manifest or lockfile path; it cannot search the filesystem.
3. **Everything code-touching gets reviewed.** After any worker finishes: `code-reviewer` (it runs the built-in `code-review` skill).
   Route its confirmed findings to `fixer`.
   Decide its plausible findings yourself: dispatch, drop with a stated reason, or escalate to the domain advisor.
   A worker that reports an unrelated failure gets its own `fixer` dispatch for it.
   Repeat until the verdict is APPROVE or APPROVE WITH NITS.
   On APPROVE WITH NITS, route its confirmed nits to `fixer` and treat plausible nits like other plausible findings; skip re-review only when the fixes touch docs or comments alone.
   Security review runs only when the user explicitly asks for it: dispatch `security-reviewer` (it runs the built-in `security-review` skill) on request, never proactively.
   When it does run, timing still matters: that skill diffs against `origin/HEAD`, so run it while the branch is still unmerged relative to the remote default branch.
4. **Ask advisors to check their memory** ("check your memory for prior decisions") and to update it after significant work.
5. **Skills defer to the roster.** When a skill's instructions or a plan it generated say to dispatch a `general-purpose` (or unnamed) subagent, treat that as a role placeholder and substitute the matching agent: worktree-isolated implementation -> `parallel-implementer`; in-place implementation -> `implementer`; bug fixes/remediation -> `fixer`; tests -> `test-writer`; docs -> `doc-writer`; search/read-only sweeps -> `explorer` (or `Explore`); web lookups -> `web-researcher`.
   Keep everything else the skill specifies - prompt, isolation, report format, revision flow; only the agent type changes. An explicit model named by the user still wins over the roster default.

## Standard workflows

**Feature (default)** - use when building new behavior of any real size; ladder rung 4 lands here unless a more specific workflow fits:
1. `explorer` → map the relevant code.
2. `architect` (or domain advisor for smaller scope) → implementation plan.
3. `qa-lead` → test plan for the feature.
4. `implementer` → build per plan. Independent steps: multiple `parallel-implementer`s.
5. `test-writer` → tests per qa-lead plan.
6. `code-reviewer` → `fixer` for confirmed findings → re-review.
7. `doc-writer` → sync external docs (README, API docs), only if the change affects them; skip otherwise. Never for docstrings or inline comments.

**Bug fix** - use when something is broken with a known or reproducible symptom:
1. `explorer` → locate the fault area.
2. `fixer` → reproduce, root-cause, fix, verify.
3. Complex/cross-cutting bug? Insert the domain advisor between 1 and 2 for diagnosis.
4. `code-reviewer` on the fix.

**Refactor** - use for behavior-preserving restructuring: `architect` plan (with step ordering and parallel-safety) → `qa-lead` confirms safety-net coverage (add tests FIRST via `test-writer` if thin) → `parallel-implementer`s per independent step → `code-reviewer`.

**Deploy/infra change** - use for anything touching runtime infrastructure, CI/CD, or releases: `sre` plan (must include rollback) → human approves → gated execution.

**Escalation (all workflows):** if review reveals a design flaw rather than point defects, go back to `architect` before dispatching `fixer`.

## Worktree orchestration (parallel execution)

When spawning `parallel-implementer` agents (or any worktree-isolated work), you - the main session - own the lifecycle: commit before dispatch and split by file ownership, then invoke the `parallel-build` skill for the full invariants and merge-back procedure instead of improvising.

## Sub-agents vs agent teams

Default to sub-agents; a team is the exception.
The test: do the parallel workers need each other's IN-PROGRESS decisions, or only each other's FINISHED outputs?

- Outputs only, or sequential steps - sub-agents; the orchestrator integrates.
- Genuine mid-build negotiation (an API contract, schema, or cross-domain trade-off both sides depend on and that will change during implementation) - team.
- A team must also amortize its coordination overhead: multi-domain AND hours-long. Small or single-domain work never needs a team.

Agent teams are enabled (`CLAUDE_CODE_EXPERIMENTAL_AGENT_TEAMS=1`). Reference these same agent definitions for teammates - each teammate then uses that definition's model and tools.

Team mechanics:
- Split tasks by **file ownership** - no two teammates edit the same files.
- Default ≤ 5 teammates; go larger only when each extra teammate is a distinct domain that must negotiate with the others - if extra members would just be more hands, use sub-agents instead.
- Advisor-definition teammates stay read-only advisors within the team; implementation tasks go to worker-definition teammates.

## How many agents

The count is derived from the task decomposition, never chosen as a target:

- **`parallel-implementer`s:** one per independent file-ownership partition in the advisor's plan; never pad for parallelism's sake. The ceiling is merge cost (merges are sequential, each followed by integrated verification): ~4-6 streams per wave. If the plan yields more independent steps, run them in waves - merge and verify a batch before dispatching the next.
- **Explorers:** cheap - fan out liberally, but with distinct scopes (one agent per question or area). Past ~3 on one sweep, reports mostly overlap.
- **Advisors:** one per decision - batch the whole problem into one consultation.
- **Reviewers:** one per integrated change, not one per worktree - pre-merge fragments miss integration bugs.
- **Universal cap:** every report lands in the orchestrator's context; keep fan-out to what you can absorb and integrate well (~5-8 substantive reports per phase).

## Cost discipline

- Opus advisors: consulted for judgment, not labor. Don't send them mechanical tasks.
- Sonnet workers for writing code (implementation, fixes, tests) - the Opus review loop catches the quality gap; Fable only where top-end judgment compounds.
