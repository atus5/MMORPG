# M2 Vertical Slice — local/test implementation

Status: **IMPLEMENTED / AWAITING INDEPENDENT REVIEW**, not accepted or production-ready. Owner's Vertical Slice authorization and subsequent three parameter/lifecycle approvals apply only to this slice. All six architecture ADRs remain **PROPOSED**; every other unresolved full-M2 PO decision remains **Product Owner Decision Pending**. This is not approval of full M2, a physical schema, real Auth, merge or deployment.

## Approved slice and explicit exclusions

- Composition root selects `TestStaticIdentityProvider` only when `TU_M2_VERTICAL_SLICE=1` and `TU_APP_ENV` is explicitly `local` or `test`. Invalid/missing permitted environment refuses startup; a request never selects an adapter. Default M1 mode does not expose M2 routes and there is no test-identity production fallback.
- Two deterministic server fixtures each have distinct Account, Player and Character IDs. The server assigns one development world (`development`), one partition (`single`) and spawns `(760,500)` / `(840,500)`. Public replication uses separate runtime entity IDs, not Account/Player/Character IDs.
- Client intent remains cardinal `up/down/left/right/idle`, with sequence and current server-issued control generation. Server controls placement, speed, time, integration and broadcast. Closed ticks are never reopened. Stale input/timeline uncertainty freezes and resyncs at the last integrated position. Expired held input requires release then a fresh press; ping cannot renew movement.
- State exists only in one process's RAM. Restart recreates fixture registry, placements, public entity IDs, control bindings and world boot ID. No PostgreSQL, Redis, Supabase, persistence adapter, schema, migration, distributed lease/owner or external messaging service is used.

No obstacles or collision geometry, world/realm transfer, combat/HP/PvP, rewards/economy, cultivation/AFK/tribulation, production AOI/sharding/load balancing or production SLO is implemented. The boundary clamp below is an explicitly approved disposable sandbox setting, not new gameplay collision policy.

## Owner-approved local parameters

- Sandbox: 1600×1000 pixels, clamp at edges as M1, speed 160 px/s, simulation/publication 20Hz, intent expiry 300ms, held renewal 100ms. These M1 values were explicitly reapproved for this slice; they do not become full-game defaults.
- Transport: 32-connection ceiling, 60 messages/s per connection, 2048-byte app frames, 2s send timeout, 5s client/bootstrap watchdog. Only two fixture principals exist: this is not a game character/player quota. Uvicorn is launched with one worker and a 64-frame transport queue.
- Local budgets: maximum receipt-to-admission 25ms; pending/admitted-input/outbound capacities 64/64/8 per binding; at most two fixed catch-up ticks before freeze/resync. No production latency/CCU promise is made.
- T-11 comparison uses observed admission latency and clock resolution for tolerance. Controlled-clock tests exercise the real receive handler and implementation-generated timestamps, not a fixture assigning admission times. Histogram boundaries are derived from the approved admission budget, not extra gameplay or production alert thresholds.

## Local identity and reconnect lifecycle

`POST /m2/session` accepts no body or query identity fields. After exact Origin and loopback-client checks, the server assigns an unused fixture and sets an opaque, random, boot-scoped, HttpOnly/SameSite=Strict cookie at `/m2`. IDs, fixture handles and adapter selection are not returned as client-selectable IDs or URL parameters. The local capability is a test harness mechanism, not real authentication. Non-browser Origin spoofing is not claimed as authentication.

Use two independent browser profiles/contexts at `http://127.0.0.1:3000/vertical-slice`; use the same hostname for browser and backend cookie site. A fixture remains reserved in RAM until restart, even after disconnect. A third fresh browser with neither assigned cookie receives `local_fixtures_in_use`; restart the backend to reset fixtures. This retention/exhaustion behavior is intentionally limited to the approved two-fixture harness.

Disconnect hides the entity, clears input and invalidates the old active binding. Reconnect with the same cookie preserves identity/position in RAM, rotates control generation and receives a full current baseline. A simultaneous second connection to that fixture is rejected, never takeover. Old callbacks/cleanup cannot erase a replacement. Unknown cookies after restart get a newly assigned fixture; no old position/control is restored.

## Time and bounded owner processing

`receive_inputs` stamps owner `t_received` immediately after the complete receive callback, before pending/admission processing. The owner uses the same monotonic, high-resolution `time.perf_counter` clock for receipt, admission and integration. `World.admit_raw` validates and stamps actual `t_admitted` in a short per-event operation with no await, RPC, database or tick-timer dependency. Accepted edges retain their order/effective times until fixed integration over `[a,b)`. An event exactly at `b` affects the next positive-duration segment.

The owner integrates each segment and clips its active duration at the original intent deadline before applying the approved boundary clamp. It never moves the expiry forward to make a late segment fit. Same-direction renewals only extend an unexpired intent from their own admission; old generations, duplicate/out-of-order sequences, already-closed receipt intervals, over-budget admission or lost queue capacity trigger explicit resync. Resync discards unsafe pending intent and rotates control generation; it does not backdate input or invent travel. Excess catch-up also resyncs instead of one oversized delta.

After expiry, server rejects non-idle input until an explicit idle/release, then a fresh directional sample. Browser key edges are sent from keyboard callbacks between frames; render updates only renew held intent. OS key-repeat cannot restart an expired/blurred hold. The server validates intent sequencing, not physical keyboard hardware attestation.

Every published state is a full baseline containing active public entities; there are no deltas or production AOI. Slow-client queues may coalesce obsolete full states but preserve welcome/resync/control messages or close that binding. Neither rendering nor transport ACK is a durability claim.

`GET /m2/metrics` requires local Origin/loopback checks. It exposes admission sample count, rolling 64-sample p50/p95/p99 and derived histogram, lifetime maximum, pending depth/oldest age, budget-overrun/reject/resync counters, event-loop lag, active count and boot ID. Pending processing is direct, not an unbounded actor mailbox; transport buffering is separately bounded. Event-loop time before observation cannot be reconstructed from admission latency.

## Run on Windows

Backend, from a dedicated PowerShell terminal:

```powershell
Set-Location 'F:\MMRPG PNTT\backend'
$env:TU_APP_ENV = 'local'
$env:TU_M2_VERTICAL_SLICE = '1'
.\.venv\Scripts\python.exe -m uvicorn app.main:app --host 127.0.0.1 --port 8000 --workers 1 --ws-max-size 4096 --ws-max-queue 64
```

Frontend, from another terminal:

```powershell
Set-Location 'F:\MMRPG PNTT\frontend'
npm run build
npm run start
```

Open `/vertical-slice` in two independent browser profiles. Focus each canvas; move with WASD/arrows. Watch both avatars and the public player list update on both clients. Reconnect preserves the same canvas/entity and RAM position. To demonstrate held expiry, drop renewals (covered by browser E2E), then release/press to resume. Restart the backend and reconnect: boot/entity identities and positions recreate. No `.env`, credential, database or cache setup is needed. Root `/` and `/ws` remain the separate legacy M1 regression demo; they are not M2 membership or an identity fallback.

## Verification and remaining gates

Backend tests cover fixture isolation/startup guards, injection/origin/loopback checks, real receive-to-admission callbacks with controlled time and an independently scheduled tick, boundaries, delayed/stale admission, exact expiry/release, overflow, cleanup/coalescing, two real ASGI clients, outbound authority and an actual Uvicorn process restart. A socket guard forbids external/database/cache connects in the in-process runtime test. The restart test uses only loopback and disables client proxy-environment routing.

Frontend tests cover v1 regression plus v2 strict envelopes, bootstrap deduplication under Strict Mode, stale authority, peer cleanup, keyboard edge delivery and release gates. Browser E2E uses two isolated contexts with real Next.js/Uvicorn; verifies bidirectional replication, dropped-renewal expiry, continued-key suppression, release/repress, peer leave and same-entity/canvas reconnect. Existing M1 browser regression tests remain enabled.

Exact executed commands, counts, exit codes, warnings/failures and screenshots belong to the immutable implementation handoff. Merely listing tests here is not a successful execution or independent acceptance. Full-M2 PostgreSQL/Redis/Auth/distributed/load tests remain NOT_IMPLEMENTED/NOT_RUN. Gemini 4 Argon implementation review and Owner acceptance are still required. Architecture fix history stays at 2/3; the new code milestone has its own initial implementation review, not a reset to evade architecture findings.
