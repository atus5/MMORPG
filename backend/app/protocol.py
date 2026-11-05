"""Strict protocol v1. Clients cannot submit positions, speed or gameplay stats."""

from typing import Annotated, Literal

from pydantic import BaseModel, ConfigDict, Field, TypeAdapter

PROTOCOL_VERSION = 1
Direction = Literal["up", "down", "left", "right", "idle"]


class Message(BaseModel):
    model_config = ConfigDict(strict=True, extra="forbid", allow_inf_nan=False)


class InputMessage(Message):
    type: Literal["input"]
    seq: int = Field(ge=1, le=2_147_483_647)
    direction: Direction


class PingMessage(Message):
    type: Literal["ping"]
    seq: int = Field(ge=1, le=2_147_483_647)


client_message = TypeAdapter(Annotated[InputMessage | PingMessage, Field(discriminator="type")])


class Player(Message):
    x: float = Field(ge=0)
    y: float = Field(ge=0)


class World(Message):
    width: int = Field(gt=0)
    height: int = Field(gt=0)


class WelcomeMessage(Message):
    type: Literal["welcome"] = "welcome"
    protocol: Literal[1] = PROTOCOL_VERSION
    connection_id: str
    world: World
    player: Player
    tick_hz: int


class StateMessage(Message):
    type: Literal["state"] = "state"
    tick: int
    ack: int
    player: Player


class PongMessage(Message):
    type: Literal["pong"] = "pong"
    seq: int


class ErrorMessage(Message):
    type: Literal["error"] = "error"
    code: Literal["invalid_message", "stale_sequence"]
