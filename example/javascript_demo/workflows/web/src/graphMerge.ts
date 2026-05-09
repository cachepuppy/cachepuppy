export type GraphEdge = {
  from: string;
  to: string;
  type: string;
};

export type GraphState = {
  nodesById: Map<string, Record<string, unknown>>;
  edges: GraphEdge[];
  childrenByParent: Map<string, Set<string>>;
  parentsByChild: Map<string, Set<string>>;
};

export function createEmptyGraphState(): GraphState {
  return {
    nodesById: new Map(),
    edges: [],
    childrenByParent: new Map(),
    parentsByChild: new Map(),
  };
}

export function mergeGraphDiff(prev: GraphState, diff: Record<string, unknown>): GraphState {
  const nodesById = new Map(prev.nodesById);
  const added = diff["addedNodes"];
  const changed = diff["changedNodes"];
  const addedEdges = diff["addedEdges"];
  const edgeKeySet = new Set(prev.edges.map((edge) => `${edge.from}->${edge.to}:${edge.type}`));
  const edges = [...prev.edges];

  if (Array.isArray(added)) {
    for (const node of added) {
      if (
        node &&
        typeof node === "object" &&
        !Array.isArray(node) &&
        typeof (node as Record<string, unknown>)["nodeId"] === "string"
      ) {
        const rec = node as Record<string, unknown>;
        nodesById.set(rec["nodeId"] as string, { ...rec });
      }
    }
  }

  if (Array.isArray(changed)) {
    for (const node of changed) {
      if (
        node &&
        typeof node === "object" &&
        !Array.isArray(node) &&
        typeof (node as Record<string, unknown>)["nodeId"] === "string"
      ) {
        const rec = node as Record<string, unknown>;
        const id = rec["nodeId"] as string;
        const old = nodesById.get(id) ?? {};
        nodesById.set(id, { ...old, ...rec });
      }
    }
  }

  if (Array.isArray(addedEdges)) {
    for (const edge of addedEdges) {
      if (
        edge &&
        typeof edge === "object" &&
        !Array.isArray(edge) &&
        typeof (edge as Record<string, unknown>)["from"] === "string" &&
        typeof (edge as Record<string, unknown>)["to"] === "string" &&
        typeof (edge as Record<string, unknown>)["type"] === "string"
      ) {
        const rec = edge as Record<string, unknown>;
        const parsed = {
          from: rec["from"] as string,
          to: rec["to"] as string,
          type: rec["type"] as string,
        };
        const key = `${parsed.from}->${parsed.to}:${parsed.type}`;
        if (!edgeKeySet.has(key)) {
          edgeKeySet.add(key);
          edges.push(parsed);
        }
      }
    }
  }

  const childrenByParent = new Map<string, Set<string>>();
  const parentsByChild = new Map<string, Set<string>>();

  for (const edge of edges) {
    const children = childrenByParent.get(edge.from) ?? new Set<string>();
    children.add(edge.to);
    childrenByParent.set(edge.from, children);

    const parents = parentsByChild.get(edge.to) ?? new Set<string>();
    parents.add(edge.from);
    parentsByChild.set(edge.to, parents);
  }

  return {
    nodesById,
    edges,
    childrenByParent,
    parentsByChild,
  };
}

/** Graph node `type` values that represent executable steps in the demo UI */
export const STEP_NODE_TYPES = new Set(["serial", "parallel_branch", "merge"]);
