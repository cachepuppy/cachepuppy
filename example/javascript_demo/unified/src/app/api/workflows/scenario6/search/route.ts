import { stepDelay } from "@/lib/delay";
import { flakySearchB1Attempts } from "@/lib/retryState";
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
  const stepId = input?.stepId;
  const topic = input?.data?.topic;
  const query = input?.data?.query;
  if (
    typeof input !== "object" ||
    input === null ||
    typeof topic !== "string" ||
    typeof query !== "string"
  ) {
    return jsonError(400, "invalid_search_request");
  }
  if (stepId === "search_b_1" && typeof workflowId === "string") {
    const key = `${workflowId}:${stepId}`;
    const n = (flakySearchB1Attempts.get(key) ?? 0) + 1;
    flakySearchB1Attempts.set(key, n);
    // First 3 attempts fail (exhausts maxRetries:2 + initial). After that the
    // manual /retry kicks in and this branch finally succeeds.
    if (n <= 3) {
      return jsonError(500, "flaky_search_b_1");
    }
  }
  await stepDelay();
  return jsonOk({ topic, result: `result:${query}` });
});
