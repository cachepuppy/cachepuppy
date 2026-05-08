import cors from "cors";
import express from "express";

const PORT = Number(process.env.PORT || 8787);
const CACHEPUPPY_API_BASE = (process.env.CACHEPUPPY_API_BASE || "http://127.0.0.1:4000").replace(/\/$/, "");
const PUBLIC_BASE = (process.env.WORKFLOW_DEMO_PUBLIC_URL || `http://127.0.0.1:${PORT}`).replace(/\/$/, "");
const STEP_DELAY_MS = Math.max(0, Number(process.env.WORKFLOW_STEP_DELAY_MS || 5000));

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

function stepDelay() {
  return new Promise((r) => setTimeout(r, STEP_DELAY_MS));
}

/**
 * @param {string} workflowId
 * @param {unknown} parallelCreated
 */
async function armParallelMerge(workflowId, parallelCreated) {
  const mergeStepId = parallelCreated?.mergeStep?.stepId;
  if (typeof mergeStepId !== "string") {
    throw new Error("parallel response missing mergeStep.stepId");
  }
  await postJson(
    `${CACHEPUPPY_API_BASE}/api/workflows/${encodeURIComponent(workflowId)}/parallel/merge_now`,
    { mergeStepId },
    200,
  );
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
      await stepDelay();
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
      await stepDelay();
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
      await stepDelay();
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
      await stepDelay();
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
      await stepDelay();

      const parallelCreated = await postJson(
        `${CACHEPUPPY_API_BASE}/api/workflows/${encodeURIComponent(workflowId)}/parallel`,
        {
          steps: [
            {
              stepId: "research_A",
              stepName: "research_A",
              url: `${base}/research_A`,
              method: "post",
              data: { keyword: "alpha" },
            },
            {
              stepId: "research_B",
              stepName: "research_B",
              url: `${base}/research_B`,
              method: "post",
              data: { keyword: "beta" },
            },
            {
              stepId: "research_C",
              stepName: "research_C",
              url: `${base}/research_C`,
              method: "post",
              data: { keyword: "gamma" },
            },
          ],
          mergeStep: {
            stepId: "compile",
            stepName: "compile",
            url: `${base}/compile`,
            method: "post",
            data: {},
          },
        },
        201,
      );
      await armParallelMerge(workflowId, parallelCreated);

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
        await stepDelay();
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
      await stepDelay();
      const compiled = mergeData.map((m) => m?.output?.result).join(", ");

      await postJson(
        `${CACHEPUPPY_API_BASE}/api/workflows/${encodeURIComponent(workflowId)}/steps`,
        {
          stepName: "store",
          url: `${base}/store`,
          method: "post",
          parentIds: ["compile"],
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
      await stepDelay();
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
      await stepDelay();
      const keywords = paragraph.split(/\s+/).filter(Boolean).slice(0, 5);

      const parallelCreated = await postJson(
        `${CACHEPUPPY_API_BASE}/api/workflows/${encodeURIComponent(workflowId)}/parallel`,
        {
          steps: keywords.map((keyword) => ({
            stepName: "research",
            url: `${base}/research`,
            method: "post",
            data: { keyword },
          })),
          mergeStep: {
            stepId: "compile",
            stepName: "compile",
            url: `${base}/compile`,
            method: "post",
            data: {},
          },
        },
        201,
      );
      await armParallelMerge(workflowId, parallelCreated);

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
      await stepDelay();
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
      await stepDelay();
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
      await stepDelay();
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
      await stepDelay();
      const topics = paragraph.split(/\s+/).filter(Boolean).slice(0, 3);

      await postJson(
        `${CACHEPUPPY_API_BASE}/api/workflows/${encodeURIComponent(workflowId)}/parallel`,
        {
          steps: topics.map((topic, idx) => ({
            stepId: `research_${idx + 1}`,
            stepName: "research",
            url: `${base}/research`,
            method: "post",
            data: {
              topic,
              researchStepId: `research_${idx + 1}`,
              summariseStepId: `summarise_${idx + 1}`,
            },
          })),
          mergeStep: {
            stepId: "compile",
            stepName: "compile",
            url: `${base}/compile`,
            method: "post",
            data: {},
          },
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
      const workflowId = input?.workflowId;
      const topic = input?.data?.topic;
      const researchStepId = input?.data?.researchStepId;
      const summariseStepId = input?.data?.summariseStepId;
      if (
        typeof input !== "object" ||
        typeof workflowId !== "string" ||
        typeof topic !== "string" ||
        typeof researchStepId !== "string" ||
        typeof summariseStepId !== "string"
      ) {
        return res.status(400).json({ error: "invalid_research_request" });
      }
      await stepDelay();
      const notes = `facts about ${topic}`;
      await postJson(
        `${CACHEPUPPY_API_BASE}/api/workflows/${encodeURIComponent(workflowId)}/steps`,
        {
          stepId: summariseStepId,
          stepName: "summarise",
          url: `${base}/summarise`,
          method: "post",
          parentIds: [researchStepId],
          data: {
            topic,
            notes,
            researchStepId,
            summariseStepId,
          },
        },
        201,
      );
      return res.status(200).json({ topic, notes });
    } catch (e) {
      console.error(e);
      return res.status(500).json({ error: String(/** @type {Error} */ (e).message || e) });
    }
  });

  r.post("/summarise", async (req, res) => {
    try {
      const input = req.body?.input;
      const workflowId = input?.workflowId;
      const topic = input?.data?.topic;
      const notes = input?.data?.notes;
      const researchStepId = input?.data?.researchStepId;
      const summariseStepId = input?.data?.summariseStepId;
      if (
        typeof input !== "object" ||
        typeof workflowId !== "string" ||
        typeof topic !== "string" ||
        typeof notes !== "string" ||
        typeof researchStepId !== "string" ||
        typeof summariseStepId !== "string"
      ) {
        return res.status(400).json({ error: "invalid_summarise_request" });
      }
      await stepDelay();
      await postJson(
        `${CACHEPUPPY_API_BASE}/api/workflows/${encodeURIComponent(workflowId)}/parallel/merge_now`,
        { mergeStepId: "compile" },
        200,
      );
      return res.status(200).json({ topic, branchSummary: `${topic}: ${notes}` });
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
      await stepDelay();
      const compiled = mergeData.map((m) => m?.output?.branchSummary).join(" | ");

      await postJson(
        `${CACHEPUPPY_API_BASE}/api/workflows/${encodeURIComponent(workflowId)}/steps`,
        {
          stepName: "store",
          url: `${base}/store`,
          method: "post",
          parentIds: ["compile"],
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
      await stepDelay();
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
  console.log(`Workflow step delay: ${STEP_DELAY_MS}ms`);
});
