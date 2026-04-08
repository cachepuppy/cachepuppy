import { createClient, type CachePuppyClient } from "cachepuppy_js_sdk";

const WS_URL = "ws://localhost:4000/socket/websocket";
const TOPIC = "demo_room";

function makeClient(label: string, clientId: string): CachePuppyClient {
  const client = createClient({
    url: WS_URL,
    transport: "phoenix",
    clientId,
  });

  client.on("stateChange", ({ state }) => {
    console.log(`[${label}] state=${state}`);
  });

  return client;
}

async function runFrontendDemo(): Promise<void> {
  const alice = makeClient("alice", "alice");
  const bob = makeClient("bob", "bob");
  const carol = makeClient("carol", "carol");

  await Promise.all([alice.connect(), bob.connect(), carol.connect()]);

  await Promise.all([
    alice.subscribe(TOPIC, (message) => {
      console.log(`[alice] received`, message.event, message.payload);
    }),
    bob.subscribe(TOPIC, (message) => {
      console.log(`[bob] received`, message.event, message.payload);
    }),
    carol.subscribe(TOPIC, (message) => {
      console.log(`[carol] received`, message.event, message.payload);
    }),
  ]);

  // Brief pause so all channel joins / Presence are settled before publishing.
  await new Promise((resolve) => setTimeout(resolve, 300));

  const count = await alice.clientCount(TOPIC);
  console.log(`[demo] clients in topic "${TOPIC}" (count):`, count);

  console.log("[demo] alice publishes to the whole topic — expect alice, bob, carol to receive:");
  await alice.publish(TOPIC, "room_broadcast", {
    text: "Hello everyone in the room",
    ts: Date.now(),
  });

  await new Promise((resolve) => setTimeout(resolve, 400));

  console.log("[demo] alice publishTo only carol — expect only carol to receive:");
  await alice.publishTo(
    TOPIC,
    "direct_to_one",
    { text: "Private line to carol", ts: Date.now() },
    ["carol"],
  );

  await new Promise((resolve) => setTimeout(resolve, 400));

  await Promise.all([
    alice.disconnect("demo-complete"),
    bob.disconnect("demo-complete"),
    carol.disconnect("demo-complete"),
  ]);
}

void runFrontendDemo();
