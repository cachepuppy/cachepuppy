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
  const stepId = input?.stepId;
  const topic = input?.data?.topic;
  const mergeData = input?.mergeData;
  if (
    typeof input !== "object" ||
    input === null ||
    typeof workflowId !== "string" ||
    typeof stepId !== "string" ||
    typeof topic !== "string" ||
    !Array.isArray(mergeData)
  ) {
    return jsonError(400, "invalid_collect_request");
  }
  await stepDelay();

  const base = scenarioBase(5);
  await getAdminClient().addWorkflowStep(
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

  return jsonOk({ topic, collected: mergeData.length });
});
