import { useMemo, useState } from "react";
import { CachePuppyProvider } from "@cachepuppy/react";
import { WS_URL } from "../constants";
import { LoginScreen } from "./LoginScreen";
import { RoomScreen } from "./RoomScreen";

export default function App() {
  const [clientId, setClientId] = useState<string | null>(null);
  const [userName, setUserName] = useState<string | null>(null);
  const [colour, setColour] = useState<string | null>(null);
  const clientOptions = useMemo(
    () =>
      clientId
        ? {
            url: WS_URL,
            transport: "phoenix" as const,
            clientId,
          }
        : null,
    [clientId],
  );

  function handleLogin(nextClientId: string, nextUserName: string, nextColour: string) {
    setClientId(nextClientId);
    setUserName(nextUserName);
    setColour(nextColour);
  }

  if (clientId && userName && colour && clientOptions) {
    return (
      <CachePuppyProvider autoConnect options={clientOptions}>
        <RoomScreen
          clientId={clientId}
          userName={userName}
          colour={colour}
          onLeave={() => {
            setClientId(null);
            setUserName(null);
            setColour(null);
          }}
        />
      </CachePuppyProvider>
    );
  }

  return <LoginScreen onConnected={handleLogin} />;
}
