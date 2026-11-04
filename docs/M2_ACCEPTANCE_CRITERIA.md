# M2 acceptance criteria — design and future implementation

Status: PROPOSED. These are verification obligations, not executed M2 tests. M1 remains accepted at its R1 source commit. Architecture approval and implementation acceptance are separate gates.

## D — design approval gate

- **D-01:** Required architecture, plan, criteria and ADRs exist; all proposed decisions and PO-01..PO-09 references are consistent. System/sequence/entity diagrams parse and links resolve.
- **D-02:** Independent Architecture Review evaluates authority/fencing, F-002 timing, persistence rollback, recovery, privacy, failure handling and unresolved product policy. No required finding remains unaddressed.
- **D-03:** Owner approves the architecture, maps/spawn/world policies, movement semantics, reconnect policy, durability/performance budgets and technical settings, or explicitly reduces scope. PO-01 is already decided: M2 identity interfaces only, no real Auth. Confirmed thresholds in the reference remain unchanged; missing policies stay Product Owner Decision Pending.
- **D-04:** This documentation task changes no M1 source, dependency lock, automation policy, historical report or production state. No M2 runtime/migration feature is claimed implemented.

D-01 may be checked during this task. D-02/D-03 remain pending until review/Owner action; committing these documents does not satisfy them.

## I — identity and ownership

- **I-01:** With two explicit local test principal contexts, each can select/control only owned characters through Account → Player → Character. Invalid, expired, missing or revoked context, disabled account and wrong ownership are denied before protected state. Account ID, Player ID and Character ID are distinct and cannot be confused with session/connection IDs. Real JWT/provider verification is NOT_IMPLEMENTED in M2 and cannot be claimed tested using fakes.
- **I-02:** Missing/unapproved Origin is rejected independently of token checks. Origin spoofing by a non-browser does not bypass verified identity/ownership.
- **I-03:** Ticket replay, expiry, origin/character mismatch, Redis replay after restore and concurrent redemption across gateways cannot create two control grants. PostgreSQL unique redemption is tested, not inferred from Redis GETDEL.
- **I-04:** Same character cannot accept input from two bindings. Approved conflict/takeover behavior and revocation bounds are demonstrated. An account can own multiple characters; no hardcoded quota or unique-character-per-account constraint. Creation with missing policy returns `POLICY_NOT_READY`; approved quota/name rules are configuration inputs, not arbitrary defaults.

## W — worlds, spawning and data boundaries

- **W-01:** Two clients in the same approved world/area observe the same public entities and authoritative movement. Different-world clients receive no unauthorized world/entity/private account data.
- **W-02:** Nhân Giới, Linh Giới and Tiên Giới have distinct stable world identities and configured map revisions. More gateways/processes do not create personal/shadow copies of a logical world.
- **W-03:** Server randomness chooses only valid approved spawn geometry. Test empty/invalid geometry, blocked candidates, sampling-attempt exhaustion and absent policy; no unbounded loop or coordinate/world fallback.
- **W-04:** Concurrent/retried spawn requests produce one committed result. Crash after database commit and before welcome recovers the same spawn. Reconnect does not reroll. Map-revision mismatch requires an explicit approved recovery policy.
- **W-05:** Starting world/eligibility/transitions and any separation/collision/safety constraints are Owner-approved test inputs. No automatic realm progression or protection rule is introduced.
- **W-06:** World Membership is durable placement, independent of Redis presence/session. At most one active membership per character. World Transition is a separate policy/orchestration interface; absent policy denies transfer. No free travel, reverse travel, point reset/loss or count limit is inferred. Confirmed thresholds 1000000 and 10000000 are preserved, not used as a complete transition policy.
- **W-07:** [Confirmed reference](GAME_RULES_REFERENCE.md) retains every supplied realm value, three sub-realm names, outfits and Đạo Tổ facts. Luyện Hư/sub-realm numeric thresholds remain absent. No progression/combat implementation or unrestricted cross-world data exposure is added.

## T — authoritative movement and F-002

- **T-01:** A deterministic server-clock fixture defines a fixed interval `[0,0.05]`, receives right at `0.01` and idle at `0.04`, and produces displacement `V × 0.03` before publication. `V` is supplied by the test, not a new gameplay default. No transition is collapsed away.
- **T-02:** Test multiple direction changes in one tick, equal-time transitions ordered by sequence, an event at a tick boundary, zero elapsed time and input-lease expiry inside an interval. Results match the piecewise integral and legal map bounds.
- **T-03:** Replayed/out-of-order/duplicate sequences, future/backdated client timestamps, client delta/speed/position injection and input spam cannot grant extra authoritative distance. Owner timestamps are the only integration time source.
- **T-04:** A fixed server event trace produces equivalent movement under different browser FPS, publication rates and bounded delivery schedules. Network delay shifts accepted receipt time; it does not grant historical movement credit.
- **T-05:** Delayed ticks perform bounded catch-up. Excess backlog, queue overflow, long process pause or authority expiry never becomes one oversized delta/teleport. Freeze/resync behavior and error codes are tested; stop events are not silently discarded.
- **T-06:** Received ACK, applied ACK and durable checkpoint version reflect their actual boundaries. No applied/durable claim precedes the corresponding integration/commit.

## S — real-time synchronization

- **S-01:** Initial join and reconnect receive a full authorized AOI baseline. Enter/state/leave, world/map IDs, owner epoch, stream ordering and entity versions are validated in both browser and backend.
- **S-02:** Missing Pub/Sub messages, new subscriptions, baseline mismatch and old-owner publications cause bounded full resynchronization. No delta is applied to an unknown baseline.
- **S-03:** Bounded slow-client queues preserve lifecycle/control semantics or explicitly force resync/disconnect. Output coalescing does not coalesce the owner's inbound input transitions.
- **S-04:** Repeated connect/loss/recovery/reload does not duplicate characters, canvases, handlers, timers or manager entries. Old epochs/input buffers cannot affect the recovered session; existing M1 cleanup regressions still pass.

## P — durability and authority safety

- **P-01:** Account/player/character/membership/position/map FK/version constraints and any approved configurable per-account limits are verified under concurrency in an approved local/non-production PostgreSQL target. No production migration or real Auth service is needed or authorized by this test criterion.
- **P-02:** Race a checkpoint writer against owner takeover and control-generation replacement. Transactions lock/validate lease/grant rows and CAS position versions in the declared order; old writers never commit through a check/use race.
- **P-03:** Pause the old owner beyond lease expiry; acquire a newer owner; resume the old process. Old inputs, publications and checkpoint writes are rejected. Redis expiry or a routing hint alone cannot acquire authority.
- **P-04:** Crash at each spawn/grant/checkpoint/outbox boundary. Recovery meets the approved checkpoint RPO/RTO and idempotency contract. State ACK does not promise durability; zero-loss claims require a separately reviewed durable-log design.
- **P-05:** Test actual connection-pool mode, transaction scope and timeout behavior. RLS/auth context cannot leak across pooled requests; session-level assumptions are not used to protect writes.
- **P-06:** Duplicate metadata delivery is harmless, event IDs/aggregate versions are checked, and relay restart can replay from durable outbox state. No exactly-once delivery claim without an end-to-end proof.

## R — Redis and failure handling

- **R-01:** Delayed cleanup with an old generation cannot delete current presence or membership. Stale-index pruning and presence renewal are atomic within the configured hash slot.
- **R-02:** Expire/delete/restart Redis data: durable characters/positions remain; online status becomes unknown or rebuildable; new tickets fail closed while unavailable. No second owner appears.
- **R-03:** Kill Pub/Sub subscribers and inject publication gaps: gateways resync. Redis Stream/outbox consumer retries/duplicates/retention are tested if that adapter is in the approved scope.
- **R-04:** Database outage, failed checkpoint/lease renewal, Redis outage, owner death and gateway death follow the documented failure behavior. Recovery requires fresh verified authority; no fallback trusts client state or stale Redis coordinates.

## Q — security, capacity and final acceptance

- **Q-01:** No secrets/private env/auth cache/service-role key in browser bundles, repository, messages or logs. Validate sanitized errors, per-IP/account/character admission budgets, size/rate/queue caps and authentication deadlines.
- **Q-02:** Run the approved workload: CCU per world/partition, AOI density, traffic/burst/lag/disconnect patterns and duration. Record p50/p95 tick time, input age, event-loop lag, memory, egress, checkpoint latency and recovery times. Thresholds must be approved before testing; placeholder numbers cannot pass a performance gate.
- **Q-03:** A multi-process integration run uses at least two gateways with one authoritative owner for a shared partition, and demonstrates no duplicate authority when scaling. A hotspot's single-owner limit is reported honestly.
- **Q-04:** Execute the complete relevant frontend/backend/protocol/database/Redis/browser/failure suites; preserve real outputs and NOT_RUN items. Developer review, exact Git scope, secret checks and remote SHA verification accompany meaningful commits.
- **Q-05:** Seal a new full-content snapshot and obtain independent Gemini milestone review before proceeding. Neither AI merges main or deploys. Production schema work remains separately authorized.
