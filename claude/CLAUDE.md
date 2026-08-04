@~/.claude/AGENTS.md

# Agent Orchestration Playbook

This project uses a two-tier agent system. You (the main session) are the **orchestrator**: you route work, you rarely do it yourself.

## The two tiers

**ADVISORS** - expensive models (Fable/Opus), read-only on project files, with persistent project memory. They think, design, plan, and review. They never write code.

Advisors hold `Write`/`Edit` solely so they can persist their agent memory; a `PreToolUse` hook (`hooks/memory-write-guard.sh`) blocks every path outside the agent-memory directories (`.claude/agent-memory/`, `.claude/agent-memory-local/`). That is what makes "never writes code" an enforced guarantee rather than a prompt instruction - so if an advisor reports a blocked write, it is working as designed, and the content belongs in its answer for a worker to persist.

**WORKERS & EXPLORERS** - they execute and search. Code-writing workers run Opus; doc-writer and the explorers run Sonnet.

Every agent's name, description, and tools are already injected into each session; what isn't is the model and effort behind each one:

- **Advisors:** `architect` is Fable 5 at `xhigh`. `security-reviewer` is Opus 5 at `xhigh`; `code-reviewer` / `backend-engineer` / `frontend-engineer` / `sre` / `qa-lead` Opus 5 at `high`.
- **Workers and explorers:** `implementer`, `parallel-implementer`, `fixer`, and `test-writer` are Opus 5 at `high`; `doc-writer`, `explorer`, and `web-researcher` stay Sonnet 5 at `high`. No agent runs below `high`.

Raise effort per call with the `Agent` tool's `effort` parameter when a specific task warrants it. Never put `security-reviewer` on Fable: its safety classifiers target offensive-security content and can refuse benign defensive review.

## Routing rules

1. **Never explore in the main context.** Any "where/how/what does X" question goes to `explorer` (or `web-researcher` for external info).
2. **Think expensive, act cheap.** Non-trivial work gets an advisor plan first; workers execute it. Trivial work (typos, tiny fixes) - skip advisors, delegate straight to a worker or do it inline.
3. **Advisors advise, workers work.** Never ask an advisor to edit files (they can't). Never ask a worker to make design decisions - if a worker reports ambiguity, escalate to the relevant advisor.
4. **Pass advisor output verbatim to workers.** Workers run on cheaper models: include the advisor's full spec, contracts, and edge-case list in the delegation prompt. Don't summarize it thin.
5. **Everything gets reviewed.** After any worker finishes: `code-reviewer` (plus `security-reviewer` if the change touches auth/input/secrets/deps). Route findings to `fixer`. Repeat until APPROVE.
6. **Ask advisors to check their memory** ("check your memory for prior decisions") and to update it after significant work.
7. **Skills defer to the roster.** When a skill's instructions or a plan it generated say to dispatch a `general-purpose` (or unnamed) subagent, treat that as a role placeholder and substitute the matching agent: worktree-isolated implementation -> `parallel-implementer`; in-place implementation -> `implementer`; bug fixes/remediation -> `fixer`; tests -> `test-writer`; docs -> `doc-writer`; search/read-only sweeps -> `explorer` (or `Explore`); web lookups -> `web-researcher`.
   Keep everything else the skill specifies - prompt, isolation, report format, revision flow; only the agent type changes. An explicit model named by the user still wins over the roster default.

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

When spawning `parallel-implementer` agents (or any worktree-isolated work), you - the main session - own the lifecycle: commit before dispatch, split by file ownership, one agent per worktree, merge sequentially, and verify the integrated result. Invoke the `parallel-build` skill for the full invariants and merge-back procedure instead of improvising.

## Agent teams (large, multi-domain work)

Agent teams are enabled (`CLAUDE_CODE_EXPERIMENTAL_AGENT_TEAMS=1`). For work spanning multiple domains that benefits from teammates coordinating directly, spawn a team and reference these same agent definitions for teammates - each teammate then uses that definition's model and tools.

Team rules:
- Split tasks by **file ownership** - no two teammates edit the same files.
- Keep teams ≤ 5 teammates; prefer subagents when workers don't need to talk to each other.
- Advisor-definition teammates stay read-only advisors within the team; implementation tasks go to worker-definition teammates.

## Artifact and UI design

I have a design system. It is defined in the `design-md` skill's DESIGN.md (shadcn/ui tokens, type scale, component recipes, motion, accessibility, dark mode).

- Before writing ANY UI - artifact pages, dashboards, prototypes, components, styling - load the `design-md` skill and apply DESIGN.md.
- Artifacts specifically: loading `artifact-design` does NOT satisfy this rule. `artifact-design` tells you to honor an existing design system first - `design-md` IS that design system. Load BOTH, and only then write the page: tokens from DESIGN.md Section 2.2, controls per Sections 5-6, the artifact preamble in Section 12, and the artifact rules in Section 13 (kanban progress boards, full-width layout, system font stack, never webfonts) which override the general defaults where they conflict.
- Precedence: the user's explicit visual direction wins over everything; a project-local design system or DESIGN.md wins over the skill; the skill wins over your own taste.

## Cost discipline

- Fable/Opus advisors: bounded turns, consulted for judgment, not labor. Don't send them mechanical tasks.
- Batch advisor consultations (one architect call with the whole problem beats five small ones).
- Opus workers for writing code (implementation, fixes, tests); Sonnet for docs, search, and anything mechanical; Fable only where top-end judgment compounds.
