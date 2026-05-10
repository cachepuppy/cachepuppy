"use client";

import Link from "next/link";
import { useRouter } from "next/navigation";
import { useEffect, useMemo, useState, type ReactNode } from "react";
import {
  CachePuppyProvider,
  useCachePuppyClient,
  usePresence,
} from "@cachepuppy/react";
import { useSession } from "@/context/SessionContext";

const WS_URL =
  process.env.NEXT_PUBLIC_WS_URL ?? "ws://127.0.0.1:4000/socket/websocket";

function PresencePill({ topic }: { topic: string }) {
  const { clientCount } = usePresence(topic, true);
  return (
    <span className="inline-flex items-center gap-1.5 rounded-full border border-[var(--color-border)] px-2.5 py-0.5 text-xs font-medium text-[var(--color-muted-fg)]">
      <span className="size-1.5 rounded-full bg-emerald-500" />
      {clientCount} in room
    </span>
  );
}

function RoomChrome({ children }: { children: ReactNode }) {
  const { session, endSession } = useSession();
  const { client, destroy } = useCachePuppyClient();
  const router = useRouter();
  const [leaving, setLeaving] = useState(false);
  if (!session) return null;

  async function leave() {
    if (leaving || !session) return;
    setLeaving(true);
    // Best-effort: announce departure on the room topic so peers drop our
    // realtime cursor immediately, then tear down the websocket so presence
    // updates everywhere.
    try {
      await client.publish(session.room, "cursor_left", {});
    } catch {
      /* channel may already be torn down */
    }
    try {
      await destroy();
    } catch {
      /* socket already closed; continue */
    }
    endSession();
    router.push("/");
  }

  return (
    <div className="flex min-h-screen flex-col">
      <header className="sticky top-0 z-10 flex items-center justify-between gap-4 border-b border-[var(--color-border)] bg-[var(--color-bg)]/85 px-6 py-3 backdrop-blur">
        <div className="flex items-center gap-3">
          <Link
            href="/room"
            className="font-semibold tracking-tight hover:opacity-80"
          >
            CachePuppy
          </Link>
          <span className="text-[var(--color-muted-fg)]">/</span>
          <span className="font-mono text-sm text-[var(--color-muted-fg)]">
            {session.room}
          </span>
          <PresencePill topic={session.room} />
        </div>
        <div className="flex items-center gap-3">
          <span className="flex items-center gap-2 text-sm">
            <span
              className="size-3 rounded-full border border-[var(--color-border)]"
              style={{ backgroundColor: session.colour }}
              aria-hidden
            />
            <span>{session.userName}</span>
          </span>
          <button
            type="button"
            onClick={() => void leave()}
            disabled={leaving}
            className="rounded-md border border-[var(--color-border)] px-3 py-1.5 text-sm font-medium hover:border-[var(--color-border-strong)] disabled:opacity-50"
          >
            {leaving ? "Leaving…" : "Leave"}
          </button>
        </div>
      </header>
      <main className="mx-auto w-full max-w-6xl flex-1 px-6 py-8">
        {children}
      </main>
    </div>
  );
}

export function RoomShell({ children }: { children: ReactNode }) {
  const { session } = useSession();
  const router = useRouter();

  useEffect(() => {
    if (!session) {
      router.replace("/");
    }
  }, [session, router]);

  const clientOptions = useMemo(
    () =>
      session
        ? {
            url: WS_URL,
            transport: "phoenix" as const,
            clientId: session.clientId,
          }
        : null,
    [session],
  );

  if (!session || !clientOptions) {
    return null;
  }

  return (
    <CachePuppyProvider autoConnect options={clientOptions}>
      <RoomChrome>{children}</RoomChrome>
    </CachePuppyProvider>
  );
}
