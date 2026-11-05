import { afterEach, describe, expect, it, vi } from "vitest";
import type { GameClient, Snapshot } from "../network/GameClient";

// Keep the real scene's presentation logic, without booting a browser renderer in Node.
vi.mock("phaser", () => ({ default: { Scene: class {} } }));
import { FoundationScene } from "./FoundationScene";

function displayObject() {
  return {
    visible: true,
    x: 0,
    y: 0,
    alpha: 1,
    setPosition(x: number, y: number) {
      this.x = x;
      this.y = y;
      return this;
    },
    setVisible(visible: boolean) {
      this.visible = visible;
      return this;
    },
    setAlpha(alpha: number) {
      this.alpha = alpha;
      return this;
    },
  };
}

function fixture() {
  let snapshot: Snapshot = {
    status: "connected",
    welcome: null,
    player: { x: 860, y: 500 },
    tick: 4,
    ack: 1,
    error: null,
  };
  const client = { getSnapshot: () => snapshot } as unknown as GameClient;
  const scene = new FoundationScene(client, {} as HTMLDivElement);
  const player = displayObject();
  const ring = displayObject();
  // Inject only renderer-owned objects. Exercise the actual scene method on one scene instance.
  const state = scene as unknown as {
    player: typeof player;
    playerRing: typeof ring;
    worldReady: boolean;
    lastDirection: string;
    renderState(): void;
  };
  Object.assign(state, { player, playerRing: ring, worldReady: true, lastDirection: "right" });
  return {
    scene,
    state,
    player,
    ring,
    render(next: Partial<Snapshot> = {}) {
      snapshot = { ...snapshot, ...next };
      state.renderState();
    },
  };
}

describe("F-001 scene presentation across reconnect failures", () => {
  it("hides both old avatar and ring until a new player snapshot arrives", () => {
    const view = fixture();
    const originalScene = view.scene;
    view.render();
    expect(view.player.visible).toBe(true);
    expect(view.player.x).toBe(860);
    view.render({ status: "connecting", player: null });
    expect(view.player.visible).toBe(false);
    expect(view.ring.visible).toBe(false);
    view.render({ status: "error", player: null });
    expect(view.player.visible).toBe(false);
    expect(view.ring.visible).toBe(false);
    view.render({ status: "connected", player: { x: 800, y: 500 } });
    expect(view.player.visible).toBe(true);
    expect(view.ring.visible).toBe(true);
    expect(view.player.x).toBe(800);
    expect(view.scene).toBe(originalScene);
  });

  it.each(["connecting", "disconnected", "error"] as const)("resets held direction when %s", (status) => {
    const view = fixture();
    view.render({ status, player: null });
    expect(view.state.lastDirection).toBe("idle");
    expect(view.player.visible).toBe(false);
  });
});

afterEach(() => vi.unstubAllGlobals());

describe("Vertical Slice input edges, release gate and peer lifecycle", () => {
  function view() {
    const host = {} as HTMLDivElement;
    vi.stubGlobal("document", { activeElement: host, hidden: false });
    let snapshot: Snapshot = {
      status: "connected",
      welcome: null,
      player: { x: 760, y: 500 },
      tick: 0,
      ack: 0,
      error: null,
      verticalSlice: true,
      releaseRequired: false,
      generation: 1,
      selfId: "self",
      players: [],
    };
    const sendInput = vi.fn();
    const scene = new FoundationScene(
      { getSnapshot: () => snapshot, sendInput } as unknown as GameClient,
      host,
    );
    const state = scene as unknown as {
      player: ReturnType<typeof displayObject>;
      worldReady: boolean;
      peers: Map<string, ReturnType<typeof displayObject> & { destroy(): void }>;
      renderState(): void;
      sliceKey(e: KeyboardEvent, down: boolean): void;
    };
    Object.assign(state, { player: displayObject(), worldReady: true });
    return {
      scene,
      state,
      sendInput,
      key(down: boolean, repeat = false) {
        state.sliceKey({ code: "KeyD", repeat, preventDefault() {} } as KeyboardEvent, down);
      },
      render(next: Partial<Snapshot>) {
        snapshot = { ...snapshot, ...next };
        state.renderState();
      },
    };
  }

  it("sends press/release between render frames without waiting for update", () => {
    const v = view();
    v.key(true);
    v.key(false);
    expect(v.sendInput.mock.calls).toEqual([["right"], ["idle"]]);
  });

  it("does not resume a held key or OS repeat after expiry until release and fresh press", () => {
    const v = view();
    v.key(true);
    v.render({ releaseRequired: true });
    v.scene.update(500);
    v.key(true, true);
    expect(v.sendInput.mock.calls).toEqual([["right"]]);
    v.key(false);
    v.key(true);
    expect(v.sendInput.mock.calls).toEqual([["right"], ["idle"], ["right"]]);
  });

  it("renders peer coordinates only from baselines and destroys stale peer representations", () => {
    const v = view();
    const peer = { ...displayObject(), destroy: vi.fn() };
    v.state.peers.set("other", peer);
    v.render({ players: [{ id: "other", label: "Test 2", x: 840, y: 500 }] });
    expect(peer.x).toBe(840);
    v.render({ players: [{ id: "other", label: "Test 2", x: 855, y: 500 }] });
    expect(peer.x).toBe(855);
    expect(v.state.peers.size).toBe(1);
    v.render({ status: "disconnected", player: null });
    expect(peer.destroy).toHaveBeenCalledTimes(1);
    expect(v.state.peers.size).toBe(0);
    expect(v.state.player.visible).toBe(false);
  });
});
