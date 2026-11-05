"""One serialized owner/event loop; canonical placement and state exist only in RAM."""

from __future__ import annotations

import asyncio
import math
import time
from collections import deque
from collections.abc import Callable
from dataclasses import dataclass, field
from uuid import uuid4

from pydantic import ValidationError

from app.config import Settings
from app.connections import Session
from app.m2.identity import Principal, TestStaticIdentityProvider
from app.m2.movement import Movement
from app.m2.protocol import Input, Reason, State, Welcome, WorldInfo, client_message
from app.protocol import ErrorMessage, Message, Player, PongMessage


@dataclass
class Member:
    principal: Principal
    movement: Movement
    id: str = field(default_factory=lambda: str(uuid4()))
    generation: int = 0
    binding: Binding | None = None


@dataclass
class Binding:
    member: Member
    transport: Session
    generation: int
    outgoing: asyncio.Queue[Message]
    last_seq: int = 0
    closing: bool = False
    pending_count: int = 0
    pending_since: float | None = None


class World:
    def __init__(
        self,
        settings: Settings,
        identity: TestStaticIdentityProvider,
        clock: Callable[[], float] = time.perf_counter,
    ) -> None:
        if not settings.m2_enabled:
            raise ValueError("Vertical Slice was not selected in the composition root")
        self.settings, self.identity, self.clock = settings, identity, clock
        self.boot_id = str(uuid4())
        self.members = {p.character_id: Member(p, Movement(settings, p.spawn)) for p in identity.fixtures}
        self.tick = self.stream_seq = 0
        self.origin = self.closed_at = clock()
        self.task: asyncio.Task[None] | None = None
        self.latencies: deque[float] = deque(maxlen=settings.input_queue_limit)
        self.admitted_count = self.rejected_count = self.budget_exceeded_count = 0
        self.resync_count = 0
        self.max_latency = 0.0
        self.event_loop_lag_seconds = 0.0

    @property
    def bindings(self) -> list[Binding]:
        return [m.binding for m in self.members.values() if m.binding is not None and not m.binding.closing]

    def current(self, binding: Binding) -> bool:
        return binding.member.binding is binding and not binding.closing

    def attach(self, principal: Principal, transport: Session) -> Binding | None:
        member = self.members[principal.character_id]
        if member.binding is not None or len(self.bindings) >= self.settings.max_connections:
            return None
        member.generation += 1
        member.movement.reset_control(require_release=False)
        binding = Binding(
            member, transport, member.generation, asyncio.Queue(self.settings.outbound_queue_limit)
        )
        member.binding = binding
        self.stream_seq += 1
        self.enqueue(
            binding,
            Welcome(
                **self.frame(binding),
                connection_id=transport.id,
                world=WorldInfo(width=self.settings.world_width, height=self.settings.world_height),
                tick_hz=self.settings.tick_hz,
            ),
        )
        self.publish()
        return binding

    def detach(self, binding: Binding) -> None:
        binding.closing = True
        if binding.member.binding is binding:
            binding.member.binding = None
            binding.member.movement.reset_control(require_release=True)
            self.publish()

    def frame(self, binding: Binding) -> dict:
        movement = binding.member.movement
        return dict(
            boot_id=self.boot_id,
            self_id=binding.member.id,
            generation=binding.generation,
            tick=self.tick,
            stream_seq=self.stream_seq,
            ack_received=movement.ack_received,
            ack_applied=movement.ack_applied,
            release_required=movement.needs_release(self.clock()),
            player=Player(x=movement.x, y=movement.y),
            players=[
                dict(id=m.id, label=m.principal.label, x=m.movement.x, y=m.movement.y)
                for m in self.members.values()
                if m.binding is not None and not m.binding.closing
            ],
        )

    def enqueue(self, binding: Binding, message: Message) -> None:
        if not self.current(binding):
            return
        if binding.outgoing.full():
            # Every state is a full baseline, so obsolete state frames can be coalesced.
            # Welcome, resync, errors and pong are never silently discarded.
            pending = []
            while not binding.outgoing.empty():
                item = binding.outgoing.get_nowait()
                binding.outgoing.task_done()
                if not isinstance(item, State) or item.type != "state":
                    pending.append(item)
            for item in pending:
                binding.outgoing.put_nowait(item)
            if binding.outgoing.full():
                self.detach(binding)
                return
        binding.outgoing.put_nowait(message)

    def publish(self) -> None:
        self.stream_seq += 1
        for binding in self.bindings:
            self.enqueue(binding, State(**self.frame(binding)))

    def resync(self, binding: Binding, reason: Reason) -> None:
        if not self.current(binding):
            return
        self.resync_count += 1
        binding.member.generation += 1
        binding.generation = binding.member.generation
        binding.member.movement.reset_control(require_release=True)
        self.stream_seq += 1
        self.enqueue(binding, State(type="resync", reason=reason, **self.frame(binding)))

    async def admit_raw(self, binding: Binding, raw: str, received_at: float) -> None:
        """Called directly by real receive callback; no await/RPC/tick-batch in admission."""
        if not self.current(binding):
            return
        try:
            message = client_message.validate_json(raw)
        except ValidationError:
            self.rejected_count += 1
            self.enqueue(binding, ErrorMessage(code="invalid_message"))
            return
        admitted_at = self.clock()
        latency = admitted_at - received_at
        if not math.isfinite(latency) or latency < 0 or admitted_at < self.closed_at:
            self.resync(binding, "timeline_uncertain")
            return
        if latency > self.settings.admission_budget_seconds:
            self.budget_exceeded_count += 1
            self.rejected_count += 1
            self.resync(binding, "admission_timeout")
            return
        if message.seq <= binding.last_seq:
            self.rejected_count += 1
            self.resync(binding, "stale_input")
            return
        binding.last_seq = message.seq
        if isinstance(message, Input):
            if message.generation != binding.generation or received_at < self.closed_at:
                self.rejected_count += 1
                self.resync(binding, "stale_input")
                return
            movement = binding.member.movement
            if len(movement.events) >= self.settings.input_queue_limit:
                self.rejected_count += 1
                self.resync(binding, "queue_overflow")
                return
            if not movement.admit(message.direction, message.seq, admitted_at):
                self.rejected_count += 1
                self.publish()  # Expired holds remain stopped until explicit idle then fresh input.
                return
        else:
            self.enqueue(binding, PongMessage(seq=message.seq))
        self.admitted_count += 1
        self.latencies.append(latency)
        self.max_latency = max(self.max_latency, latency)

    def advance(self, now: float) -> None:
        if not math.isfinite(now) or now < self.closed_at:
            for binding in self.bindings:
                self.resync(binding, "timeline_uncertain")
            return
        target = int((now - self.origin) * self.settings.tick_hz)
        steps = target - self.tick
        if steps > self.settings.catchup_tick_limit:
            self.tick = target
            self.closed_at = now
            self.origin = now - self.tick / self.settings.tick_hz
            for binding in self.bindings:
                self.resync(binding, "timeline_uncertain")
            return
        for _ in range(max(0, steps)):
            end = self.origin + (self.tick + 1) / self.settings.tick_hz
            for binding in self.bindings:
                try:
                    binding.member.movement.integrate(self.closed_at, end)
                except ValueError:
                    self.resync(binding, "timeline_uncertain")
            self.tick += 1
            self.closed_at = end
        if steps > 0:
            self.publish()

    def metrics(self) -> dict:
        samples = sorted(self.latencies)
        pending = self.bindings
        return {
            "input_admission_latency_seconds": {
                "count": self.admitted_count,
                **{
                    f"p{percent}": samples[max(0, math.ceil(len(samples) * percent / 100) - 1)]
                    if samples
                    else 0.0
                    for percent in (50, 95, 99)
                },
                "max": self.max_latency,
                "sample_window": len(samples),
                "histogram": {
                    str(bound): sum(x <= bound for x in samples)
                    for bound in (
                        self.settings.admission_budget_seconds / 4,
                        self.settings.admission_budget_seconds / 2,
                        self.settings.admission_budget_seconds,
                    )
                },
            },
            "pending_depth": sum(b.pending_count for b in pending),
            "oldest_pending_admission_age_seconds": max(
                (self.clock() - b.pending_since for b in pending if b.pending_since is not None),
                default=0.0,
            ),
            "admission_budget_exceeded_total": self.budget_exceeded_count,
            "rejected_total": self.rejected_count,
            "resync_total": self.resync_count,
            "active_players": len(pending),
            "boot_id": self.boot_id,
            "event_loop_lag_seconds": self.event_loop_lag_seconds,
        }

    async def start(self) -> None:
        self.origin = self.closed_at = self.clock()
        self.task = asyncio.create_task(self._run())

    async def _run(self) -> None:
        while True:
            expected = self.clock() + 1 / self.settings.tick_hz
            await asyncio.sleep(1 / self.settings.tick_hz)
            now = self.clock()
            self.event_loop_lag_seconds = max(0.0, now - expected)
            self.advance(now)

    async def stop(self) -> None:
        if self.task is not None:
            self.task.cancel()
            await asyncio.gather(self.task, return_exceptions=True)
        bindings = list(self.bindings)
        for binding in bindings:
            self.detach(binding)
        await asyncio.gather(*(b.transport.close() for b in bindings), return_exceptions=True)
