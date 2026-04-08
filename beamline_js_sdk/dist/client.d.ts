import type { ClientEventMap, ClientOptions, ConnectionState, TopicHandler } from "./types.js";
export declare class BeamlineClient {
    private readonly options;
    private state;
    private readonly events;
    private readonly transport;
    private readonly reconnect;
    private readonly clientId;
    private readonly topicHandlers;
    private unlistenEnvelope?;
    constructor(options: ClientOptions);
    private setState;
    getState(): ConnectionState;
    on: <K extends keyof ClientEventMap>(event: K, handler: (payload: ClientEventMap[K]) => void) => () => void;
    connect(): Promise<void>;
    disconnect(reason?: string): Promise<void>;
    destroy(): Promise<void>;
    private handleEnvelope;
    subscribe(topic: string, handler: TopicHandler): Promise<() => void>;
    unsubscribe(topic: string): Promise<void>;
    publish(topic: string, event: string, payload: unknown): Promise<void>;
    publishTo(topic: string, event: string, payload: unknown, clientIds: string[]): Promise<void>;
    clientCount(topic: string): Promise<number>;
    reconnectOnce(attempt: number): Promise<void>;
}
export declare function createClient(options: ClientOptions): BeamlineClient;
