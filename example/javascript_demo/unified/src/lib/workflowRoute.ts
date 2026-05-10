import { NextResponse } from "next/server";
import { workflowDemoPublicBase } from "./env";

/** Returns the absolute base URL for a given scenario, e.g. "http://127.0.0.1:3000/api/workflows/scenario1". */
export function scenarioBase(scenario: number): string {
  return `${workflowDemoPublicBase()}/api/workflows/scenario${scenario}`;
}

/** Parses JSON body with explicit typing; never throws. */
export async function readJson<T = unknown>(request: Request): Promise<T | null> {
  try {
    return (await request.json()) as T;
  } catch {
    return null;
  }
}

export function jsonError(status: number, error: string): NextResponse {
  return NextResponse.json({ error }, { status });
}

export function jsonOk<T>(body: T, status = 200): NextResponse {
  return NextResponse.json(body, { status });
}

/** Wraps a route handler in a try/catch that returns a 500 with the error message. */
export function withErrorBoundary<TArgs extends unknown[]>(
  fn: (...args: TArgs) => Promise<NextResponse>,
): (...args: TArgs) => Promise<NextResponse> {
  return async (...args: TArgs) => {
    try {
      return await fn(...args);
    } catch (e) {
      console.error(e);
      return jsonError(500, e instanceof Error ? e.message : String(e));
    }
  };
}

/** Shape Phoenix sends back to step callbacks. */
export interface StepCallbackBody {
  input?: {
    workflowId?: unknown;
    stepId?: unknown;
    data?: Record<string, unknown>;
    mergeData?: unknown;
  };
}
