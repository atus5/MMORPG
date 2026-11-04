# ADR-0006 — versioned synchronization and fenced recovery

Status: **PROPOSED**. Date: 2026-11-04. See [architecture](../M2_ARCHITECTURE.md), PO-02/06/08. Protocol v2 is proposed; M1 v1 is unchanged.

## Context

A reliable WebSocket does not prevent missed cross-node updates, old cleanup, slow-client overflow or an owner crash. Reconnecting transport cannot authorize client state, another random spawn or replay of old controls. Account/Player/Character IDs are distinct from a recovered session.

## Proposed decision

Use a versioned envelope with message type, bounded payload and trace ID; server binds identity and authority internally. Input carries sequence/direction/current control generation and optional diagnostic timestamp, never position/speed/world assignment. Reject unknown authority fields, nonfinite values, invalid enums, stale generations and unbounded messages before runtime admission.

Welcome/full snapshot includes authorized public AOI entities, world/map revision, membership version, owner epoch, tick, stream sequence and baseline ID. Public entity appearance is separated from account/private character metadata. Deltas are optional after full-snapshot implementation is proven; each delta names the exact baseline/source epoch/sequence. Any gap, stale owner or unknown baseline invalidates dependent deltas and requests a new full snapshot. Periodic baseline/liveness checks cover the last lost Pub/Sub message when no later sequence reveals the gap.

Separate `ack_received_seq`, `ack_applied_seq` and durable `checkpoint_version`; never show a transport ACK as a durability guarantee. State coalescing may replace obsolete full render states in a bounded outbound queue. Lifecycle/control messages must be delivered in order or explicitly force a new baseline/disconnect; silently dropping enter/leave/grant changes is unsafe. Input queues retain transitions per ADR-0003 and do not inherit this outbound coalescing rule.

## Recovery state machine

1. On transport loss, disable old binding input and idle/expire intent. Idempotent generation-aware cleanup may remove only its own manager/presence entry; socket-close errors cannot corrupt session ownership.
2. Recovery obtains a fresh trusted identity context through the interface. M2 uses explicit local test identities only; real Auth remains deferred. Recheck ownership, policy and durable/current authority; issue fresh admission/control generation. Same-character concurrent-tab handling remains Owner-pending, with dual control prohibited.
3. A healthy owner returns current in-memory authoritative position and a full AOI baseline. Otherwise acquire a valid new owner epoch after lease expiry and restore the last committed checkpoint/membership. Redis/client coordinates are not authority.
4. Old inputs, deltas, control generations, timers and cleanup callbacks cannot affect the recovered binding. Client discards its old input queue, interpolation buffer and avatar when no current snapshot exists. Do not create another Phaser Game instance to reconnect.
5. If policy, map compatibility or trusted authority is unavailable, stay failed/frozen with an explicit reason. Do not reroll spawn, choose an arbitrary world or silently relocate. Uncertain operations query durable results by operation ID.

Disconnect visibility, grace periods, despawn, rollback tolerance and recovery windows are **Product Owner Decision Pending**. No combat protection, offline reward or client rewind rule is inferred. Technical socket closure is separate from durable membership policy.

## Security and scaling boundaries

Exact Origin checks supplement, not replace, trusted principal/ownership checks. Pre-admission state is bounded and reveals no protected world state. Internal owner channels authenticate peers; routing hints never authorize input. Long-lived validity/revocation is bounded by approved interface policy; real provider enforcement is a later integration responsibility.

Gateway scaling fans out authorized AOI views without duplicating simulation. Baselines cost bandwidth but simplify correctness; delta compression/prediction comes only after measured need and recovery tests. Full-world broadcast and unbounded per-socket queues do not meet the design. Cross-world Đạo Tổ name visibility is a separately approved public projection, not a blanket world-data exception.

## Validation and approval dependencies

Future integration/browser tests cover join, two clients in one world, denied cross-world subscription, transport loss, failed reconnect, page reload, repeated cleanup, slow clients, missing final Pub/Sub update, baseline mismatch, stale owner publications and owner/database/Redis failure. Preserve M1 F-001/F-003 regression behavior. Prove no duplicate canvas/entity/handler/timer and no replayed movement on recovery.

PO-02/06/08 approve conflict behavior, disconnect/recovery semantics, `T_recover`, heartbeat/full-baseline cadence, `B_out`, input age and validity deadlines. No numeric game or infrastructure defaults are selected here.
