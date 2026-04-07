declare module "phoenix" {
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
