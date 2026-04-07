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
  | "request"
  | "response"
  | "system";

export interface BeamlineEnvelope {
  v: 1;
  type: MessageType;
  id: string;
  topic?: string;
  event?: string;
  payload?: unknown;
  ts: number;
  correlationId?: string;
  ok?: boolean;
  error?: string;
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
  authToken?: string;
  getAuthToken?: () => Promise<string>;
  reconnect?: Partial<ReconnectConfig>;
  requestTimeoutMs?: number;
  transport?: "mock";
}

export type TopicHandler = (message: BeamlineEnvelope) => void;

export interface ClientEventMap {
  connected: undefined;
  disconnected: { reason?: string };
  reconnecting: { attempt: number; delayMs: number };
  stateChange: { state: ConnectionState };
  message: BeamlineEnvelope;
  error: Error;
}
