"use client";

import {
  createContext,
  useCallback,
  useContext,
  useEffect,
  useMemo,
  useState,
  type ReactNode,
} from "react";

const STORAGE_KEY = "cachepuppy-unified-session";
const DEFAULT_ROOM = "cachepuppy_demo_room";

export interface Session {
  clientId: string;
  userName: string;
  colour: string;
  room: string;
}

interface SessionContextValue {
  session: Session | null;
  startSession: (input: { userName: string; colour: string; room: string }) => Session;
  endSession: () => void;
  defaultRoom: string;
}

const SessionContext = createContext<SessionContextValue | null>(null);

function loadSession(): Session | null {
  if (typeof window === "undefined") return null;
  try {
    const raw = window.sessionStorage.getItem(STORAGE_KEY);
    if (!raw) return null;
    const parsed = JSON.parse(raw) as Partial<Session>;
    if (
      typeof parsed.clientId === "string" &&
      typeof parsed.userName === "string" &&
      typeof parsed.colour === "string" &&
      typeof parsed.room === "string"
    ) {
      return parsed as Session;
    }
  } catch {
    // ignore corrupt storage
  }
  return null;
}

function persistSession(session: Session | null): void {
  if (typeof window === "undefined") return;
  if (session) {
    window.sessionStorage.setItem(STORAGE_KEY, JSON.stringify(session));
  } else {
    window.sessionStorage.removeItem(STORAGE_KEY);
  }
}

function newClientId(): string {
  if (typeof crypto !== "undefined" && "randomUUID" in crypto) {
    return crypto.randomUUID();
  }
  return `client-${Date.now()}-${Math.floor(Math.random() * 1e6)}`;
}

export function SessionProvider({ children }: { children: ReactNode }) {
  const [session, setSession] = useState<Session | null>(null);
  const [hydrated, setHydrated] = useState(false);

  useEffect(() => {
    setSession(loadSession());
    setHydrated(true);
  }, []);

  const startSession = useCallback(
    (input: { userName: string; colour: string; room: string }) => {
      const next: Session = {
        clientId: newClientId(),
        userName: input.userName,
        colour: input.colour,
        room: input.room,
      };
      setSession(next);
      persistSession(next);
      return next;
    },
    [],
  );

  const endSession = useCallback(() => {
    setSession(null);
    persistSession(null);
  }, []);

  const value = useMemo<SessionContextValue>(
    () => ({ session, startSession, endSession, defaultRoom: DEFAULT_ROOM }),
    [session, startSession, endSession],
  );

  // Avoid SSR/CSR mismatch by waiting for hydration before rendering children
  // that depend on session state.
  if (!hydrated) {
    return (
      <SessionContext.Provider value={value}>
        <div aria-hidden />
      </SessionContext.Provider>
    );
  }

  return (
    <SessionContext.Provider value={value}>{children}</SessionContext.Provider>
  );
}

export function useSession(): SessionContextValue {
  const ctx = useContext(SessionContext);
  if (!ctx) {
    throw new Error("useSession must be used within SessionProvider");
  }
  return ctx;
}
