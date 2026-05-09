import { CachePuppyProvider } from "@cachepuppy/react";
import { useMemo, useState } from "react";
import { ScenarioCard } from "./ScenarioCard.js";
import { WORKFLOW_DEMO_API, WS_URL } from "./constants.js";

function randomClientId(): string {
  if (typeof crypto !== "undefined" && "randomUUID" in crypto) {
    return `workflow-demo-${crypto.randomUUID()}`;
  }
  return `workflow-demo-${Date.now()}-${Math.floor(Math.random() * 1e6)}`;
}

export default function App() {
  const [paragraph, setParagraph] = useState(
    "alpha beta gamma delta epsilon zeta eta theta iota kappa",
  );

  const clientOptions = useMemo(
    () => ({
      url: WS_URL,
      transport: "phoenix" as const,
      clientId: randomClientId(),
    }),
    [],
  );

  return (
    <CachePuppyProvider autoConnect options={clientOptions}>
      <div className="app">
        <header className="header">
          <h1>CachePuppy workflows demo</h1>
          <p className="muted">
            Run each e2e-style scenario against your CachePuppy server. Step status updates stream over{" "}
            <code>graph_diff</code> on topic <code>workflow:&lt;id&gt;</code>.
          </p>
        </header>

        <label className="field-label" htmlFor="paragraph">
          Paragraph (passed to each scenario start)
        </label>
        <textarea
          id="paragraph"
          className="paragraph-input"
          rows={3}
          value={paragraph}
          onChange={(e) => setParagraph(e.target.value)}
        />

        <div className="meta">
          <span>
            WS: <code>{WS_URL}</code>
          </span>
          <span>
            Demo API: <code>{WORKFLOW_DEMO_API}</code>
          </span>
        </div>

        <div className="grid">
          <ScenarioCard scenario={1} apiBase={WORKFLOW_DEMO_API} paragraph={paragraph} />
          <ScenarioCard scenario={2} apiBase={WORKFLOW_DEMO_API} paragraph={paragraph} />
          <ScenarioCard scenario={3} apiBase={WORKFLOW_DEMO_API} paragraph={paragraph} />
          <ScenarioCard scenario={4} apiBase={WORKFLOW_DEMO_API} paragraph={paragraph} />
          <ScenarioCard scenario={5} apiBase={WORKFLOW_DEMO_API} paragraph={paragraph} />
        </div>
      </div>
    </CachePuppyProvider>
  );
}
