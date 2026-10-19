---
name: e2e-testing
description: What counts as an end-to-end test in this setup and how to write one - real entry points, real owned dependencies, stubs only at third-party network boundaries, no unit tests. Preloaded by qa-lead, test-writer and fixer.
user-invocable: false
---

# End-to-end tests only

Every new test is end-to-end.
Never plan or write a unit test.

An end-to-end test drives the product through the entry point its real users use, and asserts only on what those users can observe:
- Web UI: a real browser against the running app.
- HTTP or RPC service: real requests to the running server.
- CLI: the real command run as a subprocess, asserting on output, exit code and files written.
- Library: its public API, imported the way a consumer imports it.

Everything the repo owns runs for real: internal modules, a test instance of the database, queues and config.
Stub only third-party services you cannot run in the test environment (payments, email, external APIs), at the network boundary, preferring the provider's sandbox or a local fake server over in-process mocks.

It is a unit test, and out of bounds, when it:
- calls internal functions or classes directly,
- mocks a collaborator the repo owns,
- checks state through a side channel (such as querying the database) instead of the user-facing interface.

Rules:
- Use the repo's existing end-to-end harness and conventions; add a new harness only when a `qa-lead` plan names one for a repo that has none.
- Give each test its own data so tests pass in any order.
- Wait on observable conditions, never fixed sleeps.
- Every test must be able to fail: check that it fails without the behavior it covers.
- Leave existing unit tests as they are; repair one only when the task says so.
- Never restructure production code to make it testable; report the need instead.
- Prefer fewer, meaningful tests over coverage theater.
