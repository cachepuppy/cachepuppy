/**
 * In-memory attempt counters used by the demo's flaky steps.
 *
 * Stored on `globalThis` so they survive Next.js dev-mode HMR without resetting
 * mid-workflow.
 */

declare global {
  // eslint-disable-next-line no-var
  var __cachePuppyDemoFlakySearchB1: Map<string, number> | undefined;
  // eslint-disable-next-line no-var
  var __cachePuppyDemoScenario7Branches: Map<string, number> | undefined;
}

/** Scenario 6: per workflow `search_b_1` attempts. First 3 → 500, then 200. */
export const flakySearchB1Attempts: Map<string, number> =
  (globalThis.__cachePuppyDemoFlakySearchB1 ??= new Map());

/** Scenario 7: per `{workflowId}:{stepId}` parallel branch attempts. First 4 → 500, then 200. */
export const scenario7BranchAttempts: Map<string, number> =
  (globalThis.__cachePuppyDemoScenario7Branches ??= new Map());
