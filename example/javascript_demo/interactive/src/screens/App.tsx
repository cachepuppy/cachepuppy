import { useState } from "react";
import type { DemoSession } from "../types";
import { LoginScreen } from "./LoginScreen";
import { RoomScreen } from "./RoomScreen";

export default function App() {
  const [session, setSession] = useState<DemoSession | null>(null);

  if (session) {
    return <RoomScreen session={session} onLeave={() => setSession(null)} />;
  }

  return <LoginScreen onConnected={setSession} />;
}
