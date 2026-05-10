import { getAdminClient } from "@/lib/adminClient";
import { stepDelay } from "@/lib/delay";
import { armParallelMerge } from "@/lib/parallelMerge";
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
  if (
    typeof input !== "object" ||
    input === null ||
    typeof workflowId !== "string" ||
    typeof stepId !== "string" ||
    typeof topic !== "string"
  ) {
    return jsonError(400, "invalid_research_request");
  }
  await stepDelay();

  const base = scenarioBase(5);
  const lower = topic.toLowerCase();
  const parallelCreated = await getAdminClient().addWorkflowParallel(
    workflowId,
    [
      {
        stepId: `search_${lower}_1`,
        stepName: "search",
        url: `${base}/search`,
        method: "post",
        data: { topic, query: `${topic}-q1` },
      },
      {
        stepId: `search_${lower}_2`,
        stepName: "search",
        url: `${base}/search`,
        method: "post",
        data: { topic, query: `${topic}-q2` },
      },
    ],
    {
      stepId: `collect_${lower}`,
      stepName: "collect",
      url: `${base}/collect`,
      method: "post",
      data: { topic },
    },
    { invokingStepId: stepId },
  );

  await armParallelMerge(workflowId, parallelCreated);
  return jsonOk({ topic, stepId });
});
