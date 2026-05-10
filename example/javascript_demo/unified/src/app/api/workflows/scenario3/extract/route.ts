import { getAdminClient } from "@/lib/adminClient";
import { stepDelay } from "@/lib/delay";
import { armParallelMerge } from "@/lib/parallelMerge";
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
  const paragraph = input?.data?.paragraph;
  if (
    typeof input !== "object" ||
    input === null ||
    typeof workflowId !== "string" ||
    typeof paragraph !== "string"
  ) {
    return jsonError(400, "invalid_extract_request");
  }
  await stepDelay();
  const keywords = paragraph.split(/\s+/).filter(Boolean).slice(0, 5);

  const base = scenarioBase(3);
  const parallelCreated = await getAdminClient().addWorkflowParallel(
    workflowId,
    keywords.map((keyword) => ({
      stepName: "research",
      url: `${base}/research`,
      method: "post" as const,
      data: { keyword },
    })),
    {
      stepId: "compile",
      stepName: "compile",
      url: `${base}/compile`,
      method: "post",
      data: {},
    },
  );
  await armParallelMerge(workflowId, parallelCreated);

  return jsonOk({ branchCount: keywords.length });
});
