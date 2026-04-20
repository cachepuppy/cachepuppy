import { useId, useMemo, useState } from "react";

const DEFAULT_COLOUR = "#6366f1";

export function LoginScreen({ onConnected }) {
  const nameId = useId();
  const colourId = useId();
  const [userName, setUserName] = useState("");
  const [colour, setColour] = useState(DEFAULT_COLOUR);
  const [error, setError] = useState<string | null>(null);

  const clientId = useMemo(() => crypto.randomUUID(), []);

  function handleSubmit(e: React.FormEvent) {
    e.preventDefault();
    const trimmed = userName.trim();
    if (!trimmed) {
      setError("Please enter a name.");
      return;
    }
    setError(null);
    onConnected(clientId, trimmed, colour);
  }

  return (
    <div className="screen screen--login">
      <h1>Join the room</h1>
      <p className="muted">
        Connect to the Phoenix server, then open the sticky notes room.
      </p>
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
          />
          <span className="colour-hex">{colour}</span>
        </label>
        {error ? <p className="error">{error}</p> : null}
        <button type="submit" className="btn primary">
          Continue
        </button>
      </form>
    </div>
  );
}
