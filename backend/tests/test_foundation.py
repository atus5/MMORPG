import time
from dataclasses import replace

import pytest
from fastapi.testclient import TestClient
from pydantic import ValidationError
from starlette.websockets import WebSocketDisconnect

from app.config import Settings
from app.connections import Session
from app.main import create_app
from app.protocol import StateMessage, WelcomeMessage, client_message

ORIGIN = {"origin": "http://127.0.0.1:3000"}


def receive_type(socket, kind):
    for _ in range(100):
        message = socket.receive_json()
        if message["type"] == kind:
            return message
    raise AssertionError(f"No {kind} message")


def wait_empty(app):
    deadline = time.monotonic() + 2
    while app.state.connections.active_count and time.monotonic() < deadline:
        time.sleep(0.01)
    assert app.state.connections.active_count == 0


def test_health_and_cors():
    with TestClient(create_app()) as client:
        response = client.get("/health", headers=ORIGIN)
        assert response.status_code == 200
        assert response.json() == {"status": "ok", "service": "tu-tien-foundation", "protocol": 1}
        assert response.headers["access-control-allow-origin"] == ORIGIN["origin"]
        denied = client.get("/health", headers={"origin": "https://untrusted.invalid"})
        assert "access-control-allow-origin" not in denied.headers


@pytest.mark.parametrize("headers", [{}, {"origin": "https://untrusted.invalid"}])
def test_websocket_rejects_unapproved_origin(headers):
    app = create_app()
    with TestClient(app) as client:
        with pytest.raises(WebSocketDisconnect) as error:
            with client.websocket_connect("/ws", headers=headers):
                pass
        assert error.value.code == 1008
        assert app.state.connections.active_count == 0


def test_connect_ping_move_stop_disconnect():
    app = create_app()
    with TestClient(app) as client:
        with client.websocket_connect("/ws", headers=ORIGIN) as socket:
            welcome = WelcomeMessage.model_validate(socket.receive_json())
            assert app.state.connections.active_count == 1
            socket.send_json({"type": "ping", "seq": 1})
            assert receive_type(socket, "pong")["seq"] == 1
            socket.send_json({"type": "input", "seq": 2, "direction": "right"})
            for _ in range(100):
                state = StateMessage.model_validate(receive_type(socket, "state"))
                if state.ack == 2 and state.player.x > welcome.player.x:
                    break
            else:
                pytest.fail("No authoritative movement")
            assert state.player.y == welcome.player.y
            socket.send_json({"type": "input", "seq": 3, "direction": "idle"})
            while True:
                stopped = receive_type(socket, "state")
                if stopped["ack"] == 3:
                    break
            assert receive_type(socket, "state")["player"] == stopped["player"]
        wait_empty(app)


@pytest.mark.parametrize("message", [
    {"type": "input", "seq": 1, "direction": "right", "x": 9999},
    {"type": "input", "seq": True, "direction": "right"},
    {"type": "input", "seq": "1", "direction": "right"},
    {"type": "input", "seq": 1.0, "direction": "right"},
    {"type": "input", "seq": 0, "direction": "right"},
    {"type": "input", "seq": 1, "direction": "teleport"},
    {"type": "reward", "seq": 1, "amount": 99999},
])
def test_message_validation_does_not_move_or_echo_input(message):
    app = create_app()
    with TestClient(app) as client:
        with client.websocket_connect("/ws", headers=ORIGIN) as socket:
            start = socket.receive_json()["player"]
            socket.send_json(message)
            assert receive_type(socket, "error") == {"type": "error", "code": "invalid_message"}
            state = receive_type(socket, "state")
            assert state["ack"] == 0 and state["player"] == start
        wait_empty(app)


def test_bad_json_and_duplicate_sequence():
    with TestClient(create_app()) as client:
        with client.websocket_connect("/ws", headers=ORIGIN) as socket:
            socket.receive_json()
            socket.send_text("{not-json")
            assert receive_type(socket, "error")["code"] == "invalid_message"
            socket.send_json({"type": "ping", "seq": 1})
            receive_type(socket, "pong")
            socket.send_json({"type": "input", "seq": 1, "direction": "right"})
            assert receive_type(socket, "error")["code"] == "stale_sequence"


@pytest.mark.parametrize("binary,code", [(True, 1003), (False, 1009)])
def test_rejects_binary_and_oversize(binary, code):
    app = create_app()
    with TestClient(app) as client:
        with client.websocket_connect("/ws", headers=ORIGIN) as socket:
            socket.receive_json()
            if binary:
                socket.send_bytes(b"binary")
            else:
                socket.send_text("x" * 2049)
            with pytest.raises(WebSocketDisconnect) as error:
                while True:
                    socket.receive_json()
            assert error.value.code == code
        wait_empty(app)


def test_capacity_and_rate_limits_cleanup():
    app = create_app(replace(Settings(), max_connections=1, messages_per_second=2))
    with TestClient(app) as client:
        with client.websocket_connect("/ws", headers=ORIGIN) as socket:
            socket.receive_json()
            with pytest.raises(WebSocketDisconnect) as denied:
                with client.websocket_connect("/ws", headers=ORIGIN):
                    pass
            assert denied.value.code == 1013
            for seq in (1, 2):
                socket.send_json({"type": "ping", "seq": seq})
                receive_type(socket, "pong")
            socket.send_json({"type": "ping", "seq": 3})
            with pytest.raises(WebSocketDisconnect) as error:
                while True:
                    socket.receive_json()
            assert error.value.code == 1008
        wait_empty(app)


def test_movement_uses_server_time_lease_and_bounds():
    session = Session(None, Settings(), 0.0)  # Socket unused by pure simulation.
    session.direction, session.input_at = "right", 0.0
    initial = session.x
    session.advance(0.05)
    moved = session.x
    assert moved == initial + 8
    for _ in range(100):
        session.advance(0.05)
    assert session.x == moved  # More requests/ticks at the same time cannot add distance.
    session.advance(0.5)
    assert session.x == moved  # Lost key-up expires the input lease.
    session.x = session.settings.world_width - 1.0
    session.input_at = 0.55
    session.advance(0.55)
    assert session.x == session.settings.world_width
    with pytest.raises(ValidationError):
        client_message.validate_json('{"type":"input","seq":1,"direction":"right","speed":999}')


def test_sessions_are_independent_and_reconnect_is_new():
    app = create_app()
    with TestClient(app) as client:
        with client.websocket_connect("/ws", headers=ORIGIN) as first:
            one = first.receive_json()
            with client.websocket_connect("/ws", headers=ORIGIN) as second:
                two = second.receive_json()
                assert one["connection_id"] != two["connection_id"]
                assert app.state.connections.active_count == 2
        wait_empty(app)
        with client.websocket_connect("/ws", headers=ORIGIN) as fresh:
            assert fresh.receive_json()["connection_id"] not in (one["connection_id"], two["connection_id"])
        wait_empty(app)
