import { useState } from "react";

interface DeleteDataModalProps {
  onClose: () => void;
  onSubmit: (table: string, key: string) => Promise<boolean>;
}

export function DeleteDataModal({ onClose, onSubmit }: DeleteDataModalProps) {
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
      const deleted = await onSubmit(normalizedTable, normalizedKey);
      setResult(
        deleted
          ? "Key was present and has been deleted (deleted: true)."
          : "Key was not present; nothing removed (deleted: false).",
      );
    } catch (err) {
      setError(err instanceof Error ? err.message : "Could not delete data.");
    } finally {
      setBusy(false);
    }
  }

  return (
    <div className="modal-backdrop">
      <div className="modal card">
        <h2>Delete data</h2>
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
          {result ? <p className="result-block">{result}</p> : null}
          <div className="row-actions">
            <button type="submit" className="btn primary" disabled={busy}>
              {busy ? "Deleting..." : "Delete"}
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
