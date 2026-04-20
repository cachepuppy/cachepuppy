import { toHttpBaseUrl } from "./httpBaseUrl.js";
import type { CacheSetDataOptions, TopicStateResponse } from "./transport/transport.js";
import type { AdminClientOptions, TopicPresenceResponse } from "./types.js";

const API_PREFIX = "/api/server/v1";

export class CachePuppyAdminClient {
  private readonly serverApiBaseUrl: string;
  private readonly httpBaseUrl: string;
  private readonly authHeaders: Record<string, string>;
  private readonly fetchFn: typeof fetch;

  constructor(private readonly options: AdminClientOptions) {
    this.httpBaseUrl = toHttpBaseUrl(options.url);
    this.serverApiBaseUrl = `${this.httpBaseUrl}${API_PREFIX}`;
    this.authHeaders = options.authToken ? { authorization: `Bearer ${options.authToken}` } : {};
    this.fetchFn = options.fetchImpl ?? globalThis.fetch.bind(globalThis);
  }

  async setTopicState(topic: string, state: Record<string, unknown>): Promise<Record<string, unknown>> {
    const data = await this.requestJson<{ state?: unknown }>("PUT", topicStatePath(topic), state);
    return asRecord(data.state);
  }

  async getTopicState(topic: string): Promise<Record<string, unknown>> {
    const data = await this.requestJson<{ state?: unknown }>("GET", topicStatePath(topic));
    return asRecord(data.state);
  }

  async getTopicStateWithMeta(topic: string): Promise<TopicStateResponse> {
    const data = await this.requestJson<{ state?: unknown; meta?: unknown }>("GET", topicStatePath(topic));
    const meta = asRecord(data.meta);
    const sourceNode = typeof meta.source_node === "string" ? meta.source_node : undefined;
    const servedByNode = typeof meta.served_by_node === "string" ? meta.served_by_node : undefined;
    return { state: asRecord(data.state), sourceNode, servedByNode };
  }

  async clearTopicState(topic: string): Promise<boolean> {
    const data = await this.requestJson<{ closed?: unknown }>("DELETE", topicResourcePath(topic));
    return data.closed === true;
  }

  async sendTopicMessage(topic: string, args: { event: string; payload?: unknown }): Promise<void> {
    await this.requestJson<Record<string, unknown>>(
      "POST",
      topicMessagesPath(topic),
      { event: args.event, payload: args.payload },
      { okStatuses: [202] },
    );
  }

  async getTopicPresence(topic: string): Promise<TopicPresenceResponse> {
    const data = await this.requestJson<{ client_count?: unknown; presence?: unknown }>(
      "GET",
      topicPresencePath(topic),
    );
    const n = data.client_count;
    const clientCount = typeof n === "number" && Number.isFinite(n) ? Math.floor(n) : 0;
    const presence =
      data.presence && typeof data.presence === "object" && !Array.isArray(data.presence)
        ? (data.presence as Record<string, unknown>)
        : {};
    return { clientCount, presence };
  }

  async setData(table: string, key: string, value: unknown, options?: CacheSetDataOptions): Promise<unknown> {
    const body: Record<string, unknown> = { table, key, value };
    if (typeof options?.ttlMs === "number" && options.ttlMs > 0) {
      body.ttl_ms = options.ttlMs;
    }
    const data = await this.requestJson<{ value?: unknown }>("POST", "/api/cache/setdata", body, {
      useServerApiPrefix: false,
    });
    return data.value;
  }

  async getData(table: string, key: string): Promise<unknown> {
    const data = await this.requestJson<{ value?: unknown }>(
      "POST",
      "/api/cache/getdata",
      { table, key },
      { useServerApiPrefix: false },
    );
    return data.value;
  }

  async deleteData(table: string, key: string): Promise<boolean> {
    const data = await this.requestJson<{ deleted?: unknown }>(
      "POST",
      "/api/cache/deletedata",
      { table, key },
      { useServerApiPrefix: false },
    );
    return data.deleted === true;
  }

  private async requestJson<T>(
    method: string,
    path: string,
    body?: unknown,
    opts?: { okStatuses?: number[]; useServerApiPrefix?: boolean },
  ): Promise<T> {
    const okStatuses = opts?.okStatuses ?? [200];
    const base = opts?.useServerApiPrefix === false ? this.httpBaseUrl : this.serverApiBaseUrl;
    const headers: Record<string, string> = {
      ...this.authHeaders,
      ...(body !== undefined ? { "content-type": "application/json" } : {}),
    };

    const response = await this.fetchFn(`${base}${path}`, {
      method,
      headers,
      body: body !== undefined ? JSON.stringify(body) : undefined,
    });

    if (!okStatuses.includes(response.status)) {
      const detail = await readErrorReason(response);
      throw new Error(`Admin API ${method} ${path} failed (status ${response.status}${detail ? `, reason ${detail}` : ""})`);
    }

    if (response.status === 204 || response.headers.get("content-length") === "0") {
      return {} as T;
    }

    const text = await response.text();
    if (!text) {
      return {} as T;
    }

    return JSON.parse(text) as T;
  }
}

export function createAdminClient(options: AdminClientOptions): CachePuppyAdminClient {
  return new CachePuppyAdminClient(options);
}

function topicResourcePath(topic: string): string {
  return `/topics/${encodeURIComponent(topic)}`;
}

function topicStatePath(topic: string): string {
  return `${topicResourcePath(topic)}/state`;
}

function topicMessagesPath(topic: string): string {
  return `${topicResourcePath(topic)}/messages`;
}

function topicPresencePath(topic: string): string {
  return `${topicResourcePath(topic)}/presence`;
}

function asRecord(value: unknown): Record<string, unknown> {
  if (value && typeof value === "object" && !Array.isArray(value)) {
    return value as Record<string, unknown>;
  }
  return {};
}

async function readErrorReason(response: Response): Promise<string | null> {
  try {
    const payload = (await response.json()) as { reason?: unknown };
    return typeof payload.reason === "string" ? payload.reason : null;
  } catch {
    return null;
  }
}
