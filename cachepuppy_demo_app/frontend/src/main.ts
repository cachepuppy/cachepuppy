import { createClient, type CachePuppyClient } from "cachepuppy_js_sdk";
import {
  logDemoWsChannelNodes,
  logTopicMessage,
  probeLoadBalancer,
} from "./demoUtils.js";

/** Base URL for HTTP (LB or single node). Override with API_BASE when testing. */
const API_BASE = process.env.API_BASE ?? "http://127.0.0.1:4000";
/** WebSocket URL. Default matches nginx in docker-compose (port 4000). */
const WS_URL = process.env.WS_URL ?? "ws://127.0.0.1:4000/socket/websocket";
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
  await probeLoadBalancer(API_BASE);

  //-------------------------------------------------------------------
  //-------------------------------------------------------------------

  const alice = makeClient("alice", "alice");
  const bob = makeClient("bob", "bob");
  const carol = makeClient("carol", "carol");
  const dave = makeClient("dave", "dave");
  const eve = makeClient("eve", "eve");

  //-------------------------------------------------------------------
  //-------------------------------------------------------------------

  // Serial connects (one after another) so nginx round-robin matches HTTP probes.
  await alice.connect();
  await bob.connect();
  await carol.connect();
  await dave.connect();
  await eve.connect();

  //-------------------------------------------------------------------
  //-------------------------------------------------------------------

  await alice.subscribe(TOPIC, (message) => {
    logTopicMessage("alice", message);
  });
  await bob.subscribe(TOPIC, (message) => {
    logTopicMessage("bob", message);
  });
  await carol.subscribe(TOPIC, (message) => {
    logTopicMessage("carol", message);
  });
  await dave.subscribe(TOPIC, (message) => {
    logTopicMessage("dave", message);
  });
  await eve.subscribe(TOPIC, (message) => {
    logTopicMessage("eve", message);
  });

  logDemoWsChannelNodes(
    [
      { label: "alice", client: alice },
      { label: "bob", client: bob },
      { label: "carol", client: carol },
      { label: "dave", client: dave },
      { label: "eve", client: eve },
    ],
    TOPIC,
  );

  //-------------------------------------------------------------------
  //-------------------------------------------------------------------

  // Brief pause so all channel joins / Presence are settled before publishing.
  await new Promise((resolve) => setTimeout(resolve, 300));

  console.log(
    "[alice] publishes to the whole topic — expect all five clients to receive:",
  );
  await alice.publish(TOPIC, "room_broadcast", {
    text: "Hello everyone in the room",
    ts: Date.now(),
  });

  //-------------------------------------------------------------------
  //-------------------------------------------------------------------

  await new Promise((resolve) => setTimeout(resolve, 400));

  console.log(
    "[alice] publishes to only carol — expect only carol to receive:",
  );
  await alice.publishTo(
    TOPIC,
    "direct_to_one",
    { text: "Private line to carol", ts: Date.now() },
    ["carol"],
  );

  //-------------------------------------------------------------------
  //-------------------------------------------------------------------

  await new Promise((resolve) => setTimeout(resolve, 400));

  console.log(
    '[alice] setTopicState — expect all subscribers to receive "state_updated":',
  );
  const _ = await alice.setTopicState(TOPIC, {
    phase: "ready",
    round: 1,
    updatedBy: "alice",
    ts: Date.now(),
  });

  //-------------------------------------------------------------------
  //-------------------------------------------------------------------

  await new Promise((resolve) => setTimeout(resolve, 400));

  console.log(
    "[bob] getTopicStateWithMeta — expect latest shared state map + node ids:",
  );
  const stateFromBob = await bob.getTopicStateWithMeta(TOPIC);
  console.log(
    "[bob] getTopicState response:",
    stateFromBob.state,
    "source_node=",
    stateFromBob.sourceNode ?? "unknown",
    "served_by_node=",
    stateFromBob.servedByNode ?? "unknown",
  );

  //-------------------------------------------------------------------
  //-------------------------------------------------------------------

  await new Promise((resolve) => setTimeout(resolve, 200));

  console.log("[alice] closeTopic — explicit topic process shutdown:");
  const closed = await alice.closeTopic(TOPIC);
  console.log("[alice] closeTopic response:", closed);

  //-------------------------------------------------------------------
  //-------------------------------------------------------------------

  await new Promise((resolve) => setTimeout(resolve, 200));

  console.log(
    "[bob] getTopicState after closeTopic — expect an error (topic_not_found):",
  );
  try {
    await bob.getTopicState(TOPIC);
    console.log("[bob] unexpected: getTopicState succeeded after closeTopic");
  } catch (error) {
    console.log("[bob] expected getTopicState failure after closeTopic:");
  }

  //-------------------------------------------------------------------
  //-------------------------------------------------------------------

  await new Promise((resolve) => setTimeout(resolve, 200));

  const countBeforeDisconnect = await alice.clientCount(TOPIC);
  console.log(
    `[demo] clients in topic "${TOPIC}" right before disconnect:`,
    countBeforeDisconnect,
  );

  //-------------------------------------------------------------------
  //-------------------------------------------------------------------

  await Promise.all([
    alice.disconnect("demo-complete"),
    bob.disconnect("demo-complete"),
    carol.disconnect("demo-complete"),
    dave.disconnect("demo-complete"),
    eve.disconnect("demo-complete"),
  ]);
}

void runFrontendDemo();
