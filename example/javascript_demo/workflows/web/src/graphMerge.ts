export function mergeGraphDiff(
  prev: Map<string, Record<string, unknown>>,
  diff: Record<string, unknown>,
): Map<string, Record<string, unknown>> {
  const next = new Map(prev);
  const added = diff["addedNodes"];
  const changed = diff["changedNodes"];

  if (Array.isArray(added)) {
    for (const node of added) {
      if (
        node &&
        typeof node === "object" &&
        !Array.isArray(node) &&
        typeof (node as Record<string, unknown>)["nodeId"] === "string"
      ) {
        const rec = node as Record<string, unknown>;
        next.set(rec["nodeId"] as string, { ...rec });
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
        const old = next.get(id) ?? {};
        next.set(id, { ...old, ...rec });
      }
    }
  }

  return next;
}

/** Graph node `type` values that represent executable steps in the demo UI */
export const STEP_NODE_TYPES = new Set(["serial", "parallel_branch", "merge", "loop_iteration"]);
