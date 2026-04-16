import { useState } from "react";

interface InsertDataModalProps {
  onClose: () => void;
  onSubmit: (table: string, key: string, value: unknown) => Promise<unknown>;
}

export function InsertDataModal({ onClose, onSubmit }: InsertDataModalProps) {
  const [table, setTable] = useState("");
  const [key, setKey] = useState("");
  const [data, setData] = useState("");
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

    let parsed: unknown;
    try {
      parsed = JSON.parse(data);
    } catch {
      setError("Data must be valid JSON.");
      setResult(null);
      return;
    }

    setBusy(true);
    setError(null);
    setResult(null);
    try {
      const value = await onSubmit(normalizedTable, normalizedKey, parsed);
      setResult(JSON.stringify(value, null, 2));
    } catch {
      setError("Could not insert data.");
    } finally {
      setBusy(false);
    }
  }

  return (
    <div className="modal-backdrop">
      <div className="modal card">
        <h2>Insert data</h2>
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
          <label className="field">
            <span>Actual data (JSON)</span>
            <textarea
              value={data}
              onChange={(e) => setData(e.target.value)}
              placeholder='{"name":"Alice","role":"admin","active":true}'
              rows={5}
              disabled={busy}
            />
          </label>
          {error ? <p className="error">{error}</p> : null}
          {result ? <pre className="result-block">{result}</pre> : null}
          <div className="row-actions">
            <button type="submit" className="btn primary" disabled={busy}>
              {busy ? "Inserting..." : "Insert"}
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
