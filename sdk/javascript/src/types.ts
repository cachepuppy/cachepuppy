export type ConnectionState =
  | "idle"
  | "connecting"
  | "connected"
  | "reconnecting"
  | "disconnected"
  | "destroyed";

export type MessageType =
  | "subscribe"
  | "unsubscribe"
  | "publish"
  | "set_state"
  | "get_state"
  | "close_topic"
  | "system";

export interface CachePuppyEnvelope {
  v: 1;
  type: MessageType;
  id: string;
  topic?: string;
  event?: string;
  payload?: unknown;
  ts: number;
  meta?: Record<string, unknown>;
}

export interface ReconnectConfig {
  enabled: boolean;
  initialDelayMs: number;
  maxDelayMs: number;
  factor: number;
}

export interface ClientOptions {
  url: string;
  clientId?: string;
  authToken?: string;
  getAuthToken?: () => Promise<string>;
  reconnect?: Partial<ReconnectConfig>;
  transport?: "mock" | "phoenix";
}

/** Options for `CachePuppyAdminClient` (HTTP `/api/server/v1`, no websocket). */
export interface AdminClientOptions {
  /** Same convention as {@link ClientOptions.url}: Phoenix websocket URL; HTTP base is derived. */
  url: string;
  authToken?: string;
  fetchImpl?: typeof fetch;
}

/** Response shape from `CachePuppyAdminClient.getTopicPresence`. */
export interface TopicPresenceResponse {
  clientCount: number;
  presence: Record<string, unknown>;
}

/** Options for `configureTopicWebhook` (Phoenix `configure_topic_webhook`). */
export interface TopicWebhookConfigOptions {
  /** When true, enable periodic POSTs of topic state to `url` every `frequency` seconds if state changed. */
  flush: boolean;
  /** Required when `flush` is true. Webhook URL (`http` or `https` only). */
  url?: string;
  /** Seconds between webhook checks; default 10. Ignored when `flush` is false. */
  frequency?: number;
}

export type TopicHandler = (message: CachePuppyEnvelope) => void;

export interface ClientEventMap {
  connected: undefined;
  disconnected: { reason?: string };
  reconnecting: { attempt: number; delayMs: number };
  stateChange: { state: ConnectionState };
  message: CachePuppyEnvelope;
  /** Emitted when Phoenix Presence count changes for a subscribed topic (Phoenix + mock transports). */
  topicPresence: { topic: string; clientCount: number };
  error: Error;
}
