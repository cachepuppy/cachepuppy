import { ModuleCards } from "@/components/ModuleCards";

export default function RoomLandingPage() {
  return (
    <div className="space-y-8">
      <div>
        <h1 className="text-2xl font-semibold tracking-tight">Modules</h1>
        <p className="mt-1 text-sm text-[var(--color-muted-fg)]">
          Pick a feature to explore. Everything in this room shares the same
          CachePuppy connection.
        </p>
      </div>
      <ModuleCards />
    </div>
  );
}
