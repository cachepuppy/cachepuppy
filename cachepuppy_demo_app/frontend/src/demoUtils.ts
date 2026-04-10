import type { CachePuppyClient } from "cachepuppy_js_sdk";

export type TopicMessage = {
  event?: unknown;
  payload?: unknown;
  meta?: Record<string, unknown>;
};

export function extractNodeIds(message: { meta?: Record<string, unknown> }): {
  sourceNode: string;
  servedByNode: string;
} {
  const sourceNode = message.meta?.source_node;
  const servedByNode = message.meta?.served_by_node;
  return {
    sourceNode:
      typeof sourceNode === "string" ? sourceNode : "unknown_source_node",
    servedByNode:
      typeof servedByNode === "string"
        ? servedByNode
        : "unknown_served_by_node",
  };
}

export function logTopicMessage(user: string, message: TopicMessage): void {
  const ids = extractNodeIds(message);
  console.log(
    `[${user}]`,
    message.event,
    message.payload,
    `source_node=${ids.sourceNode}`,
    `served_by_node=${ids.servedByNode}`,
  );
}

export function logDemoWsChannelNodes(
  entries: Array<{ label: string; client: CachePuppyClient }>,
  topic: string,
): void {
  for (const { label, client } of entries) {
    const meta = client.getChannelJoinMeta(topic);
    const n = meta?.connected_node;
    console.log(
      `[${label}] websocket_channel_node=${typeof n === "string" ? n : "unknown"}`,
    );
  }
}

export async function probeLoadBalancer(apiBase: string): Promise<void> {
  console.log(
    "[demo] HTTP probes via LB (expect mixed node names if multiple backends):",
  );
  for (let i = 0; i < 9; i++) {
    const res = await fetch(`${apiBase}/api/health`);
    const data = (await res.json()) as {
      node?: string;
      cluster_size?: number;
    };
    console.log(
      `  [probe ${i}] node=${data.node ?? "?"} cluster_size=${data.cluster_size ?? "?"}`,
    );
  }
}
