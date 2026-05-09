import type { WorkflowTopicEvent } from "@cachepuppy/core";
import { useCachePuppyClient } from "@cachepuppy/react";
import type { CSSProperties } from "react";
import { useEffect, useMemo, useState } from "react";
import { createEmptyGraphState, mergeGraphDiff, STEP_NODE_TYPES, type GraphState } from "./graphMerge.js";

const SCENARIO_LABELS: Record<1 | 2 | 3 | 4 | 5 | 6 | 7, string> = {
  1: "Serial: extract → research → compile → store",
  2: "Static parallel (3 branches) + merge → store",
  3: "Dynamic parallel (word count) + merge → store",
  4: "Dynamic parallel research → summarize branches → final merge compile → store",
  5: "Nested parallel: research branches each fan out to search → collect → summarise → merge",
  6: "Nested parallel + flaky inner step (retries exhausted) → manual Retry → completes",
  7: "Two parallel branches fail (retries exhausted) → Retry all failed steps → completes",
};

export function ScenarioCard(props: {
  scenario: 1 | 2 | 3 | 4 | 5 | 6 | 7;
  apiBase: string;
  paragraph: string;
}) {
  const { scenario, apiBase, paragraph } = props;
  const { client, state: connectionState } = useCachePuppyClient();
  const [workflowId, setWorkflowId] = useState<string | null>(null);
  const [graph, setGraph] = useState<GraphState>(() => createEmptyGraphState());
  const [workflowStatus, setWorkflowStatus] = useState<string | null>(null);
  const [error, setError] = useState<string | null>(null);
  const [busy, setBusy] = useState(false);
  const [retryBusy, setRetryBusy] = useState(false);

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
          setGraph((prev) => mergeGraphDiff(prev, payload));
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

  const failedStepIdForRetry = useMemo(() => pickFailedStepIdForRetry(graph), [graph]);

  async function play() {
    setBusy(true);
    setError(null);
    setGraph(createEmptyGraphState());
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

  async function retryFailedStep() {
    if (scenario !== 6 || !workflowId || !failedStepIdForRetry) {
      return;
    }
    setRetryBusy(true);
    setError(null);
    try {
      const res = await fetch(`${apiBase}/scenario6/retry`, {
        method: "POST",
        headers: { "content-type": "application/json" },
        body: JSON.stringify({ workflowId, stepId: failedStepIdForRetry }),
      });
      const data = (await res.json()) as { workflowId?: string; status?: string; error?: string };
      if (!res.ok) {
        throw new Error(data.error ?? JSON.stringify(data));
      }
      if (typeof data.status === "string") {
        setWorkflowStatus(data.status);
      }
    } catch (e) {
      setError(e instanceof Error ? e.message : String(e));
    } finally {
      setRetryBusy(false);
    }
  }

  async function retryAllFailedSteps() {
    if (scenario !== 7 || !workflowId) {
      return;
    }
    setRetryBusy(true);
    setError(null);
    try {
      const res = await fetch(`${apiBase}/scenario7/retry_failed_steps`, {
        method: "POST",
        headers: { "content-type": "application/json" },
        body: JSON.stringify({ workflowId }),
      });
      const data = (await res.json()) as { workflowId?: string; status?: string; error?: string };
      if (!res.ok) {
        throw new Error(data.error ?? JSON.stringify(data));
      }
      if (typeof data.status === "string") {
        setWorkflowStatus(data.status);
      }
    } catch (e) {
      setError(e instanceof Error ? e.message : String(e));
    } finally {
      setRetryBusy(false);
    }
  }

  const showRetrySingle =
    scenario === 6 &&
    workflowId &&
    (workflowStatus === "failed" || workflowStatus === "failing") &&
    Boolean(failedStepIdForRetry);

  const showRetryAllFailed =
    scenario === 7 && workflowId && (workflowStatus === "failed" || workflowStatus === "failing");

  const orderedRows = useMemo(() => buildHierarchyRows(graph), [graph]);

  const hasRows = orderedRows.length > 0;

  return (
    <section className="scenario-card">
      <div className="scenario-card__head">
        <h2>Scenario {scenario}</h2>
        <p className="scenario-card__desc">{SCENARIO_LABELS[scenario]}</p>
        <div className="scenario-card__buttons">
          <button type="button" className="play-btn" disabled={busy || connectionState !== "connected"} onClick={() => void play()}>
            {busy ? "Starting…" : "Play"}
          </button>
          {showRetrySingle ? (
            <button
              type="button"
              className="play-btn play-btn--secondary"
              disabled={retryBusy || connectionState !== "connected"}
              onClick={() => void retryFailedStep()}
              title={failedStepIdForRetry ?? undefined}
            >
              {retryBusy ? "Retrying…" : `Retry failed step (${failedStepIdForRetry})`}
            </button>
          ) : null}
          {showRetryAllFailed ? (
            <button
              type="button"
              className="play-btn play-btn--secondary"
              disabled={retryBusy || connectionState !== "connected"}
              onClick={() => void retryAllFailedSteps()}
            >
              {retryBusy ? "Retrying…" : "Retry all failed steps"}
            </button>
          ) : null}
        </div>
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
      {hasRows ? (
        <div className="steps-tree">
          <div className="steps-tree__head">
            <span>Step</span>
            <span>Type</span>
            <span>Status</span>
            <span>Retries</span>
          </div>
          <div className="steps-tree__body">
            {orderedRows.map((row) => (
              <div
                key={row.key}
                className={[
                  "steps-tree__row",
                  row.kind === "group" ? "steps-tree__row--group" : "",
                  row.kind === "step" && row.nodeType === "merge" ? "steps-tree__row--merge" : "",
                ]
                  .filter(Boolean)
                  .join(" ")}
                style={{ "--step-level": String(row.level) } as CSSProperties}
              >
                {row.kind === "group" ? (
                  <>
                    <span className="steps-tree__step">
                      {row.label}
                    </span>
                    <span className="muted">fan_out</span>
                    <span />
                    <span className="muted">-</span>
                  </>
                ) : (
                  <>
                    <span className="steps-tree__step">{row.stepName}</span>
                    <span>{row.nodeType}</span>
                    <span>
                      <StepStatusPill status={row.status} />
                    </span>
                    <span>{row.retryCount}</span>
                  </>
                )}
              </div>
            ))}
          </div>
        </div>
      ) : workflowId ? (
        <p className="muted">Waiting for graph updates…</p>
      ) : null}
    </section>
  );
}

type HierarchyRow =
  | {
      kind: "group";
      key: string;
      label: string;
      level: number;
    }
  | {
      kind: "step";
      key: string;
      level: number;
      nodeId: string;
      stepName: string;
      nodeType: string;
      status: string;
      retryCount: string;
    };

function StepStatusPill(props: { status: string }) {
  const { status } = props;
  const normalized = status.trim().toLowerCase();
  if (!normalized) {
    return null;
  }
  let variant = "step-status-pill step-status-pill--plain";
  if (normalized === "completed") {
    variant = "step-status-pill step-status-pill--completed";
  } else if (normalized === "running") {
    variant = "step-status-pill step-status-pill--running";
  } else if (normalized === "failed") {
    variant = "step-status-pill step-status-pill--failed";
  }
  return <span className={variant}>{status}</span>;
}

function pickFailedStepIdForRetry(graph: GraphState): string | null {
  const rows: { id: string; stepName: string }[] = [];
  for (const node of graph.nodesById.values()) {
    const t = node["type"];
    if (typeof t !== "string" || !STEP_NODE_TYPES.has(t) || node["status"] !== "failed") {
      continue;
    }
    const id = typeof node["nodeId"] === "string" ? node["nodeId"] : null;
    if (!id) {
      continue;
    }
    const stepName = typeof node["stepName"] === "string" ? node["stepName"] : "";
    rows.push({ id, stepName });
  }
  rows.sort((a, b) => {
    if (a.stepName !== b.stepName) {
      return a.stepName.localeCompare(b.stepName);
    }
    return a.id.localeCompare(b.id);
  });
  return rows[0]?.id ?? null;
}

function buildHierarchyRows(graph: GraphState): HierarchyRow[] {
  const stepNodes = Array.from(graph.nodesById.values()).filter((node) => {
    const t = node["type"];
    return typeof t === "string" && STEP_NODE_TYPES.has(t);
  });

  if (stepNodes.length === 0) {
    return [];
  }

  const stepNodeIds = new Set(
    stepNodes
      .map((node) => (typeof node["nodeId"] === "string" ? node["nodeId"] : null))
      .filter((id): id is string => id !== null),
  );

  const childStepIdsByParent = new Map<string, string[]>();
  for (const [parentId, children] of graph.childrenByParent) {
    if (!stepNodeIds.has(parentId)) {
      continue;
    }
    const childStepIds = Array.from(children).filter((childId) => stepNodeIds.has(childId));
    if (childStepIds.length > 0) {
      childStepIdsByParent.set(parentId, childStepIds);
    }
  }

  const roots = stepNodes.filter((node) => {
    const nodeId = typeof node["nodeId"] === "string" ? node["nodeId"] : null;
    if (!nodeId) {
      return false;
    }
    const parents = graph.parentsByChild.get(nodeId);
    if (!parents || parents.size === 0) {
      return true;
    }
    for (const parentId of parents) {
      if (stepNodeIds.has(parentId)) {
        return false;
      }
    }
    return true;
  });

  const rootsOrdered = roots.sort(sortNodes);
  const rows: HierarchyRow[] = [];
  const visited = new Set<string>();

  for (const root of rootsOrdered) {
    traverseNode(root, 0, graph, childStepIdsByParent, rows, visited, new Set());
  }

  const remainingNodes = stepNodes
    .filter((node) => typeof node["nodeId"] === "string" && !visited.has(node["nodeId"] as string))
    .sort(sortNodes);
  for (const node of remainingNodes) {
    traverseNode(node, 0, graph, childStepIdsByParent, rows, visited, new Set());
  }

  return rows;
}

function traverseNode(
  node: Record<string, unknown>,
  level: number,
  graph: GraphState,
  childStepIdsByParent: Map<string, string[]>,
  rows: HierarchyRow[],
  visited: Set<string>,
  blockedNodeIds: Set<string>,
): void {
  const nodeId = typeof node["nodeId"] === "string" ? node["nodeId"] : null;
  if (!nodeId || visited.has(nodeId) || blockedNodeIds.has(nodeId)) {
    return;
  }
  visited.add(nodeId);

  rows.push({
    kind: "step",
    key: nodeId,
    level,
    nodeId,
    stepName: String(node["stepName"] ?? nodeId),
    nodeType: String(node["type"] ?? "serial"),
    status: String(node["status"] ?? ""),
    retryCount: String(node["retryCount"] ?? "0"),
  });

  const childIds = childStepIdsByParent.get(nodeId) ?? [];
  if (childIds.length === 0) {
    return;
  }

  const edgeTypeToChild = new Map<string, Set<string>>();
  for (const edge of graph.edges) {
    if (edge.from !== nodeId) {
      continue;
    }
    const childSet = edgeTypeToChild.get(edge.type) ?? new Set<string>();
    childSet.add(edge.to);
    edgeTypeToChild.set(edge.type, childSet);
  }

  const fanOutToChildIds = edgeTypeToChild.get("fan_out") ?? new Set<string>();
  const fanInToChildIds = edgeTypeToChild.get("fan_in") ?? new Set<string>();

  const fanOutChildIds = childIds.filter((childId) =>
    fanOutToChildIds.has(childId),
  );
  const serialChildIds = childIds.filter((childId) => !fanOutToChildIds.has(childId) && !fanInToChildIds.has(childId));

  const serialChildren = serialChildIds
    .filter((childId) => !blockedNodeIds.has(childId))
    .map((childId) => graph.nodesById.get(childId))
    .filter((child): child is Record<string, unknown> => Boolean(child))
    .sort(sortNodes);
  for (const child of serialChildren) {
    traverseNode(child, level + 1, graph, childStepIdsByParent, rows, visited, blockedNodeIds);
  }

  const fanOutChildren = fanOutChildIds
    .filter((childId) => !blockedNodeIds.has(childId))
    .map((childId) => graph.nodesById.get(childId))
    .filter((child): child is Record<string, unknown> => Boolean(child))
    .sort(sortNodes);

  const deferredMergeIds = new Set<string>();

  // Defer shared merge nodes until all fan-out branches (and their serial descendants) render.
  const branchDescendants = new Map<string, Set<string>>();
  const allBranchDescendants = new Set<string>();

  for (const branch of fanOutChildren) {
    const branchId = typeof branch["nodeId"] === "string" ? branch["nodeId"] : null;
    if (!branchId) {
      continue;
    }
    const descendants = collectDescendantStepIds(branchId, childStepIdsByParent, blockedNodeIds);
    descendants.add(branchId);
    branchDescendants.set(branchId, descendants);
    for (const id of descendants) {
      allBranchDescendants.add(id);
    }
  }

  for (const descendantId of allBranchDescendants) {
    const candidate = graph.nodesById.get(descendantId);
    if (!candidate || candidate["type"] !== "merge") {
      continue;
    }

    const parentIds = Array.isArray(candidate["parentIds"])
      ? candidate["parentIds"].filter((id): id is string => typeof id === "string")
      : [];

    if (parentIds.length < 2 || !parentIds.every((parentId) => allBranchDescendants.has(parentId))) {
      continue;
    }

    const hasParentFromEveryBranch = Array.from(branchDescendants.values()).every((descendants) =>
      parentIds.some((parentId) => descendants.has(parentId)),
    );

    if (hasParentFromEveryBranch) {
      const candidateId = typeof candidate["nodeId"] === "string" ? candidate["nodeId"] : null;
      if (candidateId) {
        deferredMergeIds.add(candidateId);
      }
    }
  }

  const branchBlocked = new Set([...blockedNodeIds, ...deferredMergeIds]);

  if (fanOutChildren.length > 0) {
    rows.push({
      kind: "group",
      key: `${nodeId}:parallel`,
      label: "parallel branches",
      level: level + 1,
    });
  }

  for (const child of fanOutChildren) {
    traverseNode(child, level + 2, graph, childStepIdsByParent, rows, visited, branchBlocked);
  }

  const deferredMerges = Array.from(deferredMergeIds)
    .map((nodeId) => graph.nodesById.get(nodeId))
    .filter((mergeNode): mergeNode is Record<string, unknown> => Boolean(mergeNode))
    .sort(sortNodes);
  for (const mergeNode of deferredMerges) {
    traverseNode(mergeNode, level + 1, graph, childStepIdsByParent, rows, visited, blockedNodeIds);
  }

  const fanInChildren = childIds
    .filter((childId) => fanInToChildIds.has(childId))
    .filter((childId) => !blockedNodeIds.has(childId) && !deferredMergeIds.has(childId))
    .map((childId) => graph.nodesById.get(childId))
    .filter((child): child is Record<string, unknown> => Boolean(child))
    .sort(sortNodes);

  for (const child of fanInChildren) {
    traverseNode(child, level + 1, graph, childStepIdsByParent, rows, visited, blockedNodeIds);
  }
}

function sortNodes(a: Record<string, unknown>, b: Record<string, unknown>): number {
  const aInserted = typeof a["insertedAt"] === "string" ? a["insertedAt"] : "";
  const bInserted = typeof b["insertedAt"] === "string" ? b["insertedAt"] : "";
  if (aInserted !== bInserted) {
    return aInserted.localeCompare(bInserted);
  }

  const aStepName = typeof a["stepName"] === "string" ? a["stepName"] : "";
  const bStepName = typeof b["stepName"] === "string" ? b["stepName"] : "";
  if (aStepName !== bStepName) {
    return aStepName.localeCompare(bStepName);
  }

  const aId = typeof a["nodeId"] === "string" ? a["nodeId"] : "";
  const bId = typeof b["nodeId"] === "string" ? b["nodeId"] : "";
  return aId.localeCompare(bId);
}

function collectDescendantStepIds(
  startId: string,
  childStepIdsByParent: Map<string, string[]>,
  blockedNodeIds: Set<string>,
): Set<string> {
  const seen = new Set<string>();
  const stack = [...(childStepIdsByParent.get(startId) ?? [])];

  while (stack.length > 0) {
    const current = stack.pop();
    if (!current || seen.has(current) || blockedNodeIds.has(current)) {
      continue;
    }
    seen.add(current);
    const children = childStepIdsByParent.get(current) ?? [];
    for (const child of children) {
      stack.push(child);
    }
  }

  return seen;
}
