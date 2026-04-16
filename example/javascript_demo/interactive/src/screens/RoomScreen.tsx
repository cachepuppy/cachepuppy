import { useCallback, useEffect, useRef, useState } from "react";
import { useCachePuppyClient, usePresence, useTopic, useTopicState } from "@cachepuppy/react";
import type { CachePuppyEnvelope } from "cachepuppy-js-sdk";
import { TOPIC } from "../constants";
import { GetDataModal } from "./components/GetDataModal";
import { InsertDataModal } from "./components/InsertDataModal";
import type { DemoSession, StickyNote } from "../types";
import { notesFromState } from "../types";
import { attachBoardCursorTracking } from "../utils/boardCursorPublish";
import { applyTopicMessageToPeerCursors, type PeerCursor } from "../utils/cursorTopicUtils";

interface RoomScreenProps {
  session: DemoSession;
  onLeave: () => void;
}

export function RoomScreen({ session, onLeave }: RoomScreenProps) {
  const { clientId, userName, colour } = session;
  const { client, state: connectionState, error: connectionError, destroy } = useCachePuppyClient();

  const boardRef = useRef<HTMLElement | null>(null);
  const [peerCursors, setPeerCursors] = useState<Record<string, PeerCursor>>({});
  const [draft, setDraft] = useState("");
  const [saving, setSaving] = useState(false);
  const [showInsertModal, setShowInsertModal] = useState(false);
  const [showGetModal, setShowGetModal] = useState(false);
  const topicEnabled = connectionState === "connected";

  const onTopicMessage = useCallback(
    (message: CachePuppyEnvelope) => {
      setPeerCursors((prev) => applyTopicMessageToPeerCursors(prev, message, clientId));
    },
    [clientId],
  );

  useTopic(TOPIC, { enabled: topicEnabled, onMessage: onTopicMessage });
  const { clientCount } = usePresence(TOPIC, topicEnabled);
  const { state: topicState } = useTopicState(TOPIC, topicEnabled);
  const notes = notesFromState(topicState);

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
        void client.publish(TOPIC, "cursor_tracked", { xPct, yPct, colour });
      },
    });
  }, [client, colour, topicEnabled]);

  async function postNote(e: React.FormEvent) {
    e.preventDefault();
    const text = draft.trim();
    if (!text) return;

    setSaving(true);
    try {
      const latest = await client.getTopicState(TOPIC);
      const next: StickyNote = {
        id: crypto.randomUUID(),
        userName,
        colour,
        text,
      };
      await client.setTopicState(TOPIC, {
        notes: [...notesFromState(latest), next],
      });
      setDraft("");
    } finally {
      setSaving(false);
    }
  }

  async function leave() {
    try {
      await client.publish(TOPIC, "cursor_left", {});
    } catch {
      /* channel may already be gone; still tear down */
    }
    await destroy();
    onLeave();
  }

  return (
    <div className="screen screen--room">
      <header className="room-header">
        <div>
          <h1>Topic: Sticky Notes Room</h1>
          <p className="muted">
            Signed in as <strong>{userName}</strong> · {clientCount} in room · connection: {connectionState}
          </p>
          {connectionError ? <p className="error">Connection error: {connectionError.message}</p> : null}
        </div>
        <button type="button" className="btn" onClick={() => void leave()}>
          Leave
        </button>
      </header>

      <section className="card row-actions">
        <button type="button" className="btn" onClick={() => setShowInsertModal(true)}>
          Insert data
        </button>
        <button type="button" className="btn" onClick={() => setShowGetModal(true)}>
          Get data
        </button>
      </section>

      <section ref={boardRef} className="notes-board card">
        {Object.entries(peerCursors).map(([id, c]) => (
          <span
            key={id}
            className="peer-cursor"
            style={{
              left: `${c.xPct * 100}%`,
              top: `${c.yPct * 100}%`,
              backgroundColor: c.colour,
            }}
            aria-hidden
          />
        ))}
        {notes.length === 0 ? (
          <p className="muted">No notes yet — add one below.</p>
        ) : (
          <ul className="notes-list">
            {notes.map((n) => (
              <li key={n.id} className="sticky" style={{ borderTopColor: n.colour }}>
                <p className="sticky__text">{n.text}</p>
                <span className="sticky__author" style={{ color: n.colour }}>
                  {n.userName}
                </span>
              </li>
            ))}
          </ul>
        )}
      </section>

      <form className="card" onSubmit={(e) => void postNote(e)}>
        <label className="field">
          <span>New note</span>
          <textarea
            value={draft}
            onChange={(e) => setDraft(e.target.value)}
            rows={3}
            placeholder="Adds a note for everyone (setTopicState on the server)"
            disabled={saving}
          />
        </label>
        <button type="submit" className="btn primary" disabled={saving || !draft.trim()}>
          {saving ? "Saving…" : "Add note"}
        </button>
      </form>

      {showInsertModal ? (
        <InsertDataModal
          onClose={() => setShowInsertModal(false)}
          onSubmit={(table, key, value) => client.setData(table, key, value)}
        />
      ) : null}

      {showGetModal ? (
        <GetDataModal
          onClose={() => setShowGetModal(false)}
          onSubmit={(table, key) => client.getData(table, key)}
        />
      ) : null}
    </div>
  );
}
