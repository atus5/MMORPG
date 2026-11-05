import asyncio
import logging
from dataclasses import dataclass, field
from uuid import uuid4

from fastapi import WebSocket, WebSocketDisconnect
from starlette.websockets import WebSocketState

from app.config import Settings
from app.protocol import Direction, Message, Player, StateMessage, WelcomeMessage, World


@dataclass
class Session:
    socket: WebSocket
    settings: Settings
    connected_at: float
    id: str = field(default_factory=lambda: str(uuid4()))
    seq: int = 0
    tick: int = 0
    direction: Direction = "idle"
    input_at: float = 0.0
    send_lock: asyncio.Lock = field(default_factory=asyncio.Lock)
    x: float = field(init=False)
    y: float = field(init=False)
    last_step: float = field(init=False)
    _close_started: bool = field(default=False, init=False, repr=False)

    def __post_init__(self) -> None:
        self.x = self.settings.world_width / 2
        self.y = self.settings.world_height / 2
        self.last_step = self.connected_at

    def welcome(self) -> WelcomeMessage:
        return WelcomeMessage(
            connection_id=self.id,
            world=World(width=self.settings.world_width, height=self.settings.world_height),
            player=Player(x=self.x, y=self.y),
            tick_hz=self.settings.tick_hz,
        )

    def advance(self, now: float) -> StateMessage:
        # Server monotonic time, not frame rate, message count, or a client timestamp.
        elapsed = max(0.0, min(now - self.last_step, 2 / self.settings.tick_hz))
        self.last_step = now
        direction = self.direction if now - self.input_at <= self.settings.input_lease_seconds else "idle"
        dx, dy = {"up": (0, -1), "down": (0, 1), "left": (-1, 0), "right": (1, 0), "idle": (0, 0)}[direction]
        distance = self.settings.demo_speed * elapsed
        self.x = max(0.0, min(float(self.settings.world_width), self.x + dx * distance))
        self.y = max(0.0, min(float(self.settings.world_height), self.y + dy * distance))
        self.tick += 1
        return StateMessage(tick=self.tick, ack=self.seq, player=Player(x=self.x, y=self.y))

    async def send(self, message: Message) -> None:
        async with self.send_lock:
            if (
                self._close_started
                or self.socket.application_state != WebSocketState.CONNECTED
                or self.socket.client_state != WebSocketState.CONNECTED
            ):
                raise WebSocketDisconnect(code=1000)
            await asyncio.wait_for(self.socket.send_json(message.model_dump()), self.settings.send_timeout)

    async def close(self, code: int = 1000, reason: str = "") -> None:
        async with self.send_lock:
            if self._close_started:
                return
            # A failed close must not be retried by concurrent/repeated cleanup callers.
            self._close_started = True
            if (
                self.socket.application_state == WebSocketState.CONNECTED
                and self.socket.client_state == WebSocketState.CONNECTED
            ):
                await asyncio.wait_for(
                    self.socket.close(code=code, reason=reason), self.settings.send_timeout
                )


class ConnectionManager:
    """One event loop, one process, ephemeral isolated sessions; not a shared world."""

    def __init__(self, settings: Settings) -> None:
        self.settings = settings
        self.sessions: dict[str, Session] = {}

    @property
    def active_count(self) -> int:
        return len(self.sessions)

    def register(self, socket: WebSocket) -> Session | None:
        if self.active_count >= self.settings.max_connections:
            return None
        session = Session(socket, self.settings, asyncio.get_running_loop().time())
        self.sessions[session.id] = session
        return session

    def remove(self, session: Session) -> None:
        self.sessions.pop(session.id, None)

    async def disconnect(self, session: Session) -> None:
        # Release ownership before transport cleanup, even if close fails or is cancelled.
        self.remove(session)
        try:
            await session.close()
        except (WebSocketDisconnect, OSError, asyncio.TimeoutError, RuntimeError):
            logging.getLogger("tu.websocket").info("cleanup transport closed session=%s", session.id)
