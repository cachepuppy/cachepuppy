import cors from "cors";
import express from "express";

const PORT = Number(process.env.PORT || 8787);
const CACHEPUPPY_API_BASE = (process.env.CACHEPUPPY_API_BASE || "http://127.0.0.1:4000").replace(/\/$/, "");
const PUBLIC_BASE = (process.env.WORKFLOW_DEMO_PUBLIC_URL || `http://127.0.0.1:${PORT}`).replace(/\/$/, "");

/**
 * @param {string} url
 * @param {unknown} [body]
 * @param {number} [expectedStatus]
 */
async function postJson(url, body, expectedStatus = 200) {
  const res = await fetch(url, {
    method: "POST",
    headers: { "content-type": "application/json" },
    body: body !== undefined ? JSON.stringify(body) : undefined,
  });
  const text = await res.text();
  /** @type {Record<string, unknown>} */
  let data = {};
  if (text) {
    try {
      data = JSON.parse(text);
    } catch {
      data = { raw: text };
    }
  }
  if (res.status !== expectedStatus) {
    throw new Error(`POST ${url} expected ${expectedStatus}, got ${res.status}: ${text}`);
  }
  return data;
}

function jitterSleep() {
  const ms = 50 + Math.floor(Math.random() * 251);
  return new Promise((r) => setTimeout(r, ms));
}

function scenario1Router() {
  const r = express.Router();
  const base = `${PUBLIC_BASE}/scenario1`;

  r.post("/start", async (req, res) => {
    try {
      const paragraph = req.body?.paragraph;
      if (typeof paragraph !== "string") {
        return res.status(400).json({ error: "invalid_start_request" });
      }
      const workflow = await postJson(`${CACHEPUPPY_API_BASE}/api/workflows`, { name: "e2e-scenario-1" }, 201);
      const workflowId = workflow.workflowId;
      if (typeof workflowId !== "string") {
        return res.status(500).json({ error: "no_workflow_id" });
      }

      await postJson(
        `${CACHEPUPPY_API_BASE}/api/workflows/${encodeURIComponent(workflowId)}/steps`,
        {
          stepName: "extract",
          url: `${base}/extract`,
          method: "post",
          data: { paragraph },
        },
        201,
      );

      return res.status(201).json({ workflowId });
    } catch (e) {
      console.error(e);
      return res.status(500).json({ error: String(/** @type {Error} */ (e).message || e) });
    }
  });

  r.post("/extract", async (req, res) => {
    try {
      const input = req.body?.input;
      const workflowId = input?.workflowId;
      const paragraph = input?.data?.paragraph;
      if (typeof input !== "object" || typeof workflowId !== "string" || typeof paragraph !== "string") {
        return res.status(400).json({ error: "invalid_extract_request" });
      }
      await jitterSleep();
      const keywords = paragraph.split(/\s+/).filter(Boolean).slice(0, 3);

      await postJson(
        `${CACHEPUPPY_API_BASE}/api/workflows/${encodeURIComponent(workflowId)}/steps`,
        {
          stepName: "research",
          url: `${base}/research`,
          method: "post",
          data: { keywords },
        },
        201,
      );

      return res.status(200).json({ keywords });
    } catch (e) {
      console.error(e);
      return res.status(500).json({ error: String(/** @type {Error} */ (e).message || e) });
    }
  });

  r.post("/research", async (req, res) => {
    try {
      const input = req.body?.input;
      const workflowId = input?.workflowId;
      const keywords = input?.data?.keywords;
      if (typeof input !== "object" || typeof workflowId !== "string" || !Array.isArray(keywords)) {
        return res.status(400).json({ error: "invalid_research_request" });
      }
      const summary = `summary: ${keywords.join(", ")}`;

      await postJson(
        `${CACHEPUPPY_API_BASE}/api/workflows/${encodeURIComponent(workflowId)}/steps`,
        {
          stepName: "compile",
          url: `${base}/compile`,
          method: "post",
          data: { summary },
        },
        201,
      );

      return res.status(200).json({ summary });
    } catch (e) {
      console.error(e);
      return res.status(500).json({ error: String(/** @type {Error} */ (e).message || e) });
    }
  });

  r.post("/compile", async (req, res) => {
    try {
      const input = req.body?.input;
      const workflowId = input?.workflowId;
      const summary = input?.data?.summary;
      if (typeof input !== "object" || typeof workflowId !== "string" || typeof summary !== "string") {
        return res.status(400).json({ error: "invalid_compile_request" });
      }
      const report = `report: ${summary}`;

      await postJson(
        `${CACHEPUPPY_API_BASE}/api/workflows/${encodeURIComponent(workflowId)}/steps`,
        {
          stepName: "store",
          url: `${base}/store`,
          method: "post",
          data: { report },
        },
        201,
      );

      return res.status(200).json({ report });
    } catch (e) {
      console.error(e);
      return res.status(500).json({ error: String(/** @type {Error} */ (e).message || e) });
    }
  });

  r.post("/store", async (req, res) => {
    try {
      const input = req.body?.input;
      const report = input?.data?.report;
      if (typeof input !== "object" || typeof report !== "string") {
        return res.status(400).json({ error: "invalid_store_request" });
      }
      return res.status(200).json({ stored: true, reportLength: report.length });
    } catch (e) {
      console.error(e);
      return res.status(500).json({ error: String(/** @type {Error} */ (e).message || e) });
    }
  });

  return r;
}

function scenario2Router() {
  const r = express.Router();
  const base = `${PUBLIC_BASE}/scenario2`;

  r.post("/start", async (req, res) => {
    try {
      const paragraph = req.body?.paragraph;
      if (typeof paragraph !== "string") {
        return res.status(400).json({ error: "invalid_start_request" });
      }
      const workflow = await postJson(`${CACHEPUPPY_API_BASE}/api/workflows`, { name: "e2e-scenario-2" }, 201);
      const workflowId = workflow.workflowId;
      if (typeof workflowId !== "string") {
        return res.status(500).json({ error: "no_workflow_id" });
      }

      await postJson(
        `${CACHEPUPPY_API_BASE}/api/workflows/${encodeURIComponent(workflowId)}/steps`,
        {
          stepName: "extract",
          url: `${base}/extract`,
          method: "post",
          data: { paragraph },
        },
        201,
      );

      return res.status(201).json({ workflowId });
    } catch (e) {
      console.error(e);
      return res.status(500).json({ error: String(/** @type {Error} */ (e).message || e) });
    }
  });

  r.post("/extract", async (req, res) => {
    try {
      const input = req.body?.input;
      const workflowId = input?.workflowId;
      if (typeof input !== "object" || typeof workflowId !== "string") {
        return res.status(400).json({ error: "invalid_extract_request" });
      }

      await postJson(
        `${CACHEPUPPY_API_BASE}/api/workflows/${encodeURIComponent(workflowId)}/parallel`,
        {
          steps: [
            {
              stepName: "research_A",
              url: `${base}/research_A`,
              method: "post",
              data: { keyword: "alpha" },
            },
            {
              stepName: "research_B",
              url: `${base}/research_B`,
              method: "post",
              data: { keyword: "beta" },
            },
            {
              stepName: "research_C",
              url: `${base}/research_C`,
              method: "post",
              data: { keyword: "gamma" },
            },
          ],
        },
        201,
      );

      await postJson(
        `${CACHEPUPPY_API_BASE}/api/workflows/${encodeURIComponent(workflowId)}/merge`,
        {
          stepName: "compile",
          url: `${base}/compile`,
          method: "post",
          data: {},
        },
        201,
      );

      return res.status(200).json({ keywords: ["alpha", "beta", "gamma"] });
    } catch (e) {
      console.error(e);
      return res.status(500).json({ error: String(/** @type {Error} */ (e).message || e) });
    }
  });

  for (const branch of ["A", "B", "C"]) {
    r.post(`/research_${branch}`, async (req, res) => {
      try {
        const input = req.body?.input;
        const keyword = input?.data?.keyword;
        if (typeof input !== "object" || typeof keyword !== "string") {
          return res.status(400).json({ error: "invalid_research_request" });
        }
        return res.status(200).json({ branch, result: `res:${keyword}` });
      } catch (e) {
        console.error(e);
        return res.status(500).json({ error: String(/** @type {Error} */ (e).message || e) });
      }
    });
  }

  r.post("/compile", async (req, res) => {
    try {
      const input = req.body?.input;
      const workflowId = input?.workflowId;
      const mergeData = input?.mergeData;
      if (typeof input !== "object" || typeof workflowId !== "string" || !Array.isArray(mergeData)) {
        return res.status(400).json({ error: "invalid_compile_request" });
      }
      const compiled = mergeData.map((m) => m?.output?.result).join(", ");

      await postJson(
        `${CACHEPUPPY_API_BASE}/api/workflows/${encodeURIComponent(workflowId)}/steps`,
        {
          stepName: "store",
          url: `${base}/store`,
          method: "post",
          data: { compiled },
        },
        201,
      );

      return res.status(200).json({ compiled });
    } catch (e) {
      console.error(e);
      return res.status(500).json({ error: String(/** @type {Error} */ (e).message || e) });
    }
  });

  r.post("/store", async (req, res) => {
    try {
      const input = req.body?.input;
      const compiled = input?.data?.compiled;
      if (typeof input !== "object" || typeof compiled !== "string") {
        return res.status(400).json({ error: "invalid_store_request" });
      }
      return res.status(200).json({ stored: true, compiledLength: compiled.length });
    } catch (e) {
      console.error(e);
      return res.status(500).json({ error: String(/** @type {Error} */ (e).message || e) });
    }
  });

  return r;
}

function scenario3Router() {
  const r = express.Router();
  const base = `${PUBLIC_BASE}/scenario3`;

  r.post("/start", async (req, res) => {
    try {
      const paragraph = req.body?.paragraph;
      if (typeof paragraph !== "string") {
        return res.status(400).json({ error: "invalid_start_request" });
      }
      const workflow = await postJson(`${CACHEPUPPY_API_BASE}/api/workflows`, { name: "e2e-scenario-3" }, 201);
      const workflowId = workflow.workflowId;
      if (typeof workflowId !== "string") {
        return res.status(500).json({ error: "no_workflow_id" });
      }

      await postJson(
        `${CACHEPUPPY_API_BASE}/api/workflows/${encodeURIComponent(workflowId)}/steps`,
        {
          stepName: "extract",
          url: `${base}/extract`,
          method: "post",
          data: { paragraph },
        },
        201,
      );

      return res.status(201).json({ workflowId });
    } catch (e) {
      console.error(e);
      return res.status(500).json({ error: String(/** @type {Error} */ (e).message || e) });
    }
  });

  r.post("/extract", async (req, res) => {
    try {
      const input = req.body?.input;
      const workflowId = input?.workflowId;
      const paragraph = input?.data?.paragraph;
      if (typeof input !== "object" || typeof workflowId !== "string" || typeof paragraph !== "string") {
        return res.status(400).json({ error: "invalid_extract_request" });
      }
      await jitterSleep();
      const keywords = paragraph.split(/\s+/).filter(Boolean).slice(0, 5);

      await postJson(
        `${CACHEPUPPY_API_BASE}/api/workflows/${encodeURIComponent(workflowId)}/parallel`,
        {
          steps: keywords.map((keyword) => ({
            stepName: "research",
            url: `${base}/research`,
            method: "post",
            data: { keyword },
          })),
        },
        201,
      );

      await postJson(
        `${CACHEPUPPY_API_BASE}/api/workflows/${encodeURIComponent(workflowId)}/merge`,
        {
          stepName: "compile",
          url: `${base}/compile`,
          method: "post",
          data: {},
        },
        201,
      );

      return res.status(200).json({ branchCount: keywords.length });
    } catch (e) {
      console.error(e);
      return res.status(500).json({ error: String(/** @type {Error} */ (e).message || e) });
    }
  });

  r.post("/research", async (req, res) => {
    try {
      const input = req.body?.input;
      const keyword = input?.data?.keyword;
      if (typeof input !== "object" || typeof keyword !== "string") {
        return res.status(400).json({ error: "invalid_research_request" });
      }
      return res.status(200).json({
        word: keyword,
        definition: `definition of ${keyword}`,
      });
    } catch (e) {
      console.error(e);
      return res.status(500).json({ error: String(/** @type {Error} */ (e).message || e) });
    }
  });

  r.post("/compile", async (req, res) => {
    try {
      const input = req.body?.input;
      const workflowId = input?.workflowId;
      const mergeData = input?.mergeData;
      if (typeof input !== "object" || typeof workflowId !== "string" || !Array.isArray(mergeData)) {
        return res.status(400).json({ error: "invalid_compile_request" });
      }
      const definitions = mergeData.map((m) => m?.output);

      await postJson(
        `${CACHEPUPPY_API_BASE}/api/workflows/${encodeURIComponent(workflowId)}/steps`,
        {
          stepName: "store",
          url: `${base}/store`,
          method: "post",
          data: { definitions },
        },
        201,
      );

      return res.status(200).json({ definitions });
    } catch (e) {
      console.error(e);
      return res.status(500).json({ error: String(/** @type {Error} */ (e).message || e) });
    }
  });

  r.post("/store", async (req, res) => {
    try {
      const input = req.body?.input;
      const definitions = input?.data?.definitions;
      if (typeof input !== "object" || !Array.isArray(definitions)) {
        return res.status(400).json({ error: "invalid_store_request" });
      }
      return res.status(200).json({ stored: true, definitionsCount: definitions.length });
    } catch (e) {
      console.error(e);
      return res.status(500).json({ error: String(/** @type {Error} */ (e).message || e) });
    }
  });

  return r;
}

function scenario4Router() {
  const r = express.Router();
  const base = `${PUBLIC_BASE}/scenario4`;

  r.post("/start", async (req, res) => {
    try {
      const paragraph = req.body?.paragraph;
      if (typeof paragraph !== "string") {
        return res.status(400).json({ error: "invalid_start_request" });
      }
      const workflow = await postJson(`${CACHEPUPPY_API_BASE}/api/workflows`, { name: "e2e-scenario-4" }, 201);
      const workflowId = workflow.workflowId;
      if (typeof workflowId !== "string") {
        return res.status(500).json({ error: "no_workflow_id" });
      }

      await postJson(
        `${CACHEPUPPY_API_BASE}/api/workflows/${encodeURIComponent(workflowId)}/steps`,
        {
          stepName: "extract",
          url: `${base}/extract`,
          method: "post",
          data: { paragraph },
        },
        201,
      );

      return res.status(201).json({ workflowId });
    } catch (e) {
      console.error(e);
      return res.status(500).json({ error: String(/** @type {Error} */ (e).message || e) });
    }
  });

  r.post("/extract", async (req, res) => {
    try {
      const input = req.body?.input;
      const workflowId = input?.workflowId;
      const paragraph = input?.data?.paragraph;
      if (typeof input !== "object" || typeof workflowId !== "string" || typeof paragraph !== "string") {
        return res.status(400).json({ error: "invalid_extract_request" });
      }
      await jitterSleep();
      const topics = paragraph.split(/\s+/).filter(Boolean).slice(0, 3);

      await postJson(
        `${CACHEPUPPY_API_BASE}/api/workflows/${encodeURIComponent(workflowId)}/parallel`,
        {
          steps: topics.map((topic) => ({
            stepName: "research",
            url: `${base}/research`,
            method: "post",
            data: { topic },
          })),
        },
        201,
      );

      await postJson(
        `${CACHEPUPPY_API_BASE}/api/workflows/${encodeURIComponent(workflowId)}/merge`,
        {
          stepName: "compile",
          url: `${base}/compile`,
          method: "post",
          data: {},
        },
        201,
      );

      return res.status(200).json({ topics });
    } catch (e) {
      console.error(e);
      return res.status(500).json({ error: String(/** @type {Error} */ (e).message || e) });
    }
  });

  r.post("/research", async (req, res) => {
    try {
      const input = req.body?.input;
      const topic = input?.data?.topic;
      if (typeof input !== "object" || typeof topic !== "string") {
        return res.status(400).json({ error: "invalid_research_request" });
      }
      const notes = `facts about ${topic}`;
      const summary = `summary: ${notes}`;
      return res.status(200).json({ topic, notes, summary });
    } catch (e) {
      console.error(e);
      return res.status(500).json({ error: String(/** @type {Error} */ (e).message || e) });
    }
  });

  r.post("/compile", async (req, res) => {
    try {
      const input = req.body?.input;
      const workflowId = input?.workflowId;
      const mergeData = input?.mergeData;
      if (typeof input !== "object" || typeof workflowId !== "string" || !Array.isArray(mergeData)) {
        return res.status(400).json({ error: "invalid_compile_request" });
      }
      const compiled = mergeData.map((m) => m?.output?.summary).join(" | ");

      await postJson(
        `${CACHEPUPPY_API_BASE}/api/workflows/${encodeURIComponent(workflowId)}/steps`,
        {
          stepName: "store",
          url: `${base}/store`,
          method: "post",
          data: { compiled },
        },
        201,
      );

      return res.status(200).json({ compiled });
    } catch (e) {
      console.error(e);
      return res.status(500).json({ error: String(/** @type {Error} */ (e).message || e) });
    }
  });

  r.post("/store", async (req, res) => {
    try {
      const input = req.body?.input;
      const compiled = input?.data?.compiled;
      if (typeof input !== "object" || typeof compiled !== "string") {
        return res.status(400).json({ error: "invalid_store_request" });
      }
      return res.status(200).json({ stored: true, compiledLength: compiled.length });
    } catch (e) {
      console.error(e);
      return res.status(500).json({ error: String(/** @type {Error} */ (e).message || e) });
    }
  });

  return r;
}

const app = express();
app.use(cors());
app.use(express.json());

app.get("/health", (_req, res) => {
  res.json({ ok: true, cachepuppyApiBase: CACHEPUPPY_API_BASE, publicBase: PUBLIC_BASE });
});

app.use("/scenario1", scenario1Router());
app.use("/scenario2", scenario2Router());
app.use("/scenario3", scenario3Router());
app.use("/scenario4", scenario4Router());

app.listen(PORT, () => {
  console.log(`Workflows demo server listening on ${PUBLIC_BASE} (port ${PORT})`);
  console.log(`CachePuppy API: ${CACHEPUPPY_API_BASE}`);
});
