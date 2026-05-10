import { getAdminClient } from "@/lib/adminClient";
import {
  jsonError,
  jsonOk,
  readJson,
  scenarioBase,
  withErrorBoundary,
} from "@/lib/workflowRoute";

export const runtime = "nodejs";
export const dynamic = "force-dynamic";

export const POST = withErrorBoundary(async (request: Request) => {
  const body = await readJson<{ paragraph?: unknown }>(request);
  const paragraph = body?.paragraph;
  if (typeof paragraph !== "string") {
    return jsonError(400, "invalid_start_request");
  }

  const admin = getAdminClient();
  const workflow = await admin.createWorkflow("e2e-scenario-1");
  const workflowId = workflow.workflowId;
  if (typeof workflowId !== "string") {
    return jsonError(500, "no_workflow_id");
  }

  const base = scenarioBase(1);
  await admin.addWorkflowStep(workflowId, {
    stepName: "extract",
    url: `${base}/extract`,
    method: "post",
    data: { paragraph },
  });

  return jsonOk({ workflowId }, 201);
});
