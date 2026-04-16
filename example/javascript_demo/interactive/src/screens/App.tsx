import { useMemo, useState } from "react";
import { CachePuppyProvider } from "@cachepuppy/react";
import { WS_URL } from "../constants";
import type { DemoSession } from "../types";
import { LoginScreen } from "./LoginScreen";
import { RoomScreen } from "./RoomScreen";

export default function App() {
  const [session, setSession] = useState<DemoSession | null>(null);
  const clientOptions = useMemo(
    () =>
      session
        ? {
            url: WS_URL,
            transport: "phoenix" as const,
            clientId: session.clientId,
          }
        : null,
    [session],
  );

  if (session && clientOptions) {
    return (
      <CachePuppyProvider autoConnect options={clientOptions}>
        <RoomScreen session={session} onLeave={() => setSession(null)} />
      </CachePuppyProvider>
    );
  }

  return <LoginScreen onConnected={setSession} />;
}
