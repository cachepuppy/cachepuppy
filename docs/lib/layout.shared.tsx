import type { BaseLayoutProps } from "fumadocs-ui/layouts/shared";
import { BookOpen, Braces, Rocket } from "lucide-react";
import { SiteLogo } from "@/components/site-logo";

export function baseOptions(): BaseLayoutProps {
  return {
    nav: {
      title: <SiteLogo priority />,
      url: "/",
    },
    themeSwitch: {
      enabled: false,
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
