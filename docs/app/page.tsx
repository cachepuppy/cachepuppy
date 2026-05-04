import Link from "next/link";
import { BookOpen, Braces, History, Layers, Rocket } from "lucide-react";
import type { LucideIcon } from "lucide-react";
import { SiteLogo } from "@/components/site-logo";

type Card = {
  title: string;
  description: string;
  href: string;
  icon: LucideIcon;
};

const cards: Card[] = [
  {
    title: "Quick start",
    description: "Docker, one Make target, then connect and publish from JavaScript in minutes.",
    href: "/docs/quick-start",
    icon: Rocket,
  },
  {
    title: "Core concepts",
    description: "Topics, envelopes, shared state, session data, cache tables, and how the cluster behaves.",
    href: "/docs/core-concepts",
    icon: Layers,
  },
  {
    title: "JavaScript",
    description: "Core client, React hooks, and the admin HTTP client — one chapter, three subsections.",
    href: "/docs/javascript",
    icon: Braces,
  },
  {
    title: "API reference",
    description: "HTTP routes, channel events, envelope fields, and TypeScript exports.",
    href: "/docs/api-reference",
    icon: BookOpen,
  },
  {
    title: "Changelog",
    description: "Version notes for the server and client packages.",
    href: "/docs/changelog",
    icon: History,
  },
];

export default function HomePage() {
  return (
    <main className="relative isolate flex flex-1 flex-col">
      <div className="pointer-events-none absolute inset-0 -z-10 bg-[radial-gradient(85%_55%_at_50%_-15%,color-mix(in_oklab,var(--color-fd-primary)_28%,transparent),transparent)]" />
      <div className="pointer-events-none absolute inset-0 -z-10 home-hero-grid opacity-70" />
      <div className="mx-auto flex w-full max-w-5xl flex-1 flex-col gap-12 px-6 py-16 sm:py-24">
        <header className="space-y-6 text-center sm:text-left">
          <Link href="/" className="inline-flex justify-center sm:justify-start">
            <SiteLogo priority />
          </Link>
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
              className="inline-flex h-10 items-center justify-center gap-2 rounded-lg bg-fd-primary px-5 text-sm font-medium text-fd-primary-foreground shadow-md shadow-fd-primary/25 transition hover:opacity-95"
            >
              <BookOpen className="size-4 opacity-90" aria-hidden />
              Read the docs
            </Link>
            <Link
              href="/docs/quick-start/javascript"
              className="inline-flex h-10 items-center justify-center gap-2 rounded-lg border border-fd-border bg-fd-card px-5 text-sm font-medium text-fd-card-foreground shadow-sm transition hover:border-fd-primary/35 hover:bg-fd-accent/80"
            >
              <Rocket className="size-4 text-fd-primary" aria-hidden />
              JavaScript quick start
            </Link>
          </div>
        </header>

        <section className="grid gap-4 sm:grid-cols-2">
          {cards.map((card) => {
            const Icon = card.icon;
            return (
              <Link
                key={card.href}
                href={card.href}
                className="group rounded-2xl border border-fd-border bg-fd-card/90 p-6 shadow-sm ring-1 ring-transparent transition hover:-translate-y-0.5 hover:border-fd-primary/35 hover:shadow-lg hover:ring-fd-primary/15"
              >
                <div className="mb-4 inline-flex size-11 items-center justify-center rounded-xl bg-fd-primary/10 text-fd-primary transition group-hover:bg-fd-primary/15">
                  <Icon className="size-5" aria-hidden />
                </div>
                <h2 className="text-lg font-semibold tracking-tight group-hover:text-fd-primary">{card.title}</h2>
                <p className="mt-2 text-sm leading-relaxed text-fd-muted-foreground">{card.description}</p>
                <p className="mt-4 inline-flex items-center gap-1 text-sm font-medium text-fd-primary">
                  Read section
                  <span aria-hidden className="transition group-hover:translate-x-0.5">
                    →
                  </span>
                </p>
              </Link>
            );
          })}
        </section>
      </div>
    </main>
  );
}
