import { getAdminClient } from "@/lib/adminClient";
import { stepDelay } from "@/lib/delay";
import {
  jsonError,
  jsonOk,
  readJson,
  scenarioBase,
  withErrorBoundary,
  type StepCallbackBody,
} from "@/lib/workflowRoute";

export const runtime = "nodejs";
export const dynamic = "force-dynamic";

export const POST = withErrorBoundary(async (request: Request) => {
  const body = await readJson<StepCallbackBody>(request);
  const input = body?.input;
  const workflowId = input?.workflowId;
  const keywords = input?.data?.keywords;
  if (
    typeof input !== "object" ||
    input === null ||
    typeof workflowId !== "string" ||
    !Array.isArray(keywords)
  ) {
    return jsonError(400, "invalid_research_request");
  }
  await stepDelay();
  const summary = `summary: ${keywords.join(", ")}`;

  const base = scenarioBase(1);
  await getAdminClient().addWorkflowStep(workflowId, {
    stepName: "compile",
    url: `${base}/compile`,
    method: "post",
    data: { summary },
  });

  return jsonOk({ summary });
});
