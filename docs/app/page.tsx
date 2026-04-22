import Link from "next/link";

const cards = [
  {
    title: "Quick start",
    description: "Docker, one Make target, then connect and publish from JavaScript in minutes.",
    href: "/docs/quick-start",
  },
  {
    title: "Core concepts",
    description: "Topics, envelopes, shared state, session data, cache tables, and how the cluster behaves.",
    href: "/docs/core-concepts",
  },
  {
    title: "JavaScript",
    description: "Core client, React hooks, and the admin HTTP client — one chapter, three subsections.",
    href: "/docs/javascript",
  },
  {
    title: "API reference",
    description: "HTTP routes, channel events, envelope fields, and TypeScript exports.",
    href: "/docs/api-reference",
  },
  {
    title: "Changelog",
    description: "Version notes for the server and client packages.",
    href: "/docs/changelog",
  },
];

export default function HomePage() {
  return (
    <main className="relative isolate flex flex-1 flex-col">
      <div className="pointer-events-none absolute inset-0 -z-10 bg-[radial-gradient(80%_60%_at_50%_-10%,color-mix(in_oklab,var(--color-fd-primary)_22%,transparent),transparent)]" />
      <div className="mx-auto flex w-full max-w-5xl flex-1 flex-col gap-12 px-6 py-16 sm:py-24">
        <header className="space-y-6 text-center sm:text-left">
          <p className="text-sm font-medium text-fd-muted-foreground">CachePuppy</p>
          <h1 className="text-balance text-4xl font-semibold tracking-tight sm:text-5xl">
            Realtime and cache, together
          </h1>
          <p className="text-pretty text-lg text-fd-muted-foreground sm:max-w-2xl">
            CachePuppy gives you pub/sub topics, shared room state, and a distributed key/value cache behind one opinionated API. The server runs on the{" "}
            <strong>BEAM</strong> (Erlang VM) with <strong>Elixir</strong>, so you scale out by adding nodes: the runtime handles process supervision, clustering,
            and node-to-node coordination. Websockets fan out events across the mesh, while cache data is routed and replicated through the same cluster
            pipeline—so your app gets <strong>live updates</strong> and <strong>fast shared storage</strong> without bolting half a dozen products together.
          </p>
          <div className="flex flex-wrap items-center justify-center gap-3 sm:justify-start">
            <Link
              href="/docs"
              className="inline-flex h-10 items-center justify-center rounded-lg bg-fd-primary px-5 text-sm font-medium text-fd-primary-foreground shadow-sm transition hover:opacity-95"
            >
              Read the docs
            </Link>
            <Link
              href="/docs/quick-start/javascript"
              className="inline-flex h-10 items-center justify-center rounded-lg border border-fd-border bg-fd-background px-5 text-sm font-medium text-foreground transition hover:bg-fd-muted/60"
            >
              JavaScript quick start
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
