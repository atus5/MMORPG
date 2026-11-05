# Independent review contract

## Active: Antigravity Desktop

Read `AGENTS.md`, `DESKTOP_WORKFLOW.md`, the user-selected handoff and the actual relevant files. Use exactly Gemini 4 Argon in Antigravity. The user observes the selected model in the app; record this as UI evidence, not API attestation or a claim that an external integration exists. Stop for missing/wrong model or incomplete context. Do not use any CLI AI client or reuse Desktop authentication elsewhere.

The handoff identifies the absolute checkout, branch `tu`, session ID, original base, HEAD anchor, staged/unstaged/untracked scope, source-file SHA256 manifest and real test evidence. Inspect the cumulative changes against that same original base on every round, including related callers, tests and deleted files. A dirty checkout is a worktree snapshot, not a reviewed commit. Stop if source changes during review or if the handoff does not cover the actual changes.

Only write `agentReport.md` and `reports/`. Never edit source, tests, migrations, config, rules, `.agents/state/` or Git, and never commit, push, switch branches, merge or deploy. Use file-reading tools and the prepared diff; do not run terminal commands, MCP tools, browser actions or external integrations during this review. If your file writer needs shell execution or the Desktop cannot enforce the agreed write approvals, stop direct workspace access; offer review text for the user to save from a sanitized read-only snapshot.

Write the historical report first to the exact new path in the handoff (for example `reports/YYYY-MM-DD-<HEAD>-<session>-r0.md`), then place the same completed content in `agentReport.md`. Do not overwrite history. Before replacing a meaningful older latest report, ensure its historical copy exists. r0 is the initial review; r1..r3 are at most three fixes/re-reviews in the same session. Do not reset counters between chats.

Preserve the report structure: provenance DESKTOP_MANUAL; session and round/fix count; absolute checkout and branch; HEAD/parent as anchors; original base; reviewed manifest identity; UI-observed model and evidence; time with offset; files actually read; Required Actions; Optional Improvements; reviewer test observations; supplied developer test evidence; finding dispositions from previous rounds; verdict; final status. Clearly distinguish observed test results from tests you did not execute. Mark missing prerequisites BLOCKED with verdict NOT_EVALUATED in Markdown; do not invent a schema-valid PASS.

Keep all finding fields described below. Desktop reports use Markdown, retaining the finding structure from `.automation/review.schema.json`. That unchanged JSON schema describes committed CLI snapshots and cannot express a dirty snapshot identity: do not add unsupported top-level fields, fabricate a SHA or label dirty content as a reviewed commit. A complete Desktop review may conclude PASS only with no Required Actions and successful applicable test evidence for the exact reviewed snapshot; Owner still approves merging manually.

## Shared review criteria

Assess Next.js, Phaser 3, FastAPI, Supabase schema/migrations, RLS, authentication, API, WebSocket, multiplayer, heartbeat, Diem Co Duyen, AFK, thien kiep, PvP, transactions, concurrency, security, performance, tests and regressions where code exists. Do not invent an implementation or missing product requirements. Cloud database access is not part of an automatic review: only supplied SQL and metadata can be reviewed.

Each finding needs a stable ID, severity (CRITICAL/HIGH/MEDIUM/LOW), numeric confidence (0..1), category, existing file path, positive line number, description, concrete evidence, impact, recommended_fix and nonempty verification_steps. Use action REQUIRED or OPTIONAL and confirmed true/false. Give reproducible evidence; do not raise severity without evidence. Confirmed CRITICAL/HIGH findings must be REQUIRED. CONFIRMED MEDIUM defects should be REQUIRED; stylistic suggestions are OPTIONAL.

Use CHANGES_REQUIRED if any REQUIRED finding remains, otherwise PASS. PASS with a confirmed CRITICAL/HIGH finding is invalid. Test results describe what you can establish from supplied evidence; you cannot execute tests. Do not claim tests passed because test files exist.

On subsequent rounds recheck all unresolved findings against the cumulative change, including regressions introduced by fixes. A developer's rejection is evidence to assess, not permission to ignore a valid finding. Product Owner approval is necessary to accept an unresolved confirmed HIGH or CRITICAL defect.

## Preserved legacy CLI contract - inactive

The previous engine received immutable committed snapshots through stdin: the controller supplied instructions, cumulative diff and tracked text; every tool was denied. It returned only JSON matching `.automation/review.schema.json` with exact commit_sha/parent_sha and inspected files_reviewed. Model identity came from CLI usage metadata. Only the controller wrote reports/state, and Codex returned structured edits validated against `.automation/fix.schema.json`.

Those contracts, JSON schemas, CLI policy and tests remain available for historical reference and isolated fixtures. They are not the Desktop execution/report-writing rules. No CLI invocation, probe, authentication or hook activation is permitted in the current workflow.
