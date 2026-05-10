import type { CachePuppyEnvelope } from "@cachepuppy/core";

export type PeerCursor = {
  xPct: number;
  yPct: number;
  colour: string;
  userName: string;
};

export function clamp01(n: number): number {
  return Math.min(1, Math.max(0, n));
}

export function parseCursorTrackedPayload(
  payload: unknown,
): PeerCursor | null {
  if (!payload || typeof payload !== "object" || Array.isArray(payload)) {
    return null;
  }
  const o = payload as Record<string, unknown>;
  const xPct =
    typeof o.xPct === "number" && Number.isFinite(o.xPct) ? clamp01(o.xPct) : null;
  const yPct =
    typeof o.yPct === "number" && Number.isFinite(o.yPct) ? clamp01(o.yPct) : null;
  const colour = typeof o.colour === "string" ? o.colour : null;
  const userName = typeof o.userName === "string" ? o.userName : "";
  if (xPct === null || yPct === null || colour === null) {
    return null;
  }
  return { xPct, yPct, colour, userName };
}

export function applyTopicMessageToPeerCursors(
  prev: Record<string, PeerCursor>,
  message: CachePuppyEnvelope,
  selfClientId: string,
): Record<string, PeerCursor> {
  const sender =
    message.meta && typeof message.meta.clientId === "string"
      ? (message.meta.clientId as string)
      : null;
  if (!sender || sender === selfClientId) {
    return prev;
  }

  if (message.event === "cursor_left") {
    if (!(sender in prev)) {
      return prev;
    }
    const next = { ...prev };
    delete next[sender];
    return next;
  }

  if (message.event !== "cursor_tracked") {
    return prev;
  }

  const parsed = parseCursorTrackedPayload(message.payload);
  if (!parsed) {
    return prev;
  }
  return { ...prev, [sender]: parsed };
}
