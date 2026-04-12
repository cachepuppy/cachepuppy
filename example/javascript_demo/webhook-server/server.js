/**
 * Minimal receiver for CachePuppy topic-state webhooks (POST JSON).
 * Run before the JS demo when exercising `setTopicState(..., { flush, url, frequency })`.
 */
import http from "node:http";

const port = Number(process.env.PORT ?? "8765");
const path = "/topic-state";

const server = http.createServer((req, res) => {
  if (req.method === "POST" && req.url === path) {
    const chunks = [];
    req.on("data", (c) => chunks.push(c));
    req.on("end", () => {
      const body = Buffer.concat(chunks).toString("utf8");
      console.log(`[webhook-server] ${req.method} ${path} body=${body}`);
      res.writeHead(200, { "content-type": "application/json" });
      res.end("{}");
    });
    return;
  }

  res.writeHead(404);
  res.end();
});

server.listen(port, "0.0.0.0", () => {
  console.log(`[webhook-server] listening on http://127.0.0.1:${port}${path}`);
});
