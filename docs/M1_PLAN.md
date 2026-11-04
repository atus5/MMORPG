# M1 — Game Foundation

Base: `94e9c1ab92af18de88a2e33a37370c0457f9fb6b`, branch `tu`.

1. Inspect baseline, existing Desktop contracts and dependencies (done before implementation).
2. Add separate Next.js/TypeScript frontend and FastAPI backend; no database integration.
3. Define protocol v1: client sends sequenced input intents or ping; server validates, owns movement and returns state. Per-connection, disposable demo sessions only.
4. Mount Phaser only in the browser; React owns UI, Phaser owns rendering/input, transport owns connection lifecycle. No local position prediction or gameplay authority.
5. Verify dependency installation, backend health, validation, origin policy, disconnect cleanup, time-based authority, frontend typecheck/lint/unit tests/build and real browser integration.
6. Review changes, scan for secrets, preserve baseline history and create a new byte-preserved, manifest-bound r0 snapshot for manual Gemini 4 Argon review.

Technical sandbox dimensions, pixel speed, input lease and network limits are scaffolding, not approved game balance. No progression, currencies, HP/damage, PvP, death, realms or tribulation rules are implemented. Authentication, persistence, multi-player replication and production hardening remain later work.

Do not run legacy automation/test runners, stage, commit, push, merge, deploy or access Supabase. Preserve historical reports and `.automation/DESKTOP_ONLY`. M1 is pending independent review, not complete on developer test results alone.
