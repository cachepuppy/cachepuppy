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
  const compiled = input?.data?.compiled;
  if (typeof input !== "object" || input === null || typeof compiled !== "string") {
    return jsonError(400, "invalid_store_request");
  }
  await stepDelay();
  return jsonOk({ stored: true, compiledLength: compiled.length });
});
