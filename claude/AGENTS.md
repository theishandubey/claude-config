These are common instructions for coding agents, in every project and scenario.

## General Guidelines

- Never use an em dash "—". Use a plain dash "-" instead.
- Do not add docstrings or code comments by default, neither to new code nor to existing code.
  Write a comment only when it states a constraint the code itself cannot show, and delete comments that merely restate the code.
  Comments and docstrings drift from the code and inflate token cost; clear names and structure are the documentation.
- Never manually modify CHANGELOG.md files or any files that are marked as auto-generated.
- When writing or substantially editing long Markdown files, put each full sentence on its own line.
  Preserve normal Markdown structure, but avoid wrapping multiple sentences onto one physical line.
- When making technical decisions, do not give much weight to development cost.
  Instead, prefer quality, simplicity, robustness, scalability, and long term maintainability.
- When doing bug fixes, always start with reproducing the bug in an E2E setting as closely aligned with how an end user experiences it as possible.
  This makes sure you find the real problem so your fix will actually solve it.
- When end-to-end testing a product, be picky about the UI you see and be obsessed with pixel perfection.
  If something clearly looks off, even if it is not directly related to what you are doing, try to get it fixed along the way.
- Apply that same high standard to engineering excellence: lint errors, test failures, and flaky tests.
  If you see one, even if it is not caused by what you are working on right now, still get it fixed.

## Commits

- Make atomic commits: one logically complete, self-contained change per commit, each building and passing on its own.
- Commit messages describe the change only; do not put milestone labels, task numbers, or step references in them.
- Do not add any agent/Claude co-author trailer to commits.
