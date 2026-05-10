import { getAdminClient } from "@/lib/adminClient";
import { stepDelay } from "@/lib/delay";
import {
  jsonError,
  jsonOk,
  readJson,
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
  const notes = input?.data?.notes;
  const researchStepId = input?.data?.researchStepId;
  const summariseStepId = input?.data?.summariseStepId;
  if (
    typeof input !== "object" ||
    input === null ||
    typeof workflowId !== "string" ||
    typeof topic !== "string" ||
    typeof notes !== "string" ||
    typeof researchStepId !== "string" ||
    typeof summariseStepId !== "string"
  ) {
    return jsonError(400, "invalid_summarise_request");
  }
  await stepDelay();
  await getAdminClient().mergeWorkflowParallelNow(workflowId, "compile");
  return jsonOk({ topic, branchSummary: `${topic}: ${notes}` });
});
