import asyncio
import json
from dataclasses import replace

import pytest
from starlette.websockets import WebSocketState

from app.config import Settings
from app.connections import Session
from app.m2.identity import TestStaticIdentityProvider
from app.m2.movement import Movement
from app.m2.routes import receive_inputs
from app.m2.world import World


class Clock:
    now = 0.0

    def __call__(self):
        return self.now


class Socket:
    application_state = client_state = WebSocketState.CONNECTED

    def __init__(self):
        self.incoming = asyncio.Queue()

    async def receive(self):
        return await self.incoming.get()

    async def close(self, **kwargs):
        self.application_state = self.client_state = WebSocketState.DISCONNECTED


def setup(**changes):
    clock, socket = Clock(), Socket()
    settings = replace(Settings(m2_enabled=True, app_environment="test"), **changes)
    identity = TestStaticIdentityProvider("test")
    world = World(settings, identity, clock)
    binding = world.attach(identity.fixtures[0], Session(socket, settings, 0.0))
    assert binding
    return clock, socket, world, binding


def wire(binding, seq, direction="right", **extra):
    return json.dumps(
        {"type": "input", "seq": seq, "direction": direction, "generation": binding.generation, **extra}
    )


async def feed(socket, raw):
    socket.incoming.put_nowait({"type": "websocket.receive", "text": raw})
    await asyncio.sleep(0)


def test_real_receive_path_admits_between_ticks_without_injected_admission_timestamps():
    async def run():
        clock, socket, world, binding = setup()
        receiver = asyncio.create_task(receive_inputs(binding, world))
        tick_ready = asyncio.Event()

        async def independent_tick():
            await tick_ready.wait()
            world.advance(clock())

        ticker = asyncio.create_task(independent_tick())
        try:
            clock.now = 0.01
            await feed(socket, wire(binding, 1))
            assert len(binding.member.movement.events) == 1
            clock.now = 0.04
            await feed(socket, wire(binding, 2, "idle"))
            assert len(binding.member.movement.events) == 2
            assert world.tick == 0  # An implementation admitting only at closure fails here.
            clock.now = 0.05
            tick_ready.set()
            await ticker
            assert binding.member.movement.x == pytest.approx(764.8)
            assert binding.member.movement.ack_received == binding.member.movement.ack_applied == 2
            assert world.metrics()["input_admission_latency_seconds"]["count"] == 2
        finally:
            receiver.cancel()
            await asyncio.gather(receiver, return_exceptions=True)

    asyncio.run(run())


@pytest.mark.parametrize(
    "received,admitted,expected",
    [
        (0.01, 0.06, "admission_timeout"),
        (0.049, 0.051, "stale_input"),
    ],
)
def test_receive_before_closed_tick_delayed_admission_resyncs(received, admitted, expected):
    async def run():
        clock, socket, world, binding = setup()
        original, gate = world.admit_raw, asyncio.Event()

        async def delayed(*args):
            await gate.wait()
            await original(*args)

        world.admit_raw = delayed
        receiver = asyncio.create_task(receive_inputs(binding, world))
        try:
            clock.now = received
            await feed(socket, wire(binding, 1))
            assert binding.pending_count == 1
            clock.now = 0.05
            world.advance(clock())  # Separate tick continues while admission is delayed.
            clock.now = admitted
            assert world.metrics()["oldest_pending_admission_age_seconds"] == pytest.approx(
                admitted - received
            )
            gate.set()
            await asyncio.sleep(0)
            assert binding.member.movement.x == 760
            frames = []
            while not binding.outgoing.empty():
                frames.append(binding.outgoing.get_nowait())
            assert any(getattr(f, "reason", None) == expected for f in frames)
            assert binding.member.movement.release_required
            assert binding.pending_count == 0
        finally:
            receiver.cancel()
            await asyncio.gather(receiver, return_exceptions=True)

    asyncio.run(run())


def test_right_boundary_applies_to_next_interval_and_expiry_requires_release_press():
    async def run():
        clock, socket, world, binding = setup()
        receiver = asyncio.create_task(receive_inputs(binding, world))
        try:
            clock.now = 0.05
            await feed(socket, wire(binding, 1))
            world.advance(clock())
            assert binding.member.movement.x == 760
            for n in range(2, 9):
                clock.now = n / 20
                if n == 4:
                    await feed(socket, json.dumps({"type": "ping", "seq": 2}))
                world.advance(clock())
            assert binding.member.movement.x == pytest.approx(808)  # Exactly 300ms; no expiry clamping.
            assert binding.member.movement.release_required
            await feed(socket, wire(binding, 3))
            assert not binding.member.movement.events
            clock.now = 0.41
            await feed(socket, wire(binding, 4, "idle"))
            clock.now = 0.42
            await feed(socket, wire(binding, 5))
            clock.now = 0.45
            world.advance(clock())
            assert binding.member.movement.x == pytest.approx(812.8)
        finally:
            receiver.cancel()
            await asyncio.gather(receiver, return_exceptions=True)

    asyncio.run(run())


def test_stale_generation_sequence_overflow_and_long_pause_cannot_grant_travel():
    async def run():
        clock, _, world, binding = setup(input_queue_limit=2)
        clock.now = 0.01
        await world.admit_raw(binding, wire(binding, 1), clock())
        await world.admit_raw(binding, wire(binding, 2, "left"), clock())
        await world.admit_raw(binding, wire(binding, 3), clock())
        assert world.resync_count == 1
        assert binding.member.movement.x == 760 and not binding.member.movement.events
        old_generation = binding.generation
        await world.admit_raw(binding, wire(binding, 4, generation=old_generation - 1), clock())
        await world.admit_raw(binding, wire(binding, 4), clock())
        assert world.resync_count == 3
        clock.now = 1.0
        world.advance(clock())
        assert binding.member.movement.x == 760
        assert binding.member.movement.release_required

    asyncio.run(run())


def test_old_cleanup_cannot_remove_new_binding_and_outbound_state_coalesces():
    async def run():
        _, socket, world, old = setup()
        world.detach(old)
        current = world.attach(old.member.principal, Session(socket, world.settings, 0.0))
        assert current
        world.detach(old)
        assert world.current(current)
        for _ in range(100):
            world.publish()
        assert current.outgoing.qsize() <= 8
        assert current.outgoing.get_nowait().type == "welcome"
        for _ in range(10):
            world.resync(current, "stale_input")
        assert not world.current(current)  # Control frames are never silently coalesced away.

    asyncio.run(run())


@pytest.mark.parametrize(
    "direction,expected",
    [
        ("right", (768.0, 500.0)),
        ("left", (752.0, 500.0)),
        ("down", (760.0, 508.0)),
        ("up", (760.0, 492.0)),
    ],
)
def test_approved_speed_integrates_four_directions_through_receive_path(direction, expected):
    async def run():
        clock, socket, world, binding = setup()
        assert world.settings.demo_speed == 160.0
        receiver = asyncio.create_task(receive_inputs(binding, world))
        try:
            await feed(socket, wire(binding, 1, direction))
            clock.now = 0.05
            world.advance(clock())  # Real Movement.integrate over the first closed 50ms interval.
            movement = binding.member.movement
            assert (movement.x, movement.y) == pytest.approx(expected)
            assert movement.ack_applied == 1
        finally:
            receiver.cancel()
            await asyncio.gather(receiver, return_exceptions=True)

    asyncio.run(run())


@pytest.mark.parametrize("admitted_at,end", [(0.0, 0.3), (0.025, 0.325), (0.025, 0.35)])
def test_approved_lease_integrates_deadline_and_requires_release(admitted_at, end):
    settings = Settings(m2_enabled=True, app_environment="test")
    assert settings.demo_speed == 160.0
    assert settings.input_lease_seconds == 0.3
    clock = Clock()
    movement = Movement(settings, (760.0, 500.0))
    clock.now = admitted_at
    assert movement.admit("right", 1, clock())
    deadline = admitted_at + settings.input_lease_seconds
    assert movement.projected_deadline == deadline

    # Test the actual integrator at and across expiry, including a deadline inside a tick.
    clock.now = end
    movement.integrate(0.0, clock())
    assert (movement.x, movement.y) == pytest.approx((808.0, 500.0))  # 160 * 0.300 = 48px.
    assert movement.needs_release(clock())
    clock.now = end + 0.05
    movement.integrate(end, clock())
    assert (movement.x, movement.y) == pytest.approx((808.0, 500.0))
    assert not movement.admit("right", 2, clock())  # A held input cannot revive the expired lease.
    cursor = clock()
    clock.now = end + 0.1
    movement.integrate(cursor, clock())
    assert (movement.x, movement.y) == pytest.approx((808.0, 500.0))
    assert movement.needs_release(clock())

    # Only an explicit release and fresh press can grant a new interval of travel.
    assert movement.admit("idle", 3, clock())
    assert not movement.needs_release(clock())
    cursor = clock()
    clock.now = end + 0.125
    assert movement.admit("right", 4, clock())
    clock.now = end + 0.175
    movement.integrate(cursor, clock())
    assert (movement.x, movement.y) == pytest.approx((816.0, 500.0))  # New press: another 8px/50ms.
    assert movement.ack_applied == 4
