import type { WorkflowTopicEvent } from "@cachepuppy/core";
import { useCachePuppyClient } from "@cachepuppy/react";
import { useEffect, useState } from "react";
import { mergeGraphDiff, STEP_NODE_TYPES } from "./graphMerge.js";

const SCENARIO_LABELS: Record<1 | 2 | 3 | 4, string> = {
  1: "Serial: extract → research → compile → store",
  2: "Static parallel (3 branches) + merge → store",
  3: "Dynamic parallel (word count) + merge → store",
  4: "Dynamic parallel + compile on output.summary → store",
};

export function ScenarioCard(props: {
  scenario: 1 | 2 | 3 | 4;
  apiBase: string;
  paragraph: string;
}) {
  const { scenario, apiBase, paragraph } = props;
  const { client, state: connectionState } = useCachePuppyClient();
  const [workflowId, setWorkflowId] = useState<string | null>(null);
  const [nodes, setNodes] = useState<Map<string, Record<string, unknown>>>(() => new Map());
  const [workflowStatus, setWorkflowStatus] = useState<string | null>(null);
  const [error, setError] = useState<string | null>(null);
  const [busy, setBusy] = useState(false);

  useEffect(() => {
    if (!workflowId || connectionState !== "connected") {
      return;
    }

    let cancelled = false;
    let unsubscribe: (() => void) | undefined;

    void client
      .subscribeWorkflow(workflowId, (ev: WorkflowTopicEvent) => {
        if (cancelled) {
          return;
        }
        if (
          ev.event === "graph_diff" &&
          ev.payload &&
          typeof ev.payload === "object" &&
          !Array.isArray(ev.payload)
        ) {
          const payload = ev.payload as Record<string, unknown>;
          setNodes((prev) => mergeGraphDiff(prev, payload));
          const ws = payload["workflowStatus"];
          if (typeof ws === "string") {
            setWorkflowStatus(ws);
          }
        }
      })
      .then((off: () => void) => {
        if (cancelled) {
          off();
        } else {
          unsubscribe = off;
        }
      })
      .catch(() => {
        if (!cancelled) {
          setError("Failed to subscribe to workflow topic");
        }
      });

    return () => {
      cancelled = true;
      unsubscribe?.();
    };
  }, [client, connectionState, workflowId]);

  async function play() {
    setBusy(true);
    setError(null);
    setNodes(new Map());
    setWorkflowStatus(null);
    setWorkflowId(null);

    try {
      const res = await fetch(`${apiBase}/scenario${scenario}/start`, {
        method: "POST",
        headers: { "content-type": "application/json" },
        body: JSON.stringify({ paragraph }),
      });
      const data = (await res.json()) as { workflowId?: string; error?: string };
      if (!res.ok) {
        throw new Error(data.error ?? JSON.stringify(data));
      }
      if (typeof data.workflowId !== "string") {
        throw new Error("Missing workflowId in response");
      }
      setWorkflowId(data.workflowId);
    } catch (e) {
      setError(e instanceof Error ? e.message : String(e));
    } finally {
      setBusy(false);
    }
  }

  const stepRows = Array.from(nodes.values()).filter((n) => {
    const t = n["type"];
    return typeof t === "string" && STEP_NODE_TYPES.has(t);
  });

  stepRows.sort((a, b) => {
    const na = typeof a["stepName"] === "string" ? a["stepName"] : "";
    const nb = typeof b["stepName"] === "string" ? b["stepName"] : "";
    return na.localeCompare(nb);
  });

  return (
    <section className="scenario-card">
      <div className="scenario-card__head">
        <h2>Scenario {scenario}</h2>
        <p className="scenario-card__desc">{SCENARIO_LABELS[scenario]}</p>
        <button type="button" className="play-btn" disabled={busy || connectionState !== "connected"} onClick={() => void play()}>
          {busy ? "Starting…" : "Play"}
        </button>
      </div>
      {connectionState !== "connected" ? (
        <p className="muted">Connect websocket to run scenarios…</p>
      ) : null}
      {error ? <p className="error">{error}</p> : null}
      {workflowId ? (
        <p className="workflow-id">
          <code>{workflowId}</code>
          {workflowStatus ? <span className="status-pill">{workflowStatus}</span> : null}
        </p>
      ) : null}
      {stepRows.length > 0 ? (
        <table className="steps-table">
          <thead>
            <tr>
              <th>Step</th>
              <th>Type</th>
              <th>Status</th>
              <th>Retries</th>
            </tr>
          </thead>
          <tbody>
            {stepRows.map((row) => (
              <tr key={String(row["nodeId"])}>
                <td>{String(row["stepName"] ?? "")}</td>
                <td>{String(row["type"] ?? "")}</td>
                <td>{String(row["status"] ?? "")}</td>
                <td>{String(row["retryCount"] ?? "0")}</td>
              </tr>
            ))}
          </tbody>
        </table>
      ) : workflowId ? (
        <p className="muted">Waiting for graph updates…</p>
      ) : null}
    </section>
  );
}
