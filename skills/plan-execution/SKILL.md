---
name: plan-execution
description: How workers execute a handoff plan or spec from the orchestrator - drift check, verify gates, scope, STOP conditions, approvals and the report. Preloaded by implementer, parallel-implementer, fixer and doc-writer.
user-invocable: false
---

# Executing a plan

When your task is a plan from `plans/` (or any spec the orchestrator sends):

1. Run its drift check first.
   If an in-scope file no longer matches Current state, stop and report.
2. Run every step's Verify and confirm the expected result before the next step.
3. Scope and STOP conditions are binding.
   On a STOP condition, stop and report; do not improvise around it.
4. Stop before any step marked `REQUIRES HUMAN APPROVAL` and report it instead of running it.
5. Do everything the plan asks, across every site its pattern matches, and nothing it does not.
   Say which sites you covered.
   Suggest extra features, files, docs or refactors in your report instead of doing them.
6. On genuine ambiguity, or a plan that seems wrong, stop and ask in your report rather than picking a reading.
7. The orchestrator maintains `plans/README.md`: never edit it, and ignore an untracked `plans/` or `advisor-plans/` in `git status`.
8. Read the files you will touch and one similar existing example first; match its naming, error handling, imports and layout, but not its comment density.
9. Before reporting done, run a real check that exercises the change: the project's type-checker, build or linter, or the changed command itself, plus the end-to-end tests your agent instructions call for. Run no other tests.
   A syntax-only check, or a command that failed to start, does not count.
   If only the project's declared dependencies are missing, install them with its own package manager and lockfile, never with sudo or a system package manager.
   If no real check can run, say which one you did not run and why instead of reporting done.
10. Never report done with a red build, except for failures your change did not cause.
    Fix an unrelated lint, type or build error only when it is in a file you already change and the fix is small, and list it under deviations.
    Report every other one with the exact output.
11. Report against the plan's Done criteria.

When working from review findings, address each exactly as specified.
If you disagree with one, implement it anyway when harmless, otherwise report the disagreement with your reasoning; never skip one silently.
