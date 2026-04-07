import type { BeamlineEnvelope, MessageType } from "./types.js";

let counter = 0;

export function nextId(prefix = "msg"): string {
  counter += 1;
  return `${prefix}_${Date.now()}_${counter}`;
}

export function createEnvelope(input: {
  type: MessageType;
  topic?: string;
  event?: string;
  payload?: unknown;
  correlationId?: string;
  ok?: boolean;
  error?: string;
  meta?: Record<string, unknown>;
}): BeamlineEnvelope {
  return {
    v: 1,
    id: nextId(),
    ts: Date.now(),
    ...input,
  };
}

export function isEnvelope(value: unknown): value is BeamlineEnvelope {
  if (!value || typeof value !== "object") {
    return false;
  }
  const v = value as Partial<BeamlineEnvelope>;
  return v.v === 1 && typeof v.type === "string" && typeof v.id === "string";
}
