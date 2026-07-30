---
name: team-handoff
description: Capture an agent-team TEAMMATE's state into a durable handoff doc so a replacement teammate can resume its work. Invoke when running as a teammate whose context is filling or whose turn limit is near, before a teammate is replaced, or before ending a session with live teammates. Not for subagents - a subagent's final report is its handoff.
argument-hint: "What should the replacement focus on?"
disable-model-invocation: false
---

Write a handoff document for the agent you are running as, so a fresh teammate can take over its work.

Agent teams have no resumption - `/resume` does not restore in-process teammates, and a replacement teammate inherits none of the lead's conversation history.
This document is the only thing that crosses that gap, so write it for someone with zero context.

## Which agent you are writing for

You write a handoff for **yourself**, not for the team.

- Running as a teammate: write your own doc (see [Teammate handoff](#teammate-handoff)).
- Running as the team lead: write the index instead (see [Lead index](#lead-index)). Do not attempt to write teammates' docs for them - you cannot see their context. The human runs this skill inside each teammate.

## Where the state lives

Find the team directory under `~/.claude/teams/` - there is exactly one team per session, named `session-` plus the first eight characters of the session ID.

| Path | What to take from it |
|---|---|
| `~/.claude/teams/<team>/config.json` | `members[]` - your `name`, the `agentType` you were spawned from, `model`, `cwd`, and your **original spawn `prompt`** |
| `~/.claude/tasks/<team>/*.json` | tasks: `subject`, `description`, `owner`, `status`, `blocks[]`, `blockedBy[]` |
| `~/.claude/teams/<team>/inboxes/<your-name>.json` | your mailbox - threads that are still open |

**`~/.claude/teams/<team>/` is deleted when the session ends; the task directory survives.**
Your spawn prompt exists nowhere else, so copy it into the document verbatim rather than referencing the file. A doc that points at `config.json` is worthless by the time anyone reads it.

Write to `~/.claude/handoffs/<team>/<your-name>.md`, creating the directory if needed. Never write inside `~/.claude/teams/`.

## Teammate handoff

Include, in this order:

1. **Identity** - your teammate name, the agent definition you were spawned from, and your model.
2. **Original assignment** - your spawn prompt, verbatim and complete.
3. **Task state** - your tasks grouped by status, and for anything unfinished, which tasks it `blocks`. A replacement needs to know who is waiting on it.
4. **Files you own** - the exact set. File ownership is how the team avoids conflicts, so the replacement must inherit the same boundary and not widen it.
5. **Where you got to** - what is done, what is half-done and in what state, what you would do next.
6. **Decisions and why** - the reasoning a replacement would otherwise relitigate. Reference commits, ADRs, plans and specs by path; do not restate their contents.
7. **Open threads** - unanswered messages, by teammate name, and what you owe or are waiting on.
8. **Suggested skills** - see below.
9. **Respawn prompt** - a complete, ready-to-paste block the lead can hand to a new teammate, including the path to this document.

### The suggested-skills section is load-bearing

The `skills:` and `mcpServers:` frontmatter of an agent definition are **not applied when that definition runs as a teammate** - only `tools`, `model`, and the definition body carry over.
A `test-writer` teammate does not receive the `tdd` preload its definition declares; a `frontend-engineer` teammate does not receive `design-md`.

So name the skills explicitly and say when to invoke each. Do not assume the replacement inherits anything.

## Lead index

Write `~/.claude/handoffs/<team>/INDEX.md`:

- One line per teammate: name, agent definition, current state, and a link to its doc. Mark teammates that have no doc yet - those are gaps the human still needs to capture.
- **Respawn order**, derived from the task `blockedBy` edges: whoever unblocks the most work comes back first.
- Team-level context that belongs to no single teammate: the shared goal, the integration state, and anything the team agreed collectively.

## Rules

- Write for a reader with no context. "As discussed above" and "the usual approach" are broken references.
- Do not duplicate what an artifact already records. Point at commits, branches, plans, ADRs and issues by path or URL.
- Redact credentials, tokens, and personal data. Reference a secret's location and type, never its value.
- Be honest about uncertainty. Mark what you believe but did not verify, so the replacement re-checks it instead of inheriting a guess as fact.
- If the user passed arguments, treat them as what the next session will focus on and weight the document toward that.
