import { createClient } from "beamline_js_sdk";

async function runFrontendDemo(): Promise<void> {
  const frontend = createClient({
    // Replace with hosted Beamline websocket URL in real usage.
    url: "ws://localhost:4000/socket/websocket",
    transport: "mock",
  });

  frontend.on("stateChange", ({ state }) => {
    console.log(`[frontend] state=${state}`);
  });

  await frontend.connect();

  await frontend.subscribe("demo.events", (message) => {
    console.log("[frontend] topic message:", message.event, message.payload);
  });

  await frontend.publish("demo.events", "client_ready", {
    from: "frontend",
    ts: Date.now(),
  });

  await frontend.disconnect("demo-complete");
}

void runFrontendDemo();
