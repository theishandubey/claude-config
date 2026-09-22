---
name: handoff
description: Write a handoff document so a fresh session, possibly on another machine, can continue the current task. Invoke before stopping mid-task, before switching machines, or when context is nearly full and compaction would lose working state.
argument-hint: "[focus of the next session]"
disable-model-invocation: true
---

Write a handoff document for the task in this conversation so a session with zero context can continue it.

## Where to write it

Write to `~/.claude/handoffs/<project>/<YYYY-MM-DD-HHMM>.md`, where `<project>` is the basename of the current working directory.
Create the directory if needed.
Never write to the session scratchpad, `/tmp`, the project tree, or any memory directory: the next session cannot find the first two, the third pollutes the repo, and memory holds durable facts rather than task state.

## What to include, in this order

1. **Goal**: what the task is trying to achieve and how the user will judge it done.
2. **Status**: what is finished, what is half-done and in what state, and what you would do next.
3. **Verification**: what was run, whether it passed, and what has not been verified yet.
   State plainly what you believe but did not check, so the next session re-checks it instead of inheriting a guess.
4. **Decisions and why**: choices a fresh session would otherwise relitigate, with the reasoning.
5. **Open questions**: anything blocked on the user or on information you could not get.
6. **Files and artifacts**: files touched, and the branch, commits, plans, specs, ADRs, issues, or PRs that hold detail.
   Reference them by path or URL; do not restate their contents.
7. **Commands**: the exact commands to build, test, run, or reproduce, ready to paste.
8. **Next dispatch**: which playbook step comes next and which agent it belongs to, with the prompt to give that agent.
   Name skills only where the next step must invoke one directly.
9. **Opening prompt**: a complete, ready-to-paste first message for the next session that names this document's absolute path and states the first action.

## Rules

- Write for a reader with no context; "as discussed above" is a broken reference.
- Be terse; the document is loaded into a fresh context and every line costs tokens.
- Redact credentials, tokens, and personal data; reference a secret's location and type, never its value.
- If arguments were passed, treat them as what the next session will focus on and weight the document toward that.
- Finish by printing the document's absolute path and the opening prompt in the chat reply.
