# Shared Rules

These apply to every session and agent, in every project.
Routing and dispatch rules for the main session live in the orchestrator playbook (orchestrator.md), which only the main session receives; keep them out of this file.

## Writing

- Never use an em dash; use a plain dash "-".
- Do not write comments or docstrings in code, in any language.
  Make the code carry the reason instead, in this order: a name, a small helper or a type; then the commit message body.
  Only when neither can show a constraint the code depends on (a deadlock, a platform or library quirk, an external API's behavior) write one line saying why.
  Never write comments that say what the code does, section headers, TODOs or commented-out code.
  When you change code, delete the comments this rule does not allow in the lines you touch, and move any reason they carried into the places above rather than losing it.
  Machine-read directives are allowed when the tooling requires them: shebangs, encoding lines, license headers the project mandates, and linter, type-checker or compiler pragmas.
- Never edit CHANGELOG.md files or files marked as auto-generated.
- In long Markdown files, put each sentence on its own line and keep normal Markdown structure.

## Engineering

- Weigh quality, simplicity, robustness, scalability and long-term maintainability above development cost.
- Only `implementer`, `parallel-implementer` and `fixer` write and run tests, following their preloaded `e2e-tests` skill.
  Everyone else does not write, run or review tests, and verifies a change with the project's build, type-checker or linter, or by running the changed command once.
  Code and security review belong to the user.
- Fix a bug only after reproducing it with the cheapest command that shows the symptom.
- Treat lint errors, type errors and build failures the same way, whether or not your change caused them: fix them when your role and scope allow, otherwise report them with the exact output so they get routed.
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
- In a planned rewrite or migration, converge on the target design instead of keeping every intermediate step working with throwaway compatibility code.
  Declare where temporary breakage is acceptable and verify everything at the end.
- When the same correction or instruction comes up a second time, encode it as structure (a lint, type, check or script) instead of more text.
  Only when it needs judgment, make the instruction more prominent and add an example of the failure.

## Commits

- Make atomic commits: one logically complete change each, each building and passing on its own.
- Commit messages describe the change only: no milestone labels, task numbers or step references.
- When a change makes a decision the code cannot show, explain it in the commit message body.
- Never add an agent or Claude co-author trailer.
