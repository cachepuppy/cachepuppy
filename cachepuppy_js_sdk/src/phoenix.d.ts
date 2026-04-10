declare module "phoenix" {
  /** Phoenix JS Presence helper for merging `presence_state` / `presence_diff` payloads. */
  export const Presence: {
    syncState(
      currentState: Record<string, unknown>,
      newState: Record<string, unknown>,
    ): Record<string, unknown>;
    syncDiff(
      currentState: Record<string, unknown>,
      diff: { joins?: Record<string, unknown>; leaves?: Record<string, unknown> },
    ): Record<string, unknown>;
  };

  export class Socket {
    constructor(endPoint: string, opts?: { params?: Record<string, unknown> });
    connect(params?: Record<string, unknown>): void;
    disconnect(callback?: () => void, code?: number, reason?: string): void;
    channel(topic: string, params?: Record<string, unknown>): Channel;
  }

  export interface Push {
    receive(status: string, callback: (response?: unknown) => void): Push;
  }

  export class Channel {
    join(timeout?: number): Push;
    leave(timeout?: number): Push;
    on(event: string, callback: (payload: any, ref?: string, joinRef?: string) => void): void;
    push(event: string, payload: Record<string, unknown>, timeout?: number): Push;
  }
}
