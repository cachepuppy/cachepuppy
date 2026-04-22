import type { BaseLayoutProps } from "fumadocs-ui/layouts/shared";
import { BookOpen, Boxes, Braces, Rocket } from "lucide-react";

export function baseOptions(): BaseLayoutProps {
  return {
    nav: {
      title: (
        <span className="flex items-center gap-2 font-semibold tracking-tight">
          <Boxes className="size-5 shrink-0 text-fd-primary" aria-hidden />
          CachePuppy
        </span>
      ),
      url: "/",
    },
    themeSwitch: {
      enabled: true,
    },
    links: [
      {
        text: "Docs",
        url: "/docs",
        active: "nested-url",
        icon: <BookOpen className="size-4 shrink-0 opacity-80" aria-hidden />,
      },
      {
        text: "Quick start",
        url: "/docs/quick-start",
        icon: <Rocket className="size-4 shrink-0 opacity-80" aria-hidden />,
      },
      {
        text: "JavaScript",
        url: "/docs/javascript",
        icon: <Braces className="size-4 shrink-0 opacity-80" aria-hidden />,
      },
    ],
  };
}
