import type { CachePuppyClient } from "cachepuppy-js-sdk";
import { useEffect } from "react";
import type { Dispatch, RefObject, SetStateAction } from "react";
import type { StickyNote } from "../types";
import { notesFromState } from "../types";
import { attachBoardCursorTracking } from "../utils/boardCursorPublish";
import {
  applyTopicMessageToPeerCursors,
  type PeerCursor,
} from "../utils/cursorTopicUtils";

export interface UseRoomChannelParams {
  topic: string;
  client: CachePuppyClient;
  clientId: string;
  colour: string;
  boardRef: RefObject<HTMLElement | null>;
  setHowManyPeople: Dispatch<SetStateAction<number>>;
  setNotes: Dispatch<SetStateAction<StickyNote[]>>;
  setPeerCursors: Dispatch<SetStateAction<Record<string, PeerCursor>>>;
}

/**
 * Joins the topic, wires presence, notes state, peer cursors from publishes, and board pointer tracking.
 * Tear-down order matches a single user leaving: board listeners first, then channel subscriptions.
 */
export function useRoomChannel(params: UseRoomChannelParams): void {
  const {
    topic,
    client,
    clientId,
    colour,
    boardRef,
    setHowManyPeople,
    setNotes,
    setPeerCursors,
  } = params;

  useEffect(() => {
    let cancelled = false;
    const isCurrent = () => !cancelled;

    let cleanupPresence: (() => void) | undefined;
    let cleanupSub: (() => void) | undefined;
    let cleanupUpdates: (() => void) | undefined;
    let cleanupBoard: (() => void) | undefined;

    const runCleanups = () => {
      cleanupBoard?.();
      cleanupPresence?.();
      cleanupSub?.();
      cleanupUpdates?.();
    };

    const run = async () => {
      try {
        cleanupPresence = client.onPresenceChange(topic, ({ clientCount }) => {
          if (isCurrent()) setHowManyPeople(clientCount);
        });

        cleanupSub = await client.subscribe(topic, (message) => {
          if (!isCurrent()) return;
          setPeerCursors((prev) => applyTopicMessageToPeerCursors(prev, message, clientId));
        });

        if (!isCurrent()) {
          cleanupSub();
          return;
        }

        const headcount = await client.clientCount(topic);
        if (isCurrent()) setHowManyPeople(headcount);

        let data: Record<string, unknown> = {};
        try {
          data = await client.getTopicState(topic);
        } catch {
          /* cold topic or error — start with empty notes */
        }
        if (isCurrent()) setNotes(notesFromState(data));

        cleanupUpdates = await client.onStateUpdated(topic, (next) => {
          if (isCurrent()) setNotes(notesFromState(next));
        });

        if (!isCurrent()) {
          cleanupUpdates();
          return;
        }

        const el = boardRef.current;
        if (el) {
          cleanupBoard = attachBoardCursorTracking(el, {
            isActive: isCurrent,
            publish: (xPct, yPct) => {
              void client.publish(topic, "cursor_tracked", { xPct, yPct, colour });
            },
          });
        }
      } catch {
        runCleanups();
      }
    };

    void run();

    return () => {
      cancelled = true;
      runCleanups();
    };
  }, [topic, client, clientId, colour, boardRef, setHowManyPeople, setNotes, setPeerCursors]);
}
