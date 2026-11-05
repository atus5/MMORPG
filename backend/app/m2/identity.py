"""Server fixtures and opaque capabilities; no real authentication or persistence."""

import secrets
from dataclasses import dataclass
from typing import NewType
from uuid import NAMESPACE_URL, uuid5

AccountId = NewType("AccountId", str)
PlayerId = NewType("PlayerId", str)
CharacterId = NewType("CharacterId", str)
COOKIE_NAME = "tt_m2_fixture"


@dataclass(frozen=True)
class Principal:
    account_id: AccountId
    player_id: PlayerId
    character_id: CharacterId
    label: str
    spawn: tuple[float, float]


class TestStaticIdentityProvider:
    __test__ = False

    def __init__(self, environment: str) -> None:
        if environment not in {"local", "test"}:
            raise ValueError("Test identities are unavailable outside explicit local/test mode")
        self.fixtures = tuple(
            Principal(
                AccountId(str(uuid5(NAMESPACE_URL, f"tu:local:account:{n}"))),
                PlayerId(str(uuid5(NAMESPACE_URL, f"tu:local:player:{n}"))),
                CharacterId(str(uuid5(NAMESPACE_URL, f"tu:local:character:{n}"))),
                f"Test {n}",
                spawn,
            )
            for n, spawn in enumerate(((760.0, 500.0), (840.0, 500.0)), 1)
        )
        self._handles: dict[str, Principal] = {}

    def resolve(self, handle: str | None) -> Principal | None:
        return self._handles.get(handle) if handle else None

    def issue(self, existing_handle: str | None) -> tuple[str, Principal] | None:
        principal = self.resolve(existing_handle)
        if principal is not None:
            return str(existing_handle), principal
        assigned = {p.character_id for p in self._handles.values()}
        for fixture in self.fixtures:
            if fixture.character_id not in assigned:
                handle = secrets.token_urlsafe(32)
                self._handles[handle] = fixture
                return handle, fixture
        return None
