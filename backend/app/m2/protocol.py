"""Protocol 2 uses the existing cardinal intent vocabulary, never client positions."""

from typing import Annotated, Literal

from pydantic import Field, TypeAdapter

from app.protocol import Direction, Message, Player


class Input(Message):
    type: Literal["input"]
    seq: int = Field(ge=1, le=2_147_483_647)
    direction: Direction
    generation: int = Field(ge=1)


class Ping(Message):
    type: Literal["ping"]
    seq: int = Field(ge=1, le=2_147_483_647)


client_message = TypeAdapter(Annotated[Input | Ping, Field(discriminator="type")])
Reason = Literal["stale_input", "admission_timeout", "queue_overflow", "timeline_uncertain"]


class PublicPlayer(Player):
    id: str
    label: str


class WorldInfo(Message):
    id: Literal["development"] = "development"
    partition: Literal["single"] = "single"
    width: int = 1600
    height: int = 1000


class Frame(Message):
    boot_id: str
    self_id: str
    generation: int
    tick: int
    stream_seq: int
    ack_received: int
    ack_applied: int
    release_required: bool
    player: Player
    players: list[PublicPlayer]


class Welcome(Frame):
    type: Literal["welcome"] = "welcome"
    protocol: Literal[2] = 2
    connection_id: str
    world: WorldInfo
    tick_hz: int


class State(Frame):
    type: Literal["state", "resync"] = "state"
    reason: Reason | None = None
