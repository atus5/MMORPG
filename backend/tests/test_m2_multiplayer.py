import os
import socket
import subprocess
import sys
import time
from pathlib import Path

import httpx
from fastapi.testclient import TestClient
from websockets.sync.client import connect

from app.config import Settings
from app.m2.identity import COOKIE_NAME
from app.main import create_app

ORIGIN = {"origin": "http://127.0.0.1:3000"}


def receive_until(ws, predicate):
    for _ in range(100):
        message = ws.receive_json()
        if predicate(message):
            return message
    raise AssertionError("Expected authoritative state did not arrive")


def issue(client):
    response = client.post("/m2/session", headers=ORIGIN)
    assert response.status_code == 200
    return {**ORIGIN, "cookie": f"{COOKIE_NAME}={client.cookies.get(COOKIE_NAME)}"}


def test_two_real_asgi_clients_share_world_move_reconnect_and_reject_position_injection():
    app = create_app(Settings(m2_enabled=True, app_environment="test"))
    with TestClient(app) as client:
        first = issue(client)
        client.cookies.clear()
        second = issue(client)
        with client.websocket_connect("/m2/ws", headers=first) as a:
            wa = a.receive_json()
            with client.websocket_connect("/m2/ws", headers=second) as b:
                wb = b.receive_json()
                assert wa["self_id"] != wb["self_id"]
                assert wa["boot_id"] == wb["boot_id"]
                assert (
                    wa["world"]
                    == wb["world"]
                    == {
                        "id": "development",
                        "partition": "single",
                        "width": 1600,
                        "height": 1000,
                    }
                )
                assert wb["player"] == {"x": 840, "y": 500}
                assert len(wb["players"]) == 2
                a.send_json({"type": "input", "seq": 1, "direction": "right", "generation": wa["generation"]})
                moved = receive_until(
                    b, lambda f: any(p["id"] == wa["self_id"] and p["x"] > 762 for p in f.get("players", []))
                )
                assert len(moved["players"]) == 2
                a.send_json({"type": "input", "seq": 2, "direction": "idle", "generation": wa["generation"]})
                settled = receive_until(a, lambda f: f.get("ack_applied", 0) >= 2)
                position = settled["player"]
                a.send_json(
                    {
                        "type": "input",
                        "seq": 3,
                        "direction": "right",
                        "generation": wa["generation"],
                        "x": 99999,
                        "account_id": "forged",
                    }
                )
                assert receive_until(a, lambda f: f["type"] == "error")["code"] == "invalid_message"
                a.close()
                left = receive_until(b, lambda f: len(f.get("players", [])) == 1)
                assert left["players"][0]["id"] == wb["self_id"]
                with client.websocket_connect("/m2/ws", headers=first) as recovered:
                    welcome = recovered.receive_json()
                    assert welcome["self_id"] == wa["self_id"]
                    assert welcome["player"] == position
                    assert welcome["generation"] > wa["generation"]
                    assert len({p["id"] for p in welcome["players"]}) == 2
                    recovered.send_json(
                        {"type": "input", "seq": 1, "direction": "right", "generation": wa["generation"]}
                    )
                    reset = receive_until(recovered, lambda f: f["type"] == "resync")
                    assert reset["reason"] == "stale_input" and reset["release_required"]
                    assert reset["player"] == position
        assert app.state.m2_world.metrics()["active_players"] == 0


def test_world_runtime_never_opens_external_database_or_cache_connections(monkeypatch):
    attempts = []
    original = socket.socket.connect

    def guarded(sock, address):
        if isinstance(address, tuple) and (
            address[0] not in {"127.0.0.1", "::1"} or address[1] in {5432, 6543, 6379}
        ):
            attempts.append(address)
            raise AssertionError("External/database/cache network access is forbidden")
        return original(sock, address)

    monkeypatch.setattr(socket.socket, "connect", guarded)
    with TestClient(create_app(Settings(m2_enabled=True, app_environment="test"))) as client:
        headers = issue(client)
        with client.websocket_connect("/m2/ws", headers=headers) as ws:
            welcome = ws.receive_json()
            ws.send_json(
                {"type": "input", "seq": 1, "direction": "right", "generation": welcome["generation"]}
            )
            assert receive_until(ws, lambda f: f.get("ack_applied", 0) == 1)["player"]["x"] >= 760
    assert attempts == []


def test_actual_uvicorn_process_restart_recreates_ram_state():
    with socket.socket() as available:
        available.bind(("127.0.0.1", 0))
        port = available.getsockname()[1]
    backend = Path(__file__).resolve().parents[1]
    command = [
        sys.executable,
        "-m",
        "uvicorn",
        "app.main:app",
        "--host",
        "127.0.0.1",
        "--port",
        str(port),
        "--workers",
        "1",
        "--ws-max-size",
        "4096",
        "--ws-max-queue",
        "64",
    ]
    environment = {**os.environ, "TU_APP_ENV": "local", "TU_M2_VERTICAL_SLICE": "1"}
    process = None

    def start(client):
        proc = subprocess.Popen(
            command, cwd=backend, env=environment, stdout=subprocess.DEVNULL, stderr=subprocess.DEVNULL
        )
        deadline = time.monotonic() + 5
        while time.monotonic() < deadline:
            if proc.poll() is not None:
                raise AssertionError("Local Uvicorn exited before startup")
            try:
                if client.get("/health").status_code == 200:
                    return proc
            except httpx.TransportError:
                pass
            time.sleep(0.02)
        proc.terminate()
        proc.wait(timeout=5)
        raise AssertionError("Local Uvicorn startup timed out")

    try:
        with httpx.Client(base_url=f"http://127.0.0.1:{port}", timeout=2, trust_env=False) as client:
            process = start(client)
            first = issue(client)
            import json

            with connect(
                f"ws://127.0.0.1:{port}/m2/ws",
                origin=ORIGIN["origin"],
                additional_headers={"cookie": first["cookie"]},
                open_timeout=5,
                proxy=None,
            ) as ws:
                before = json.loads(ws.recv(timeout=5))
                ws.send(
                    json.dumps(
                        {"type": "input", "seq": 1, "direction": "right", "generation": before["generation"]}
                    )
                )
                for _ in range(100):
                    state = json.loads(ws.recv(timeout=5))
                    if state.get("player", {}).get("x", 0) > 762:
                        break
                assert state["player"]["x"] > 762
            process.terminate()
            process.wait(timeout=5)
            process = start(client)
            second = issue(client)  # Old cookie is not valid in the new registry.
            with connect(
                f"ws://127.0.0.1:{port}/m2/ws",
                origin=ORIGIN["origin"],
                additional_headers={"cookie": second["cookie"]},
                open_timeout=5,
                proxy=None,
            ) as ws:
                after = json.loads(ws.recv(timeout=5))
                assert after["boot_id"] != before["boot_id"]
                assert after["self_id"] != before["self_id"]
                assert after["player"] == {"x": 760.0, "y": 500.0}
    finally:
        if process is not None and process.poll() is None:
            process.terminate()
            process.wait(timeout=5)
