import { useEffect, useState } from "react";
import { useCachePuppyClient } from "./useCachePuppyClient.js";

export interface UsePresenceResult {
  clientCount: number;
  error: Error | null;
}

export function usePresence(topic: string, enabled = true): UsePresenceResult {
  const { client, state } = useCachePuppyClient();
  const [clientCount, setClientCount] = useState(0);
  const [error, setError] = useState<Error | null>(null);

  useEffect(() => {
    if (!enabled || state !== "connected") {
      return;
    }

    let cancelled = false;
    const offPresence = client.onPresenceChange(topic, ({ clientCount: nextCount }) => {
      if (!cancelled) {
        setClientCount(nextCount);
      }
    });

    void client.clientCount(topic).then((count) => {
      if (!cancelled) {
        setClientCount(count);
      }
    }).catch((err: unknown) => {
      if (!cancelled) {
        setError(err instanceof Error ? err : new Error("Failed to read presence"));
      }
    });

    return () => {
      cancelled = true;
      offPresence();
    };
  }, [client, enabled, state, topic]);

  return { clientCount, error };
}
