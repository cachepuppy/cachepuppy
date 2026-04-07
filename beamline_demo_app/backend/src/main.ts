import { createClient } from "beamline_js_sdk";

async function runBackendDemo(): Promise<void> {
  const backend = createClient({
    url: "mock://beamline",
    transport: "mock",
  });

  backend.on("stateChange", ({ state }) => {
    console.log(`[backend] state=${state}`);
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
