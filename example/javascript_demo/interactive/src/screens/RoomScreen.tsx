import { useRef, useState } from "react";
import { TOPIC } from "../constants";
import { useRoomChannel } from "../hooks/useRoomChannel";
import type { DemoSession, StickyNote } from "../types";
import { notesFromState } from "../types";
import type { PeerCursor } from "../utils/cursorTopicUtils";

interface RoomScreenProps {
  session: DemoSession;
  onLeave: () => void;
}

export function RoomScreen({ session, onLeave }: RoomScreenProps) {
  const { client, clientId, userName, colour } = session;

  const boardRef = useRef<HTMLElement | null>(null);
  const [notes, setNotes] = useState<StickyNote[]>([]);
  const [howManyPeople, setHowManyPeople] = useState(0);
  const [peerCursors, setPeerCursors] = useState<Record<string, PeerCursor>>({});
  const [draft, setDraft] = useState("");
  const [saving, setSaving] = useState(false);

  useRoomChannel({
    topic: TOPIC,
    client,
    clientId,
    colour,
    boardRef,
    setHowManyPeople,
    setNotes,
    setPeerCursors,
  });

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
    await client.unsubscribe(TOPIC);
    await client.destroy();
    onLeave();
  }

  return (
    <div className="screen screen--room">
      <header className="room-header">
        <div>
          <h1>Topic: Sticky Notes Room</h1>
          <p className="muted">
            Signed in as <strong>{userName}</strong> · {howManyPeople} in room
          </p>
        </div>
        <button type="button" className="btn" onClick={() => void leave()}>
          Leave
        </button>
      </header>

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
    </div>
  );
}
