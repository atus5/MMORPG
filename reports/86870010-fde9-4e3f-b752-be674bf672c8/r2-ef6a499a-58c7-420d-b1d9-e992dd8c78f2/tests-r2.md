# R2 developer test evidence

Provenance: CODEX_DESKTOP_DEVELOPER_TESTS, not a Gemini verdict.
Session: 86870010-fde9-4e3f-b752-be674bf672c8; round r2; fix attempts consumed 2/3.
Recorded at: 2026-11-04T12:28:52.854798+07:00

- `powershell -NoProfile -File .automation/tests/run-tests.ps1 -NoReceipt`: exit 0; 29 passed, 0 failed. Fixture commits only in fresh temporary, remote-free repositories. No commit, hook installation or activation in the actual project. Existing receipt not overwritten.
- `powershell -NoProfile -File .automation/tests/desktop-policy.tests.ps1`: exit 0; 11 checks passed. Whole child-test executions fail with DESKTOP_POLICY_MISSING / DESKTOP_POLICY_INVALID when only their temporary copy is mutated. The actual marker was never modified. AI resolutions/process calls: 0.
- Installer fixture independently checked CLI_DISABLED_DESKTOP_ONLY, PRODUCT_OWNER_APPROVAL_REQUIRED and PROJECT_TEST_COMMANDS_MISSING from nonzero child exits and exact error identifiers. No fixture hook/activation state was created by those rejected requests.
- PowerShell AST parse of every automation .ps1: no errors.
- Skill validator for .agents/skills/gemini-reviewer: valid.
- git diff --check: exit 0 (existing README newline conversion warning only).
- Source review: full changes-r1-to-r2.patch inspected, including untracked files which normal Git diff omits.

Captured suite fingerprint: 724be0ae6c9d961ebc7da04045ef8048ca25fc8baf47c9570ee2e05acb19e6af; suite checked_at: 2026-11-04T05:24:29.5517764+00:00.
Full observed output is in evidence/controller-tests.log and evidence/desktop-tests.log (UTF-8 transcription of the PowerShell captures).

Not executed: live AI CLI/model/auth probes (prohibited), Antigravity UI/model review (manual next step), game integration/RLS/runtime tests (no game implementation or migrations). Passing baseline tests is not a game PASS or Gemini R2 approval.
