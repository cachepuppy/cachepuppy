/**
 * Centralised env access for both server and browser code.
 *
 * Server values are read lazily so missing values surface only when actually
 * needed (e.g. workflow API routes), not at module import time.
 */

const stripTrailingSlash = (value: string) => value.replace(/\/$/, "");

export function publicWsUrl(): string {
  return process.env.NEXT_PUBLIC_WS_URL ?? "ws://127.0.0.1:4000/socket/websocket";
}

export function cachepuppyApiBase(): string {
  return stripTrailingSlash(
    process.env.CACHEPUPPY_API_BASE ?? "http://127.0.0.1:4000",
  );
}

export function cachepuppySocketUrl(): string {
  return `${cachepuppyApiBase().replace(/^http/i, "ws")}/socket/websocket`;
}

export function workflowDemoPublicBase(): string {
  return stripTrailingSlash(
    process.env.WORKFLOW_DEMO_PUBLIC_URL ?? "http://127.0.0.1:3000",
  );
}

export function workflowStepDelayMs(): number {
  const raw = Number(process.env.WORKFLOW_STEP_DELAY_MS ?? 5000);
  return Number.isFinite(raw) && raw >= 0 ? raw : 5000;
}
