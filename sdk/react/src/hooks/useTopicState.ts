import { useCallback, useEffect, useState } from "react";
import { useCachePuppyClient } from "./useCachePuppyClient.js";

export interface UseTopicStateResult {
  state: Record<string, unknown>;
  loading: boolean;
  error: Error | null;
  setState: (nextState: Record<string, unknown>) => Promise<Record<string, unknown>>;
  refresh: () => Promise<void>;
  clear: () => Promise<boolean>;
}

export function useTopicState(topic: string, enabled = true): UseTopicStateResult {
  const { client, state: connectionState } = useCachePuppyClient();
  const [state, setState] = useState<Record<string, unknown>>({});
  const [loading, setLoading] = useState(false);
  const [error, setError] = useState<Error | null>(null);

  const refresh = useCallback(async () => {
    setLoading(true);
    try {
      setError(null);
      const next = await client.getTopicState(topic);
      setState(next);
    } catch (err) {
      setError(err instanceof Error ? err : new Error("Failed to fetch topic state"));
      throw err;
    } finally {
      setLoading(false);
    }
  }, [client, topic]);

  useEffect(() => {
    if (!enabled || connectionState !== "connected") {
      return;
    }

    let cancelled = false;
    void refresh().catch(() => {
      if (!cancelled) {
        setState({});
      }
    });

    let cleanup: (() => void) | undefined;
    void client.onStateUpdated(topic, (nextState) => {
      if (!cancelled) {
        setState(nextState);
      }
    }).then((off) => {
      if (cancelled) {
        off();
      } else {
        cleanup = off;
      }
    }).catch((err: unknown) => {
      if (!cancelled) {
        setError(err instanceof Error ? err : new Error("Failed to watch topic updates"));
      }
    });

    return () => {
      cancelled = true;
      cleanup?.();
    };
  }, [client, connectionState, enabled, refresh, topic]);

  const setTopicState = useCallback(async (nextState: Record<string, unknown>) => {
    try {
      setError(null);
      const updated = await client.setTopicState(topic, nextState);
      setState(updated);
      return updated;
    } catch (err) {
      setError(err instanceof Error ? err : new Error("Failed to set topic state"));
      throw err;
    }
  }, [client, topic]);

  const clear = useCallback(async () => {
    try {
      setError(null);
      const cleared = await client.clearTopicState(topic);
      if (cleared) {
        setState({});
      }
      return cleared;
    } catch (err) {
      setError(err instanceof Error ? err : new Error("Failed to clear topic state"));
      throw err;
    }
  }, [client, topic]);

  return {
    state,
    loading,
    error,
    setState: setTopicState,
    refresh,
    clear,
  };
}
