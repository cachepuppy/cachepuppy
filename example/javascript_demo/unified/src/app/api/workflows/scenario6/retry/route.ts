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
  const body = await readJson<{ workflowId?: unknown; stepId?: unknown }>(request);
  const workflowId = body?.workflowId;
  const stepId = body?.stepId;
  if (typeof workflowId !== "string" || typeof stepId !== "string") {
    return jsonError(400, "invalid_retry_request");
  }
  const result = await getAdminClient().retryWorkflow(workflowId, { stepId });
  return jsonOk(result);
});
