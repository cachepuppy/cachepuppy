/**
 * Derive HTTP origin from a Phoenix websocket URL (e.g. strip `/socket/websocket`, ws→http).
 */
export function toHttpBaseUrl(url: string): string {
  const parsed = new URL(url);
  if (parsed.protocol === "ws:") parsed.protocol = "http:";
  if (parsed.protocol === "wss:") parsed.protocol = "https:";

  if (parsed.pathname.endsWith("/socket/websocket")) {
    parsed.pathname = parsed.pathname.slice(0, -"/socket/websocket".length) || "/";
  } else if (parsed.pathname.endsWith("/socket")) {
    parsed.pathname = parsed.pathname.slice(0, -"/socket".length) || "/";
  }

  return parsed.toString().replace(/\/$/, "");
}
