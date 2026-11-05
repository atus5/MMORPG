from dataclasses import replace

import pytest
from fastapi.testclient import TestClient
from starlette.websockets import WebSocketDisconnect

from app.config import Settings
from app.m2.identity import COOKIE_NAME, TestStaticIdentityProvider
from app.main import create_app

ORIGIN = {"origin": "http://127.0.0.1:3000"}


def local_settings() -> Settings:
    return Settings(m2_enabled=True, app_environment="test")


@pytest.mark.parametrize("environment", ["unspecified", "production", "staging", "", "LOCAL"])
def test_test_provider_and_startup_fail_closed(environment):
    with pytest.raises(ValueError):
        TestStaticIdentityProvider(environment)
    with pytest.raises(ValueError):
        Settings(m2_enabled=True, app_environment=environment)


def test_environment_requires_explicit_opt_in(monkeypatch):
    monkeypatch.setenv("TU_M2_VERTICAL_SLICE", "1")
    monkeypatch.delenv("TU_APP_ENV", raising=False)
    with pytest.raises(ValueError):
        create_app()
    monkeypatch.setenv("TU_APP_ENV", "local")
    assert create_app().state.settings.m2_enabled
    monkeypatch.setenv("TU_M2_VERTICAL_SLICE", "true")
    with pytest.raises(ValueError):
        Settings.from_environment()


def test_server_fixtures_have_distinct_domain_ids_and_opaque_boot_scoped_handles():
    provider = TestStaticIdentityProvider("test")
    first, second = provider.issue(None), provider.issue(None)
    assert first and second
    ids = [
        str(v)
        for fixture in provider.fixtures
        for v in (
            fixture.account_id,
            fixture.player_id,
            fixture.character_id,
        )
    ]
    assert len(set(ids)) == 6
    assert first[1] != second[1]
    assert provider.issue(first[0]) == first
    assert provider.issue(None) is None
    assert provider.resolve(str(first[1].account_id)) is None
    assert provider.resolve(str(first[1].character_id)) is None
    assert TestStaticIdentityProvider("test").resolve(first[0]) is None


def test_request_cannot_choose_adapter_principal_spawn_or_cross_origins():
    with TestClient(create_app(local_settings())) as client:
        assert client.post("/m2/session").status_code == 403
        assert client.post("/m2/session", headers={"origin": "https://evil.invalid"}).status_code == 403
        for body in [{"account_id": "other"}, {"provider": "TestStaticIdentityProvider"}, {"x": 999}]:
            assert client.post("/m2/session", headers=ORIGIN, json=body).status_code == 400
        assert client.post("/m2/session?character_id=other", headers=ORIGIN).status_code == 400
        response = client.post("/m2/session", headers=ORIGIN)
        assert response.status_code == 200
        assert "httponly" in response.headers["set-cookie"].lower()
        assert "samesite=strict" in response.headers["set-cookie"].lower()
        assert set(response.json()) == {"protocol", "boot_id"}
        with client.websocket_connect("/m2/ws", headers=ORIGIN) as ws:
            welcome = ws.receive_json()
            assert welcome["player"] == {"x": 760.0, "y": 500.0}
            assert not any(key in welcome for key in ["account_id", "player_id", "character_id"])
            with pytest.raises(WebSocketDisconnect):
                with client.websocket_connect("/m2/ws", headers=ORIGIN):
                    pass
            ws.send_json(
                {
                    "type": "input",
                    "seq": 1,
                    "direction": "right",
                    "generation": welcome["generation"],
                    "character_id": "other",
                    "x": 9999,
                }
            )
            for _ in range(20):
                frame = ws.receive_json()
                if frame["type"] == "error":
                    break
            assert frame == {"type": "error", "code": "invalid_message"}


def test_handles_and_routes_are_unavailable_without_explicit_local_provider():
    with TestClient(create_app()) as client:
        assert client.post("/m2/session", headers=ORIGIN).status_code == 404
    with TestClient(create_app(local_settings())) as client:
        with pytest.raises(WebSocketDisconnect):
            with client.websocket_connect("/m2/ws", headers={**ORIGIN, "cookie": f"{COOKIE_NAME}=forged"}):
                pass
        client.post("/m2/session", headers=ORIGIN)
        with pytest.raises(WebSocketDisconnect):
            with client.websocket_connect("/m2/ws?account_id=other", headers=ORIGIN):
                pass


def test_non_loopback_request_is_denied_even_with_spoofed_origin():
    with TestClient(
        create_app(replace(local_settings(), app_environment="local")), client=("203.0.113.1", 1234)
    ) as client:
        assert client.post("/m2/session", headers=ORIGIN).status_code == 403
