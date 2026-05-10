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
  if (typeof input !== "object" || input === null || typeof workflowId !== "string") {
    return jsonError(400, "invalid_extract_request");
  }
  await stepDelay();

  const base = scenarioBase(6);
  await getAdminClient().addWorkflowParallel(
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

  return jsonOk({ topics: ["A", "B"] });
});
