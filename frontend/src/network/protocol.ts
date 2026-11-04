import { z } from "zod";

const position = z.strictObject({
  x: z.number().finite().nonnegative(),
  y: z.number().finite().nonnegative(),
});
const sequence = z.number().int().min(1).max(2_147_483_647);

export const clientMessage = z.discriminatedUnion("type", [
  z.strictObject({
    type: z.literal("input"),
    seq: sequence,
    direction: z.enum(["up", "down", "left", "right", "idle"]),
  }),
  z.strictObject({ type: z.literal("ping"), seq: sequence }),
]);

export const serverMessage = z.discriminatedUnion("type", [
  z.strictObject({
    type: z.literal("welcome"),
    protocol: z.literal(1),
    connection_id: z.uuid(),
    world: z.strictObject({ width: z.number().int().positive(), height: z.number().int().positive() }),
    player: position,
    tick_hz: z.number().int().positive(),
  }),
  z.strictObject({
    type: z.literal("state"),
    tick: z.number().int().nonnegative(),
    ack: z.number().int().nonnegative(),
    player: position,
  }),
  z.strictObject({ type: z.literal("pong"), seq: sequence }),
  z.strictObject({ type: z.literal("error"), code: z.enum(["invalid_message", "stale_sequence"]) }),
]);

export type ServerMessage = z.infer<typeof serverMessage>;
export type Welcome = Extract<ServerMessage, { type: "welcome" }>;
export type Direction = Extract<z.infer<typeof clientMessage>, { type: "input" }>["direction"];
