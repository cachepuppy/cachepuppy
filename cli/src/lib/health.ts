import { setTimeout as sleep } from "node:timers/promises";
import { CliError, ExitCode } from "./ui.js";

export async function waitForReady(
  url: string,
  timeoutSeconds: number,
  pollMs: number = 2000,
): Promise<void> {
  const timeoutMs = timeoutSeconds * 1000;
  const started = Date.now();

  while (Date.now() - started < timeoutMs) {
    try {
      const response = await fetch(url);
      if (response.ok) {
        return;
      }
    } catch {
      // Readiness endpoint is expected to fail while containers boot.
    }

    await sleep(pollMs);
  }

  throw new CliError(
    `Timed out waiting for readiness at ${url}.`,
    ExitCode.HealthTimeout,
  );
}
