import { getAdminClient } from "@/lib/adminClient";
import {
  jsonError,
  jsonOk,
  readJson,
  withErrorBoundary,
} from "@/lib/workflowRoute";

export const runtime = "nodejs";
export const dynamic = "force-dynamic";

export const POST = withErrorBoundary(async (request: Request) => {
  const body = await readJson<{ workflowId?: unknown }>(request);
  const workflowId = body?.workflowId;
  if (typeof workflowId !== "string") {
    return jsonError(400, "invalid_retry_failed_steps_request");
  }
  const result = await getAdminClient().retryFailedWorkflowSteps(workflowId);
  return jsonOk(result);
});
