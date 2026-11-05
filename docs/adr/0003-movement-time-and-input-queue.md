# ADR-0003 — fixed steps with ordered input edges

Status: **PROPOSED**. Date: 2026-11-04. Addresses M1 **F-002: DEFERRED_BY_OWNER_TO_M2**. M1 source is not changed. See [architecture](../M2_ARCHITECTURE.md), PO-05/07/08.

## Context

M1 can quantize a press/release within a 50ms simulation interval, up to the observed 8px at its demonstration speed. Raising tick frequency alone does not retain input edges overwritten between ticks. Browser FPS, client timestamps and client delta time must not decide authoritative distance.

## Proposed decision

Use fixed simulation intervals, a bounded ordered event queue per controlled character and piecewise integration over each interval. The following is a proposed temporal contract, not a selected gameplay/lag policy.

### Observation, admission and tick closure — NR-M2-001

- `t_received`: the owner's monotonic observation time at its earliest complete-event ingress callback, before placing the event in a pending actor mailbox. Do not defer this observation/stamp to a simulation-tick mailbox drain. A socket/gateway timestamp is diagnostic; buffering, scheduling and unsynchronized process clocks prevent it from recovering time the owner has not observed. It does not measure the original key press.
- `t_admitted`: the owner's monotonic time at the serialized admission point, after validation and successful reservation of bounded queue capacity. Admission and tick closure share one ordered actor operation/critical section, but admission runs per event between ticks, not only when a tick closes. The event's effective time is `t_admitted`, never an earlier client/socket time. Validation/scheduling delay between receipt and admission grants no movement credit and is a measured, bounded failure risk rather than permission to defer processing arbitrarily.
- Integration time: the event's position on the admitted timeline while a fixed interval is processed; the computation may occur later in wall-clock time. It cannot move an event across a closed interval or change its effective time.

### Continuous admission and latency — R1-001

After ingress observes a complete event, schedule its admission as the next ordered input operation for that binding, after any already-running bounded owner operation and earlier input events. Service this path continuously between simulation ticks; it must not wait for the next tick/publication timer, a render callback or a batch threshold. Admission validates the trusted binding/sequence/authority and reserves capacity in a short serialized operation, without a database/Redis/external RPC wait. Preserve each event and its actual effective time. Draining both a right event received at `0.01` and an idle event received at `0.04` only at `0.05` is not a conforming low-load implementation, even if it retains both sequence numbers. Integration may consume the already admitted timeline at closure; admission itself cannot be implemented as that deferred integration batch.

Measure `input_admission_latency_seconds = t_admitted - t_received` on the same owner monotonic clock for every admitted event. Record sample count, histogram/p50/p95/p99/max, pending admission queue depth and oldest `pending_admission_age_seconds`; count `admission_budget_exceeded_total`, rejects and freeze/resync events separately so rejected or never-admitted inputs do not disappear from latency evidence. Bounds cover the pending ingress/mailbox as well as the admitted input queue. Observe event-loop lag separately: a pause before the owner can observe a frame is not included in this latency and cannot be repaired by fabricating earlier `t_received` values.

`T_admission_budget`, histogram buckets/alert policy and the pending-queue bound require PO-07/08 approval and workload measurement; no numeric threshold is supplied. Check pending age before admission and after any delayed operation. If that approved budget is exceeded, queue capacity is lost or timely admission cannot preserve the timeline, do not silently admit at a new common timestamp and claim F-002 correctness: freeze the affected binding, invalidate unsafe pending intent and require authorized resync under the existing failure contract. Never compensate by backdating `t_admitted`. Missing budget/fixture approval leaves this acceptance gate pending; absence of a configured threshold is not a latency PASS or permission to deploy. Late-input UX and held-key resumption remain PO-05 pending.

Intervals are half-open `[a,b)`. Closure atomically seals the admitted prefix eligible for that interval; an event at `b` changes state for the next positive-duration segment. Equal-time events use strictly increasing binding sequence, including directional samples and renewals. Already admitted edges retain effective times/order through bounded scheduling delay. An event observed earlier but admitted after closure has no right to the closed interval. Its current admission time can be used only under an approved late-input policy; reject/freeze/resync alternatives and admissible input age remain PO-05 pending. No rollback, historical backfill or silent timestamp clamp is authorized.

Every queued event binds session/control generation, membership/placement and owner epoch. Validate that binding, sequence, payload and authority before admission and again before application. A received-but-not-admitted event has no admission ACK; a rejected/duplicate event cannot extend intent expiry. Check input age/expiry against the owner timeline and authority deadlines, not client time. Any negative/nonmonotonic time, ambiguous closure, lost admitted edge, queue overflow or excessive backlog that prevents a valid timeline freezes affected movement and requires a fresh authorized baseline. Choosing rejection/disconnect/recovery UX and numeric bounds remains pending; do not silently discard a stop or continue on guessed history.

### Ordered segment integration — NR-M2-004

For each `[a,b)`, construct ordered temporal segments from admitted transitions and intent-expiry boundaries. Starting at the current canonical position, integrate one segment's approved velocity/duration, apply that segment's approved collision and map bounds, then use its resulting position as the next segment's start. Never sum displacement vectors before collision: a turn or reversal around a blocked segment can otherwise tunnel or produce a different path. Zero-duration ties change state in sequence order without adding travel. Position, speed and duration never come from client authority.

Hitbox, obstacle contact, sliding, bounce, diagonal normalization and map geometry remain PO-04/05 pending. An unobstructed one-dimensional fixture can test temporal arithmetic without defining production collision. Collision fixtures must supply explicitly approved semantics; expiry and renewal split the same ordered timeline rather than a second movement path.

Arithmetic regression: idle at `0`, right admitted at `0.01`, idle admitted at `0.04`, publish at `0.05` gives `V * 0.03` displacement on an unobstructed one-dimensional test map. A fixture explicitly using M1's demonstration `V=160px/s` would expect `4.8px`; this is not a production speed decision. This integration-only example does not establish real ingress/admission correctness; [T-11/T-12](../M2_ACCEPTANCE_CRITERIA.md#t--authoritative-movement-and-f-002) must exercise the actual receiving path without injecting admission timestamps.

Separate simulation rate `f_sim`, publication rate `f_pub`, input expiry `T_intent`, input queue bound `B_input` and catch-up work bound `K_catchup`. Their values require approved measurements/semantics. Input expiry splits integration inside an interval; elapsed authority/lease deadlines use real monotonic time, not slowed simulation time.

### Direction samples, held-input renewal and expiry — NR-M2-007

A directional sample explicitly states the desired approved direction (including an explicit idle/release); a renewal asserts continued intent for the same already active direction and references its accepted sample/intent generation. Validate this against the admitted intent timeline in sequence order, including pending samples, not only the last published direction. Transport ping/pong measures connection liveness only and never renews movement. Renewals and samples share one strictly ordered sequence within the current binding and owner epoch. Reject old sessions/generations, replay/out-of-order sequences and renewals for a replaced direction. A renewal cannot synthesize a direction transition or resurrect an expired sample.

An accepted non-idle sample starts a bounded intent interval at `t_admitted`; a valid renewal admitted strictly before its current expiry may extend the deadline from that renewal's admission by approved `T_intent`. Explicit idle ends movement and invalidates that active intent. At the exact expiry boundary the old interval is over; a renewal cannot retroactively bridge it. A direction change ends the previous direction at its admission time and starts the new approved sample there; earlier queued segments remain intact. Deadline changes are timeline events, so a future renewal cannot erase an expiry that occurred earlier in integration.

An idle gap is the interval from expiry/release until an approved fresh non-idle sample becomes effective. Movement receives no credit during it. Whether a still-held physical key must be released/repressed or may send a fresh sample after expiry is **Product Owner Decision Pending (PO-05)**; the protocol must distinguish either approved behavior from renewing an expired intent. No automatic resumption is selected. Unsupported/unapproved resume semantics stay unavailable. Timer, renewal cadence, rate/queue bounds and maximum input age require PO-05/07/08 approval; none is assigned here.

On overload, never coalesce input to only the latest direction and silently lose a stop. Preserve admitted edge ordering within bounds; if admission cannot do so, freeze and resynchronize the binding under the approved error policy. Rate limiting cannot create extra simulated time. Past/future client timestamps, replayed sequences and packet spam do not increase displacement.

After a long event-loop pause, run only bounded catch-up. If backlog exceeds the approved window, abandon that backlog, invalidate old queued intent and establish a fresh authoritative time baseline/full snapshot under the same authority checks. Do not compress missed time into a huge delta or compensate lag with travel. Owner expiry forces freeze even if a queue remains.

## Acknowledgement semantics

`ack_received_seq` means successfully admitted to the bounded owner queue at `t_admitted`; raw receipt at `t_received` is only diagnostic. `ack_applied_seq` means consumed, including a renewal's timeline effect, in a completed closed interval. Durable means the corresponding checkpoint transaction committed. Do not acknowledge an unprocessed sequence gap or infer durability from an applied/render ACK. Reconnect discards old-session events and receives a fresh snapshot.

## Alternatives and consequences

Latest-direction polling loses brief transitions. Client delta integration enables speed/time cheating. A higher tick rate raises cost without solving lost edges. Full deterministic rollback using client time introduces trust and complexity unnecessary for M2's proposed foundation.

Owner admission time favors security and simple time authority, but network/validation/scheduling delay shifts when movement begins and cannot be fully hidden. Interpolation improves visual smoothness only. Optional later prediction must reconcile to this same server trace and cannot change authority.

## Validation and approval dependencies

Use deterministic owner-clock traces: multiple transitions in one tick, identical timestamps, exact boundaries, expiry mid-tick, delayed gateway delivery, spam/duplicate/out-of-order sequences, owner pause and full queues. Vary browser FPS and publication frequency with the same accepted server trace. Verify displacement, collision boundaries and received/applied/durable ACKs independently.

Add receipt-before/admission-after-closure traces, admission/closure races, delayed validation, renewals before/at/after expiry, ping without renewal, stale direction renewal, release/repress versus fresh-sample policy fixtures, idle gaps and obstacle/turn/reversal segments. Compare ordered collision results, not only total unconstrained distance. All are future test specifications, NOT_RUN in this documentation-only revision.

End-to-end specifications use the production-equivalent complete-message receive/decode/route/owner-ingress/admission path with a controlled server clock and independently scheduled tick loop. Inject right/idle frames at `0.01`/`0.04`; let the implementation stamp receipt and admission, rather than calling the queue/integrator directly or assigning `t_admitted`. In the no-delay fixture both admissions precede closure and retain a positive right segment; displacement is `V * (t_idle_admitted - t_right_admitted)`, approaching `V * 0.03` within an explicitly approved tolerance derived from measured admission latency. A tick-end-only drain must fail this test. Inject delay after observed receipt to test latency metrics and budget-triggered freeze/resync, and a separate pause before observation to prove no unobserved historical time is claimed. These tests remain NOT_RUN until M2 implementation, fixture and budgets are approved.

PO-05 defines direction/diagonal/collision/speed/lag semantics. PO-07/08 approve rate/queue/catch-up/security and admission-latency/pending-queue budgets. No new gameplay or latency value is chosen or implemented by this ADR.
