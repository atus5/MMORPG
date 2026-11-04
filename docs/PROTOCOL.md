# Local WebSocket protocol v1

Endpoint `/ws`, UTF-8 text JSON, one object per frame. Local, unauthenticated scaffold: loopback only, one worker, no database, keys or persistent identity.

## Messages and ownership

Client sends only:

```json
{"type":"input","seq":1,"direction":"right"}
{"type":"ping","seq":2}
```

Direction: `up`, `down`, `left`, `right`, `idle`. Sequence is a strict integer 1..2147483647, increasing across both message types per connection. Extra fields, coerced strings/bools/floats, client coordinates/speed/timestamps/stats are forbidden. Invalid messages do not advance seq. Reconnect starts a new session and sequence; no input retry/replay.

Server messages (shape examples, not an exact timing trace):

```json
{"type":"welcome","protocol":1,"connection_id":"00000000-0000-4000-8000-000000000000","world":{"width":1600,"height":1000},"player":{"x":800.0,"y":500.0},"tick_hz":20}
{"type":"state","tick":1,"ack":1,"player":{"x":808.0,"y":500.0}}
{"type":"pong","seq":2}
{"type":"error","code":"invalid_message"}
{"type":"error","code":"stale_sequence"}
```

`ack` is latest accepted seq, including ping. Tick increases per session. Server monotonic elapsed time determines movement; client time/message count cannot add distance. Integration caps a stall at two ticks. Inputs expire after 0.3s without renewal; browser renews held direction every 100ms. Only server coordinates move the rendered character; camera smoothing is visual.

The 1600×1000 map, 160px/s speed and 20Hz state rate are disposable **technical demo settings**, not approved MMO balance or progression rules. No other gameplay values are defaulted.

## Lifecycle/security

- Explicit browser origin allowlist checked before accept. Missing/unapproved Origin denied. Origin checks are not authentication: non-browser clients can spoof headers.
- Max 32 ephemeral isolated sessions; capacity rejection 1013. One process/event loop; no shared-world replication.
- Max 2048 UTF-8 message bytes in app; recommended Uvicorn transport limit 4096. Oversize closes 1009, binary 1003.
- Max 60 received messages per server one-second window, including invalid messages; excess closes 1008. Basic local limit, not distributed anti-abuse.
- Pydantic strict validation; errors/logs never echo raw inputs or validation details. Lifecycle logs use server-generated session IDs.
- Serialized timeout-bounded sends. Paired receive/publish tasks are cancelled/awaited and session removed on disconnect. Restart discards all sessions.
- Frontend Zod validation checks version, finite positions/world bounds, acknowledgement and monotonic ticks. A five-second handshake/response watchdog closes a stalled socket. Manual reconnect creates a fresh session.
- Blur/visibility loss releases keys/sends idle; server input lease handles a lost key-up. Movement keys apply only while the canvas region is focused.

## Verification and future work

Backend tests cover handshake/ping, validation, origin, capacity/rate/size/binary rejection, cleanup/reconnect and server-clock authority. Frontend unit tests cover protocol, stale callbacks, timeout and authority. Browser tests use real Next.js/Uvicorn servers.

Later milestones require Owner-confirmed gameplay rules, verified Auth identity, persistence/RLS separately, shared simulation, TLS and production admission/observability. Nothing here authorizes deployment or Supabase access.

Primary references checked for M1: [Next.js lazy loading](https://nextjs.org/docs/app/guides/lazy-loading), [FastAPI WebSockets](https://fastapi.tiangolo.com/advanced/websockets/), [WebSocket tests](https://fastapi.tiangolo.com/advanced/testing-websockets/), [Pydantic strict mode](https://docs.pydantic.dev/latest/concepts/strict_mode/), [Phaser scale manager](https://docs.phaser.io/phaser/concepts/scale-manager).
