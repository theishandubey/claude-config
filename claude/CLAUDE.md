# Shared Rules

These apply to every session and agent, in every project.
Routing and dispatch rules for the main session live in the orchestrator playbook (orchestrator.md), which only the main session receives; keep them out of this file.

## Writing

- Never use an em dash; use a plain dash "-".
- Never write comments or docstrings in code, in any language, new or existing code, with no exceptions for explaining intent, constraints, TODOs, section headers or commented-out code.
  Express what a comment would say through names, types, structure or a test instead.
  When you change code, delete the comments in the lines you touch.
  Only machine-read directives are allowed, and only when the tooling requires them: shebangs, encoding lines, license headers the project mandates, and linter, type-checker or compiler pragmas.
- Never edit CHANGELOG.md files or files marked as auto-generated.
- In long Markdown files, put each sentence on its own line and keep normal Markdown structure.

## Engineering

- Weigh quality, simplicity, robustness, scalability and long-term maintainability above development cost.
- Fix a bug only after reproducing it end to end, as close to how a user meets it as you can.
- Hold any UI you see during end-to-end testing to a pixel-perfect bar.
- Treat lint errors, test failures, flaky tests and visibly broken UI the same way, whether or not your change caused them: fix them when your role and scope allow, otherwise report them with the exact output so they get routed.
- Call only the tools in your own tool list; the shell tool is `Bash`.
- Put scratch files in the session scratchpad when one is given, otherwise in a `mktemp -d` directory, never inside a repository, and leave them for the OS to clean.
- A guard hook blocks catastrophic commands (wiping the filesystem, home or project, dropping databases, destroying infrastructure, force-pushing main).
  Never work around a block; tell the user what you wanted to run.
- Never poll with `sleep` followed by a read.
  Run a long command in the foreground with a timeout, or in the background and wait for its completion notice.

## Principles

- Default to subtraction: remove dead code, redundant validators and stubs before building on the simpler base.
  Make the smallest change that solves the problem, and add no abstraction, layer, guard or option the current need does not demand.
- Keep each decision in one place and pass its result along, instead of repeating the same choice in several places.
- When you replace an internal API, migrate every caller and delete the old one in the same change, unless external users depend on it.
  Update tests to the new contract and delete tests that only pin the old implementation.
- In a planned rewrite or migration, converge on the target design instead of keeping every intermediate step working with throwaway compatibility code.
  Declare where temporary breakage is acceptable and verify everything at the end.
- When the same correction or instruction comes up a second time, encode it as structure (a lint, type, check or script) instead of more text.
  Only when it needs judgment, make the instruction more prominent and add an example of the failure.

## Commits

- Make atomic commits: one logically complete change each, each building and passing on its own.
- Commit messages describe the change only: no milestone labels, task numbers or step references.
- Never add an agent or Claude co-author trailer.
