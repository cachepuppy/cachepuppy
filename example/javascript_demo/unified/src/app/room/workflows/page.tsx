import { WorkflowsPanel } from "@/components/WorkflowsPanel";

export default function WorkflowsPage() {
  return (
    <div className="space-y-6">
      <div>
        <p className="text-xs font-medium uppercase tracking-wider text-[var(--color-muted-fg)]">
          Module 3
        </p>
        <h1 className="mt-1 text-2xl font-semibold tracking-tight">Workflows</h1>
        <p className="mt-1 text-sm text-[var(--color-muted-fg)]">
          Seven orchestration scenarios run via Next.js API routes that talk to
          the CachePuppy admin client.
        </p>
      </div>
      <WorkflowsPanel />
    </div>
  );
}
