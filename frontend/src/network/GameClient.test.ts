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

const ownId = "105ac64f-5cd0-43d1-b0a8-d60170940ad0";
const peerId = "fafb071a-f22f-4e2d-a33c-cb5118a5346b";
const bootId = "12d5d9ed-0f2e-4696-b57f-877ca19b115d";
const sliceFrame = {
  boot_id: bootId,
  self_id: ownId,
  generation: 1,
  tick: 0,
  stream_seq: 1,
  ack_received: 0,
  ack_applied: 0,
  release_required: false,
  player: { x: 760, y: 500 },
  players: [{ id: ownId, label: "Test 1", x: 760, y: 500 }],
};
const sliceWelcome = {
  ...sliceFrame,
  type: "welcome",
  protocol: 2,
  connection_id: welcome.connection_id,
  world: { id: "development", partition: "single", width: 1600, height: 1000 },
  tick_hz: 20,
};

async function setupSlice(bootstrap = vi.fn(async (_url: string) => {})) {
  const sockets: FakeSocket[] = [];
  const urls: string[] = [];
  const client = new GameClient(
    "ws://127.0.0.1:8000/ws",
    (url) => {
      urls.push(url);
      const socket = new FakeSocket();
      sockets.push(socket);
      return socket as unknown as WebSocket;
    },
    { verticalSlice: true, bootstrap },
  );
  clients.push(client);
  client.connect();
  await vi.waitFor(() => expect(sockets).toHaveLength(1));
  return { client, sockets, urls, bootstrap };
}

describe("Vertical Slice fixture, authority and recovery", () => {
  it("bootstraps an opaque server fixture and replicates peers without optimistic movement", async () => {
    const { client, sockets, urls, bootstrap } = await setupSlice();
    expect(bootstrap).toHaveBeenCalledWith("http://127.0.0.1:8000/m2/session");
    expect(urls).toEqual(["ws://127.0.0.1:8000/m2/ws"]);
    sockets[0].receive(sliceWelcome);
    client.sendInput("right");
    expect(JSON.parse(sockets[0].sent[0])).toEqual({
      type: "input",
      seq: 1,
      direction: "right",
      generation: 1,
    });
    expect(client.getSnapshot().player).toEqual({ x: 760, y: 500 });
    sockets[0].receive({
      ...sliceFrame,
      type: "state",
      reason: null,
      stream_seq: 2,
      tick: 1,
      ack_received: 1,
      ack_applied: 1,
      players: [...sliceFrame.players, { id: peerId, label: "Test 2", x: 830, y: 500 }],
    });
    expect(client.getSnapshot().players).toHaveLength(2);
    client.disconnect();
    expect(client.getSnapshot()).toMatchObject({ players: [], selfId: null, player: null, generation: 0 });
  });

  it("requires idle then a fresh press after resync and rejects stale server authority", async () => {
    const { client, sockets } = await setupSlice();
    sockets[0].receive(sliceWelcome);
    client.sendInput("right");
    sockets[0].receive({
      ...sliceFrame,
      type: "resync",
      reason: "stale_input",
      stream_seq: 2,
      generation: 2,
      release_required: true,
    });
    client.sendInput("right");
    expect(sockets[0].sent).toHaveLength(1);
    client.sendInput("idle");
    client.sendInput("right");
    expect(sockets[0].sent.map((s) => JSON.parse(s))).toEqual([
      { type: "input", seq: 1, direction: "right", generation: 1 },
      { type: "input", seq: 2, direction: "idle", generation: 2 },
      { type: "input", seq: 3, direction: "right", generation: 2 },
    ]);
    sockets[0].receive({ ...sliceFrame, type: "state", reason: null, stream_seq: 3, generation: 1 });
    expect(client.getSnapshot().status).toBe("error");
    expect(client.getSnapshot().players).toEqual([]);
  });

  it("deduplicates pending bootstrap across setup/cleanup and ignores an obsolete attempt", async () => {
    let resolve: (() => void) | undefined;
    const bootstrap = vi.fn(
      () =>
        new Promise<void>((done) => {
          resolve = done;
        }),
    );
    const sockets: FakeSocket[] = [];
    const client = new GameClient(
      "ws://127.0.0.1:8000/ws",
      () => {
        const socket = new FakeSocket();
        sockets.push(socket);
        return socket as unknown as WebSocket;
      },
      { verticalSlice: true, bootstrap },
    );
    clients.push(client);
    client.connect();
    client.disconnect();
    client.connect();
    expect(bootstrap).toHaveBeenCalledTimes(1);
    resolve?.();
    await vi.waitFor(() => expect(sockets).toHaveLength(1));
    sockets[0].receive(sliceWelcome);
    expect(client.getSnapshot().status).toBe("connected");
  });

  it("rejects duplicate peer IDs and closes stalled bootstrap within the watchdog", async () => {
    const { client, sockets } = await setupSlice();
    sockets[0].receive({ ...sliceWelcome, players: [...sliceFrame.players, ...sliceFrame.players] });
    expect(client.getSnapshot().status).toBe("error");
    vi.useFakeTimers();
    const stalled = new GameClient(
      "ws://127.0.0.1:8000/ws",
      () => {
        throw new Error("Must not open before bootstrap");
      },
      { verticalSlice: true, bootstrap: () => new Promise<void>(() => {}) },
    );
    clients.push(stalled);
    stalled.connect();
    vi.advanceTimersByTime(5001);
    expect(stalled.getSnapshot().status).toBe("error");
    expect(vi.getTimerCount()).toBe(0);
  });
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
