"use client";

import { useRouter } from "next/navigation";
import { useEffect, useId, useState } from "react";
import { useSession } from "@/context/SessionContext";

const DEFAULT_COLOUR = "#0a0a0a";

export function LoginCard() {
  const router = useRouter();
  const { session, startSession, defaultRoom } = useSession();

  const nameId = useId();
  const colourId = useId();
  const roomId = useId();

  const [userName, setUserName] = useState("");
  const [colour, setColour] = useState(DEFAULT_COLOUR);
  const [room, setRoom] = useState(defaultRoom);
  const [error, setError] = useState<string | null>(null);

  useEffect(() => {
    if (session) {
      router.replace("/room");
    }
  }, [session, router]);

  function handleSubmit(e: React.FormEvent) {
    e.preventDefault();
    const trimmedName = userName.trim();
    const trimmedRoom = room.trim();
    if (!trimmedName) {
      setError("Please enter your name.");
      return;
    }
    if (!trimmedRoom) {
      setError("Please enter a room name.");
      return;
    }
    setError(null);
    startSession({ userName: trimmedName, colour, room: trimmedRoom });
    router.push("/room");
  }

  return (
    <div className="flex min-h-screen items-center justify-center bg-[var(--color-bg)] px-6 py-10">
      <div className="w-full max-w-[400px]">
        <div className="mb-6 text-center">
          <h1 className="text-2xl font-semibold tracking-tight">CachePuppy</h1>
          <p className="mt-1 text-sm text-[var(--color-muted-fg)]">
            Join a room to try caching, realtime, and workflows.
          </p>
        </div>

        <form
          onSubmit={handleSubmit}
          className="space-y-4 rounded-xl border border-[var(--color-border)] bg-[var(--color-bg)] p-6 shadow-[0_1px_0_rgba(0,0,0,0.04)]"
        >
          <div className="space-y-1.5">
            <label htmlFor={nameId} className="text-sm font-medium">
              Name
            </label>
            <input
              id={nameId}
              type="text"
              autoComplete="username"
              value={userName}
              onChange={(e) => setUserName(e.target.value)}
              placeholder="Ada Lovelace"
              className="w-full rounded-md border border-[var(--color-border)] bg-[var(--color-bg)] px-3 py-2 text-sm outline-none focus:border-[var(--color-border-strong)]"
            />
          </div>

          <div className="space-y-1.5">
            <label htmlFor={colourId} className="text-sm font-medium">
              Colour
            </label>
            <div className="flex items-center gap-3">
              <input
                id={colourId}
                type="color"
                value={colour}
                onChange={(e) => setColour(e.target.value)}
                className="size-10 cursor-pointer rounded-md border border-[var(--color-border)] bg-transparent p-0"
              />
              <code className="text-xs text-[var(--color-muted-fg)]">{colour}</code>
            </div>
          </div>

          <div className="space-y-1.5">
            <label htmlFor={roomId} className="text-sm font-medium">
              Room
            </label>
            <input
              id={roomId}
              type="text"
              value={room}
              onChange={(e) => setRoom(e.target.value)}
              placeholder="cachepuppy_demo_room"
              className="w-full rounded-md border border-[var(--color-border)] bg-[var(--color-bg)] px-3 py-2 font-mono text-sm outline-none focus:border-[var(--color-border-strong)]"
            />
          </div>

          {error ? (
            <p className="text-sm text-red-600 dark:text-red-400">{error}</p>
          ) : null}

          <button
            type="submit"
            className="w-full rounded-md bg-[var(--color-fg)] px-4 py-2 text-sm font-medium text-[var(--color-bg)] transition hover:opacity-90"
          >
            Join room
          </button>
        </form>

        <p className="mt-4 text-center text-xs text-[var(--color-muted-fg)]">
          A new client id is generated each time you join.
        </p>
      </div>
    </div>
  );
}
