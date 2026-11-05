import asyncio
import logging

from fastapi import APIRouter, WebSocket, WebSocketDisconnect
from pydantic import ValidationError

from app.connections import Session
from app.protocol import ErrorMessage, InputMessage, PongMessage, client_message

router = APIRouter()
logger = logging.getLogger("tu.websocket")


@router.get("/health")
async def health() -> dict[str, str | int]:
    return {"status": "ok", "service": "tu-tien-foundation", "protocol": 1}


async def receive_inputs(session: Session) -> None:
    loop = asyncio.get_running_loop()
    window_at, count = loop.time(), 0
    while True:
        event = await session.socket.receive()
        if event["type"] == "websocket.disconnect":
            return
        now = loop.time()
        if now - window_at >= 1:
            window_at, count = now, 0
        count += 1
        if count > session.settings.messages_per_second:
            await session.close(code=1008, reason="Message rate exceeded")
            return
        raw = event.get("text")
        if raw is None:
            await session.close(code=1003, reason="Text JSON required")
            return
        if len(raw.encode("utf-8")) > session.settings.max_message_bytes:
            await session.close(code=1009, reason="Message too large")
            return
        try:
            message = client_message.validate_json(raw)
        except ValidationError:
            # Never echo input or validation details (which may contain credentials).
            await session.send(ErrorMessage(code="invalid_message"))
            continue
        if message.seq <= session.seq:
            await session.send(ErrorMessage(code="stale_sequence"))
            continue
        session.seq = message.seq
        if isinstance(message, InputMessage):
            session.direction, session.input_at = message.direction, now
        else:
            await session.send(PongMessage(seq=message.seq))


async def publish_state(session: Session) -> None:
    loop = asyncio.get_running_loop()
    while True:
        await asyncio.sleep(1 / session.settings.tick_hz)
        await session.send(session.advance(loop.time()))


@router.websocket("/ws")
async def websocket_endpoint(socket: WebSocket) -> None:
    settings = socket.app.state.settings
    if socket.headers.get("origin") not in settings.allowed_origins:
        await socket.close(code=1008, reason="Origin not allowed")
        return
    manager = socket.app.state.connections
    session = manager.register(socket)
    if session is None:
        await socket.close(code=1013, reason="Local demo capacity reached")
        return
    tasks: list[asyncio.Task] = []
    try:
        await socket.accept()
        logger.info("connected session=%s active=%d", session.id, manager.active_count)
        await session.send(session.welcome())
        tasks = [asyncio.create_task(receive_inputs(session)), asyncio.create_task(publish_state(session))]
        done, _ = await asyncio.wait(tasks, return_when=asyncio.FIRST_COMPLETED)
        for task in done:
            task.result()
    except (WebSocketDisconnect, OSError, asyncio.TimeoutError):
        logger.info("transport closed session=%s", session.id)
    finally:
        try:
            for task in tasks:
                task.cancel()
            await asyncio.gather(*tasks, return_exceptions=True)
        finally:
            await manager.disconnect(session)
        logger.info("disconnected session=%s active=%d", session.id, manager.active_count)
