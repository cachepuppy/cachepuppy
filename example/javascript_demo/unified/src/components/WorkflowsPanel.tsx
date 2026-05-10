"use client";

import { useState } from "react";
import { ScenarioCard } from "./ScenarioCard";

const SCENARIOS: (1 | 2 | 3 | 4 | 5 | 6 | 7)[] = [1, 2, 3, 4, 5, 6, 7];
const API_BASE = "/api/workflows";

export function WorkflowsPanel() {
  const [paragraph, setParagraph] = useState(
    "alpha beta gamma delta epsilon zeta eta theta iota kappa",
  );

  return (
    <div className="space-y-6">
      <div className="space-y-2">
        <label htmlFor="paragraph" className="text-sm font-medium">
          Paragraph (passed to each scenario start)
        </label>
        <textarea
          id="paragraph"
          rows={3}
          value={paragraph}
          onChange={(e) => setParagraph(e.target.value)}
          className="w-full rounded-md border border-[var(--color-border)] bg-[var(--color-bg)] px-3 py-2 text-sm outline-none focus:border-[var(--color-border-strong)]"
        />
        <p className="text-xs text-[var(--color-muted-fg)]">
          Endpoints live at <code className="font-mono">{API_BASE}/scenarioN/...</code>
          . Step status streams in over <code className="font-mono">graph_diff</code>{" "}
          on topic <code className="font-mono">workflow:&lt;id&gt;</code>.
        </p>
      </div>

      <div className="grid gap-4 lg:grid-cols-2">
        {SCENARIOS.map((s) => (
          <ScenarioCard
            key={s}
            scenario={s}
            apiBase={API_BASE}
            paragraph={paragraph}
          />
        ))}
      </div>
    </div>
  );
}
