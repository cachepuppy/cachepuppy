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
  | "publish_to"
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

export type TopicHandler = (message: CachePuppyEnvelope) => void;

export interface ClientEventMap {
  connected: undefined;
  disconnected: { reason?: string };
  reconnecting: { attempt: number; delayMs: number };
  stateChange: { state: ConnectionState };
  message: CachePuppyEnvelope;
  error: Error;
}
