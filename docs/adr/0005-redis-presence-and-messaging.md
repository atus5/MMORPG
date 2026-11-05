# ADR-0005 — disposable Redis presence and messaging

Status: **PROPOSED**. Date: 2026-11-04. See [architecture](../M2_ARCHITECTURE.md), PO-07/08. No Redis service is provisioned or accessed by this design task.

## Context

Presence needs expiry and fast fan-out; it must not become character ownership, durable World Membership or authoritative position recovery. Delayed cleanup and restored cache records must not invalidate a newer session or revive authorization.

## Proposed key strategy

Use separate environment credentials/instances where practical, plus namespace `tt:<env>:v2:`. Do not put credentials, raw tickets or provider tokens into keys. Partition tokens encode the complete world/map/partition identity unambiguously, not delimiter-concatenated user input. Cluster hash tags place keys used in one atomic script into one slot; Redis documents this restriction in its [cluster specification](https://redis.io/docs/latest/operate/oss_and_stack/reference/cluster-spec/).

Proposed key families, not executed commands:

- `tt:<env>:v2:{<partition-token>}:presence:<character-id>`: bounded record of public entity/session/control/owner generations, membership version and expiry. Only current owner renews its TTL. TTL is an approved liveness budget, not a combat/offline/despawn rule.
- `tt:<env>:v2:{<partition-token>}:members`: disposable membership index. Expiry of a presence key does not automatically remove SET entries. A same-slot atomic operation checks missing/current generation and prunes/renews consistently; authoritative membership remains in PostgreSQL.
- `tt:<env>:v2:{<partition-token>}:owner_hint`: cached owner route/epoch. Validate against current authority; a hint or TTL expiry cannot grant ownership.
- `tt:<env>:v2:{<partition-token>}:state`: bounded latest public render baseline/sequence metadata. Not a recovery checkpoint or private account store.
- `tt:<env>:v2:ticket:<digest>`: origin/character/principal reference, unique redemption ID and explicit expiry. Atomic consume only for this record; PostgreSQL unique redemption is separate and mandatory.
- `tt:<env>:v2:limit:<scope>:<opaque-id>`: bounded rate-bucket state; sensitive network identifiers use an approved privacy-preserving representation/retention. Bounds remain configuration decisions.

Presence cleanup compares the complete expected session/control/owner tuple atomically before deleting/updating. An old gateway/owner cleanup cannot erase a replacement's record. Index rebuild/repair reads current valid owner state, not unverified client joins. Expiry is a cache lifetime mechanism, as documented by [Redis EXPIRE](https://redis.io/docs/latest/commands/expire/); observed key absence alone says nothing definitive about a durable character.

## Messaging contract

Redis Pub/Sub is optional disposable cross-gateway render fan-out. It is **at-most-once**; messages lost during disconnect are not replayed. Attach full source identity, owner epoch and monotonic sequence. Gaps/new subscriptions require a full authoritative baseline; periodic baseline/heartbeat also detects a last lost update with no subsequent delta. [Redis Pub/Sub documentation](https://redis.io/docs/latest/develop/pubsub/).

Critical metadata changes originate in the PostgreSQL transactional outbox. A relay may use an approved reliable adapter or Streams later, but must remain idempotent and tolerate duplicates/restarts/retention. No exactly-once claim and no requirement to add Streams before it is useful. Movement input routes via a bounded authenticated owner channel with explicit admission ACKs; do not use lossy Pub/Sub as the sole input queue.

## Failure behavior and trade-offs

Redis unavailable: deny new ticket/presence admissions. Existing direct in-process simulation may continue only while database authority and delivery remain healthy; cross-node state/route uncertainty freezes/resynchronizes affected sessions. Online status is unknown, not a durable logout/deletion. Rebuild cache after dependency recovery without creating another authority. Redis restore may revive ticket bytes, so check their explicit expiry and durable redemption ID again.

### Ticket cache is not redemption authorization — NR-M2-006

A consumed/restored Redis record supplies only a lookup reference. At redemption apply [ADR-0001's current principal and Account → Player → Character revalidation](0001-identity-and-session-admission.md#redemption-revalidation--nr-m2-006), including account status, ownership and canonical membership/control binding. Commit the durable unique ticket redemption with the resulting grant/result using [ADR-0004](0004-postgres-durability-and-fencing.md#operation-level-lock-matrix--nr-m2-005). Redis availability, atomic consume or a cache hit cannot replace these checks. Consume Redis before opening the database transaction; a later failure may require an explicitly authorized retry, not restoring a ticket as proof of eligibility.

Unknown database commit outcome means no welcome or blind second grant. Resolve the original durable operation/redemption identity, including any still-in-flight transaction, and revalidate authorization before returning a result. A missing cache key is not evidence that the database committed or aborted. Cache rebuild never changes durable placement, principal validity or ticket redemption history.

Keeping Redis disposable simplifies recovery but may reduce availability during cache loss. Local process maps are acceptable adapters for unit tests, not proof of multi-process safety. Redis deployment/auth/TLS/persistence/eviction/topology and capacity need operational review; key prefixes alone are not security isolation.

## Validation and approvals

Test delayed old cleanup, generation changes during renewal, stale SET pruning, same-slot scripts, Redis restart/data restore, replayed tickets, fan-out gaps/last-update loss, bounded cache sizes and unauthorized route publication. PO-07/08 approve TTLs, budgets, privacy retention and adapter topology. Do not configure production services in this task.
