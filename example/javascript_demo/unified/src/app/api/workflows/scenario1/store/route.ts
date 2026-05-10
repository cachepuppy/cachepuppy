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
  const report = input?.data?.report;
  if (typeof input !== "object" || input === null || typeof report !== "string") {
    return jsonError(400, "invalid_store_request");
  }
  await stepDelay();
  return jsonOk({ stored: true, reportLength: report.length });
});
