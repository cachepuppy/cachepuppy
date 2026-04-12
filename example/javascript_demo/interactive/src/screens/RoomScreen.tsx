import { useEffect, useRef, useState } from "react";
import { TOPIC } from "../constants";
import type { DemoSession, StickyNote } from "../types";
import { notesFromState } from "../types";

interface RoomScreenProps {
  session: DemoSession;
  onLeave: () => void;
}

type PeerCursor = { xPct: number; yPct: number; colour: string };

function clamp01(n: number): number {
  return Math.min(1, Math.max(0, n));
}

function parsePeerPayload(
  payload: unknown,
): Pick<PeerCursor, "xPct" | "yPct" | "colour"> | null {
  if (!payload || typeof payload !== "object" || Array.isArray(payload)) {
    return null;
  }
  const o = payload as Record<string, unknown>;
  const xPct =
    typeof o.xPct === "number" && Number.isFinite(o.xPct)
      ? clamp01(o.xPct)
      : null;
  const yPct =
    typeof o.yPct === "number" && Number.isFinite(o.yPct)
      ? clamp01(o.yPct)
      : null;
  const colour = typeof o.colour === "string" ? o.colour : null;
  if (xPct === null || yPct === null || colour === null) {
    return null;
  }
  return { xPct, yPct, colour };
}

export function RoomScreen({ session, onLeave }: RoomScreenProps) {
  const { client, clientId, userName, colour } = session;

  const boardRef = useRef<HTMLElement | null>(null);
  const [notes, setNotes] = useState<StickyNote[]>([]);
  const [howManyPeople, setHowManyPeople] = useState(0);
  const [peerCursors, setPeerCursors] = useState<Record<string, PeerCursor>>(
    {},
  );
  const [draft, setDraft] = useState("");
  const [saving, setSaving] = useState(false);

  /**
   * Wire the SDK to this screen. One topic = one shared room on the server.
   * Order matters: headcount listener first, then join (with publish handler), then notes.
   */
  useEffect(() => {
    let isCurrent = true;
    let cleanupPresence: (() => void) | undefined;
    let cleanupSub: (() => void) | undefined;
    let cleanupUpdates: (() => void) | undefined;
    let cleanupBoardListeners: (() => void) | undefined;

    const start = async () => {
      try {
        //Set up presence listeners to update in realtime how many are in channel
        cleanupPresence = client.onPresenceChange(TOPIC, ({ clientCount }) => {
          if (isCurrent) setHowManyPeople(clientCount);
        });

        //Subscribe tp topics
        cleanupSub = await client.subscribe(TOPIC, (message) => {
          if (!isCurrent) {
            return;
          }

          const sender =
            message.meta && typeof message.meta.clientId === "string"
              ? message.meta.clientId
              : null;
          if (!sender || sender === clientId) {
            return;
          }

          if (message.event === "cursor_left") {
            setPeerCursors((prev) => {
              if (!(sender in prev)) {
                return prev;
              }
              const next = { ...prev };
              delete next[sender];
              return next;
            });
            return;
          }

          if (message.event !== "cursor_tracked") {
            return;
          }

          const parsed = parsePeerPayload(message.payload);
          if (!parsed) {
            return;
          }
          setPeerCursors((prev) => ({ ...prev, [sender]: parsed }));
        });
        if (!isCurrent) {
          cleanupSub();
          return;
        }

        //Refresh headcount and topic state for new joiners
        const headcount = await client.clientCount(TOPIC);
        if (isCurrent) setHowManyPeople(headcount);

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
          return;
        }

        const el = boardRef.current;
        if (el) {
          const last = { xPct: 0, yPct: 0 };
          let rafId = 0;
          let scheduled = false;

          const flushMove = () => {
            scheduled = false;
            rafId = 0;
            if (!isCurrent) {
              return;
            }
            void client.publish(TOPIC, "cursor_tracked", {
              xPct: last.xPct,
              yPct: last.yPct,
              colour,
            });
          };

          const onMove = (e: MouseEvent) => {
            if (!isCurrent) {
              return;
            }
            const r = el.getBoundingClientRect();
            if (r.width <= 0 || r.height <= 0) {
              return;
            }
            last.xPct = clamp01((e.clientX - r.left) / r.width);
            last.yPct = clamp01((e.clientY - r.top) / r.height);
            if (!scheduled) {
              scheduled = true;
              rafId = requestAnimationFrame(flushMove);
            }
          };

          const onLeaveBoard = () => {
            if (rafId !== 0) {
              cancelAnimationFrame(rafId);
              rafId = 0;
              scheduled = false;
            }
          };

          el.addEventListener("mousemove", onMove);
          el.addEventListener("mouseleave", onLeaveBoard);

          cleanupBoardListeners = () => {
            onLeaveBoard();
            el.removeEventListener("mousemove", onMove);
            el.removeEventListener("mouseleave", onLeaveBoard);
          };
        }
      } catch {
        cleanupPresence?.();
        cleanupSub?.();
        cleanupUpdates?.();
        cleanupBoardListeners?.();
      }
    };

    void start();

    return () => {
      isCurrent = false;
      cleanupBoardListeners?.();
      cleanupPresence?.();
      cleanupSub?.();
      cleanupUpdates?.();
    };
  }, [client, clientId, colour]);

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
              <li
                key={n.id}
                className="sticky"
                style={{ borderTopColor: n.colour }}
              >
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
        <button
          type="submit"
          className="btn primary"
          disabled={saving || !draft.trim()}
        >
          {saving ? "Saving…" : "Add note"}
        </button>
      </form>
    </div>
  );
}
