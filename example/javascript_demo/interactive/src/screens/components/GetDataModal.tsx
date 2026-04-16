import { useState } from "react";

interface GetDataModalProps {
  onClose: () => void;
  onSubmit: (table: string, key: string) => Promise<unknown>;
}

export function GetDataModal({ onClose, onSubmit }: GetDataModalProps) {
  const [table, setTable] = useState("");
  const [key, setKey] = useState("");
  const [busy, setBusy] = useState(false);
  const [result, setResult] = useState<string | null>(null);
  const [error, setError] = useState<string | null>(null);

  async function handleSubmit(e: React.FormEvent) {
    e.preventDefault();
    const normalizedTable = table.trim();
    const normalizedKey = key.trim();
    if (!normalizedTable || !normalizedKey) {
      setError("Table and key are required.");
      setResult(null);
      return;
    }

    setBusy(true);
    setError(null);
    setResult(null);
    try {
      const value = await onSubmit(normalizedTable, normalizedKey);
      setResult(JSON.stringify(value, null, 2));
    } catch {
      setError("Could not fetch data.");
    } finally {
      setBusy(false);
    }
  }

  return (
    <div className="modal-backdrop">
      <div className="modal card">
        <h2>Get data</h2>
        <form onSubmit={(e) => void handleSubmit(e)} className="modal-form">
          <label className="field">
            <span>Table name</span>
            <input
              type="text"
              value={table}
              onChange={(e) => setTable(e.target.value)}
              placeholder="users"
              disabled={busy}
            />
          </label>
          <label className="field">
            <span>Key name</span>
            <input
              type="text"
              value={key}
              onChange={(e) => setKey(e.target.value)}
              placeholder="user_123"
              disabled={busy}
            />
          </label>
          {error ? <p className="error">{error}</p> : null}
          {result ? <pre className="result-block">{result}</pre> : null}
          <div className="row-actions">
            <button type="submit" className="btn primary" disabled={busy}>
              {busy ? "Fetching..." : "Get"}
            </button>
            <button type="button" className="btn" onClick={onClose} disabled={busy}>
              Close
            </button>
          </div>
        </form>
      </div>
    </div>
  );
}
