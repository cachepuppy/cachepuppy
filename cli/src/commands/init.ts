import { Command } from "commander";
import ora from "ora";
import {
  ensureRuntimeCompose,
  resolveRuntimePaths,
  saveConfig,
  writeComposeEnv,
  type CliConfig,
} from "../lib/config.js";
import { dockerPull } from "../lib/docker.js";
import { assertDockerReady } from "../lib/preflight.js";
import { resolveLatestTag } from "../lib/registry.js";
import { info, success } from "../lib/ui.js";

interface InitOptions {
  image?: string;
  noPull?: boolean;
  httpPort?: string;
  yes?: boolean;
}

export function registerInitCommand(program: Command): void {
  program
    .command("init")
    .description("Initialize CachePuppy runtime files in this directory")
    .option("--image <image>", "Override image, e.g. cachepuppy/cachepuppy:sha-xxxx")
    .option("--http-port <port>", "Public HTTP port", "4000")
    .option("--no-pull", "Skip docker pull during init")
    .option("--yes", "Use defaults without prompts")
    .action(async (options: InitOptions) => {
      const paths = resolveRuntimePaths();
      const spinner = ora("Checking Docker prerequisites").start();
      await assertDockerReady();
      spinner.succeed("Docker prerequisites are ready");

      const defaultRepo = "cachepuppy/cachepuppy";
      const imageRef = options.image?.trim();
      const httpPort = Number.parseInt(options.httpPort ?? "4000", 10);
      const explicitTag = imageRef?.includes(":") ? imageRef.split(":").at(-1) : undefined;
      const imageRepo = imageRef?.includes(":")
        ? imageRef.slice(0, imageRef.lastIndexOf(":"))
        : imageRef ?? defaultRepo;

      const tagSpinner = ora("Resolving image tag").start();
      const currentTag = explicitTag ?? (await resolveLatestTag(imageRepo, "stable"));
      tagSpinner.succeed(`Using image tag ${currentTag}`);

      const config: CliConfig = {
        projectName: "cachepuppy",
        composeFile: "docker-compose.runtime.yml",
        imageRepo,
        channel: "stable",
        currentTag,
        httpPort: Number.isFinite(httpPort) ? httpPort : 4000,
        volumeName: "cachepuppy_cache_shards_data",
      };

      await ensureRuntimeCompose(paths);
      await saveConfig(paths, config);
      await writeComposeEnv(paths, config);

      if (options.noPull !== true) {
        const pullSpinner = ora(`Pulling ${config.imageRepo}:${config.currentTag}`).start();
        await dockerPull(`${config.imageRepo}:${config.currentTag}`);
        pullSpinner.succeed("Image pulled");
      }

      success("CachePuppy initialized.");
      info(`Config: ${paths.configPath}`);
      info(`Run: cachepuppy start`);
    });
}
