---
name: e2e-tests
description: How implementers and fixer write and run end-to-end tests - what to test, the shape of a test, setting up a harness, how to run them and output discipline. Preloaded by implementer, parallel-implementer and fixer.
user-invocable: false
---

# End-to-end tests

Write full end-to-end coverage for the user-visible behavior your change adds or alters.
Test and browser output is the main cost of testing, so the output rules below are binding.

## What to test

- Cover every user-visible behavior the change adds or alters, including its error and edge cases, one behavior per test.
- Drive the product through the entry point its users use and assert only what they can observe:
  - Web UI: Playwright, with role-based locators (`getByRole`, `getByLabel`).
  - HTTP or RPC service: real requests to the running server.
  - CLI: the real command as a subprocess, asserting on output, exit code and files written.
  - Library: its public API, imported the way a consumer imports it.
- Each test creates its own data, waits on visible conditions and never on fixed sleeps, and has a plain-language name.
- No mutation checks, model-based tests or forced-interleaving tests unless the spec asks for them.
- Use the repo's existing harness, directory, fixtures and naming exactly.
- If the repo has no end-to-end harness, add the minimum first and list it in your report:
  - Web app: `@playwright/test` as a dev dependency through the project's package manager, a `playwright.config` whose `webServer` uses the dev script, and one e2e directory.
  - Anything else: the language's standard test runner, driving the real entry point as above.

## Learning the page

Read the markup or templates first; use `agent-browser` to map a page only when its roles and labels are not clear from the code and it is installed (`agent-browser skills get core` loads its guide).
Take compact snapshots of the interactive elements only, and save anything larger to a file and `grep` it.

## Running

- While you work, run only the tests you wrote and the existing specs that cover the files you changed.
- Before reporting, run the whole end-to-end suite once, and report anything it shows failing.
- Send output to a file and read only the summary and failures:
  `PLAYWRIGHT_HTML_OPEN=never npx playwright test <specs> --reporter=line > "$LOG" 2>&1; tail -n 60 "$LOG"`, with `LOG` under `mktemp -d`, or the same redirection for the repo's own test command.
- Never paste traces, HTML dumps, screenshots or server logs into your report; give their paths.
- Start a dev server only if nothing answers at the base URL, and stop it when you finish.

## Failures

- A test that fails because of your change: fix the change.
- A test that fails because the test is wrong or the UI changed on purpose (a renamed label, a moved control): fix the test.
- A bug that predates your change: leave the test out, and report the bug with the failing command.

## Report

List each test you added, the command you ran, and passed and failed counts.
