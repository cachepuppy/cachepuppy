import { useEffect, useState } from "react";
import type { CachePuppyEnvelope } from "@cachepuppy/core";
import { useCachePuppyClient } from "./useCachePuppyClient.js";

export interface UseTopicOptions {
  enabled?: boolean;
  onMessage?: (message: CachePuppyEnvelope) => void;
}

export function useTopic(topic: string, options: UseTopicOptions = {}) {
  const { client, state } = useCachePuppyClient();
  const { enabled = true, onMessage } = options;
  const [error, setError] = useState<Error | null>(null);

  useEffect(() => {
    if (!enabled || state !== "connected") {
      return;
    }

    let cancelled = false;
    let unsubscribe: (() => void) | undefined;

    const run = async () => {
      try {
        setError(null);
        unsubscribe = await client.subscribe(topic, (message) => {
          if (!cancelled) {
            onMessage?.(message);
          }
        });
      } catch (err) {
        setError(err instanceof Error ? err : new Error("Failed to subscribe"));
      }
    };

    void run();
    return () => {
      cancelled = true;
      unsubscribe?.();
    };
  }, [client, enabled, onMessage, state, topic]);

  return { error };
}
