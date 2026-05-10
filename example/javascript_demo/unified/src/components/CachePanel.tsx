"use client";

import { useState } from "react";
import { useCachePuppyClient } from "@cachepuppy/react";

type Op = "insert" | "update" | "get" | "delete";

const OPS: { id: Op; label: string; verb: string }[] = [
  { id: "insert", label: "Insert", verb: "setData" },
  { id: "update", label: "Update", verb: "updateData" },
  { id: "get", label: "Get", verb: "getData" },
  { id: "delete", label: "Delete", verb: "deleteData" },
];

interface FieldProps {
  label: string;
  hint?: string;
  children: React.ReactNode;
}

function Field({ label, hint, children }: FieldProps) {
  return (
    <label className="block space-y-1.5">
      <span className="text-sm font-medium">{label}</span>
      {children}
      {hint ? (
        <span className="block text-xs text-[var(--color-muted-fg)]">{hint}</span>
      ) : null}
    </label>
  );
}

function inputClass(extra = ""): string {
  return [
    "w-full rounded-md border border-[var(--color-border)] bg-[var(--color-bg)] px-3 py-2 text-sm outline-none focus:border-[var(--color-border-strong)]",
    extra,
  ]
    .filter(Boolean)
    .join(" ");
}

function parseTtl(input: string): { ok: true; ttlMs?: number } | { ok: false; error: string } {
  const trimmed = input.trim();
  if (!trimmed) return { ok: true };
  const seconds = Number(trimmed);
  if (!Number.isFinite(seconds) || seconds <= 0) {
    return { ok: false, error: "TTL (seconds) must be a positive number, or leave blank." };
  }
  return { ok: true, ttlMs: Math.round(seconds * 1000) };
}

function ResultBlock({ result, error }: { result: string | null; error: string | null }) {
  if (!error && !result) return null;
  return (
    <div className="space-y-1.5">
      <span className="text-sm font-medium">{error ? "Error" : "Result"}</span>
      <pre
        className={[
          "max-h-64 overflow-auto rounded-md border px-3 py-2 font-mono text-xs whitespace-pre-wrap break-words",
          error
            ? "border-red-300 bg-red-50 text-red-900 dark:border-red-900 dark:bg-red-950/40 dark:text-red-200"
            : "border-[var(--color-border)] bg-[var(--color-subtle)]",
        ].join(" ")}
      >
        {error ?? result}
      </pre>
    </div>
  );
}

function SubmitButton({ busy, label }: { busy: boolean; label: string }) {
  return (
    <button
      type="submit"
      disabled={busy}
      className="rounded-md bg-[var(--color-fg)] px-4 py-2 text-sm font-medium text-[var(--color-bg)] transition hover:opacity-90 disabled:opacity-50"
    >
      {busy ? "Working…" : label}
    </button>
  );
}

function InsertForm() {
  const { client } = useCachePuppyClient();
  const [table, setTable] = useState("users");
  const [key, setKey] = useState("user_123");
  const [data, setData] = useState('{"name":"Alice","role":"admin","active":true}');
  const [ttl, setTtl] = useState("");
  const [busy, setBusy] = useState(false);
  const [result, setResult] = useState<string | null>(null);
  const [error, setError] = useState<string | null>(null);

  async function onSubmit(e: React.FormEvent) {
    e.preventDefault();
    setError(null);
    setResult(null);
    if (!table.trim() || !key.trim()) {
      setError("Table and key are required.");
      return;
    }
    let parsed: unknown;
    try {
      parsed = JSON.parse(data);
    } catch {
      setError("Data must be valid JSON.");
      return;
    }
    const ttlResult = parseTtl(ttl);
    if (!ttlResult.ok) {
      setError(ttlResult.error);
      return;
    }
    setBusy(true);
    try {
      const value = await client.setData(
        table.trim(),
        key.trim(),
        parsed,
        ttlResult.ttlMs ? { ttlMs: ttlResult.ttlMs } : undefined,
      );
      setResult(JSON.stringify(value, null, 2));
    } catch (e) {
      setError(e instanceof Error ? e.message : String(e));
    } finally {
      setBusy(false);
    }
  }

  return (
    <form onSubmit={onSubmit} className="space-y-4">
      <Field label="Table"><input className={inputClass()} value={table} onChange={(e) => setTable(e.target.value)} /></Field>
      <Field label="Key"><input className={inputClass()} value={key} onChange={(e) => setKey(e.target.value)} /></Field>
      <Field label="Value (JSON)">
        <textarea rows={5} className={inputClass("font-mono")} value={data} onChange={(e) => setData(e.target.value)} />
      </Field>
      <Field label="TTL (seconds, optional)" hint="Leave blank for no expiry.">
        <input className={inputClass()} value={ttl} onChange={(e) => setTtl(e.target.value)} placeholder="60" />
      </Field>
      <SubmitButton busy={busy} label="Insert" />
      <ResultBlock result={result} error={error} />
    </form>
  );
}

function UpdateForm() {
  const { client } = useCachePuppyClient();
  const [table, setTable] = useState("users");
  const [key, setKey] = useState("user_123");
  const [patch, setPatch] = useState('{"role":"superadmin"}');
  const [ttl, setTtl] = useState("");
  const [busy, setBusy] = useState(false);
  const [result, setResult] = useState<string | null>(null);
  const [error, setError] = useState<string | null>(null);

  async function onSubmit(e: React.FormEvent) {
    e.preventDefault();
    setError(null);
    setResult(null);
    if (!table.trim() || !key.trim()) {
      setError("Table and key are required.");
      return;
    }
    let parsed: unknown;
    try {
      parsed = JSON.parse(patch);
    } catch {
      setError("Patch must be valid JSON.");
      return;
    }
    if (typeof parsed !== "object" || parsed === null || Array.isArray(parsed)) {
      setError("Patch must be a JSON object, not an array or primitive.");
      return;
    }
    const ttlResult = parseTtl(ttl);
    if (!ttlResult.ok) {
      setError(ttlResult.error);
      return;
    }
    setBusy(true);
    try {
      const value = await client.updateData(
        table.trim(),
        key.trim(),
        parsed as Record<string, unknown>,
        ttlResult.ttlMs ? { ttlMs: ttlResult.ttlMs } : undefined,
      );
      setResult(JSON.stringify(value, null, 2));
    } catch (e) {
      setError(e instanceof Error ? e.message : String(e));
    } finally {
      setBusy(false);
    }
  }

  return (
    <form onSubmit={onSubmit} className="space-y-4">
      <p className="text-sm text-[var(--color-muted-fg)]">
        Shallow-merges the patch into the existing value. Insert first if the
        key is new.
      </p>
      <Field label="Table"><input className={inputClass()} value={table} onChange={(e) => setTable(e.target.value)} /></Field>
      <Field label="Key"><input className={inputClass()} value={key} onChange={(e) => setKey(e.target.value)} /></Field>
      <Field label="Patch (JSON object)">
        <textarea rows={5} className={inputClass("font-mono")} value={patch} onChange={(e) => setPatch(e.target.value)} />
      </Field>
      <Field label="TTL (seconds, optional)" hint="Leave blank to keep existing TTL.">
        <input className={inputClass()} value={ttl} onChange={(e) => setTtl(e.target.value)} placeholder="60" />
      </Field>
      <SubmitButton busy={busy} label="Update" />
      <ResultBlock result={result} error={error} />
    </form>
  );
}

function GetForm() {
  const { client } = useCachePuppyClient();
  const [table, setTable] = useState("users");
  const [key, setKey] = useState("user_123");
  const [busy, setBusy] = useState(false);
  const [result, setResult] = useState<string | null>(null);
  const [error, setError] = useState<string | null>(null);

  async function onSubmit(e: React.FormEvent) {
    e.preventDefault();
    setError(null);
    setResult(null);
    if (!table.trim() || !key.trim()) {
      setError("Table and key are required.");
      return;
    }
    setBusy(true);
    try {
      const value = await client.getData(table.trim(), key.trim());
      setResult(JSON.stringify(value, null, 2));
    } catch (e) {
      setError(e instanceof Error ? e.message : String(e));
    } finally {
      setBusy(false);
    }
  }

  return (
    <form onSubmit={onSubmit} className="space-y-4">
      <Field label="Table"><input className={inputClass()} value={table} onChange={(e) => setTable(e.target.value)} /></Field>
      <Field label="Key"><input className={inputClass()} value={key} onChange={(e) => setKey(e.target.value)} /></Field>
      <SubmitButton busy={busy} label="Get" />
      <ResultBlock result={result} error={error} />
    </form>
  );
}

function DeleteForm() {
  const { client } = useCachePuppyClient();
  const [table, setTable] = useState("users");
  const [key, setKey] = useState("user_123");
  const [busy, setBusy] = useState(false);
  const [result, setResult] = useState<string | null>(null);
  const [error, setError] = useState<string | null>(null);

  async function onSubmit(e: React.FormEvent) {
    e.preventDefault();
    setError(null);
    setResult(null);
    if (!table.trim() || !key.trim()) {
      setError("Table and key are required.");
      return;
    }
    setBusy(true);
    try {
      const value = await client.deleteData(table.trim(), key.trim());
      setResult(JSON.stringify({ deleted: value }, null, 2));
    } catch (e) {
      setError(e instanceof Error ? e.message : String(e));
    } finally {
      setBusy(false);
    }
  }

  return (
    <form onSubmit={onSubmit} className="space-y-4">
      <Field label="Table"><input className={inputClass()} value={table} onChange={(e) => setTable(e.target.value)} /></Field>
      <Field label="Key"><input className={inputClass()} value={key} onChange={(e) => setKey(e.target.value)} /></Field>
      <SubmitButton busy={busy} label="Delete" />
      <ResultBlock result={result} error={error} />
    </form>
  );
}

export function CachePanel() {
  const [op, setOp] = useState<Op>("insert");
  return (
    <div className="space-y-6">
      <nav className="flex flex-wrap gap-1 rounded-lg border border-[var(--color-border)] bg-[var(--color-subtle)] p-1">
        {OPS.map((tab) => {
          const active = tab.id === op;
          return (
            <button
              key={tab.id}
              type="button"
              onClick={() => setOp(tab.id)}
              className={[
                "rounded-md px-3 py-1.5 text-sm font-medium transition",
                active
                  ? "bg-[var(--color-bg)] shadow-[0_1px_0_rgba(0,0,0,0.04)]"
                  : "text-[var(--color-muted-fg)] hover:text-[var(--color-fg)]",
              ].join(" ")}
            >
              {tab.label}
              <span className="ml-1.5 font-mono text-[10px] text-[var(--color-muted-fg)]">
                {tab.verb}
              </span>
            </button>
          );
        })}
      </nav>

      <div className="rounded-xl border border-[var(--color-border)] bg-[var(--color-bg)] p-6">
        {op === "insert" ? <InsertForm /> : null}
        {op === "update" ? <UpdateForm /> : null}
        {op === "get" ? <GetForm /> : null}
        {op === "delete" ? <DeleteForm /> : null}
      </div>
    </div>
  );
}
