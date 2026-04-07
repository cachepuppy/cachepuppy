import { createClient } from "beamline_js_sdk";

async function runBackendDemo(): Promise<void> {
  const backend = createClient({
    url: "mock://beamline",
    transport: "mock",
    requestTimeoutMs: 3000,
  });

  backend.on("stateChange", ({ state }) => {
    console.log(`[backend] state=${state}`);
  });

  backend.on("message", async (message) => {
    if (message.type === "request" && message.topic === "demo.rpc" && message.event === "get_status") {
      const correlationId = message.correlationId ?? message.id;
      await backend.respond(correlationId, true, {
        service: "beamline_demo_backend",
        ok: true,
        now: Date.now(),
      });
    }
  });

  await backend.connect();

  await backend.subscribe("demo.events", async (message) => {
    if (message.event === "ping") {
      console.log("[backend] received ping, publishing pong");
      await backend.publish("demo.events", "pong", {
        from: "backend",
        ts: Date.now(),
      });
    }
  });
}

void runBackendDemo();
