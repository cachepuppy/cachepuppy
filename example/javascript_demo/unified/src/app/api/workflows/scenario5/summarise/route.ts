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
  const resultsCount = input?.data?.resultsCount;
  if (
    typeof input !== "object" ||
    input === null ||
    typeof workflowId !== "string" ||
    typeof topic !== "string" ||
    typeof resultsCount !== "number"
  ) {
    return jsonError(400, "invalid_summarise_request");
  }
  await stepDelay();
  await getAdminClient().mergeWorkflowParallelNow(workflowId, "merge_summaries");
  return jsonOk({ branchSummary: `${topic}:${resultsCount}` });
});
