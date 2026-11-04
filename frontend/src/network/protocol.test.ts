import { describe, expect, it } from "vitest";
import { clientMessage, serverMessage } from "./protocol";

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
