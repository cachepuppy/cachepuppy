import { Command } from "commander";
import { execa } from "execa";
import { loadConfig, resolveRuntimePaths } from "../lib/config.js";
import { composePs } from "../lib/docker.js";
import { errorMessage, info, success, warn } from "../lib/ui.js";

export function registerStatusCommand(program: Command): void {
  program
    .command("status")
    .description("Show CachePuppy runtime status")
    .action(async () => {
      const paths = resolveRuntimePaths();
      const config = await loadConfig(paths);

      try {
        await execa("docker", ["info"]);
        success("Docker daemon: running");
      } catch {
        errorMessage("Docker daemon: unavailable");
      }

      const ps = await composePs(paths, config);
      info(ps);

      info(`Image: ${config.imageRepo}:${config.currentTag}`);
      info(`HTTP: http://localhost:${config.httpPort}`);
      info(`WS: ws://localhost:${config.httpPort}/socket/websocket`);
      warn("Use `cachepuppy logs` for streaming logs.");
    });
}
