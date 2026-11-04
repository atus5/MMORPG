---
name: gemini-reviewer
description: Prepare and inspect manual review handoffs between Codex Desktop and Antigravity Desktop for Tu Tien Online; preserve report history and a three-fix budget without invoking AI CLIs.
---

Read root `AGENTS.md`, `GEMINI_REVIEW.md` and `DESKTOP_WORKFLOW.md`. The user operates Codex Desktop and Antigravity Desktop; no Codex/Gemini CLI calls, CLI probes/authentication, UI automation or activation of the preserved CLI controller.

In Codex Desktop, verify checkout/branch `tu`, test the implementation, and prepare the sealed create-only package described in `DESKTOP_WORKFLOW.md`. Include commit/HEAD anchor and dirty status, tracked diff, full relevant tracked/untracked bytes, included/excluded inventory, prior snapshots, SHA256 manifest, actual tests, session/package UUIDs, base and fix count. Do not commit/push unless separately authorized.

The user opens the package in Antigravity with report-only write approvals, selects Gemini 4 Argon and sends the review prompt. Gemini reviews saved snapshot contents, not live workspace substitutes. Starting an agent, observing the model and confirming completion are manual. A file's presence alone is not proof of a complete review.

Gemini may write only `agentReport.md` and new report files under `reports/`; it cannot alter sealed packages, history, source, tests, rules, configuration, migrations, state or Git. Use overwrite=false/exclusive creation for history at `reports/YYYY-MM-DD-<HEAD>-<session-UUID>-<package-UUID>-r<round>.md`; if unavailable, Owner saves text with create-new. If Desktop cannot enforce write boundaries, use the read-only snapshot and user-saved reports.

Separate hashes supplied by Codex, independently verified hashes with actual supported-tool evidence, and hashes not independently verified. Do not require Gemini command execution or pretend read_file computes byte hashes. Codex/Owner computes SHA256 with local checksum tools before sealing and after receiving the report.

Back in Codex, verify package bytes and whether live source still matches, then verify findings and fix confirmed issues. Record FIXED/REJECTED reasons/tests in a new package's fix-response, never by rewriting Gemini's review. Re-review a new snapshot against the same original base; r0 then r1..r3, at most three fixes. A valid old snapshot review does not approve newer live changes.

CRITICAL stops for Owner decision; unresolved confirmed HIGH findings cannot be silently accepted. Incomplete/stale reviews and missing tests are BLOCKED, never fabricated PASS. Neither AI merges into main or deploys production.

Legacy scripts/schemas/fixture tests/policies and `.agents/state/` history remain preserved. Their old receipts and CLI `-Resume` flow do not authorize Desktop work or represent its current counters. Inspect `.automation/DESKTOP_CAPABILITIES.md` for evidence and limits; no verified bridge between the two running apps is configured.
