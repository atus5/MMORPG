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
    # Explicitly approved local/test Vertical Slice settings; not production defaults.
    m2_enabled: bool = False
    app_environment: str = "unspecified"
    admission_budget_seconds: float = 0.025
    pending_input_limit: int = 64
    input_queue_limit: int = 64
    outbound_queue_limit: int = 8
    catchup_tick_limit: int = 2

    def __post_init__(self) -> None:
        if self.m2_enabled and self.app_environment not in {"local", "test"}:
            raise ValueError("TestStaticIdentityProvider requires explicit local/test configuration")
        if self.m2_enabled and (
            self.tick_hz <= 0
            or self.input_lease_seconds <= 0
            or self.admission_budget_seconds <= 0
            or min(self.pending_input_limit, self.input_queue_limit, self.outbound_queue_limit) <= 0
            or self.catchup_tick_limit <= 0
        ):
            raise ValueError("Invalid local Vertical Slice bounds")

    @classmethod
    def from_environment(cls) -> "Settings":
        origins = os.getenv("TU_ALLOWED_ORIGINS")
        enabled = os.getenv("TU_M2_VERTICAL_SLICE", "0")
        if enabled not in {"0", "1"}:
            raise ValueError("TU_M2_VERTICAL_SLICE must be 0 or 1")
        defaults = cls()
        values = (
            defaults.allowed_origins
            if origins is None
            else tuple(value.strip() for value in origins.split(",") if value.strip())
        )
        if not values or any(
            value == "*" or not value.startswith(("http://", "https://")) for value in values
        ):
            raise ValueError("TU_ALLOWED_ORIGINS requires explicit HTTP(S) origins")
        return cls(
            allowed_origins=values,
            m2_enabled=enabled == "1",
            app_environment=os.getenv("TU_APP_ENV", "unspecified"),
        )
