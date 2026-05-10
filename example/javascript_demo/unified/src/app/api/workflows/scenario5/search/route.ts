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
  await stepDelay();
  return jsonOk({ topic, result: `result:${query}` });
});
