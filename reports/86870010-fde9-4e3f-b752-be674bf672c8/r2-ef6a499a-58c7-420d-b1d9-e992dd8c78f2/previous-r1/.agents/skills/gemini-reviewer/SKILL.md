---
name: gemini-reviewer
description: Prepare and inspect manual review handoffs between Codex Desktop and Antigravity Desktop for Tu Tien Online; preserve report history and a three-fix budget without invoking AI CLIs.
---

Read root `AGENTS.md`, `GEMINI_REVIEW.md` and `DESKTOP_WORKFLOW.md`. The user operates Codex Desktop and Antigravity Desktop; no Codex/Gemini CLI calls, CLI probes/authentication, UI automation or activation of the preserved CLI controller.

In Codex Desktop, verify checkout/branch `tu`, test the implementation, and prepare the explicit frozen handoff described in `DESKTOP_WORKFLOW.md`. It must cover cumulative tracked and relevant untracked changes, file hashes, actual test evidence, session/base and fix count. Do not commit/push unless separately authorized.

The user opens the same local folder in Antigravity, verifies report-only write approvals, selects Gemini 4 Argon and sends the review prompt. Starting an agent, observing the model and announcing review completion are manual. A file's presence alone is not proof of a complete review.

Gemini may write only `agentReport.md` and `reports/`; it cannot change source, tests, rules, configuration, migrations, state or Git. Require the source manifest to remain unchanged. If Desktop permissions cannot enforce this boundary, stop writable-workspace review and use a sanitized read-only snapshot with user-saved report text instead.

Back in Codex, read the latest report and its history, verify scope, test evidence and finding IDs, then fix only confirmed issues. Record FIXED/REJECTED reasons and tests in a separate fix-response handoff, never by rewriting Gemini's review. Ask Gemini to re-review against the same original base and the updated manifest; r0 then r1..r3, with at most three fixes.

CRITICAL stops for Owner decision; unresolved confirmed HIGH findings cannot be silently accepted. Incomplete/stale reviews and missing tests are BLOCKED, never fabricated PASS. Neither AI merges into main or deploys production.

Legacy scripts/schemas/fixture tests/policies and `.agents/state/` history remain preserved. Their old receipts and CLI `-Resume` flow do not authorize Desktop work or represent its current counters. Inspect `.automation/DESKTOP_CAPABILITIES.md` for evidence and limits; no verified bridge between the two running apps is configured.
