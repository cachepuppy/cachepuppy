import { getAdminClient } from "./adminClient";

/**
 * Pulls the merge-step id out of an `addWorkflowParallel` response and arms
 * the merge so the demo doesn't need any external fan-in trigger.
 */
export async function armParallelMerge(
  workflowId: string,
  parallelCreated: unknown,
): Promise<void> {
  const mergeStepId =
    parallelCreated &&
    typeof parallelCreated === "object" &&
    !Array.isArray(parallelCreated)
      ? ((parallelCreated as { mergeStep?: { stepId?: unknown } }).mergeStep
          ?.stepId as string | undefined)
      : undefined;
  if (typeof mergeStepId !== "string") {
    throw new Error("parallel response missing mergeStep.stepId");
  }
  await getAdminClient().mergeWorkflowParallelNow(workflowId, mergeStepId);
}
