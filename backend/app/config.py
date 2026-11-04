"""Transport limits and sandbox geometry; these are not MMORPG balance rules."""

import os
from dataclasses import dataclass


@dataclass(frozen=True)
class Settings:
    allowed_origins: tuple[str, ...] = ("http://localhost:3000", "http://127.0.0.1:3000")
    max_connections: int = 32
    max_message_bytes: int = 2048
    messages_per_second: int = 60
    send_timeout: float = 2.0
    tick_hz: int = 20
    input_lease_seconds: float = 0.3
    # Pixel-only disposable test scene, never persisted or used for game progression.
    world_width: int = 1600
    world_height: int = 1000
    demo_speed: float = 160.0

    @classmethod
    def from_environment(cls) -> "Settings":
        origins = os.getenv("TU_ALLOWED_ORIGINS")
        if origins is None:
            return cls()
        values = tuple(value.strip() for value in origins.split(",") if value.strip())
        if not values or any(
            value == "*" or not value.startswith(("http://", "https://")) for value in values
        ):
            raise ValueError("TU_ALLOWED_ORIGINS requires explicit HTTP(S) origins")
        return cls(allowed_origins=values)
