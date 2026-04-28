import { Command } from "commander";
import ora from "ora";
import { loadConfig, resolveRuntimePaths, writeComposeEnv } from "../lib/config.js";
import { composeUp } from "../lib/docker.js";
import { waitForReady } from "../lib/health.js";
import { assertDockerReady, assertPortsAvailable } from "../lib/preflight.js";
import { info, success } from "../lib/ui.js";

interface StartOptions {
  timeout?: string;
  skipPortCheck?: boolean;
}

export function registerStartCommand(program: Command): void {
  program
    .command("start")
    .description("Start CachePuppy Docker runtime")
    .option("--timeout <seconds>", "Readiness timeout in seconds", "90")
    .option("--skip-port-check", "Skip local port availability checks")
    .action(async (options: StartOptions) => {
      const paths = resolveRuntimePaths();
      const config = await loadConfig(paths);

      const prereq = ora("Checking Docker prerequisites").start();
      await assertDockerReady();
      prereq.succeed("Docker prerequisites are ready");

      if (!options.skipPortCheck) {
        const portSpinner = ora("Checking local ports").start();
        await assertPortsAvailable([config.httpPort]);
        portSpinner.succeed("Required ports are available");
      }

      await writeComposeEnv(paths, config);
      const upSpinner = ora("Starting CachePuppy services").start();
      await composeUp(paths, config);
      upSpinner.succeed("Services started");

      const timeoutSeconds = Number.parseInt(options.timeout ?? "90", 10);
      const readyUrl = `http://localhost:${config.httpPort}/readyz`;
      const healthSpinner = ora(`Waiting for readiness (${readyUrl})`).start();
      await waitForReady(readyUrl, Number.isFinite(timeoutSeconds) ? timeoutSeconds : 90);
      healthSpinner.succeed("Server is ready");

      success("CachePuppy is running.");
      info(`HTTP: http://localhost:${config.httpPort}`);
      info(`WS: ws://localhost:${config.httpPort}/socket/websocket`);
    });
}
