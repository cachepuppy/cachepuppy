import { createClient } from "beamline_js_sdk";
async function runFrontendDemo() {
    const client = createClient({
        // Replace with hosted Beamline websocket URL in real usage.
        url: "ws://localhost:4000/socket/websocket",
        transport: "phoenix",
        clientId: "frontend_demo_user_1",
    });
    client.on("stateChange", ({ state }) => {
        console.log(`[frontend] state=${state}`);
    });
    await client.connect();
    await client.subscribe("chat_room_123", (message) => {
        console.log("[frontend] Received:", message.event, message.payload, message.meta);
    });
    console.log("[frontend] Publishing chat_message_event to topic chat_room_123");
    await client.publish("chat_room_123", "chat_message_event", {
        text: "Hey all how is it going",
        ts: Date.now(),
    });
    // Keep the socket open briefly to show inbound broadcast logs.
    await new Promise((resolve) => setTimeout(resolve, 250));
    await client.disconnect("demo-complete");
}
void runFrontendDemo();
