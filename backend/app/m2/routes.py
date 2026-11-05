"""Local-only bootstrap capability and WebSocket transport for the single owner."""

import asyncio
import ipaddress

from fastapi import APIRouter, Request, WebSocket, WebSocketDisconnect
from fastapi.responses import JSONResponse

from app.connections import Session
from app.m2.identity import COOKIE_NAME
from app.m2.world import Binding, World

router = APIRouter(prefix="/m2")


def allowed(client_host: str | None, origin: str | None, world: World) -> bool:
    if origin not in world.settings.allowed_origins:
        return False
    if client_host == "testclient" and world.settings.app_environment == "test":
        return True
    try:
        return ipaddress.ip_address(client_host or "").is_loopback
    except ValueError:
        return False


@router.post("/session")
async def bootstrap(request: Request) -> JSONResponse:
    world = request.app.state.m2_world
    if not allowed(request.client.host if request.client else None, request.headers.get("origin"), world):
        return JSONResponse({"error": "local_origin_required"}, status_code=403)
    if request.query_params:
        return JSONResponse({"error": "server_fixture_only"}, status_code=400)
    async for chunk in request.stream():
        if chunk:
            return JSONResponse({"error": "server_fixture_only"}, status_code=400)
    issued = world.identity.issue(request.cookies.get(COOKIE_NAME))
    if issued is None:
        return JSONResponse({"error": "local_fixtures_in_use"}, status_code=503)
    handle, _ = issued
    response = JSONResponse({"protocol": 2, "boot_id": world.boot_id}, headers={"Cache-Control": "no-store"})
    response.set_cookie(COOKIE_NAME, handle, httponly=True, samesite="strict", path="/m2")
    return response


@router.get("/metrics")
async def metrics(request: Request) -> JSONResponse:
    world = request.app.state.m2_world
    if not allowed(request.client.host if request.client else None, request.headers.get("origin"), world):
        return JSONResponse({"error": "local_origin_required"}, status_code=403)
    return JSONResponse(world.metrics(), headers={"Cache-Control": "no-store"})


async def receive_inputs(binding: Binding, world: World) -> None:
    window_at, count = world.clock(), 0
    while True:
        event = await binding.transport.socket.receive()
        received_at = world.clock()  # Earliest complete-event observation, before admission.
        if event["type"] == "websocket.disconnect":
            return
        if received_at - window_at >= 1:
            window_at, count = received_at, 0
        count += 1
        raw = event.get("text")
        if raw is None:
            await binding.transport.close(code=1003, reason="Text JSON required")
            return
        if len(raw.encode("utf-8")) > world.settings.max_message_bytes:
            await binding.transport.close(code=1009, reason="Message too large")
            return
        if count > world.settings.messages_per_second:
            await binding.transport.close(code=1008, reason="Message rate exceeded")
            return
        binding.pending_count += 1
        if binding.pending_since is None:
            binding.pending_since = received_at
        try:
            if binding.pending_count > world.settings.pending_input_limit:
                world.resync(binding, "queue_overflow")
            else:
                await world.admit_raw(binding, raw, received_at)
        finally:
            binding.pending_count -= 1
            if binding.pending_count == 0:
                binding.pending_since = None


async def send_frames(binding: Binding) -> None:
    while True:
        message = await binding.outgoing.get()
        try:
            if binding.closing:
                await binding.transport.close(code=1008, reason="Slow consumer")
                return
            await binding.transport.send(message)
        finally:
            binding.outgoing.task_done()


@router.websocket("/ws")
async def websocket(socket: WebSocket) -> None:
    world = socket.app.state.m2_world
    if not allowed(socket.client.host if socket.client else None, socket.headers.get("origin"), world):
        await socket.close(code=1008, reason="Local origin required")
        return
    principal = world.identity.resolve(socket.cookies.get(COOKIE_NAME))
    if principal is None or socket.query_params:
        await socket.close(code=1008, reason="Server fixture required")
        return
    transport = Session(socket, world.settings, world.clock())
    binding = world.attach(principal, transport)
    if binding is None:
        await socket.close(code=1013, reason="Fixture already controlled")
        return
    tasks: list[asyncio.Task] = []
    try:
        await socket.accept()
        tasks = [
            asyncio.create_task(receive_inputs(binding, world)),
            asyncio.create_task(send_frames(binding)),
        ]
        done, _ = await asyncio.wait(tasks, return_when=asyncio.FIRST_COMPLETED)
        for task in done:
            task.result()
    except (WebSocketDisconnect, OSError, asyncio.TimeoutError, RuntimeError):
        pass
    finally:
        world.detach(binding)
        try:
            for task in tasks:
                task.cancel()
            await asyncio.gather(*tasks, return_exceptions=True)
        finally:
            try:
                await transport.close()
            except (WebSocketDisconnect, OSError, asyncio.TimeoutError, RuntimeError):
                pass
