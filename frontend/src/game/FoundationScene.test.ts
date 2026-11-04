import { describe, expect, it, vi } from "vitest";
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
