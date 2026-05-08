import { useEffect, useState } from "react";
import type { WorkflowStatusResponse } from "@cachepuppy/core";
import { useCachePuppyClient } from "./useCachePuppyClient.js";

export interface UseWorkflowStatusOptions {
  enabled?: boolean;
  onStatus?: (status: WorkflowStatusResponse) => void;
}

export interface UseWorkflowStatusResult {
  status: WorkflowStatusResponse["status"] | null;
  latest: WorkflowStatusResponse | null;
  error: Error | null;
}

export function useWorkflowStatus(workflowId: string, options: UseWorkflowStatusOptions = {}): UseWorkflowStatusResult {
  const { client, state } = useCachePuppyClient();
  const { enabled = true, onStatus } = options;
  const [latest, setLatest] = useState<WorkflowStatusResponse | null>(null);
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
        unsubscribe = await client.onWorkflowStatus(workflowId, (next) => {
          if (!cancelled) {
            setLatest(next);
            onStatus?.(next);
          }
        });
      } catch (err) {
        setError(err instanceof Error ? err : new Error("Failed to subscribe to workflow status"));
      }
    };

    void run();
    return () => {
      cancelled = true;
      unsubscribe?.();
    };
  }, [client, enabled, onStatus, state, workflowId]);

  return {
    status: latest?.status ?? null,
    latest,
    error,
  };
}
