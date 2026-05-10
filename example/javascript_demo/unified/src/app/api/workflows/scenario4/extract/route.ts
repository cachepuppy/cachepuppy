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
  const topics = paragraph.split(/\s+/).filter(Boolean).slice(0, 3);

  const base = scenarioBase(4);
  await getAdminClient().addWorkflowParallel(
    workflowId,
    topics.map((topic, idx) => ({
      stepId: `research_${idx + 1}`,
      stepName: "research",
      url: `${base}/research`,
      method: "post" as const,
      data: {
        topic,
        researchStepId: `research_${idx + 1}`,
        summariseStepId: `summarise_${idx + 1}`,
      },
    })),
    {
      stepId: "compile",
      stepName: "compile",
      url: `${base}/compile`,
      method: "post",
      data: {},
    },
  );

  return jsonOk({ topics });
});
