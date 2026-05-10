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
  const keyword = input?.data?.keyword;
  if (typeof input !== "object" || input === null || typeof keyword !== "string") {
    return jsonError(400, "invalid_research_request");
  }
  await stepDelay();
  return jsonOk({
    word: keyword,
    definition: `definition of ${keyword}`,
  });
});
