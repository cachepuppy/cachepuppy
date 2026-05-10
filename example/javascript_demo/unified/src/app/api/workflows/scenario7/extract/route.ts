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
  if (typeof input !== "object" || input === null || typeof workflowId !== "string") {
    return jsonError(400, "invalid_extract_request");
  }
  await stepDelay();

  const base = scenarioBase(7);
  const parallelCreated = await getAdminClient().addWorkflowParallel(
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

  return jsonOk({ keywords: ["a", "b"] });
});
