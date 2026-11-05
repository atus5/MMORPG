# ADR-0004 — PostgreSQL checkpoints and durable fencing

Status: **PROPOSED**. Date: 2026-11-04. See [architecture](../M2_ARCHITECTURE.md), PO-06/08. Conceptual design only: no DDL, migrations, service access or production changes.

## Context

Redis presence/locks and process-local ownership cannot prevent a paused former owner from writing after takeover. Periodic persistence also cannot promise zero-loss movement. Schema compatibility and actual PostgreSQL/pool versions have not been inspected for this task.

## Proposed decision

PostgreSQL holds accounts/player profiles/characters, approved world/map metadata, active World Membership, latest position checkpoints, owner leases, control grants, operation results, ticket redemptions and transactional metadata outbox. Preserve service schemas and existing RLS helper objects. New physical names/roles/DDL need separate local-schema review; Supabase Auth integration and production migrations are outside M2 authorization.

One durable lease row per full partition identity has owner instance ID, monotonically increasing owner epoch and database-time expiry. Acquire/renew with conditional transactions; never steal an unexpired lease because Redis timed out. A process derives a conservative local monotonic deadline from successful renewal, deducting round-trip/uncertainty margin; check it before every integration and publication. An expired/replaced owner freezes. Downstream gateways reject old epochs/generations and require resync when authority is uncertain.

One current control grant per character includes session ID, monotonic control generation and full owner fence. Domain identities do not change when this transport/control generation changes. Membership version, grant placement and checkpoint placement must agree. A cross-world handoff is not implemented until its policy/transaction contract is approved.

### Operation-level lock matrix — NR-M2-005

This revision replaces the incomplete partition-then-character sketch with a **PROPOSED** operation matrix and conflict analysis. It is not an Accepted ADR or a tested physical-schema guarantee. Proposed rank order: Account anchors → Player anchors → Character anchors → full partition lease keys → membership rows → control-grant rows → checkpoint rows → operation-result keys → ticket-redemption keys → outbox insertion. Within each rank acquire every required key in a stable sorted order; partition sorting uses the complete `(world_id, map_revision, partition_id)` tuple. Select the strongest required mode at first acquisition; no later lock upgrades or expanding a batch after later ranks are locked.

Use Account/Player shared row locks when validating unchanged ownership/status and Character exclusive row locks to serialize every placement/control/checkpoint mutation, including absent child rows. Status/ownership/revocation mutations must conflict with those anchors and follow the same rank order; their unapproved product policy is not supplied here. Lease readers use a shared row lock that conflicts with lease updates (proposed PostgreSQL `FOR SHARE`, not merely `FOR KEY SHARE`); acquire/renew/takeover use exclusive/update locking. Exact SQL, isolation and schema remain gated on local/non-production validation.

| Operation | Locks and revalidation in rank order | Outcome boundary |
| --- | --- | --- |
| First spawn / ticket admission | Account → Player → Character anchors; approved placement lease; membership → grant → checkpoint; operation result → unique ticket redemption when applicable. Revalidate principal/account/ownership, policy/map candidate, membership absence/current version and full fence after locks. | One atomic placement/grant/result, plus redemption/outbox when required; publish only after known commit. |
| Recovery / control replacement | Same anchors; current/approved target lease set sorted; membership → grant → checkpoint; operation/redemption. Revalidate current placement and fresh principal; conflict behavior must be approved. | One new control generation or an explicit denial; no replay of old intent. |
| Checkpoint, including a bounded batch | Acquire all Account, then Player, then Character anchors sorted by rank; discover placement under anchors; acquire all leases sorted in shared mode, then membership/grant/checkpoint rows sorted; CAS checkpoint versions. | Commit only current fences/placements/generations and canonical positions. A stale member aborts the batch for explicit revalidation/retry, never partial success claims. |
| Lease acquire / renewal / takeover | Lease rows only, sorted when more than one. Conditional owner/epoch and advancing database-time expiry check after lock. No Character/grant/checkpoint locks in this transaction. | Renewal preserves epoch only for the still-valid matching owner; takeover after expiry increments epoch. Old grants remain fenced out until separately re-admitted. |
| Approved membership transition | All affected anchors first; full source/target lease set sorted; membership → grants → checkpoints → operation result → outbox. Revalidate source version, both fences and approved policy. | Atomic handoff, never duplicate active placement. No enabled transition until policy and cross-owner tests are approved. |

Operation/result or redemption lookups before locking are advisory only. Re-read under the declared locks; never lock a result/key first and then request a lower-ranked anchor. An absent row needs a durable unique constraint plus an existing anchor, not a lock on a nonexistent row. Replayed ticket keys bind the same character/request digest, preventing cross-character uniqueness waits from creating an inverted protocol. Changed ownership or a different discovered lease set aborts/restarts from the beginning rather than adding locks out of order. Candidate geometry, principal-interface calls and target-reservation RPCs happen before the transaction and are revalidated within it using approved versions; no Redis/external RPC is awaited inside it.

### Checkpoint, renewal and takeover conflict analysis

A checkpoint's shared lease lock permits another valid checkpoint reader but blocks renewal/takeover updates until it ends. Renewal/takeover may delay the checkpoint, but their lease-only transaction never waits for a Character anchor held by that checkpoint. This removes the lease→Character / Character→lease cycle that a takeover or renewal sweeping grants in the same transaction would introduce. Account/Player shared locks and Character-exclusive serialization also prevent concurrent first-spawn or control replacement from bypassing missing membership/grant rows. Two overlapping batches acquire all ranks/keys in the same order, avoiding opposite Character or source/target acquisition order. Shared-to-exclusive upgrades or ownership writes bypassing the anchors/rank order would invalidate that reasoning and are prohibited by the proposed protocol.

Long checkpoint batches can starve or delay renewal despite consistent ordering. Prepare an immutable bounded snapshot before opening the transaction; do not hold a lease lock across runtime ticks or a whole world scan. Recheck safe local deadlines before starting/waiting and database-time lease validity, full fence, membership/control and expected checkpoint version after acquiring locks and before writes. Abort/freeze if validity cannot be established; do not wait indefinitely and then extend an already expired old lease. A timed-out/uncertain renewal cannot extend the local deadline based on an assumed commit. Recover its durable outcome before resuming, and treat a local safe-deadline expiry as frozen until verified authority and resync.

An unlocked `WHERE EXISTS(lease...)` snapshot check alone permits a check/use race. Locking plus CAS orders valid writes against takeover; it does not promise every commit completes before a hard wall-clock expiry. Bound lock waits, statements, transactions, batch size and renewal margin through PO-06/07/08-approved budgets and measurements. No numeric capacity or timing value is selected. Never wait on Redis, another actor, external RPC, retry backoff or client input while holding transaction locks. Retry the entire aborted transaction with the same operation identity, outside old locks and only while authority remains valid.

The [PostgreSQL row-lock conflict table and deadlock guidance](https://www.postgresql.org/docs/current/explicit-locking.html) support the proposed shared/update conflict and consistent-order reasoning. Physical FK locks, uniqueness conflicts, triggers, isolation retries, database version and all competing mutation paths still need inspection and concurrency tests in an approved target. The matrix is a design analysis, not proof those unimplemented paths already comply.

### Durability contract

Use periodic and explicit lifecycle checkpoints, not one database write per frame/input. ACK received/applied remains distinct from a durable checkpoint version. Owner crash recovers only committed checkpoints: uncheckpointed movement may roll back up to an approved operating bound. A checkpoint/lease failure freezes affected authority rather than silently accumulating unbounded loss. Zero-loss movement would require a separate durable command/state log and cost review.

Create/spawn/transition operation IDs use request digests and stored results. Retry same key/same request returns the result; same key/different request fails. Ticket redemption uniqueness is in the control-grant transaction, preventing Redis-resurrection replay. Retain redemption records beyond ticket expiry plus the approved safety window; do not let cleanup revive a valid ticket.

Outbox metadata is stored in the same transaction as the authoritative change. Relay is retryable/at-least-once and consumers deduplicate event ID/aggregate version. It is not a durable movement journal or exactly-once delivery guarantee.

## Pooling, privacy and failure handling

Use a restricted backend role with explicit ownership authorization. A trusted principal in FastAPI does not automatically establish RLS claims in a pooled database connection. Apply any required per-request context transaction-locally and test pool reuse; avoid session-level advisory-lock assumptions with transaction pooling. [Supabase connection guidance](https://supabase.com/docs/guides/database/connecting-to-postgres), [RLS guidance](https://supabase.com/docs/guides/database/postgres/row-level-security).

Database failure denies new admissions/durable operations. Existing actors freeze on critical checkpoint/authority failure and always before their safe lease deadline. An uncertain commit is resolved from durable operation/checkpoint state after recovery, never client coordinates or a blind duplicate write.

## Alternatives, validation and approvals

Redis-only ownership lacks durable stale-writer protection. Per-frame database writes increase contention and still need fencing. Event sourcing could reduce movement rollback but is not justified before RPO/load approval.

Test writer/takeover/control-generation races, process pause/resume, lock timeouts/deadlocks/retries, failed commits, pool context leakage, checkpoint rollback, idempotent creation/spawn and outbox replay. PO-06/08 must approve RPO/RTO, `T_checkpoint`, `T_lease`, renewal margin and transaction/retention limits. No interval value is assigned here.
