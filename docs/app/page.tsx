import Link from "next/link";

const cards = [
  {
    title: "Quick start",
    description: "Run Phoenix, build the SDKs, and ship your first subscribe/publish loop in minutes.",
    href: "/docs/quick-start",
  },
  {
    title: "Core concepts",
    description: "Channels, envelopes, topic state, session state, cache tables, and how they fit together.",
    href: "/docs/core-concepts",
  },
  {
    title: "JavaScript & React SDKs",
    description: "Connection-oriented client plus React hooks that stay aligned with the wire protocol.",
    href: "/docs/js-sdk",
  },
  {
    title: "Admin HTTP client",
    description: "Server-side HTTP access to topic fan-out, presence, and cache without a websocket.",
    href: "/docs/admin-http-client",
  },
  {
    title: "API reference",
    description: "HTTP routes, channel events, envelope fields, and exported TypeScript surface area.",
    href: "/docs/api-reference",
  },
  {
    title: "Changelog",
    description: "Version notes across the Elixir app and npm packages.",
    href: "/docs/changelog",
  },
];

export default function HomePage() {
  return (
    <main className="relative isolate flex flex-1 flex-col">
      <div className="pointer-events-none absolute inset-0 -z-10 bg-[radial-gradient(80%_60%_at_50%_-10%,color-mix(in_oklab,var(--color-fd-primary)_22%,transparent),transparent)]" />
      <div className="mx-auto flex w-full max-w-5xl flex-1 flex-col gap-12 px-6 py-16 sm:py-24">
        <header className="space-y-6 text-center sm:text-left">
          <p className="text-sm font-medium text-fd-muted-foreground">Beamline · CachePuppy</p>
          <h1 className="text-balance text-4xl font-semibold tracking-tight sm:text-5xl">
            Documentation that matches the code
          </h1>
          <p className="text-pretty text-lg text-fd-muted-foreground sm:max-w-2xl">
            Phoenix realtime core, a typed JavaScript client, a thin React layer, and an admin HTTP client — all
            described in one calm, navigable place.
          </p>
          <div className="flex flex-wrap items-center justify-center gap-3 sm:justify-start">
            <Link
              href="/docs"
              className="inline-flex h-10 items-center justify-center rounded-lg bg-fd-primary px-5 text-sm font-medium text-fd-primary-foreground shadow-sm transition hover:opacity-95"
            >
              Open documentation
            </Link>
            <Link
              href="/docs/quick-start/hello-realtime"
              className="inline-flex h-10 items-center justify-center rounded-lg border border-fd-border bg-fd-background px-5 text-sm font-medium text-foreground transition hover:bg-fd-muted/60"
            >
              Jump to Hello realtime
            </Link>
          </div>
        </header>

        <section className="grid gap-4 sm:grid-cols-2">
          {cards.map((card) => (
            <Link
              key={card.href}
              href={card.href}
              className="group rounded-2xl border border-fd-border bg-fd-card p-6 shadow-sm transition hover:-translate-y-0.5 hover:border-fd-primary/40 hover:shadow-md"
            >
              <h2 className="text-lg font-semibold tracking-tight group-hover:text-fd-primary">{card.title}</h2>
              <p className="mt-2 text-sm leading-relaxed text-fd-muted-foreground">{card.description}</p>
              <p className="mt-4 text-sm font-medium text-fd-primary">Read section →</p>
            </Link>
          ))}
        </section>
      </div>
    </main>
  );
}
