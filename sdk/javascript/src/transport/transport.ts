import type { CachePuppyEnvelope, TopicWebhookConfigOptions } from "../types.js";

export interface TopicStateResponse {
  state: Record<string, unknown>;
  sourceNode?: string;
  servedByNode?: string;
}

export interface CacheSetDataOptions {
  /** Time-to-live in milliseconds (optional). */
  ttlMs?: number;
}

export interface Transport {
  connect(clientId: string): Promise<void>;
  disconnect(clientId: string): Promise<void>;
  sendEnvelope(clientId: string, message: CachePuppyEnvelope): Promise<void>;
  onEnvelope(clientId: string, handler: (message: CachePuppyEnvelope) => void): () => void;
  clientCount?(clientId: string, topic: string): Promise<number>;
  setState?(clientId: string, topic: string, payload: Record<string, unknown>): Promise<Record<string, unknown>>;
  configureTopicWebhook?(
    clientId: string,
    topic: string,
    options: TopicWebhookConfigOptions,
  ): Promise<void>;
  getState?(clientId: string, topic: string): Promise<Record<string, unknown>>;
  setData?(
    clientId: string,
    table: string,
    key: string,
    value: unknown,
    options?: CacheSetDataOptions,
  ): Promise<unknown>;
  getData?(clientId: string, table: string, key: string): Promise<unknown>;
  /** Shallow-merge `patch` into the existing map value; mirrors `POST /api/cache/updatedata` / `update_cache_data`. */
  updateData?(
    clientId: string,
    table: string,
    key: string,
    patch: Record<string, unknown>,
    options?: CacheSetDataOptions,
  ): Promise<unknown>;
  deleteData?(clientId: string, table: string, key: string): Promise<boolean>;
  /** Per-websocket private state on the fixed `session` channel (no room topic). */
  setSessionState?(clientId: string, payload: Record<string, unknown>): Promise<Record<string, unknown>>;
  getSessionState?(clientId: string): Promise<Record<string, unknown>>;
  getStateWithMeta?(clientId: string, topic: string): Promise<TopicStateResponse>;
  clearTopicState?(clientId: string, topic: string): Promise<boolean>;
  getChannelJoinMeta?(clientId: string, topic: string): Record<string, unknown> | undefined;
}
