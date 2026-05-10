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
  const summary = input?.data?.summary;
  if (
    typeof input !== "object" ||
    input === null ||
    typeof workflowId !== "string" ||
    typeof summary !== "string"
  ) {
    return jsonError(400, "invalid_compile_request");
  }
  await stepDelay();
  const report = `report: ${summary}`;

  const base = scenarioBase(1);
  await getAdminClient().addWorkflowStep(workflowId, {
    stepName: "store",
    url: `${base}/store`,
    method: "post",
    data: { report },
  });

  return jsonOk({ report });
});
