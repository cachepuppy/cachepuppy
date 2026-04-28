import { Command } from "commander";
import enquirer from "enquirer";
import ora from "ora";
import { loadConfig, resolveRuntimePaths, writeComposeEnv } from "../lib/config.js";
import { composeDown, composeUp, dockerPull } from "../lib/docker.js";
import { waitForReady } from "../lib/health.js";
import { assertDockerReady } from "../lib/preflight.js";
import { CliError, ExitCode, success } from "../lib/ui.js";

interface ResetOptions {
  yes?: boolean;
  noPull?: boolean;
  noStart?: boolean;
}

export function registerResetCommand(program: Command): void {
  program
    .command("reset")
    .description("Reset CachePuppy containers and volumes")
    .option("--yes", "Skip destructive confirmation")
    .option("--no-pull", "Skip pulling image after reset")
    .option("--no-start", "Do not restart services after reset")
    .action(async (options: ResetOptions) => {
      const paths = resolveRuntimePaths();
      const config = await loadConfig(paths);

      await assertDockerReady();

      if (!options.yes) {
        const answer = (await enquirer.prompt({
          type: "confirm",
          name: "reset",
          message: "This removes local CachePuppy volumes. Continue?",
          initial: false,
        })) as { reset: boolean };
        if (!answer.reset) {
          throw new CliError("Reset cancelled by user.", ExitCode.UserCancelled);
        }
      }

      await writeComposeEnv(paths, config);
      const downSpinner = ora("Removing containers and volumes").start();
      await composeDown(paths, config, { volumes: true, removeOrphans: true });
      downSpinner.succeed("Runtime cleaned");

      if (options.noPull !== true) {
        const pullSpinner = ora(`Pulling ${config.imageRepo}:${config.currentTag}`).start();
        await dockerPull(`${config.imageRepo}:${config.currentTag}`);
        pullSpinner.succeed("Image pulled");
      }

      if (options.noStart !== true) {
        const upSpinner = ora("Restarting services").start();
        await composeUp(paths, config);
        upSpinner.succeed("Services restarted");

        const readyUrl = `http://localhost:${config.httpPort}/readyz`;
        const healthSpinner = ora("Waiting for readiness").start();
        await waitForReady(readyUrl, 90);
        healthSpinner.succeed("Server is ready");
      }

      success("CachePuppy reset complete.");
    });
}
