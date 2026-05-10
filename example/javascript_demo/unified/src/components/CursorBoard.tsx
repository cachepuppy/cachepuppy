"use client";

import { useCallback, useEffect, useRef, useState } from "react";
import {
  useCachePuppyClient,
  useTopic,
} from "@cachepuppy/react";
import type { CachePuppyEnvelope } from "@cachepuppy/core";
import { useSession } from "@/context/SessionContext";
import { attachBoardCursorTracking } from "@/lib/cursorPublish";
import {
  applyTopicMessageToPeerCursors,
  type PeerCursor,
} from "@/lib/cursors";

export function CursorBoard() {
  const { session } = useSession();
  const { client, state } = useCachePuppyClient();
  const boardRef = useRef<HTMLDivElement | null>(null);
  const [peerCursors, setPeerCursors] = useState<Record<string, PeerCursor>>({});

  const enabled = state === "connected" && Boolean(session);
  const topic = session?.room ?? "";

  const onTopicMessage = useCallback(
    (message: CachePuppyEnvelope) => {
      if (!session) return;
      setPeerCursors((prev) =>
        applyTopicMessageToPeerCursors(prev, message, session.clientId),
      );
    },
    [session],
  );

  useTopic(topic, { enabled, onMessage: onTopicMessage });

  useEffect(() => {
    if (!enabled || !session) return;
    const el = boardRef.current;
    if (!el) return;
    return attachBoardCursorTracking(el, {
      isActive: () => true,
      publish: (xPct, yPct) => {
        void client.publish(topic, "cursor_tracked", {
          xPct,
          yPct,
          colour: session.colour,
          userName: session.userName,
        });
      },
    });
  }, [client, enabled, session, topic]);

  // Announce departure when the user leaves the realtime page so peers can
  // drop the stale dot.
  useEffect(() => {
    if (!enabled) return;
    return () => {
      void client.publish(topic, "cursor_left", {}).catch(() => {
        /* channel may already be torn down */
      });
    };
  }, [client, enabled, topic]);

  if (!session) return null;

  return (
    <div
      ref={boardRef}
      className="relative h-[60vh] min-h-[420px] w-full overflow-hidden rounded-xl border border-[var(--color-border)] bg-[var(--color-subtle)]"
    >
      {Object.entries(peerCursors).map(([id, c]) => (
        <div
          key={id}
          className="pointer-events-none absolute -translate-x-1/2 -translate-y-1/2"
          style={{ left: `${c.xPct * 100}%`, top: `${c.yPct * 100}%` }}
        >
          <div
            className="size-3 rounded-full border-2 border-white shadow"
            style={{ backgroundColor: c.colour }}
            aria-hidden
          />
          {c.userName ? (
            <div
              className="mt-1 inline-block rounded-md px-1.5 py-0.5 text-[11px] font-medium text-white"
              style={{ backgroundColor: c.colour }}
            >
              {c.userName}
            </div>
          ) : null}
        </div>
      ))}

      {Object.keys(peerCursors).length === 0 ? (
        <div className="pointer-events-none absolute inset-0 flex items-center justify-center text-center text-sm text-[var(--color-muted-fg)]">
          <div>
            <p>Move your mouse over this board to broadcast a cursor.</p>
            <p className="mt-1">Open this page in another window to see peers.</p>
          </div>
        </div>
      ) : null}
    </div>
  );
}
