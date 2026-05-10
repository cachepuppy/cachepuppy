import { stepDelay } from "@/lib/delay";
import { scenario7BranchAttempts } from "@/lib/retryState";
import {
  jsonError,
  jsonOk,
  readJson,
  withErrorBoundary,
  type StepCallbackBody,
} from "@/lib/workflowRoute";

export function makeBranchHandler(stepId: "branch_a" | "branch_b") {
  return withErrorBoundary(async (request: Request) => {
    const body = await readJson<StepCallbackBody>(request);
    const input = body?.input;
    const workflowId = input?.workflowId;
    if (typeof input !== "object" || input === null || typeof workflowId !== "string") {
      return jsonError(400, "invalid_branch_request");
    }
    await stepDelay();
    const key = `${workflowId}:${stepId}`;
    const n = (scenario7BranchAttempts.get(key) ?? 0) + 1;
    scenario7BranchAttempts.set(key, n);
    // First 4 HTTP responses fail (initial + maxRetries 0 already exhausts;
    // matching server.mjs which counts cumulative POSTs across retry-all
    // attempts). Then succeed.
    if (n <= 4) {
      return jsonError(500, "branch_fail");
    }
    return jsonOk({ result: `${stepId}_ok` });
  });
}
