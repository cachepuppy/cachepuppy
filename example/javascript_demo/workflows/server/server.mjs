import cors from "cors";
import express from "express";
import { createAdminClient } from "@cachepuppy/core";

const PORT = Number(process.env.PORT || 8787);
const CACHEPUPPY_API_BASE = (process.env.CACHEPUPPY_API_BASE || "http://127.0.0.1:4000").replace(/\/$/, "");
const PUBLIC_BASE = (process.env.WORKFLOW_DEMO_PUBLIC_URL || `http://127.0.0.1:${PORT}`).replace(/\/$/, "");
const STEP_DELAY_MS = Math.max(0, Number(process.env.WORKFLOW_STEP_DELAY_MS || 5000));
const CACHEPUPPY_SOCKET_URL = `${CACHEPUPPY_API_BASE.replace(/^http/i, "ws")}/socket/websocket`;
const admin = createAdminClient({ url: CACHEPUPPY_SOCKET_URL });

/** Invocations of `search_b_1` per workflow; first 3 return 500 (exhaust maxRetries:2), later calls succeed (manual retry). */
const flakySearchB1Attempts = new Map();

/** Per `{workflowId}:{stepId}` for scenario 7 parallel branches; first 4 HTTP responses are 500 (exhaust retries), then 200 until manual `retry_failed_steps`. */
const scenario7BranchAttempts = new Map();

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
  await admin.mergeWorkflowParallelNow(workflowId, mergeStepId);
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
      const workflow = await admin.createWorkflow("e2e-scenario-1");
      const workflowId = workflow.workflowId;
      if (typeof workflowId !== "string") {
        return res.status(500).json({ error: "no_workflow_id" });
      }

      await admin.addWorkflowStep(workflowId, {
        stepName: "extract",
        url: `${base}/extract`,
        method: "post",
        data: { paragraph },
      });

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

      await admin.addWorkflowStep(workflowId, {
        stepName: "research",
        url: `${base}/research`,
        method: "post",
        data: { keywords },
      });

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

      await admin.addWorkflowStep(workflowId, {
        stepName: "compile",
        url: `${base}/compile`,
        method: "post",
        data: { summary },
      });

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

      await admin.addWorkflowStep(workflowId, {
        stepName: "store",
        url: `${base}/store`,
        method: "post",
        data: { report },
      });

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
      const workflow = await admin.createWorkflow("e2e-scenario-2");
      const workflowId = workflow.workflowId;
      if (typeof workflowId !== "string") {
        return res.status(500).json({ error: "no_workflow_id" });
      }

      await admin.addWorkflowStep(workflowId, {
        stepName: "extract",
        url: `${base}/extract`,
        method: "post",
        data: { paragraph },
      });

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

      const parallelCreated = await admin.addWorkflowParallel(workflowId, [
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
          ], {
            stepId: "compile",
            stepName: "compile",
            url: `${base}/compile`,
            method: "post",
            data: {},
          });
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

      await admin.addWorkflowStep(workflowId, {
        stepName: "store",
        url: `${base}/store`,
        method: "post",
        parentIds: ["compile"],
        data: { compiled },
      });

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
      const workflow = await admin.createWorkflow("e2e-scenario-3");
      const workflowId = workflow.workflowId;
      if (typeof workflowId !== "string") {
        return res.status(500).json({ error: "no_workflow_id" });
      }

      await admin.addWorkflowStep(workflowId, {
        stepName: "extract",
        url: `${base}/extract`,
        method: "post",
        data: { paragraph },
      });

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

      const parallelCreated = await admin.addWorkflowParallel(
        workflowId,
        keywords.map((keyword) => ({
            stepName: "research",
            url: `${base}/research`,
            method: "post",
            data: { keyword },
          })),
        {
          stepId: "compile",
          stepName: "compile",
          url: `${base}/compile`,
          method: "post",
          data: {},
        },
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

      await admin.addWorkflowStep(workflowId, {
        stepName: "store",
        url: `${base}/store`,
        method: "post",
        data: { definitions },
      });

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
      const workflow = await admin.createWorkflow("e2e-scenario-4");
      const workflowId = workflow.workflowId;
      if (typeof workflowId !== "string") {
        return res.status(500).json({ error: "no_workflow_id" });
      }

      await admin.addWorkflowStep(workflowId, {
        stepName: "extract",
        url: `${base}/extract`,
        method: "post",
        data: { paragraph },
      });

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

      await admin.addWorkflowParallel(
        workflowId,
        topics.map((topic, idx) => ({
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
        {
          stepId: "compile",
          stepName: "compile",
          url: `${base}/compile`,
          method: "post",
          data: {},
        },
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
      await admin.addWorkflowStep(workflowId, {
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
      });
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
      await admin.mergeWorkflowParallelNow(workflowId, "compile");
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

      await admin.addWorkflowStep(workflowId, {
        stepName: "store",
        url: `${base}/store`,
        method: "post",
        parentIds: ["compile"],
        data: { compiled },
      });

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

function scenario5Router() {
  const r = express.Router();
  const base = `${PUBLIC_BASE}/scenario5`;

  r.post("/start", async (req, res) => {
    try {
      const paragraph = req.body?.paragraph;
      if (typeof paragraph !== "string") {
        return res.status(400).json({ error: "invalid_start_request" });
      }
      const workflow = await admin.createWorkflow("e2e-scenario-5");
      const workflowId = workflow.workflowId;
      if (typeof workflowId !== "string") {
        return res.status(500).json({ error: "no_workflow_id" });
      }

      await admin.addWorkflowStep(workflowId, {
        stepName: "extract",
        url: `${base}/extract`,
        method: "post",
        data: { paragraph },
      });

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

      await admin.addWorkflowParallel(
        workflowId,
        [
          {
            stepId: "research_a",
            stepName: "research",
            url: `${base}/research`,
            method: "post",
            data: { topic: "A" },
          },
          {
            stepId: "research_b",
            stepName: "research",
            url: `${base}/research`,
            method: "post",
            data: { topic: "B" },
          },
        ],
        {
          stepId: "merge_summaries",
          stepName: "merge_summaries",
          url: `${base}/merge_summaries`,
          method: "post",
          data: {},
        },
      );

      return res.status(200).json({ topics: ["A", "B"] });
    } catch (e) {
      console.error(e);
      return res.status(500).json({ error: String(/** @type {Error} */ (e).message || e) });
    }
  });

  r.post("/research", async (req, res) => {
    try {
      const input = req.body?.input;
      const workflowId = input?.workflowId;
      const stepId = input?.stepId;
      const topic = input?.data?.topic;
      if (
        typeof input !== "object" ||
        typeof workflowId !== "string" ||
        typeof stepId !== "string" ||
        typeof topic !== "string"
      ) {
        return res.status(400).json({ error: "invalid_research_request" });
      }
      await stepDelay();

      const parallelCreated = await admin.addWorkflowParallel(
        workflowId,
        [
          {
            stepId: `search_${topic.toLowerCase()}_1`,
            stepName: "search",
            url: `${base}/search`,
            method: "post",
            data: { topic, query: `${topic}-q1` },
          },
          {
            stepId: `search_${topic.toLowerCase()}_2`,
            stepName: "search",
            url: `${base}/search`,
            method: "post",
            data: { topic, query: `${topic}-q2` },
          },
        ],
        {
          stepId: `collect_${topic.toLowerCase()}`,
          stepName: "collect",
          url: `${base}/collect`,
          method: "post",
          data: { topic },
        },
        { invokingStepId: stepId },
      );

      await armParallelMerge(workflowId, parallelCreated);
      return res.status(200).json({ topic, stepId });
    } catch (e) {
      console.error(e);
      return res.status(500).json({ error: String(/** @type {Error} */ (e).message || e) });
    }
  });

  r.post("/search", async (req, res) => {
    try {
      const input = req.body?.input;
      const topic = input?.data?.topic;
      const query = input?.data?.query;
      if (typeof input !== "object" || typeof topic !== "string" || typeof query !== "string") {
        return res.status(400).json({ error: "invalid_search_request" });
      }
      await stepDelay();
      return res.status(200).json({ topic, result: `result:${query}` });
    } catch (e) {
      console.error(e);
      return res.status(500).json({ error: String(/** @type {Error} */ (e).message || e) });
    }
  });

  r.post("/collect", async (req, res) => {
    try {
      const input = req.body?.input;
      const workflowId = input?.workflowId;
      const stepId = input?.stepId;
      const topic = input?.data?.topic;
      const mergeData = input?.mergeData;
      if (
        typeof input !== "object" ||
        typeof workflowId !== "string" ||
        typeof stepId !== "string" ||
        typeof topic !== "string" ||
        !Array.isArray(mergeData)
      ) {
        return res.status(400).json({ error: "invalid_collect_request" });
      }
      await stepDelay();

      await admin.addWorkflowStep(
        workflowId,
        {
          stepId: `summarise_${topic.toLowerCase()}`,
          stepName: "summarise",
          url: `${base}/summarise`,
          method: "post",
          data: { topic, resultsCount: mergeData.length },
        },
        { invokingStepId: stepId },
      );

      return res.status(200).json({ topic, collected: mergeData.length });
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
      const resultsCount = input?.data?.resultsCount;
      if (
        typeof input !== "object" ||
        typeof workflowId !== "string" ||
        typeof topic !== "string" ||
        typeof resultsCount !== "number"
      ) {
        return res.status(400).json({ error: "invalid_summarise_request" });
      }
      await stepDelay();
      await admin.mergeWorkflowParallelNow(workflowId, "merge_summaries");
      return res.status(200).json({ branchSummary: `${topic}:${resultsCount}` });
    } catch (e) {
      console.error(e);
      return res.status(500).json({ error: String(/** @type {Error} */ (e).message || e) });
    }
  });

  r.post("/merge_summaries", async (req, res) => {
    try {
      const input = req.body?.input;
      const workflowId = input?.workflowId;
      const stepId = input?.stepId;
      const mergeData = input?.mergeData;
      if (
        typeof input !== "object" ||
        typeof workflowId !== "string" ||
        typeof stepId !== "string" ||
        !Array.isArray(mergeData)
      ) {
        return res.status(400).json({ error: "invalid_merge_summaries_request" });
      }
      await stepDelay();

      const compiled = mergeData.map((m) => m?.output?.branchSummary).join(" | ");

      await admin.addWorkflowStep(
        workflowId,
        {
          stepName: "store",
          stepId: "store",
          url: `${base}/store`,
          method: "post",
          data: { compiled },
        },
        { invokingStepId: stepId },
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

function scenario6Router() {
  const r = express.Router();
  const base = `${PUBLIC_BASE}/scenario6`;

  r.post("/retry", async (req, res) => {
    try {
      const workflowId = req.body?.workflowId;
      const stepId = req.body?.stepId;
      if (typeof workflowId !== "string" || typeof stepId !== "string") {
        return res.status(400).json({ error: "invalid_retry_request" });
      }
      const result = await admin.retryWorkflow(workflowId, { stepId });
      return res.status(200).json(result);
    } catch (e) {
      console.error(e);
      return res.status(500).json({ error: String(/** @type {Error} */ (e).message || e) });
    }
  });

  r.post("/start", async (req, res) => {
    try {
      const paragraph = req.body?.paragraph;
      if (typeof paragraph !== "string") {
        return res.status(400).json({ error: "invalid_start_request" });
      }
      const workflow = await admin.createWorkflow("e2e-scenario-6-retry");
      const workflowId = workflow.workflowId;
      if (typeof workflowId !== "string") {
        return res.status(500).json({ error: "no_workflow_id" });
      }

      await admin.addWorkflowStep(workflowId, {
        stepName: "extract",
        url: `${base}/extract`,
        method: "post",
        data: { paragraph },
      });

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

      await admin.addWorkflowParallel(
        workflowId,
        [
          {
            stepId: "research_a",
            stepName: "research",
            url: `${base}/research`,
            method: "post",
            data: { topic: "A" },
          },
          {
            stepId: "research_b",
            stepName: "research",
            url: `${base}/research`,
            method: "post",
            data: { topic: "B" },
          },
        ],
        {
          stepId: "merge_summaries",
          stepName: "merge_summaries",
          url: `${base}/merge_summaries`,
          method: "post",
          data: {},
        },
      );

      return res.status(200).json({ topics: ["A", "B"] });
    } catch (e) {
      console.error(e);
      return res.status(500).json({ error: String(/** @type {Error} */ (e).message || e) });
    }
  });

  r.post("/research", async (req, res) => {
    try {
      const input = req.body?.input;
      const workflowId = input?.workflowId;
      const stepId = input?.stepId;
      const topic = input?.data?.topic;
      if (
        typeof input !== "object" ||
        typeof workflowId !== "string" ||
        typeof stepId !== "string" ||
        typeof topic !== "string"
      ) {
        return res.status(400).json({ error: "invalid_research_request" });
      }
      await stepDelay();

      const parallelCreated = await admin.addWorkflowParallel(
        workflowId,
        [
          {
            stepId: `search_${topic.toLowerCase()}_1`,
            stepName: "search",
            url: `${base}/search`,
            method: "post",
            data: { topic, query: `${topic}-q1` },
            ...(topic === "B" ? { maxRetries: 2 } : {}),
          },
          {
            stepId: `search_${topic.toLowerCase()}_2`,
            stepName: "search",
            url: `${base}/search`,
            method: "post",
            data: { topic, query: `${topic}-q2` },
          },
        ],
        {
          stepId: `collect_${topic.toLowerCase()}`,
          stepName: "collect",
          url: `${base}/collect`,
          method: "post",
          data: { topic },
        },
        { invokingStepId: stepId },
      );

      await armParallelMerge(workflowId, parallelCreated);
      return res.status(200).json({ topic, stepId });
    } catch (e) {
      console.error(e);
      return res.status(500).json({ error: String(/** @type {Error} */ (e).message || e) });
    }
  });

  r.post("/search", async (req, res) => {
    try {
      const input = req.body?.input;
      const workflowId = input?.workflowId;
      const stepId = input?.stepId;
      const topic = input?.data?.topic;
      const query = input?.data?.query;
      if (
        typeof input !== "object" ||
        typeof workflowId !== "string" ||
        typeof topic !== "string" ||
        typeof query !== "string"
      ) {
        return res.status(400).json({ error: "invalid_search_request" });
      }
      if (stepId === "search_b_1") {
        const key = `${workflowId}:${stepId}`;
        const n = (flakySearchB1Attempts.get(key) ?? 0) + 1;
        flakySearchB1Attempts.set(key, n);
        if (n <= 3) {
          return res.status(500).json({ error: "flaky_search_b_1" });
        }
      }
      await stepDelay();
      return res.status(200).json({ topic, result: `result:${query}` });
    } catch (e) {
      console.error(e);
      return res.status(500).json({ error: String(/** @type {Error} */ (e).message || e) });
    }
  });

  r.post("/collect", async (req, res) => {
    try {
      const input = req.body?.input;
      const workflowId = input?.workflowId;
      const stepId = input?.stepId;
      const topic = input?.data?.topic;
      const mergeData = input?.mergeData;
      if (
        typeof input !== "object" ||
        typeof workflowId !== "string" ||
        typeof stepId !== "string" ||
        typeof topic !== "string" ||
        !Array.isArray(mergeData)
      ) {
        return res.status(400).json({ error: "invalid_collect_request" });
      }
      await stepDelay();

      await admin.addWorkflowStep(
        workflowId,
        {
          stepId: `summarise_${topic.toLowerCase()}`,
          stepName: "summarise",
          url: `${base}/summarise`,
          method: "post",
          data: { topic, resultsCount: mergeData.length },
        },
        { invokingStepId: stepId },
      );

      return res.status(200).json({ topic, collected: mergeData.length });
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
      const resultsCount = input?.data?.resultsCount;
      if (
        typeof input !== "object" ||
        typeof workflowId !== "string" ||
        typeof topic !== "string" ||
        typeof resultsCount !== "number"
      ) {
        return res.status(400).json({ error: "invalid_summarise_request" });
      }
      await stepDelay();
      await admin.mergeWorkflowParallelNow(workflowId, "merge_summaries");
      return res.status(200).json({ branchSummary: `${topic}:${resultsCount}` });
    } catch (e) {
      console.error(e);
      return res.status(500).json({ error: String(/** @type {Error} */ (e).message || e) });
    }
  });

  r.post("/merge_summaries", async (req, res) => {
    try {
      const input = req.body?.input;
      const workflowId = input?.workflowId;
      const stepId = input?.stepId;
      const mergeData = input?.mergeData;
      if (
        typeof input !== "object" ||
        typeof workflowId !== "string" ||
        typeof stepId !== "string" ||
        !Array.isArray(mergeData)
      ) {
        return res.status(400).json({ error: "invalid_merge_summaries_request" });
      }
      await stepDelay();

      const compiled = mergeData.map((m) => m?.output?.branchSummary).join(" | ");

      await admin.addWorkflowStep(
        workflowId,
        {
          stepName: "store",
          stepId: "store",
          url: `${base}/store`,
          method: "post",
          data: { compiled },
        },
        { invokingStepId: stepId },
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

function scenario7Router() {
  const r = express.Router();
  const base = `${PUBLIC_BASE}/scenario7`;

  r.post("/retry_failed_steps", async (req, res) => {
    try {
      const workflowId = req.body?.workflowId;
      if (typeof workflowId !== "string") {
        return res.status(400).json({ error: "invalid_retry_failed_steps_request" });
      }
      const result = await admin.retryFailedWorkflowSteps(workflowId);
      return res.status(200).json(result);
    } catch (e) {
      console.error(e);
      return res.status(500).json({ error: String(/** @type {Error} */ (e).message || e) });
    }
  });

  r.post("/start", async (req, res) => {
    try {
      const paragraph = req.body?.paragraph;
      if (typeof paragraph !== "string") {
        return res.status(400).json({ error: "invalid_start_request" });
      }
      const workflow = await admin.createWorkflow("e2e-scenario-7");
      const workflowId = workflow.workflowId;
      if (typeof workflowId !== "string") {
        return res.status(500).json({ error: "no_workflow_id" });
      }

      await admin.addWorkflowStep(workflowId, {
        stepName: "extract",
        url: `${base}/extract`,
        method: "post",
        data: { paragraph },
      });

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

      const parallelCreated = await admin.addWorkflowParallel(
        workflowId,
        [
          {
            stepId: "branch_a",
            stepName: "branch_a",
            url: `${base}/branch_a`,
            method: "post",
            maxRetries: 0,
            data: {},
          },
          {
            stepId: "branch_b",
            stepName: "branch_b",
            url: `${base}/branch_b`,
            method: "post",
            maxRetries: 0,
            data: {},
          },
        ],
        {
          stepId: "compile",
          stepName: "compile",
          url: `${base}/compile`,
          method: "post",
          data: {},
        },
      );
      await armParallelMerge(workflowId, parallelCreated);

      return res.status(200).json({ keywords: ["a", "b"] });
    } catch (e) {
      console.error(e);
      return res.status(500).json({ error: String(/** @type {Error} */ (e).message || e) });
    }
  });

  r.post("/branch_a", async (req, res) => {
    return scenario7BranchResponse(req, res, "branch_a");
  });

  r.post("/branch_b", async (req, res) => {
    return scenario7BranchResponse(req, res, "branch_b");
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
      const compiled = mergeData.map((m) => m?.output?.result).join(", ");

      await admin.addWorkflowStep(workflowId, {
        stepName: "store",
        url: `${base}/store`,
        method: "post",
        parentIds: ["compile"],
        data: { compiled },
      });

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

/**
 * @param {import("express").Request} req
 * @param {import("express").Response} res
 * @param {string} stepId
 */
async function scenario7BranchResponse(req, res, stepId) {
  try {
    const input = req.body?.input;
    const workflowId = input?.workflowId;
    if (typeof input !== "object" || typeof workflowId !== "string") {
      return res.status(400).json({ error: "invalid_branch_request" });
    }
    await stepDelay();
    const key = `${workflowId}:${stepId}`;
    const n = (scenario7BranchAttempts.get(key) ?? 0) + 1;
    scenario7BranchAttempts.set(key, n);
    if (n <= 4) {
      return res.status(500).json({ error: "branch_fail" });
    }
    return res.status(200).json({ result: `${stepId}_ok` });
  } catch (e) {
    console.error(e);
    return res.status(500).json({ error: String(/** @type {Error} */ (e).message || e) });
  }
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
app.use("/scenario5", scenario5Router());
app.use("/scenario6", scenario6Router());
app.use("/scenario7", scenario7Router());

app.listen(PORT, () => {
  console.log(`Workflows demo server listening on ${PUBLIC_BASE} (port ${PORT})`);
  console.log(`CachePuppy API: ${CACHEPUPPY_API_BASE}`);
  console.log(`Workflow step delay: ${STEP_DELAY_MS}ms`);
});
