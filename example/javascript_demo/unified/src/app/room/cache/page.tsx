import { CachePanel } from "@/components/CachePanel";

export default function CachePage() {
  return (
    <div className="space-y-6">
      <div>
        <p className="text-xs font-medium uppercase tracking-wider text-[var(--color-muted-fg)]">
          Module 1
        </p>
        <h1 className="mt-1 text-2xl font-semibold tracking-tight">Caching</h1>
        <p className="mt-1 text-sm text-[var(--color-muted-fg)]">
          Insert, update, get, and delete keyed records using the CachePuppy
          React SDK directly from the browser.
        </p>
      </div>
      <CachePanel />
    </div>
  );
}
