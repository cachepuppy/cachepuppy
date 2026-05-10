import { createAdminClient, CachePuppyAdminClient } from "@cachepuppy/core";
import { cachepuppySocketUrl } from "./env";

declare global {
  // Reuse the admin client across hot reloads in dev to avoid leaking sockets.
  // eslint-disable-next-line no-var
  var __cachePuppyAdminClient: CachePuppyAdminClient | undefined;
}

export function getAdminClient(): CachePuppyAdminClient {
  if (!globalThis.__cachePuppyAdminClient) {
    globalThis.__cachePuppyAdminClient = createAdminClient({
      url: cachepuppySocketUrl(),
    });
  }
  return globalThis.__cachePuppyAdminClient;
}
