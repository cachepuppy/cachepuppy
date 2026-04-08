import type { CachePuppyEnvelope, MessageType } from "./types.js";

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
  meta?: Record<string, unknown>;
}): CachePuppyEnvelope {
  return {
    v: 1,
    id: nextId(),
    ts: Date.now(),
    ...input,
  };
}

export function isEnvelope(value: unknown): value is CachePuppyEnvelope {
  if (!value || typeof value !== "object") {
    return false;
  }
  const v = value as Partial<CachePuppyEnvelope>;
  return v.v === 1 && typeof v.type === "string" && typeof v.id === "string";
}
