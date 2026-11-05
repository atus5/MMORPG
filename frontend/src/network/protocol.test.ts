import { describe, expect, it } from "vitest";
import { clientMessage, serverMessage, sliceClientMessage } from "./protocol";

describe("protocol v1", () => {
  it("accepts only sequenced intents, never client coordinates or speed", () => {
    expect(clientMessage.parse({ type: "input", seq: 1, direction: "right" }).type).toBe("input");
    for (const extra of [{ x: 900 }, { speed: 1000 }, { hp: 900 }]) {
      expect(clientMessage.safeParse({ type: "input", seq: 1, direction: "right", ...extra }).success).toBe(
        false,
      );
    }
    for (const seq of [true, "1", 0, -1, 0.5])
      expect(clientMessage.safeParse({ type: "ping", seq }).success).toBe(false);
  });
  it("rejects incompatible or invalid server messages", () => {
    for (const x of [NaN, Infinity, -1, "800"]) {
      expect(serverMessage.safeParse({ type: "state", tick: 1, ack: 0, player: { x, y: 500 } }).success).toBe(
        false,
      );
    }
    expect(serverMessage.safeParse({ type: "combat", hp: 100 }).success).toBe(false);
  });
});

describe("Vertical Slice input boundary", () => {
  it("requires the current generation but never accepts identity, position or time authority", () => {
    const input = { type: "input", seq: 1, direction: "right", generation: 1 };
    expect(sliceClientMessage.safeParse(input).success).toBe(true);
    for (const extra of [
      { account_id: "other" },
      { player_id: "other" },
      { character_id: "other" },
      { x: 999 },
      { speed: 999 },
      { timestamp: 0.01 },
      { provider: "test" },
    ])
      expect(sliceClientMessage.safeParse({ ...input, ...extra }).success).toBe(false);
    expect(sliceClientMessage.safeParse({ ...input, generation: 0 }).success).toBe(false);
    expect(sliceClientMessage.safeParse({ type: "ping", seq: 2, direction: "right" }).success).toBe(false);
  });
});
