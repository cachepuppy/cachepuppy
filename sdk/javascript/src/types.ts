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

export type WorkflowStatus = "pending" | "running" | "completed" | "failed";

export interface WorkflowStepInput {
  stepId?: string;
  stepName: string;
  url: string;
  method: "get" | "post" | "put" | "patch" | "delete";
  data?: Record<string, unknown>;
  successCodes?: number[];
  maxRetries?: number;
  parentIds?: string[];
}

export interface WorkflowSummary {
  workflowId: string;
  name: string;
  status: WorkflowStatus;
}

export interface WorkflowStepSummary {
  stepId: string;
  stepName: string;
  status: WorkflowStatus;
  parentIds?: string[];
  groupId?: string | null;
  groupType?: "parallel_branch" | "parallel_merge" | "loop_iteration" | null;
  parentGroupId?: string | null;
  branchIndex?: number | null;
  retryCount?: number;
  maxRetries?: number;
  method?: string;
  url?: string;
  data?: unknown;
  successCodes?: number[];
  input?: unknown;
  output?: unknown;
  executionError?: unknown;
  insertedAt?: string | null;
  startedAt?: string | null;
  completedAt?: string | null;
}

export interface WorkflowGroupSummary {
  groupId: string;
  type: "parallel" | "loop";
  stepIds: string[];
  branchCount?: number | null;
  mergeStepId?: string | null;
  maxIterations?: number | null;
  continueIf?: string | null;
}

export interface WorkflowStateResponse extends WorkflowSummary {
  steps: WorkflowStepSummary[];
  groups: WorkflowGroupSummary[];
}

export interface WorkflowParallelCreatedResponse {
  groupId: string;
  totalBranches: number;
  steps: WorkflowStepSummary[];
  mergeStep: WorkflowStepSummary;
}

export interface WorkflowParallelBranchCloseResponse {
  workflowId: string;
  status: "ok";
}

export interface WorkflowLoopCreatedResponse {
  groupId: string;
  stepName: string;
  maxIterations: number;
  continueIf: string;
}

export interface WorkflowStatusResponse {
  workflowId: string;
  status: WorkflowStatus;
}

export interface WorkflowExecuteNowResponse {
  stepId: string;
  output: unknown;
  status: WorkflowStatus;
}

export interface WorkflowResumeInput {
  stepId: string;
  output?: Record<string, unknown>;
}

export interface WorkflowTopicEvent {
  workflowId: string;
  event: string;
  payload: unknown;
  envelope: CachePuppyEnvelope;
}

export type WorkflowStatusHandler = (payload: WorkflowStatusResponse) => void;
export type WorkflowEventHandler = (event: WorkflowTopicEvent) => void;

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
