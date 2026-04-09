import type { CachePuppyEnvelope } from "../types.js";

export interface Transport {
  connect(clientId: string): Promise<void>;
  disconnect(clientId: string): Promise<void>;
  sendEnvelope(clientId: string, message: CachePuppyEnvelope): Promise<void>;
  onEnvelope(clientId: string, handler: (message: CachePuppyEnvelope) => void): () => void;
  clientCount?(clientId: string, topic: string): Promise<number>;
  setState?(clientId: string, topic: string, payload: Record<string, unknown>): Promise<Record<string, unknown>>;
  getState?(clientId: string, topic: string): Promise<Record<string, unknown>>;
  closeTopic?(clientId: string, topic: string): Promise<boolean>;
}
