# ADR-0002 — shared logical worlds, membership and authority

Status: **PROPOSED**. Date: 2026-11-04. See [architecture](../M2_ARCHITECTURE.md), PO-03/04/07, and [confirmed rules](../GAME_RULES_REFERENCE.md).

## Context

M1's per-session runtime is not a shared MMORPG world. More socket gateways must not create independent copies of Nhân Giới, Linh Giới or Tiên Giới. World membership, transient online presence and permission to transfer worlds are different concerns.

## Proposed decision

Start with a modular monolith: separate gateway, admission, simulation, persistence and cache modules, but one backend process and one serialized owner per enabled world's initial partition. A partition key is the full `(world_id, map_revision, partition_id)` tuple. Gateways route to owners; they do not integrate movement independently. Every input/state/checkpoint carries the appropriate owner epoch and character control generation. Distributed extension is a seam to validate, not a claim that multiple Uvicorn workers are already safe.

The three worlds are shared logical spaces. AOI controls visible entities inside a space; infrastructure partitioning cannot introduce hidden personal worlds/channels. Spatial partitioning requires border AOI and fenced handoff before use. Capacity/hotspots must be measured; gateway scaling alone does not scale a crowded actor.

### World Membership abstraction

Durable membership relates Character ID to world/map/partition and version/lifecycle state. At most one active membership exists per character; checkpoint placement and control grant must reference that same placement. Membership survives transport loss and Redis expiry. Its lifecycle policy does not assume an offline character remains visible or protected; those are separate Owner decisions.

Server-only first spawn uses approved world eligibility, versioned navigable geometry and bounded random sampling. Persist the idempotent membership/position result before publishing the entity. Missing policy or valid geometry fails explicitly. Reconnect restores, not rerolls. Map-revision incompatibility cannot silently teleport the character.

### World Transition abstraction

`WorldTransitionPolicy.evaluate(trusted_character_state, source, target, policy_version)` returns approved transition parameters or a typed denial/unavailable result. No default allow exists. `WorldTransitionCoordinator` manages operation ID, source freeze, target reservation, fenced atomic membership/checkpoint/control change, durable result/outbox and target snapshot. Repeated calls retrieve the same result. Neither source nor target publishes an active duplicate. Transaction lock ordering and stale source/target handling must be demonstrated before enabling handoff; cross-partition details may be deferred while there is one partition per world.

No gameplay world-transfer implementation is authorized now. Confirmed thresholds remain exactly 1000000 Nhân Giới → Linh Giới and 10000000 Linh Giới → Tiên Giới. Do not confuse these confirmed values with a complete eligibility/cost/reset policy. Return travel, point loss/reset, transfer limits, starting/transition realms and missing Luyện Hư/sub-realm thresholds are **Product Owner Decision Pending**. Same-world partition transfer is not an escape from world policy.

## Alternatives and trade-offs

Per-socket worlds violate sharing. Uncoordinated multiprocess actors create split brain. Redis-lock-only ownership permits stale writers and cannot replace durable fencing. A full distributed cluster immediately would increase complexity before workload and rules are known.

One owner serializes mutations and simplifies invariant testing, at a per-partition throughput ceiling. Later owners can host distinct partitions under durable leases; transparent cross-owner handoff is not assumed. If a required policy is absent, affected admission/transition stays unavailable rather than inventing gameplay.

## Validation and approval dependencies

Two clients in one world must see the same authoritative public state; different worlds cannot leak private state. Future Đạo Tổ cross-map name visibility is an explicitly approved public projection from the confirmed reference, not permission for arbitrary cross-world subscriptions today.

Tests must cover two gateways/one owner, stale routes, owner pause/takeover/resume, one active membership, crash at spawn/transition boundaries, idempotent retries and generation-aware cleanup. PO-03/04/07 must provide usable world/map policies and workload before implementation acceptance.
