import { useEffect, useState } from "react";
import { TOPIC } from "../constants";
import type { DemoSession, StickyNote } from "../types";
import { notesFromState } from "../types";

interface RoomScreenProps {
  session: DemoSession;
  onLeave: () => void;
}

export function RoomScreen({ session, onLeave }: RoomScreenProps) {
  const { client, userName, colour } = session;

  const [notes, setNotes] = useState<StickyNote[]>([]);
  const [howManyPeople, setHowManyPeople] = useState(0);
  const [draft, setDraft] = useState("");
  const [saving, setSaving] = useState(false);

  /**
   * Wire the SDK to this screen. One topic = one shared room on the server.
   * Order matters: headcount listener first, then join, then read notes, then live updates.
   * subscribe’s second arg is for publish events; this demo doesn’t use those → empty fn.
   */
  useEffect(() => {
    let isCurrent = true;
    let cleanupPresence: (() => void) | undefined;
    let cleanupSub: (() => void) | undefined;
    let cleanupUpdates: (() => void) | undefined;

    const start = async () => {
      try {
        cleanupPresence = client.onPresenceChange(TOPIC, ({ clientCount }) => {
          if (isCurrent) setHowManyPeople(clientCount);
        });

        cleanupSub = await client.subscribe(TOPIC, () => {});
        if (!isCurrent) {
          cleanupSub();
          return;
        }

        // Ask the server directly (same as EventChannel "client_count"). Stays correct even if
        // Phoenix→JS presence sync is late or React Strict Mode replays this effect once.
        const headcount = await client.clientCount(TOPIC);
        if (isCurrent) setHowManyPeople(headcount);

        // Topic state can fail (e.g. cold topic); don’t throw — that would hit the outer catch
        // and remove the presence listener while you’re still in the room.
        let data: Record<string, unknown> = {};
        try {
          data = await client.getTopicState(TOPIC);
        } catch {
          /* empty notes */
        }
        if (isCurrent) setNotes(notesFromState(data));

        cleanupUpdates = await client.onStateUpdated(TOPIC, (next) => {
          if (isCurrent) setNotes(notesFromState(next));
        });
        if (!isCurrent) {
          cleanupUpdates();
        }
      } catch {
        cleanupPresence?.();
        cleanupSub?.();
        cleanupUpdates?.();
      }
    };

    void start();

    // User left this screen — turn off listeners / leave the topic (whatever we set up).
    return () => {
      isCurrent = false;
      cleanupPresence?.();
      cleanupSub?.();
      cleanupUpdates?.();
    };
  }, [client]);

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

      <section className="notes-board card">
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
