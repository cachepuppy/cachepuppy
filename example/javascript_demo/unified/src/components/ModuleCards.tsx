import Link from "next/link";

const modules = [
  {
    href: "/room/cache",
    title: "Caching",
    description:
      "Insert, get, update, and delete arbitrary key/value records, optionally with a TTL.",
    badge: "Module 1",
  },
  {
    href: "/room/realtime",
    title: "Realtime",
    description:
      "See live cursors of every participant in this room, streamed over Phoenix websockets.",
    badge: "Module 2",
  },
  {
    href: "/room/workflows",
    title: "Workflows",
    description:
      "Run seven orchestration scenarios — serial, parallel, dynamic fan-out, retries — and watch the graph fill in live.",
    badge: "Module 3",
  },
] as const;

export function ModuleCards() {
  return (
    <div className="grid gap-4 sm:grid-cols-2 lg:grid-cols-3">
      {modules.map((m) => (
        <Link
          key={m.href}
          href={m.href}
          className="group flex h-full flex-col justify-between rounded-xl border border-[var(--color-border)] bg-[var(--color-bg)] p-5 transition hover:border-[var(--color-border-strong)]"
        >
          <div>
            <span className="inline-block rounded-full border border-[var(--color-border)] px-2 py-0.5 text-[10px] font-medium uppercase tracking-wider text-[var(--color-muted-fg)]">
              {m.badge}
            </span>
            <h2 className="mt-3 text-lg font-semibold tracking-tight">
              {m.title}
            </h2>
            <p className="mt-1.5 text-sm text-[var(--color-muted-fg)]">
              {m.description}
            </p>
          </div>
          <div className="mt-6 flex items-center gap-1 text-sm font-medium">
            Open
            <span className="transition group-hover:translate-x-0.5" aria-hidden>
              →
            </span>
          </div>
        </Link>
      ))}
    </div>
  );
}
