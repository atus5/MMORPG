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

For a future approved Auth integration, require supported verification of signature, issuer, audience, algorithms, expiry and key rotation before constructing the principal. Provider binding/account linking and revocation semantics need their own approval. [Supabase JWT documentation](https://supabase.com/docs/guides/auth/jwts).

## Admission boundary

Propose an opaque, short-lived, one-use ticket bound to principal, selected character, origin, protocol version and expiry. Return the ticket over an approved session channel; authenticate WSS with its first bounded message. Do not put tickets/tokens in URLs, logs or Redis key names. Ticket cache keys use a digest; consumers validate expiry independently of cache existence. The M2 variant is a local test adapter flow, not an implemented public login endpoint.

Atomic Redis consumption alone cannot prevent a resurrected ticket after cache restore. Record a unique ticket redemption in the same PostgreSQL transaction that validates the partition lease and issues a control grant. A failed/uncertain redemption must be resolved from committed operation state or a newly authorized ticket; never trust a stale cache hit. Grant and cleanup include `(character_id, session_id, control_generation, world/map/partition, owner_epoch)`.

Before trust is established: exact allowed Origin, handshake timeout, bounded frame size, connection count and per-origin/IP admission budgets; no protected state. Origin is not authentication. Use HTTPS/WSS outside local tests, and never treat an Origin header as proof of a user's identity. [OWASP WebSocket guidance](https://cheatsheetseries.owasp.org/cheatsheets/WebSocket_Security_Cheat_Sheet.html).

## Alternatives and consequences

Rejected: socket UUID as Player ID; arbitrary client Account ID; provider subject reused for every domain ID; one-character uniqueness; real Auth implementation hidden inside M2; copying Desktop AI credentials. They confuse lifecycle/trust or violate Owner scope.

A game-profile layer adds an ownership join but avoids coupling avatars and sessions to provider identity. One-profile-per-account semantics remain reviewable. Single current control is a safety invariant; whether a second tab is rejected or explicitly replaces the first is **Product Owner Decision Pending**, not selected by this ADR.

## Validation and approval dependencies

Future tests: ID type confusion, cross-account selection, absent/expired/revoked principal, unavailable policy, configured creation races, ticket replay/concurrent redemption, restored Redis ticket and delayed old cleanup. No fake-principal test may be reported as real JWT/Auth coverage.

PO-02/08 must settle quotas/naming, multi-tab conflict, validity/revocation and admission budgets. Login/provider integration remains deferred beyond M2. No numeric TTL/rate default is supplied here.
