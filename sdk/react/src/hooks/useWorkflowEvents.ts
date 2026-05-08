import { useEffect, useState } from "react";
import type { WorkflowTopicEvent } from "@cachepuppy/core";
import { useCachePuppyClient } from "./useCachePuppyClient.js";

export interface UseWorkflowEventsOptions {
  enabled?: boolean;
  onEvent?: (event: WorkflowTopicEvent) => void;
}

export function useWorkflowEvents(workflowId: string, options: UseWorkflowEventsOptions = {}) {
  const { client, state } = useCachePuppyClient();
  const { enabled = true, onEvent } = options;
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
        unsubscribe = await client.subscribeWorkflow(workflowId, (event) => {
          if (!cancelled) {
            onEvent?.(event);
          }
        });
      } catch (err) {
        setError(err instanceof Error ? err : new Error("Failed to subscribe to workflow events"));
      }
    };

    void run();
    return () => {
      cancelled = true;
      unsubscribe?.();
    };
  }, [client, enabled, onEvent, state, workflowId]);

  return { error };
}
