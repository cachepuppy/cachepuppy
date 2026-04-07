import { createClient } from "beamline_js_sdk";
async function runFrontendDemo() {
    // Mock transport is in-memory and process-local, so we spin up both
    // sides inside one script for a full end-to-end demo without backend engine.
    const embeddedBackend = createClient({
        url: "mock://beamline",
        transport: "mock",
        requestTimeoutMs: 3000,
    });
    await embeddedBackend.connect();
    await embeddedBackend.subscribe("demo.events", async (message) => {
        if (message.event === "ping") {
            await embeddedBackend.publish("demo.events", "pong", {
                from: "embedded-backend",
                ts: Date.now(),
            });
        }
    });
    embeddedBackend.on("message", async (message) => {
        if (message.type === "request" && message.topic === "demo.rpc" && message.event === "get_status") {
            await embeddedBackend.respond(message.correlationId ?? message.id, true, {
                service: "embedded_backend",
                ok: true,
            });
        }
    });
    const frontend = createClient({
        url: "mock://beamline",
        transport: "mock",
        requestTimeoutMs: 3000,
    });
    frontend.on("stateChange", ({ state }) => {
        console.log(`[frontend] state=${state}`);
    });
    await frontend.connect();
    await frontend.subscribe("demo.events", (message) => {
        console.log("[frontend] topic message:", message.event, message.payload);
    });
    await frontend.publish("demo.events", "ping", {
        from: "frontend",
        ts: Date.now(),
    });
    const response = await frontend.request("demo.rpc", "get_status", {
        requester: "frontend",
    });
    console.log("[frontend] rpc response:", response.payload);
    await frontend.disconnect("demo-complete");
    await embeddedBackend.disconnect("demo-complete");
}
void runFrontendDemo();
