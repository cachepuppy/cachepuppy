import { workflowStepDelayMs } from "./env";

export function stepDelay(ms: number = workflowStepDelayMs()): Promise<void> {
  return new Promise((resolve) => setTimeout(resolve, ms));
}
