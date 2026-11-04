# ADR-0004 — PostgreSQL checkpoints and durable fencing

Status: **PROPOSED**. Date: 2026-11-04. See [architecture](../M2_ARCHITECTURE.md), PO-06/08. Conceptual design only: no DDL, migrations, service access or production changes.

## Context

Redis presence/locks and process-local ownership cannot prevent a paused former owner from writing after takeover. Periodic persistence also cannot promise zero-loss movement. Schema compatibility and actual PostgreSQL/pool versions have not been inspected for this task.

## Proposed decision

PostgreSQL holds accounts/player profiles/characters, approved world/map metadata, active World Membership, latest position checkpoints, owner leases, control grants, operation results, ticket redemptions and transactional metadata outbox. Preserve service schemas and existing RLS helper objects. New physical names/roles/DDL need separate local-schema review; Supabase Auth integration and production migrations are outside M2 authorization.

One durable lease row per full partition identity has owner instance ID, monotonically increasing owner epoch and database-time expiry. Acquire/renew with conditional transactions; never steal an unexpired lease because Redis timed out. A process derives a conservative local monotonic deadline from successful renewal, deducting round-trip/uncertainty margin; check it before every integration and publication. An expired/replaced owner freezes. Downstream gateways reject old epochs/generations and require resync when authority is uncertain.

One current control grant per character includes session ID, monotonic control generation and full owner fence. Domain identities do not change when this transport/control generation changes. Membership version, grant placement and checkpoint placement must agree. A cross-world handoff is not implemented until its policy/transaction contract is approved.

### Checkpoint and takeover serialization

Proposed bounded transaction order:

1. Lock the partition lease row in a mode conflicting with takeover updates, then the character grant row, then its checkpoint row. Validate owner identity, epoch and database-time expiry **after acquiring locks**.
2. Validate current control generation and membership/version, finite canonical map-valid position, and expected checkpoint version.
3. Update using version CAS under those locks; commit promptly. Takeover/renewal uses the same canonical partition-then-character lock ordering. Multi-partition operations use a globally sorted full partition key before character locks.

An unlocked `WHERE EXISTS(lease...)` snapshot check alone is insufficient: it can pass before a concurrent takeover commits. Row-lock serialization plus CAS must be verified by concurrent integration tests. Expiry is assessed using an advancing database clock, not a transaction-start timestamp held indefinitely. Set bounded lock/statement/transaction timeouts; do not perform network awaits inside a transaction. Takeover cannot commit across the locked lease until the earlier valid writer transaction completes. Its ordering, validity and commit-uncertainty behavior are the guarantee; this is not a claim of a hard wall-clock deadline without bounded transactions.

PostgreSQL documents row-lock conflicts and transaction-scoped lock release in [explicit locking](https://www.postgresql.org/docs/current/explicit-locking.html). Actual target-version behavior and isolation/retry settings must be tested before implementation acceptance.

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
