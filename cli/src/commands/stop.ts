import { Command } from "commander";
import ora from "ora";
import { loadConfig, resolveRuntimePaths } from "../lib/config.js";
import { composeDown } from "../lib/docker.js";
import { success } from "../lib/ui.js";

interface StopOptions {
  volumes?: boolean;
  removeOrphans?: boolean;
}

export function registerStopCommand(program: Command): void {
  program
    .command("stop")
    .description("Stop CachePuppy containers")
    .option("--volumes", "Also remove Docker volumes")
    .option("--remove-orphans", "Remove orphan containers")
    .action(async (options: StopOptions) => {
      const paths = resolveRuntimePaths();
      const config = await loadConfig(paths);

      const spinner = ora("Stopping CachePuppy services").start();
      await composeDown(paths, config, {
        volumes: options.volumes === true,
        removeOrphans: options.removeOrphans === true,
      });
      spinner.succeed("Services stopped");

      success("CachePuppy stopped.");
    });
}
