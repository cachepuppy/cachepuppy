import { useCachePuppyClient, usePresence, useTopic, useTopicState } from "@cachepuppy/react";
import { useCallback, useEffect } from "react";
import type { CachePuppyEnvelope } from "cachepuppy-js-sdk";
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
  const { topic, clientId, colour, boardRef, setHowManyPeople, setNotes, setPeerCursors } = params;
  const { client, state: connectionState } = useCachePuppyClient();
  const topicEnabled = connectionState === "connected";

  const onMessage = useCallback((message: CachePuppyEnvelope) => {
    setPeerCursors((prev) => applyTopicMessageToPeerCursors(prev, message, clientId));
  }, [clientId, setPeerCursors]);

  useTopic(topic, { enabled: topicEnabled, onMessage });
  const { clientCount } = usePresence(topic, topicEnabled);
  const { state: topicState } = useTopicState(topic, topicEnabled);

  useEffect(() => {
    setHowManyPeople(clientCount);
  }, [clientCount, setHowManyPeople]);

  useEffect(() => {
    setNotes(notesFromState(topicState));
  }, [setNotes, topicState]);

  useEffect(() => {
    if (!topicEnabled) {
      return;
    }
    const el = boardRef.current;
    if (!el) {
      return;
    }
    return attachBoardCursorTracking(el, {
      isActive: () => true,
      publish: (xPct, yPct) => {
        void client.publish(topic, "cursor_tracked", { xPct, yPct, colour });
      },
    });
  }, [boardRef, client, colour, topic, topicEnabled]);
}
