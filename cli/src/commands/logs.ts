import { Command } from "commander";
import { loadConfig, resolveRuntimePaths } from "../lib/config.js";
import { composeLogs } from "../lib/docker.js";

interface LogsOptions {
  service?: string;
  tail?: string;
  since?: string;
}

export function registerLogsCommand(program: Command): void {
  program
    .command("logs")
    .description("Stream CachePuppy compose logs")
    .option("--service <service>", "Service name filter")
    .option("--tail <n>", "Line count", "100")
    .option("--since <duration>", "Since duration (e.g. 10m)")
    .action(async (options: LogsOptions) => {
      const paths = resolveRuntimePaths();
      const config = await loadConfig(paths);

      const tail = Number.parseInt(options.tail ?? "100", 10);
      await composeLogs(paths, config, {
        service: options.service,
        tail: Number.isFinite(tail) ? tail : 100,
        since: options.since,
      });
    });
}
