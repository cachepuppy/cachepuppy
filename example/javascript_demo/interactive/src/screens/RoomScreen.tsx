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
  const [showInsertModal, setShowInsertModal] = useState(false);
  const [showGetModal, setShowGetModal] = useState(false);
  const [insertTable, setInsertTable] = useState("");
  const [insertKey, setInsertKey] = useState("");
  const [insertData, setInsertData] = useState("");
  const [insertBusy, setInsertBusy] = useState(false);
  const [insertResult, setInsertResult] = useState<string | null>(null);
  const [insertError, setInsertError] = useState<string | null>(null);
  const [getTable, setGetTable] = useState("");
  const [getKey, setGetKey] = useState("");
  const [getBusy, setGetBusy] = useState(false);
  const [getResult, setGetResult] = useState<string | null>(null);
  const [getError, setGetError] = useState<string | null>(null);

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

  async function submitInsertData(e: React.FormEvent) {
    e.preventDefault();
    const table = insertTable.trim();
    const key = insertKey.trim();

    if (!table || !key) {
      setInsertError("Table and key are required.");
      setInsertResult(null);
      return;
    }

    let parsed: unknown;
    try {
      parsed = JSON.parse(insertData);
    } catch {
      setInsertError("Data must be valid JSON.");
      setInsertResult(null);
      return;
    }

    setInsertBusy(true);
    setInsertError(null);
    setInsertResult(null);
    try {
      const value = await client.setData(table, key, parsed);
      setInsertResult(JSON.stringify(value, null, 2));
    } catch {
      setInsertError("Could not insert data.");
    } finally {
      setInsertBusy(false);
    }
  }

  async function submitGetData(e: React.FormEvent) {
    e.preventDefault();
    const table = getTable.trim();
    const key = getKey.trim();

    if (!table || !key) {
      setGetError("Table and key are required.");
      setGetResult(null);
      return;
    }

    setGetBusy(true);
    setGetError(null);
    setGetResult(null);
    try {
      const value = await client.getData(table, key);
      setGetResult(JSON.stringify(value, null, 2));
    } catch {
      setGetError("Could not fetch data.");
    } finally {
      setGetBusy(false);
    }
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
        <div className="modal-backdrop">
          <div className="modal card">
            <h2>Insert data</h2>
            <form onSubmit={(e) => void submitInsertData(e)} className="modal-form">
              <label className="field">
                <span>Table name</span>
                <input
                  type="text"
                  value={insertTable}
                  onChange={(e) => setInsertTable(e.target.value)}
                  placeholder="users"
                  disabled={insertBusy}
                />
              </label>
              <label className="field">
                <span>Key name</span>
                <input
                  type="text"
                  value={insertKey}
                  onChange={(e) => setInsertKey(e.target.value)}
                  placeholder="user_123"
                  disabled={insertBusy}
                />
              </label>
              <label className="field">
                <span>Actual data (JSON)</span>
                <textarea
                  value={insertData}
                  onChange={(e) => setInsertData(e.target.value)}
                  placeholder='{"name":"Alice","role":"admin","active":true}'
                  rows={5}
                  disabled={insertBusy}
                />
              </label>
              {insertError ? <p className="error">{insertError}</p> : null}
              {insertResult ? <pre className="result-block">{insertResult}</pre> : null}
              <div className="row-actions">
                <button type="submit" className="btn primary" disabled={insertBusy}>
                  {insertBusy ? "Inserting..." : "Insert"}
                </button>
                <button type="button" className="btn" onClick={() => setShowInsertModal(false)} disabled={insertBusy}>
                  Close
                </button>
              </div>
            </form>
          </div>
        </div>
      ) : null}

      {showGetModal ? (
        <div className="modal-backdrop">
          <div className="modal card">
            <h2>Get data</h2>
            <form onSubmit={(e) => void submitGetData(e)} className="modal-form">
              <label className="field">
                <span>Table name</span>
                <input
                  type="text"
                  value={getTable}
                  onChange={(e) => setGetTable(e.target.value)}
                  placeholder="users"
                  disabled={getBusy}
                />
              </label>
              <label className="field">
                <span>Key name</span>
                <input
                  type="text"
                  value={getKey}
                  onChange={(e) => setGetKey(e.target.value)}
                  placeholder="user_123"
                  disabled={getBusy}
                />
              </label>
              {getError ? <p className="error">{getError}</p> : null}
              {getResult ? <pre className="result-block">{getResult}</pre> : null}
              <div className="row-actions">
                <button type="submit" className="btn primary" disabled={getBusy}>
                  {getBusy ? "Fetching..." : "Get"}
                </button>
                <button type="button" className="btn" onClick={() => setShowGetModal(false)} disabled={getBusy}>
                  Close
                </button>
              </div>
            </form>
          </div>
        </div>
      ) : null}
    </div>
  );
}
