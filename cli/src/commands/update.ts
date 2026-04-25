import { Command } from "commander";
import ora from "ora";
import {
  loadConfig,
  resolveRuntimePaths,
  saveConfig,
  writeComposeEnv,
} from "../lib/config.js";
import { composeUp, dockerPull } from "../lib/docker.js";
import { waitForReady } from "../lib/health.js";
import { resolveLatestTag } from "../lib/registry.js";
import { info, success } from "../lib/ui.js";

interface UpdateOptions {
  image?: string;
  noRestart?: boolean;
}

export function registerUpdateCommand(program: Command): void {
  program
    .command("update")
    .description("Pull and switch to a newer CachePuppy image")
    .option("--image <image>", "Use explicit image:tag")
    .option("--no-restart", "Do not restart runtime after updating")
    .action(async (options: UpdateOptions) => {
      const paths = resolveRuntimePaths();
      const config = await loadConfig(paths);

      let imageRepo = config.imageRepo;
      let nextTag = config.currentTag;

      if (options.image) {
        const imageRef = options.image.trim();
        if (imageRef.includes(":")) {
          imageRepo = imageRef.slice(0, imageRef.lastIndexOf(":"));
          nextTag = imageRef.split(":").at(-1) ?? nextTag;
        } else {
          imageRepo = imageRef;
          const tagSpinner = ora("Resolving latest stable tag").start();
          nextTag = await resolveLatestTag(imageRepo, "stable");
          tagSpinner.succeed(`Resolved ${nextTag}`);
        }
      } else {
        const tagSpinner = ora("Resolving latest stable tag").start();
        nextTag = await resolveLatestTag(imageRepo, config.channel);
        tagSpinner.succeed(`Resolved ${nextTag}`);
      }

      if (nextTag === config.currentTag && imageRepo === config.imageRepo) {
        success(`Already up to date at ${imageRepo}:${nextTag}.`);
        return;
      }

      const pullSpinner = ora(`Pulling ${imageRepo}:${nextTag}`).start();
      await dockerPull(`${imageRepo}:${nextTag}`);
      pullSpinner.succeed("Image pulled");

      const updated = { ...config, imageRepo, currentTag: nextTag };
      await saveConfig(paths, updated);
      await writeComposeEnv(paths, updated);

      if (options.noRestart !== true) {
        const upSpinner = ora("Recreating services with new image").start();
        await composeUp(paths, updated, { forceRecreate: true });
        upSpinner.succeed("Services recreated");

        const readyUrl = `http://localhost:${updated.httpPort}/readyz`;
        const healthSpinner = ora("Waiting for readiness").start();
        await waitForReady(readyUrl, 90);
        healthSpinner.succeed("Cluster is ready");
      }

      success(`Updated to ${imageRepo}:${nextTag}`);
      info("Run `cachepuppy status` to inspect service health.");
    });
}
