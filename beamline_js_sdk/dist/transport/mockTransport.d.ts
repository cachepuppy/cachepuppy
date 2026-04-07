import type { BeamlineEnvelope } from "../types.js";
import type { Transport } from "./transport.js";
type EnvelopeHandler = (message: BeamlineEnvelope) => void;
export declare class MockTransport implements Transport {
    connect(clientId: string): Promise<void>;
    disconnect(clientId: string): Promise<void>;
    sendEnvelope(clientId: string, message: BeamlineEnvelope): Promise<void>;
    onEnvelope(clientId: string, handler: EnvelopeHandler): () => void;
    listClientIds(_clientId: string, topic: string): Promise<string[]>;
}
export {};
