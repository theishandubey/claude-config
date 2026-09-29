---
name: parallel-build
description: Orchestrate a parallel implementation run - split a plan into file-disjoint tasks, dispatch parallel-implementer agents in isolated worktrees, then merge branches back sequentially and verify the integrated result. Use for multi-part features or refactors sized for 2+ simultaneous implementers.
argument-hint: "[plan or task description]"
---

Orchestrate a parallel build for: $ARGUMENTS

Run this procedure in the MAIN conversation (this skill must not fork - you own the merge).

ROLE NOTE: if you are reading this as a preloaded skill inside a `parallel-implementer` agent, this document is context about the pipeline around you - do NOT execute these phases. Only the main orchestrating session runs this procedure.

## Invariants

The main session owns the worktree lifecycle end to end. These hold for ANY worktree-isolated work, whether or not you run the full procedure below:

- **One task, one agent, one worktree.** Never send two agents into the same worktree.
- **Worktrees check out committed state only.** Uncommitted scaffolding or plan groundwork is invisible to them, so the working tree must be clean (or intentionally so) before dispatch.
- **No two parallel tasks may touch the same files.** If the plan doesn't specify file ownership per step, get that from the `architect` advisor before dispatching.
- **Merge sequentially, never in parallel**, and verify the INTEGRATED result - each worktree only verified itself.
- **Clean up after abandoned runs.** If a run is cancelled or superseded, list leftovers with `git worktree list` and prune the merged/abandoned ones rather than letting them accumulate.

## Phase 1 - Prepare
1. If no implementation plan with per-step file ownership exists, get one from the `architect` advisor first. Every task must list the exact files it owns; reject plans with overlapping ownership or renegotiate the split.
2. **Bootstrap `.worktreeinclude`**: check for a `.worktreeinclude` file at the repo root. If missing, create one BEFORE dispatching:
   a. Detect untracked-but-required files: `git status --ignored --short` cross-checked against what the build/test setup references - env files (`.env.local`, `.env.development`), local certs, tool configs (`.npmrc`, `docker-compose.override.yml`).
   b. Write the detected paths to `.worktreeinclude` (one per line, comments with `#`). If nothing is detected, still create it with a commented header explaining its purpose, so future runs and teammates find it.
   c. NEVER list secrets that shouldn't propagate (production credentials, personal tokens) - only local dev prerequisites.
   d. Commit it with the base (it's team-shareable config).
   If the file exists, skim it for obvious gaps against the same detection and append if needed.
3. Ensure the working tree is committed: `git status` clean, base work committed. Record the base branch and SHA.
4. Confirm task count ≤ 4 (more rarely helps; merge cost grows).

## Phase 2 - Dispatch
5. Spawn one `parallel-implementer` per task, in parallel. Each delegation prompt MUST include: the full task spec verbatim, the owned-file list, the repo's install/build/test commands, and the instruction to commit but never push/merge.
6. While they run, do not edit the repo yourself in the main checkout.

## Phase 3 - Integrate (sequential, never parallel)
7. Collect each agent's reported branch, base SHA, and tip SHA. Order the merges: least-risky/most-foundational first (shared types/utils before consumers).
   Check each report's Completion line; hold back partial branches and resolve what remains (re-dispatch, or route to `fixer` or the advisor) before merging them.
8. Create or check out the integration branch from the recorded base.
9. For each branch in order:
   a. `git merge --no-ff <branch>` (or `git cherry-pick <base>..<tip>` using the reported base and tip SHAs if the branch history is noisy).
   b. On conflict: resolve using the task specs as the source of truth for intent. If a conflict reveals genuinely overlapping ownership, stop and route the overlapping piece to a single `fixer` rather than hand-blending both versions.
   c. After each merge, run typecheck/build only (fast signal). Full tests wait for step 10.
10. After ALL merges: run the complete test suite once on the integrated branch. Route failures to `fixer` with the failing output and the list of merged branches (integration bugs usually live at the seams between tasks).

## Phase 4 - Review & clean up
11. Run `code-reviewer` on the combined diff (`git diff <base-SHA>...HEAD`) - post-merge only. Handle the verdict and its findings per routing invariant 3 in the playbook, including nits and any unrelated failures the workers reported.
12. **Fold back `.worktreeinclude` suggestions**: collect the `.worktreeinclude` suggestions section from every worker report. Append any legitimate new lines (dedupe; apply the no-secrets rule from Phase 1) and commit - next run's workers start with a complete environment.
13. Prune the worktree branches that merged cleanly; run `git worktree list` and remove leftovers from this run.
14. Report: tasks completed, branches merged (in order), conflicts encountered and how resolved, final verification results, `.worktreeinclude` lines added, unrelated failures reported by workers, and worktrees cleaned.