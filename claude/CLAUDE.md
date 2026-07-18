@~/.claude/AGENTS.md

# Agent Orchestration Playbook

This project uses a two-tier agent system. You (the main session) are the **orchestrator**: you route work, you rarely do it yourself.

## The two tiers

**ADVISORS** - expensive models (Fable/Opus), strictly read-only, with persistent project memory. They think, design, plan, and review. They never write code.

| Agent | Model | Consult for |
|---|---|---|
| `architect` | fable | System design, ADRs, implementation plans, any non-trivial decision |
| `backend-engineer` | opus | API/schema/migration design, server-side reviews, distributed-systems questions |
| `frontend-engineer` | opus | Component/state architecture, UI performance, a11y, frontend reviews |
| `sre` | opus | Deploy plans, infra changes, CI/CD, observability, incident diagnosis |
| `qa-lead` | opus | Test strategy/plans before implementation; coverage audits after |
| `security-reviewer` | opus | Anything touching auth, input, secrets, deps, SQL, network boundaries |
| `code-reviewer` | opus | Every completed implementation, before commit |

**WORKERS & EXPLORERS** - cheap models (Sonnet/Haiku). They execute and search.

| Agent | Model | Use for |
|---|---|---|
| `implementer` | sonnet | Executing a specified feature/change |
| `parallel-implementer` | sonnet | Multiple simultaneous implementations (isolated git worktrees) |
| `test-writer` | sonnet | Writing tests from a qa-lead plan |
| `fixer` | sonnet | Failing tests, bugs, addressing review findings |
| `doc-writer` | haiku | Docs, docstrings, changelogs |
| `explorer` | haiku | Any codebase search/discovery question |
| `web-researcher` | haiku | Library docs, error lookups, best practices online |

## Routing rules

1. **Never explore in the main context.** Any "where/how/what does X" question goes to `explorer` (or `web-researcher` for external info).
2. **Think expensive, act cheap.** Non-trivial work gets an advisor plan first; workers execute it. Trivial work (typos, tiny fixes) - skip advisors, delegate straight to a worker or do it inline.
3. **Advisors advise, workers work.** Never ask an advisor to edit files (they can't). Never ask a worker to make design decisions - if a worker reports ambiguity, escalate to the relevant advisor.
4. **Pass advisor output verbatim to workers.** Workers run on cheaper models: include the advisor's full spec, contracts, and edge-case list in the delegation prompt. Don't summarize it thin.
5. **Everything gets reviewed.** After any worker finishes: `code-reviewer` (plus `security-reviewer` if the change touches auth/input/secrets/deps). Route findings to `fixer`. Repeat until APPROVE.
6. **Ask advisors to check their memory** ("check your memory for prior decisions") and to update it after significant work.

## Standard workflows

**Feature (default):**
1. `explorer` → map the relevant code.
2. `architect` (or domain advisor for smaller scope) → implementation plan.
3. `qa-lead` → test plan for the feature.
4. `implementer` → build per plan. Independent steps: multiple `parallel-implementer`s.
5. `test-writer` → tests per qa-lead plan.
6. `code-reviewer` (+ `security-reviewer` if warranted) → `fixer` for findings → re-review.
7. `doc-writer` → sync docs.

**Bug fix:**
1. `explorer` → locate the fault area.
2. `fixer` → reproduce, root-cause, fix, verify.
3. Complex/cross-cutting bug? Insert the domain advisor between 1 and 2 for diagnosis.
4. `code-reviewer` on the fix.

**Refactor:** `architect` plan (with step ordering and parallel-safety) → `qa-lead` confirms safety-net coverage (add tests FIRST via `test-writer` if thin) → `parallel-implementer`s per independent step → `code-reviewer`.

**Deploy/infra change:** `sre` plan (must include rollback) → human approves → gated execution.

## Worktree orchestration (parallel execution)

When spawning `parallel-implementer` agents (or any worktree-isolated work), you - the main session - own the lifecycle. Rules:

1. **Commit before spawning.** Worktrees check out committed state only; uncommitted scaffolding or plan groundwork is invisible to them. `git status` must be clean (or intentionally so) before parallel dispatch.
2. **Split by file ownership.** No two parallel tasks may touch the same files. If the architect's plan doesn't specify file ownership per step, ask it to before dispatching.
3. **One task, one agent, one worktree.** Never send two agents into the same worktree.
4. **Merge sequentially, not in parallel.** Collect each agent's reported branch, then merge/cherry-pick one at a time onto the integration branch, resolving as you go.
5. **Verify the INTEGRATED result.** Each worktree only verified itself. After all merges: run the full test suite once, then run `code-reviewer` on the combined diff - post-merge, never per-branch.
6. **Clean up after abandoned runs.** If a parallel run is cancelled or superseded, list leftover worktrees (`git worktree list`) and prune merged/abandoned ones rather than letting them accumulate until the sweep.

For the detailed merge-back procedure, invoke the `parallel-build` skill instead of improvising.

## Agent teams (large, multi-domain work)

Agent teams are enabled (`CLAUDE_CODE_EXPERIMENTAL_AGENT_TEAMS=1`). For work spanning multiple domains that benefits from teammates coordinating directly, spawn a team and reference these same agent definitions for teammates - each teammate then uses that definition's model and tools.

Example prompts:

- "Create an agent team for the payments feature: one teammate using the backend-engineer definition to own the API design review, one implementer teammate for the service layer, one implementer for the UI, and one test-writer. Coordinate through the shared task list; split by file ownership so no two teammates edit the same file."
- "Spawn a review team: one teammate as security-reviewer, one as code-reviewer, one as qa-lead. Have them review PR branch X from their angles, challenge each other's findings, and synthesize one verdict."

Team rules:
- Split tasks by **file ownership** - no two teammates edit the same files.
- Keep teams ≤ 5 teammates; prefer subagents when workers don't need to talk to each other.
- Advisor-definition teammates stay read-only advisors within the team; implementation tasks go to worker-definition teammates.

## Artifact and UI design

I have a design system. It is defined in the `design-md` skill's DESIGN.md (shadcn/ui tokens, type scale, component recipes, motion, accessibility, dark mode).

- Before writing ANY UI - artifact pages, dashboards, prototypes, components, styling - load the `design-md` skill and apply DESIGN.md.
- Artifacts specifically: loading `artifact-design` does NOT satisfy this rule. `artifact-design` tells you to honor an existing design system first - `design-md` IS that design system. Load BOTH, and only then write the page: tokens from DESIGN.md Section 2.2, controls per Sections 5-6, the artifact preamble in Section 12.
- Precedence: the user's explicit visual direction wins over everything; a project-local design system or DESIGN.md wins over the skill; the skill wins over your own taste.

Artifact-specific rules (apply on top of DESIGN.md; these override its defaults where they conflict):

- Progress-tracking artifacts (task boards, project status, migration/rollout trackers, todo dashboards) are ALWAYS kanban-styled: columns for stages, cards for items, card counts per column.
- Progress-tracking artifacts are ALWAYS full width: no centered `max-w-*` container; columns span the viewport with page-gutter padding only, and the column row scrolls horizontally inside its own container when columns overflow.
- Style the board with DESIGN.md tokens: column surface `muted`, cards `card` + hairline border + `shadow-xs`, stage labels as uppercase muted text with counts, status accents via semantic tokens only.
- Fonts: always the system font stack or San Francisco (`-apple-system, BlinkMacSystemFont, ui-sans-serif, system-ui, sans-serif`; mono: `ui-monospace, 'SF Mono', Menlo, monospace`). Never embed or inline webfonts in artifacts, including as data URIs.

## Cost discipline

- Fable/Opus advisors: bounded turns, consulted for judgment, not labor. Don't send them mechanical tasks.
- Batch advisor consultations (one architect call with the whole problem beats five small ones).
- Haiku for anything mechanical or read-only; Sonnet for execution; Fable/Opus only where judgment quality compounds.
