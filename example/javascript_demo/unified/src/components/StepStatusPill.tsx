export function StepStatusPill({ status }: { status: string }) {
  const normalized = status.trim().toLowerCase();
  if (!normalized) return null;
  let cls =
    "inline-block rounded-full border border-[var(--color-border)] px-2 py-0.5 text-[11px] font-medium text-[var(--color-muted-fg)]";
  if (normalized === "completed") {
    cls =
      "inline-block rounded-full bg-emerald-600 px-2 py-0.5 text-[11px] font-medium text-white";
  } else if (normalized === "running") {
    cls =
      "inline-block rounded-full bg-amber-300 px-2 py-0.5 text-[11px] font-medium text-amber-950 dark:bg-amber-400/90 dark:text-amber-950";
  } else if (normalized === "failed") {
    cls =
      "inline-block rounded-full bg-red-600 px-2 py-0.5 text-[11px] font-medium text-white";
  }
  return <span className={cls}>{status}</span>;
}

export function WorkflowStatusPill({ status }: { status: string | null }) {
  if (!status) return null;
  return (
    <span className="ml-2 inline-block rounded-full border border-[var(--color-border)] bg-[var(--color-subtle)] px-2 py-0.5 text-[10px] font-medium uppercase tracking-wider text-[var(--color-muted-fg)]">
      {status}
    </span>
  );
}
