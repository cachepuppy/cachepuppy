import { CursorBoard } from "@/components/CursorBoard";

export default function RealtimePage() {
  return (
    <div className="space-y-6">
      <div>
        <p className="text-xs font-medium uppercase tracking-wider text-[var(--color-muted-fg)]">
          Module 2
        </p>
        <h1 className="mt-1 text-2xl font-semibold tracking-tight">Realtime</h1>
        <p className="mt-1 text-sm text-[var(--color-muted-fg)]">
          Each move publishes a <code className="font-mono">cursor_tracked</code>{" "}
          message on the room topic. Peers receive it through the same
          subscription.
        </p>
      </div>
      <CursorBoard />
    </div>
  );
}
