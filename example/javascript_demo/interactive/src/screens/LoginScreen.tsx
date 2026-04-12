import { useId, useMemo, useState } from "react";
import { createClient } from "cachepuppy-js-sdk";
import { WS_URL } from "../constants";
import type { DemoSession } from "../types";

const DEFAULT_COLOUR = "#6366f1";

interface LoginScreenProps {
  onConnected: (session: DemoSession) => void;
}

export function LoginScreen({ onConnected }: LoginScreenProps) {
  const nameId = useId();
  const colourId = useId();
  const [userName, setUserName] = useState("");
  const [colour, setColour] = useState(DEFAULT_COLOUR);
  const [error, setError] = useState<string | null>(null);
  const [busy, setBusy] = useState(false);
  const [connState, setConnState] = useState<string>("idle");

  const clientId = useMemo(() => crypto.randomUUID(), []);

  async function handleSubmit(e: React.FormEvent) {
    e.preventDefault();
    const trimmed = userName.trim();
    if (!trimmed) {
      setError("Please enter a name.");
      return;
    }
    setError(null);
    setBusy(true);

    const client = createClient({
      url: WS_URL,
      transport: "phoenix",
      clientId,
    });

    const offState = client.on("stateChange", ({ state }) => {
      setConnState(state);
    });

    try {
      await client.connect();
      onConnected({ client, clientId, userName: trimmed, colour });
    } catch {
      setError("Could not connect to the server. Is Phoenix running?");
      void client.destroy();
    } finally {
      offState();
      setBusy(false);
    }
  }

  return (
    <div className="screen screen--login">
      <h1>Join the room</h1>
      <p className="muted">Connect to the Phoenix server, then open the sticky notes room.</p>
      <form className="card" onSubmit={handleSubmit}>
        <label className="field" htmlFor={nameId}>
          <span>User name</span>
          <input
            id={nameId}
            name="userName"
            autoComplete="username"
            value={userName}
            onChange={(e) => setUserName(e.target.value)}
            placeholder="Your name"
            disabled={busy}
          />
        </label>
        <label className="field field--row" htmlFor={colourId}>
          <span>Colour</span>
          <input
            id={colourId}
            name="colour"
            type="color"
            value={colour}
            onChange={(e) => setColour(e.target.value)}
            disabled={busy}
          />
          <span className="colour-hex">{colour}</span>
        </label>
        {error ? <p className="error">{error}</p> : null}
        <button type="submit" className="btn primary" disabled={busy}>
          {busy ? "Connecting…" : "Connect"}
        </button>
      </form>
      <p className="status subtle">Status: {connState}</p>
      <p className="subtle mono">{WS_URL}</p>
    </div>
  );
}
