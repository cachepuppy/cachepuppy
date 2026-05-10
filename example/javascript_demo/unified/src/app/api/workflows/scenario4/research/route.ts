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
  const topic = input?.data?.topic;
  const researchStepId = input?.data?.researchStepId;
  const summariseStepId = input?.data?.summariseStepId;
  if (
    typeof input !== "object" ||
    input === null ||
    typeof workflowId !== "string" ||
    typeof topic !== "string" ||
    typeof researchStepId !== "string" ||
    typeof summariseStepId !== "string"
  ) {
    return jsonError(400, "invalid_research_request");
  }
  await stepDelay();
  const notes = `facts about ${topic}`;
  const base = scenarioBase(4);
  await getAdminClient().addWorkflowStep(workflowId, {
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
  return jsonOk({ topic, notes });
});
