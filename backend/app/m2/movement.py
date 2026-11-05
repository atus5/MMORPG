"""Ordered server-time segments; expiry never extends an effective input lease."""

from collections import deque
from dataclasses import dataclass

from app.config import Settings
from app.protocol import Direction


@dataclass(frozen=True)
class Edge:
    at: float
    seq: int
    direction: Direction
    deadline: float | None


class Movement:
    def __init__(self, settings: Settings, spawn: tuple[float, float]) -> None:
        self.settings = settings
        self.x, self.y = spawn
        self.events: deque[Edge] = deque()
        self.direction: Direction = "idle"
        self.deadline: float | None = None
        self.projected_direction: Direction = "idle"
        self.projected_deadline: float | None = None
        self.release_required = False
        self.ack_received = 0
        self.ack_applied = 0

    def needs_release(self, now: float) -> bool:
        if self.projected_deadline is not None and now >= self.projected_deadline:
            self.projected_direction = "idle"
            self.projected_deadline = None
            self.release_required = True
        return self.release_required

    def reset_control(self, *, require_release: bool) -> None:
        self.events.clear()
        self.direction = self.projected_direction = "idle"
        self.deadline = self.projected_deadline = None
        self.release_required = require_release
        self.ack_received = self.ack_applied = 0

    def admit(self, direction: Direction, seq: int, now: float) -> bool:
        self.needs_release(now)
        if direction != "idle" and self.release_required:
            return False
        if direction == "idle":
            self.release_required = False
        self.projected_direction = direction
        self.projected_deadline = None if direction == "idle" else now + self.settings.input_lease_seconds
        self.events.append(Edge(now, seq, direction, self.projected_deadline))
        self.ack_received = seq
        return True

    def _segment(self, start: float, end: float) -> None:
        stop = min(end, self.deadline) if self.deadline is not None else start
        duration = max(0.0, stop - start)
        dx, dy = {
            "up": (0, -1),
            "down": (0, 1),
            "left": (-1, 0),
            "right": (1, 0),
            "idle": (0, 0),
        }[self.direction]
        self.x = max(
            0.0, min(float(self.settings.world_width), self.x + dx * duration * self.settings.demo_speed)
        )
        self.y = max(
            0.0, min(float(self.settings.world_height), self.y + dy * duration * self.settings.demo_speed)
        )
        if self.deadline is not None and end >= self.deadline:
            self.direction, self.deadline = "idle", None

    def integrate(self, start: float, end: float) -> None:
        cursor = start
        while self.events and self.events[0].at < end:
            edge = self.events.popleft()
            if edge.at < cursor:
                raise ValueError("An event cannot reopen an integrated interval")
            self._segment(cursor, edge.at)
            self.direction, self.deadline = edge.direction, edge.deadline
            self.ack_applied = edge.seq
            cursor = edge.at
        self._segment(cursor, end)
