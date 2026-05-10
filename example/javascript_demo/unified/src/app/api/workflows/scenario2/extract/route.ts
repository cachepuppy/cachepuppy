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

  const base = scenarioBase(2);
  const parallelCreated = await getAdminClient().addWorkflowParallel(
    workflowId,
    [
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
    {
      stepId: "compile",
      stepName: "compile",
      url: `${base}/compile`,
      method: "post",
      data: {},
    },
  );
  await armParallelMerge(workflowId, parallelCreated);

  return jsonOk({ keywords: ["alpha", "beta", "gamma"] });
});
