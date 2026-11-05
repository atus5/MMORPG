import asyncio
import time
from unittest.mock import AsyncMock

import pytest
from fastapi.testclient import TestClient
from starlette.websockets import WebSocket, WebSocketDisconnect, WebSocketState

from app.config import Settings
from app.connections import ConnectionManager
from app.main import create_app


async def accepted_socket():
    receive = AsyncMock(return_value={"type": "websocket.connect"})
    send = AsyncMock()
    socket = WebSocket({"type": "websocket", "path": "/ws"}, receive, send)
    await socket.accept()
    send.reset_mock()
    return socket, receive, send


def test_client_disconnect_never_sends_redundant_close():
    async def scenario():
        socket, receive, send = await accepted_socket()
        manager = ConnectionManager(Settings())
        session = manager.register(socket)
        receive.return_value = {"type": "websocket.disconnect", "code": 1001}
        await socket.receive()  # The real Starlette transition, as on client close/page reload.
        assert socket.client_state == WebSocketState.DISCONNECTED
        assert socket.application_state == WebSocketState.CONNECTED
        with pytest.raises(WebSocketDisconnect):
            await session.send(session.welcome())
        await session.close()
        manager.remove(session)
        manager.remove(session)
        assert manager.active_count == 0
        send.assert_not_awaited()

    asyncio.run(scenario())


def test_repeated_concurrent_cleanup_sends_at_most_one_close():
    async def scenario():
        socket, _, send = await accepted_socket()
        manager = ConnectionManager(Settings())
        session = manager.register(socket)
        await asyncio.gather(manager.disconnect(session), manager.disconnect(session))
        await manager.disconnect(session)
        assert manager.active_count == 0
        assert send.await_count == 1
        assert send.await_args.args[0]["type"] == "websocket.close"

    asyncio.run(scenario())


@pytest.mark.parametrize("failure", [RuntimeError("already closed"), OSError("peer reset"), TimeoutError()])
def test_cleanup_transport_failure_cannot_retain_session(failure):
    async def scenario():
        socket, _, _ = await accepted_socket()
        manager = ConnectionManager(Settings())
        session = manager.register(socket)
        # Failure before the fake transport can update its state: cleanup must not retry.
        socket.close = AsyncMock(side_effect=failure)
        await manager.disconnect(session)
        await manager.disconnect(session)
        assert manager.active_count == 0
        assert socket.close.await_count == 1

    asyncio.run(scenario())


def test_endpoint_cleanup_failure_does_not_leak_or_block_reconnect():
    app = create_app()
    origin = {"origin": "http://127.0.0.1:3000"}
    with TestClient(app) as client:
        with client.websocket_connect("/ws", headers=origin) as socket:
            old_id = socket.receive_json()["connection_id"]
            session = app.state.connections.sessions[old_id]
            session.close = AsyncMock(side_effect=RuntimeError("transport already closed"))
        deadline = time.monotonic() + 2
        while app.state.connections.active_count and time.monotonic() < deadline:
            time.sleep(0.01)
        assert app.state.connections.active_count == 0
        session.close.assert_awaited_once()
        with client.websocket_connect("/ws", headers=origin) as fresh:
            assert fresh.receive_json()["connection_id"] != old_id
