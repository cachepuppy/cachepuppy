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
  const mergeData = input?.mergeData;
  if (
    typeof input !== "object" ||
    input === null ||
    typeof workflowId !== "string" ||
    !Array.isArray(mergeData)
  ) {
    return jsonError(400, "invalid_compile_request");
  }
  await stepDelay();
  const compiled = mergeData
    .map((m) => (m as { output?: { result?: unknown } } | null)?.output?.result)
    .join(", ");

  const base = scenarioBase(2);
  await getAdminClient().addWorkflowStep(workflowId, {
    stepName: "store",
    url: `${base}/store`,
    method: "post",
    parentIds: ["compile"],
    data: { compiled },
  });

  return jsonOk({ compiled });
});
