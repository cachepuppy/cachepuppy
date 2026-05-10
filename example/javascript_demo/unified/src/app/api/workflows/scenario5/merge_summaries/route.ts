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
  const mergeData = input?.mergeData;
  if (
    typeof input !== "object" ||
    input === null ||
    typeof workflowId !== "string" ||
    typeof stepId !== "string" ||
    !Array.isArray(mergeData)
  ) {
    return jsonError(400, "invalid_merge_summaries_request");
  }
  await stepDelay();

  const compiled = mergeData
    .map(
      (m) =>
        (m as { output?: { branchSummary?: unknown } } | null)?.output
          ?.branchSummary,
    )
    .join(" | ");

  const base = scenarioBase(5);
  await getAdminClient().addWorkflowStep(
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

  return jsonOk({ compiled });
});
