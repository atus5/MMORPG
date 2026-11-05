# M1 developer review — pending independent Gemini review

## Architecture and safety

- React renders UI and connection status; Phaser is browser-only and owns scene/input/camera. Transport and strict protocol schemas are separate modules. Scene positions come only from validated server state.
- Server uses monotonic time, expiring input intent, world bounds and per-session sequence checks. Client coordinates, speed and gameplay fields are rejected. Send/close operations share a lock; tasks are cancelled/awaited and sessions removed on disconnect.
- Explicit origins, local connection/message/size/send limits, no raw input logging, no credentials, database driver or Supabase call. Origin checks are not authentication. Bind to loopback and use one worker.
- No gameplay progression or balance rules were selected. Sandbox pixel geometry/timing are temporary technical settings. No persistence, shared-world replication, production deployment or M2 work.
- Baseline policies, schemas, historical reports and disabled CLI automation are preserved. The pre-M1 factual sentence in baseline AGENTS.md about applications not existing predates this Owner-authorized milestone; the new application files are uncommitted inputs and must be reviewed in full.

## Executed verification

See the sealed package test evidence for exact tool outputs and exit codes, including initial failures and corrected runs. Final backend checks: pip dependency consistency, Ruff, 17 pytest tests. Final frontend checks: TypeScript, Biome, 7 unit tests, production build, 2 real-server Chromium production E2E tests and 2 dev/React Strict Mode E2E tests. Dependency installation and real Uvicorn startup/health/WS/disconnect were exercised. Npm audit reports zero vulnerabilities after replacing the initial ESLint dependency chain with Biome; no forced major overrides were used.

## Limits and observations for Gemini

- Backend tests pass with a Starlette warning: using httpx with TestClient is deprecated in favor of httpx2. Current lock uses tested httpx 0.28.1. The warning is retained in evidence.
- Two production E2E runs logged `ConnectionResetError: [WinError 10054]` from Python 3.10's `_ProactorBasePipeTransport._call_connection_lost` during the browser lifecycle test, including after a fresh install. Both tests passed in each run and session counts returned to zero. Recurrence was observed; root cause is **UNKNOWN**. No exception filter was added and logs are preserved. Functional PASS does not mean stderr was empty.
- Other E2E output includes Node FORCE_COLOR/NO_COLOR warnings. Browser tests cover Chromium on this Windows environment; Firefox/WebKit, touch movement, sustained load and production security are not verified.
- `npm ci` completed successfully with zero audit vulnerabilities. `npm ls --depth=0 --json` exits 0 but labels two optional Sharp-related packages (`@img/sharp-wasm32@0.35.5`, `@emnapi/runtime@1.11.3`) extraneous, including after a fresh lockfile install. Both have entries/integrities in package-lock.json. The metadata discrepancy's cause is **UNKNOWN**; no manual node_modules pruning or forced dependency override was used. Unit/build/E2E checks passed after the fresh install; the version output is included in evidence.
- Dependency audit is point-in-time registry evidence, not a full security audit. Secret scanning uses known patterns and cannot prove universal absence.
- Earlier Temp metadata anomaly remains **UNKNOWN** in historical evidence. It was not re-investigated; legacy desktop-policy/run-tests runners were not executed for M1.
- No independent Gemini execution, model identity, checksum verification or PASS is claimed. The Owner must select Gemini 4 Argon and hand off the new saved snapshot under the approved Desktop write restrictions.
