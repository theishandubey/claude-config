---
name: plan-handoff
description: How planning advisors write implementation, test and rollout plans for a worker with zero context - file location, numbering, the plan template, the index and the quality bar. Preloaded by architect, backend-engineer, frontend-engineer, sre and qa-lead.
user-invocable: false
---

# Writing handoff plans

Every plan is executed by a cheaper model that has seen nothing but the plan and the repo.
It follows explicit instructions well and fills gaps badly, so the plan carries all context, verifies every step with a command, and says exactly when to stop.

## Where plans go

- One plan per independently executable unit of work, at `plans/NNN-<slug>.md` in the repository root, numbered in execution order.
  In a multi-repo workspace whose `plans/` sits above the repos, use that one.
- Keep the index in `plans/README.md`.
  If `plans/` already exists, read the index first: keep numbering monotonic, skip work already planned or rejected, and mark a superseded plan `REJECTED` with the number that replaces it.
- If `plans/` serves an unrelated purpose, use `advisor-plans/` instead and say so.
  `plans/mode/` holds plan-mode files; it does not make `plans/` unrelated, and you leave it alone.
- Your write guard allows exactly these files besides your memory.
  Write nothing else, scratch files included.
  If the guard blocks a plan, return its full text under its target path in your answer.
- Finish your answer with each plan's path and a one-line summary.

## Rules

- Fill `Planned at` from `git rev-parse --short HEAD`, and inline every excerpt from your own reads.
- Name exact files and symbols, never "the relevant module".
- Every Verify is a command with its expected result, never a judgment.
- STOP conditions name this plan's real risks, not boilerplate.
- No secret values anywhere: name locations and credential types only.
- Implementation plans never assign new tests: their Checks section lists existing commands to run.
  New tests come only from `qa-lead` test plans, which plan end-to-end tests only.
- Executors in place never branch or commit; a `parallel-implementer` commits on its worktree branch and never pushes.
- Mark every step that mutates shared or production state (apply, migrate, delete, scale, restart, deploy) `REQUIRES HUMAN APPROVAL`.
- A plan that changes a schema, infrastructure or a deploy ends with a Rollback section whose steps have their own Verify commands.
- Plans that may run in parallel share no in-scope file; say which ones in the index's dependency notes.
- End your answer with `Confidence: high`, `medium` or `low`, then the structural questions you could not settle.
  Say `low` whenever the recommendation rests on facts you could not verify; the orchestrator takes low-confidence plans to the user.

## Template

```markdown
# Plan NNN: <imperative title - what is true after this plan>

> Executor: run the drift check first. Follow the steps in order and run every Verify before the next step.
> On any STOP condition, stop and report. Do not edit `plans/README.md`; the orchestrator maintains it.
>
> Drift check: `git diff --stat <planned-at SHA>..HEAD -- <in-scope paths>`
> If an in-scope file changed, compare it with Current state; a mismatch is a STOP condition.

## Status

- Priority: P1 | P2 | P3
- Effort: S | M | L
- Risk: LOW | MED | HIGH
- Depends on: plans/NNN-*.md or none
- Planned at: `<short SHA>`, <YYYY-MM-DD>

## Why this matters

2-5 sentences: the problem, its cost, what improves. Intent lets the executor judge a detail that is off.

## Current state

- Each relevant file with one line on its role.
- Short excerpts of today's code with `file:line` markers.
- The conventions that apply, each with one exemplar file to match.
- Vocabulary, design tokens or ADR decisions the work must honor, quoted.

## Commands

| Purpose | Command | Expected |
|---|---|---|
| Install | ... | exit 0 |
| Build or typecheck | ... | exit 0 |
| Tests | ... | all pass |

## Scope

In scope (the only files to create or modify):
- `path`

Out of scope (do not touch), each with why:
- `path` - reason

## Steps

### Step 1: <imperative title>

What to do, with exact files and symbols, and the target code shape when it matters.

Verify: `<command>` -> <expected result>

## Checks

Implementation plans: the existing checks to run at the end.
Test plans: the test matrix - per behavior, the user-facing entry point, each case (boundaries, errors, concurrency, idempotency where relevant) and the observable outcome it asserts, plus the existing test file to model on.

## Done criteria

- [ ] Each a machine-checkable condition.
- [ ] Nothing outside the in-scope list changed (`git status`).

## STOP conditions

- The code does not match Current state.
- A Verify fails twice after a reasonable fix.
- The work needs an out-of-scope file.
- <this plan's own risks>

## Rollback

(Only for schema, infrastructure and deploy changes.) Steps and triggers, each with Verify.

## Notes for reviewers

What to scrutinize, and follow-ups deliberately left out.
```

## Index

```markdown
# Plans

| Plan | Title | Priority | Effort | Depends on | Status |
|---|---|---|---|---|---|
| 001 | ... | P1 | S | - | TODO |

Status: TODO | IN PROGRESS | DONE | BLOCKED (reason) | REJECTED (reason)

## Dependency notes

- 002 needs 001 because ...
- 003 and 004 can run in parallel.

## Considered and rejected

- <idea>: <one-line reason>
```

## Quality bar

Before finishing each plan, check:
- Could a model that never saw this repo or conversation execute it from the plan and the repo alone?
- Does every step end in a command with an expected result?
- Would a reviewer reading only Why this matters and Done criteria know what they approve?
- Do the drift-check paths match the in-scope list?
