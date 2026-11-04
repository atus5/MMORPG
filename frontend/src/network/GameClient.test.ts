import { afterEach, describe, expect, it, vi } from "vitest";
import { GameClient } from "./GameClient";

class FakeSocket {
  readyState = 1;
  sent: string[] = [];
  onopen: (() => void) | null = null;
  onmessage: ((event: { data: unknown }) => void) | null = null;
  onerror: (() => void) | null = null;
  onclose: (() => void) | null = null;
  send(value: string) {
    this.sent.push(value);
  }
  close() {
    this.readyState = 3;
    this.onclose?.();
  }
  receive(value: unknown) {
    this.onmessage?.({ data: JSON.stringify(value) });
  }
}
const welcome = {
  type: "welcome",
  protocol: 1,
  connection_id: "8ab0ef94-11d8-495c-a72a-fb1447ccb80a",
  world: { width: 1600, height: 1000 },
  player: { x: 800, y: 500 },
  tick_hz: 20,
};
const clients: GameClient[] = [];
function setup() {
  const sockets: FakeSocket[] = [];
  const client = new GameClient("ws://127.0.0.1:8000/ws", () => {
    const socket = new FakeSocket();
    sockets.push(socket);
    return socket as unknown as WebSocket;
  });
  clients.push(client);
  client.connect();
  return { client, sockets };
}
afterEach(() => {
  for (const client of clients.splice(0)) client.disconnect();
  vi.useRealTimers();
});

describe("GameClient lifecycle and authority", () => {
  it("waits for welcome and never moves the player optimistically", () => {
    const { client, sockets } = setup();
    client.sendInput("right");
    expect(sockets[0].sent).toHaveLength(0);
    sockets[0].receive(welcome);
    client.sendInput("right");
    expect(JSON.parse(sockets[0].sent[0])).toEqual({ type: "input", seq: 1, direction: "right" });
    expect(client.getSnapshot().player).toEqual({ x: 800, y: 500 });
    sockets[0].receive({ type: "state", tick: 1, ack: 1, player: { x: 808, y: 500 } });
    expect(client.getSnapshot().player?.x).toBe(808);
  });
  it("closes invalid server data and ignores callbacks from an old socket", () => {
    const { client, sockets } = setup();
    const oldHandler = sockets[0].onmessage;
    if (!oldHandler) throw new Error("Socket handler not installed");
    client.connect();
    oldHandler({ data: JSON.stringify(welcome) });
    expect(client.getSnapshot().status).toBe("connecting");
    sockets[1].receive({ ...welcome, protocol: 2 });
    expect(client.getSnapshot().status).toBe("error");
    expect(sockets[1].readyState).toBe(3);
  });
  it("disconnects on out-of-bounds state or missing welcome", () => {
    const { client, sockets } = setup();
    sockets[0].receive({ type: "state", tick: 1, ack: 0, player: { x: 800, y: 500 } });
    expect(client.getSnapshot().status).toBe("error");
    client.connect();
    sockets[1].receive(welcome);
    sockets[1].receive({ type: "state", tick: 1, ack: 0, player: { x: 1601, y: 500 } });
    expect(client.getSnapshot().status).toBe("error");
  });
  it("reports disconnect and starts a fresh sequence on manual reconnect", () => {
    const { client, sockets } = setup();
    sockets[0].receive(welcome);
    client.sendInput("right");
    sockets[0].close();
    expect(client.getSnapshot().status).toBe("disconnected");
    client.connect();
    sockets[1].receive(welcome);
    client.sendInput("idle");
    expect(JSON.parse(sockets[1].sent[0]).seq).toBe(1);
  });
  it("times out a missing welcome and clears watchdog on cleanup", () => {
    vi.useFakeTimers();
    const { client } = setup();
    vi.advanceTimersByTime(6000);
    expect(client.getSnapshot().status).toBe("error");
    expect(vi.getTimerCount()).toBe(0);
  });

  it.each(["error", "close", "timeout"] as const)(
    "clears the previous session when reconnect fails via %s",
    (failure) => {
      vi.useFakeTimers();
      const { client, sockets } = setup();
      sockets[0].receive(welcome);
      sockets[0].receive({ type: "state", tick: 1, ack: 0, player: { x: 860, y: 500 } });
      sockets[0].close();
      expect(client.getSnapshot()).toMatchObject({
        status: "disconnected",
        player: null,
        welcome: null,
        tick: 0,
        ack: 0,
      });
      client.connect();
      expect(client.getSnapshot()).toMatchObject({ status: "connecting", player: null, welcome: null });
      if (failure === "error") sockets[1].onerror?.();
      else if (failure === "close") sockets[1].close();
      else vi.advanceTimersByTime(6000);
      expect(client.getSnapshot().status).toBe(failure === "close" ? "disconnected" : "error");
      expect(client.getSnapshot().player).toBeNull();
      expect(client.getSnapshot().welcome).toBeNull();
      expect(vi.getTimerCount()).toBe(0);
    },
  );
});
