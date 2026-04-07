import type { BeamlineEnvelope } from "../types.js";
export interface Transport {
    connect(clientId: string): Promise<void>;
    disconnect(clientId: string): Promise<void>;
    sendEnvelope(clientId: string, message: BeamlineEnvelope): Promise<void>;
    onEnvelope(clientId: string, handler: (message: BeamlineEnvelope) => void): () => void;
}
