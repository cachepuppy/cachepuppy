"use client";

import mermaid from "mermaid";
import { useEffect, useId, useState } from "react";

mermaid.initialize({
  startOnLoad: false,
  theme: "neutral",
  securityLevel: "strict",
});

export function Mermaid({ chart }: { chart: string }) {
  const id = useId().replace(/:/g, "");
  const [svg, setSvg] = useState<string | null>(null);

  useEffect(() => {
    let cancelled = false;

    const render = async () => {
      try {
        const { svg: out } = await mermaid.render(`mermaid-${id}`, chart);
        if (!cancelled) {
          setSvg(out);
        }
      } catch {
        if (!cancelled) {
          setSvg(null);
        }
      }
    };

    void render();
    return () => {
      cancelled = true;
    };
  }, [chart, id]);

  if (!svg) {
    return (
      <div className="my-6 rounded-xl border border-fd-border bg-fd-muted/40 p-4 text-sm text-fd-muted-foreground">
        Rendering diagram…
      </div>
    );
  }

  return (
    <div
      className="my-6 overflow-x-auto rounded-xl border border-fd-border bg-fd-background p-4 [&_svg]:mx-auto"
      dangerouslySetInnerHTML={{ __html: svg }}
    />
  );
}
