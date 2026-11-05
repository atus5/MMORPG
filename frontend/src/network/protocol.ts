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

const publicPlayer = position.extend({ id: z.uuid(), label: z.string().min(1).max(16) });
const frame = {
  boot_id: z.uuid(),
  self_id: z.uuid(),
  generation: z.number().int().positive(),
  tick: z.number().int().nonnegative(),
  stream_seq: z.number().int().positive(),
  ack_received: z.number().int().nonnegative(),
  ack_applied: z.number().int().nonnegative(),
  release_required: z.boolean(),
  player: position,
  players: z.array(publicPlayer).min(1).max(2),
};
export const sliceClientMessage = z.discriminatedUnion("type", [
  z.strictObject({
    type: z.literal("input"),
    seq: sequence,
    direction: z.enum(["up", "down", "left", "right", "idle"]),
    generation: z.number().int().positive(),
  }),
  z.strictObject({ type: z.literal("ping"), seq: sequence }),
]);
export const sliceServerMessage = z.discriminatedUnion("type", [
  z.strictObject({
    ...frame,
    type: z.literal("welcome"),
    protocol: z.literal(2),
    connection_id: z.uuid(),
    world: z.strictObject({
      id: z.literal("development"),
      partition: z.literal("single"),
      width: z.number().int().positive(),
      height: z.number().int().positive(),
    }),
    tick_hz: z.number().int().positive(),
  }),
  z.strictObject({ ...frame, type: z.literal("state"), reason: z.null() }),
  z.strictObject({
    ...frame,
    type: z.literal("resync"),
    reason: z.enum(["stale_input", "admission_timeout", "queue_overflow", "timeline_uncertain"]),
  }),
  z.strictObject({ type: z.literal("pong"), seq: sequence }),
  z.strictObject({ type: z.literal("error"), code: z.literal("invalid_message") }),
]);
export type SliceWelcome = Extract<z.infer<typeof sliceServerMessage>, { type: "welcome" }>;
export type PublicPlayer = z.infer<typeof publicPlayer>;
