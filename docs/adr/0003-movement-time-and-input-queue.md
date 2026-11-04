# ADR-0003 — fixed steps with ordered input edges

Status: **PROPOSED**. Date: 2026-11-04. Addresses M1 **F-002: DEFERRED_BY_OWNER_TO_M2**. M1 source is not changed. See [architecture](../M2_ARCHITECTURE.md), PO-05/07/08.

## Context

M1 can quantize a press/release within a 50ms simulation interval, up to the observed 8px at its demonstration speed. Raising tick frequency alone does not retain input edges overwritten between ticks. Browser FPS, client timestamps and client delta time must not decide authoritative distance.

## Proposed decision

Use fixed simulation intervals, a bounded ordered event queue per controlled character and piecewise integration over each interval. The owner stamps accepted events using its own monotonic clock, with sequence ordering for equal timestamps. A gateway timestamp is diagnostic only: clocks across processes are not assumed synchronized. Client timestamps may detect anomalies but cannot grant retroactive simulation time.

For interval `[a,b]`, retain every accepted direction transition and integrate the current allowed velocity until the next transition or input-lease expiry. Sum these subintervals and apply approved collision/map constraints through the simulation integrator; position is never accepted from the client. Direction semantics and speed are approved configuration, not M1 defaults. At the exact right boundary an event changes state for the next positive-duration segment; equal-time events have deterministic sequence order. Expired/stale grant events are rejected before integration.

Reference regression: idle at `0`, right accepted at `0.01`, idle at `0.04`, publish at `0.05` gives `V * 0.03` displacement on an unobstructed one-dimensional test map. A fixture explicitly using M1's demonstration `V=160px/s` would expect `4.8px`; this is not a production speed decision. Both edges must survive even if no render occurs between them.

Separate simulation rate `f_sim`, publication rate `f_pub`, input expiry `T_intent`, input queue bound `B_input` and catch-up work bound `K_catchup`. Their values require approved measurements/semantics. Input expiry splits integration inside an interval; elapsed authority/lease deadlines use real monotonic time, not slowed simulation time.

On overload, never coalesce input to only the latest direction and silently lose a stop. Preserve admitted edge ordering within bounds; if admission cannot do so, explicitly freeze/idle and resynchronize the binding under the approved error policy. Rate limiting cannot create extra simulated time. Past/future client timestamps, replayed sequences and packet spam do not increase displacement.

After a long event-loop pause, run only bounded catch-up. If backlog exceeds the approved window, abandon that backlog, invalidate old queued intent and establish a fresh authoritative time baseline/full snapshot under the same authority checks. Do not compress missed time into a huge delta or compensate lag with travel. Owner expiry forces freeze even if a queue remains.

## Acknowledgement semantics

Received means admitted to the owner's queue. Applied means integrated into a completed simulation interval. Durable means the corresponding checkpoint transaction committed. These are separate fields/boundaries; a render ACK cannot promise recovery without rollback. Reconnect discards old-session events and receives a fresh snapshot.

## Alternatives and consequences

Latest-direction polling loses brief transitions. Client delta integration enables speed/time cheating. A higher tick rate raises cost without solving lost edges. Full deterministic rollback using client time introduces trust and complexity unnecessary for M2's proposed foundation.

Server receipt time favors security and simple time authority, but network delay shifts when movement begins and cannot be fully hidden. Interpolation improves visual smoothness only. Optional later prediction must reconcile to this same server trace and cannot change authority.

## Validation and approval dependencies

Use deterministic owner-clock traces: multiple transitions in one tick, identical timestamps, exact boundaries, expiry mid-tick, delayed gateway delivery, spam/duplicate/out-of-order sequences, owner pause and full queues. Vary browser FPS and publication frequency with the same accepted server trace. Verify displacement, collision boundaries and received/applied/durable ACKs independently.

PO-05 defines direction/diagonal/collision/speed/lag semantics. PO-07/08 approve rate/queue/catch-up/security budgets. No new gameplay value is chosen or implemented by this ADR.
