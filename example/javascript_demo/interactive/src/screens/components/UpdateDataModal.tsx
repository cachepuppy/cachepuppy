import { useState } from "react";

interface UpdateDataModalProps {
  onClose: () => void;
  onSubmit: (
    table: string,
    key: string,
    patch: Record<string, unknown>,
    options?: { ttlMs?: number },
  ) => Promise<unknown>;
}

export function UpdateDataModal({ onClose, onSubmit }: UpdateDataModalProps) {
  const [table, setTable] = useState("");
  const [key, setKey] = useState("");
  const [patchJson, setPatchJson] = useState("");
  const [ttlSeconds, setTtlSeconds] = useState("");
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
      parsed = JSON.parse(patchJson);
    } catch {
      setError("Patch must be valid JSON.");
      setResult(null);
      return;
    }

    if (typeof parsed !== "object" || parsed === null || Array.isArray(parsed)) {
      setError("Patch must be a JSON object (e.g. {\"role\":\"editor\"}), not an array or primitive.");
      setResult(null);
      return;
    }

    const ttlTrimmed = ttlSeconds.trim();
    let options: { ttlMs?: number } | undefined;
    if (ttlTrimmed !== "") {
      const seconds = Number(ttlTrimmed);
      if (!Number.isFinite(seconds) || seconds <= 0) {
        setError("TTL (seconds) must be a positive number, or leave blank.");
        setResult(null);
        return;
      }
      options = { ttlMs: Math.round(seconds * 1000) };
    }

    setBusy(true);
    setError(null);
    setResult(null);
    try {
      const value = await onSubmit(normalizedTable, normalizedKey, parsed as Record<string, unknown>, options);
      setResult(JSON.stringify(value, null, 2));
    } catch {
      setError("Could not update data (key may be missing, value not an object, or cache unavailable).");
    } finally {
      setBusy(false);
    }
  }

  return (
    <div className="modal-backdrop">
      <div className="modal card">
        <h2>Update data</h2>
        <p className="muted" style={{ marginTop: 0 }}>
          Shallow-merges the patch into the existing value for this key. The stored value must already be a JSON
          object (use Insert data first if the key is new).
        </p>
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
            <span>Patch (JSON object)</span>
            <textarea
              value={patchJson}
              onChange={(e) => setPatchJson(e.target.value)}
              placeholder='{"role":"superadmin"}'
              rows={5}
              disabled={busy}
            />
          </label>
          <label className="field">
            <span>TTL (seconds, optional)</span>
            <input
              type="text"
              inputMode="decimal"
              value={ttlSeconds}
              onChange={(e) => setTtlSeconds(e.target.value)}
              placeholder="Leave blank to keep existing TTL rules on the server"
              disabled={busy}
            />
          </label>
          {error ? <p className="error">{error}</p> : null}
          {result ? <pre className="result-block">{result}</pre> : null}
          <div className="row-actions">
            <button type="submit" className="btn primary" disabled={busy}>
              {busy ? "Updating..." : "Update"}
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
