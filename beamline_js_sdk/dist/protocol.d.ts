import type { BeamlineEnvelope, MessageType } from "./types.js";
export declare function nextId(prefix?: string): string;
export declare function createEnvelope(input: {
    type: MessageType;
    topic?: string;
    event?: string;
    payload?: unknown;
    meta?: Record<string, unknown>;
}): BeamlineEnvelope;
export declare function isEnvelope(value: unknown): value is BeamlineEnvelope;
