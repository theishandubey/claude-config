---
name: parallel-build
description: Orchestrate a parallel implementation run - split plans into file-disjoint tasks, dispatch parallel-implementer agents in isolated worktrees, merge their branches back one at a time and verify the integrated result. Use in the main session for work sized for 2 or more simultaneous implementers.
argument-hint: "[plans or task description]"
---

Run a parallel build for: $ARGUMENTS

Run this in the main session; it owns the worktrees and the merge.

## Invariants

- One task, one agent, one worktree.
- Worktrees check out committed state only: commit the base before dispatch.
- No two tasks in a wave touch the same file.
- Merge one branch at a time and verify the integrated result; each worktree only verified itself.
- Dispatch from inside the target repo: the agent's worktree is created from the main session's shell directory.
- Remove only worktrees this run created, and inspect `git -C <worktree> status` before any forced removal.

## 1. Prepare

1. Every task needs a plan whose in-scope list is the files it owns.
   Get plans from the planning advisor if they are missing, and send overlapping ownership back to it.
2. Make sure `.worktreeinclude` exists at the repo root, listing untracked files the build needs (local env files, local certs, tool config), never production secrets.
   Find them with `git status --ignored --short` against what the build references.
   Create it with a commented header even when nothing is needed, and commit it with the base.
3. Commit the base and record the branch and SHA.
   An untracked `plans/` stays uncommitted and does not block dispatch: you pass each plan's full text in the prompt.
4. In its own `Bash` call right before each dispatch, `cd` to the repo root and confirm `git rev-parse --show-toplevel`.
5. At most 4 tasks per wave; finish steps 2-4 of this procedure for one wave before the next.

## 2. Dispatch

Spawn one `parallel-implementer` per task, in parallel.
Each prompt holds the plan verbatim, the owned-file list, the repo's install, build and type-check commands, and the reminder that it commits but never pushes or merges and that you maintain `plans/README.md`.
Do not edit the main checkout while they run.

## 3. Integrate

1. Collect each report's branch, base SHA, tip SHA and completion line.
   Hold back partial branches: re-dispatch the remaining work to a fresh `parallel-implementer` whose prompt names the partial branch and its SHAs and tells it to `git cherry-pick <base>..<tip>` first.
2. Create or check out the integration branch from the recorded base.
3. Merge the branches one at a time, foundational ones first: `git merge --no-ff <branch>`.
   After each merge run the typecheck or build only.
4. On a merge conflict, abort the merge (`git merge --abort`) and dispatch `fixer` with both task plans, the conflicting branch and the integration branch, to merge it on the integration branch by the plans' intent.
   If the conflict shows the plans overlap, stop and send them back to the planning advisor.
5. After all merges, run the build and type-check once.
   Route failures to `fixer` with the output and the list of merged branches.

## 4. Review and clean up

1. Run `code-reviewer` once on the combined diff (`git diff <base>...HEAD`) and follow the playbook's review loop.
2. Add legitimate `.worktreeinclude` suggestions from the reports and commit them.
3. Delete merged branches and remove this run's worktrees; list any others to the user.
4. Report: tasks completed, merge order, conflicts and how they were resolved, verification results, `.worktreeinclude` lines added, unrelated failures the workers reported, and worktrees removed.
