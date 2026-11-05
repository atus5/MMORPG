# ADR-0001 — distinct identities and interface-based admission

Status: **PROPOSED**. Date: 2026-11-04. Owner scope decision: M2 designs identity interfaces; no real Auth integration. See [architecture](../M2_ARCHITECTURE.md), PO-01/02/08.

## Context

M1's socket-local demonstration entity cannot become an account, persistent avatar or verified user. Browser-supplied IDs do not establish ownership. An account must support multiple characters without inventing a quota. Providers, login UX and production trust remain outside M2.

## Proposed decision

Separate opaque typed identifiers, even when their storage representation is UUID:

- Account ID identifies the application account. A future provider link uses `(provider, issuer, subject)` and cannot silently equate a provider subject with an application account.
- Player ID identifies a stable game-domain profile. Proposed one-to-one account/profile relationship is a technical recommendation for review, not a character limit. It persists across sockets, selected characters and worlds.
- Character ID identifies one persistent avatar owned through that profile. Account → Player → Character is the authorization chain; an account can own many characters. No hardcoded count, implicit unlimited creation, or unique `character.player_id` constraint.
- Session/connection IDs and public runtime entity IDs serve separate purposes. Reconnect rotates transport/control generations, not domain IDs. Public replication excludes Account ID/provider subjects and private profile fields.

`IdentityProvider.resolve(context)` returns either a trusted principal with validity/revocation metadata or a typed failure. Admission receives that server-produced context, never a client-selected identity adapter. Authorization checks the ownership chain from storage on selection and recovery. Absent character-creation policy returns `POLICY_NOT_READY`; a later approved quota is transactional configurable policy, not a magic constant.

M2 can eventually exercise this contract with an explicitly selected local/test adapter on loopback in a non-production harness. It is not a real Auth implementation. A browser cannot enable test mode or choose an arbitrary account via a production request. An absent real provider means public real-user admission is unavailable. Tests must distinguish fake principal/authorization coverage from unimplemented signature/provider verification. No Supabase Auth calls, OAuth setup or production credentials are authorized by this ADR.

### Test composition and principal fixtures — NR-M2-002

Only the server composition root selects the identity adapter at process/test-harness startup from trusted environment configuration. Reject contradictory or production/test configuration before serving requests. No header, query, cookie, message field, fixture handle or failed provider lookup may switch adapters. Loopback alone is not authorization to use a fake identity; production composition has no local/test fallback.

The harness creates principal fixtures server-side, including their Account/Player ownership graph, validity interval, revocation/version state and account status. A direct unit test passes this trusted context internally. If browser tests need identity selection, the non-production harness may issue an opaque fixture handle scoped to that isolated run and fixture; resolve it through a server-owned registry, not an arbitrary account ID supplied by the browser. Unknown, expired, cross-run or revoked handles fail closed. A handle cannot manufacture or modify a principal or activate the harness. Test target, fixture lifetime/isolation/cleanup and persistence adapter remain **Product Owner Decision Pending**. In-memory fixture success is not PostgreSQL concurrency or real Auth coverage.

For a future approved Auth integration, require supported verification of signature, issuer, audience, algorithms, expiry and key rotation before constructing the principal. Provider binding/account linking and revocation semantics need their own approval. [Supabase JWT documentation](https://supabase.com/docs/guides/auth/jwts).

## Admission boundary

Propose an opaque, short-lived, one-use ticket bound to principal, selected character, origin, protocol version and expiry. Return the ticket over an approved session channel; authenticate WSS with its first bounded message. Do not put tickets/tokens in URLs, logs or Redis key names. Ticket cache keys use a digest; consumers validate expiry independently of cache existence. The M2 variant is a local test adapter flow, not an implemented public login endpoint.

Atomic Redis consumption alone cannot prevent a resurrected ticket after cache restore. Record a unique ticket redemption in the same PostgreSQL transaction that validates the partition lease and issues a control grant. Grant and cleanup include `(character_id, session_id, control_generation, membership_id, membership_version, world/map/partition, owner_epoch)`.

### Redemption revalidation — NR-M2-006

Issuing a ticket does not preserve authorization until redemption. Immediately before the short database transaction, resolve the principal's current validity/revocation context through the configured interface, with no external RPC inside the transaction. Under the [ADR-0004 lock matrix](0004-postgres-durability-and-fencing.md#operation-level-lock-matrix--nr-m2-005), re-read and validate Account → Player → Character, enabled account/status, ownership, applicable policy, principal-to-account binding, principal deadline and locally authoritative validity/revocation version. A provider response alone cannot give atomic consistency with a concurrent revocation; an approved version/freshness and revocation-bound contract is required. If it cannot be established, admission remains unavailable. Real provider integration is still excluded from M2.

Revalidate ticket expiry/origin/protocol/character and the canonical membership identity/version, full placement, owner lease/epoch and current control generation after acquiring locks. A placement/control change since issue invalidates the old binding; do not silently reinterpret it for a new world or session. First placement must use the atomic first-spawn contract in [ADR-0002](0002-shared-world-authority.md#first-spawn-transaction--nr-m2-003); an absent placement is never permission to pick a default world. Multi-tab reject/replace policy remains pending.

Only a transaction committing the durable unique ticket ID, matching request digest, resulting control grant and operation result permits welcome. A uniqueness conflict returns the same committed operation result for an authorized retry, or a replay/conflict denial; it cannot mint another generation. If the commit outcome is uncertain, do not welcome or issue a replacement grant: query the durable redemption/result after recovery and recheck authorization before returning anything. An absent row is not proof of abort while an earlier transaction may still commit. Resolve/serialize that transaction or use the same unique operation identity until its outcome is definitive. A new ticket requires fresh authorization and the approved conflict policy after resolution; Redis cache state cannot settle the outcome.

Before trust is established: exact allowed Origin, handshake timeout, bounded frame size, connection count and per-origin/IP admission budgets; no protected state. Origin is not authentication. Use HTTPS/WSS outside local tests, and never treat an Origin header as proof of a user's identity. [OWASP WebSocket guidance](https://cheatsheetseries.owasp.org/cheatsheets/WebSocket_Security_Cheat_Sheet.html).

## Alternatives and consequences

Rejected: socket UUID as Player ID; arbitrary client Account ID; provider subject reused for every domain ID; one-character uniqueness; real Auth implementation hidden inside M2; copying Desktop AI credentials. They confuse lifecycle/trust or violate Owner scope.

A game-profile layer adds an ownership join but avoids coupling avatars and sessions to provider identity. One-profile-per-account semantics remain reviewable. Single current control is a safety invariant; whether a second tab is rejected or explicitly replaces the first is **Product Owner Decision Pending**, not selected by this ADR.

## Validation and approval dependencies

Future tests: ID type confusion, cross-account selection, absent/expired/revoked principal, unavailable policy, configured creation races, ticket replay/concurrent redemption, restored Redis ticket and delayed old cleanup. No fake-principal test may be reported as real JWT/Auth coverage.

Additional specifications: request-driven adapter switching fails; opaque handles cannot cross harness runs; account disablement, ownership/membership change and fixture revocation between ticket issue and redemption deny stale authorization; simultaneous redemption and uncertain commit produce one durable result. These are future test specifications, not executions in this documentation revision.

PO-02/08 must settle quotas/naming, multi-tab conflict, validity/revocation and admission budgets. Login/provider integration remains deferred beyond M2. No numeric TTL/rate default is supplied here.
