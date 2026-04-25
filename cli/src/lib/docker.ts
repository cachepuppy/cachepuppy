import { execa } from "execa";
import { CliConfig, RuntimePaths } from "./config.js";

function composeBaseArgs(paths: RuntimePaths, config: CliConfig): string[] {
  return [
    "compose",
    "--project-name",
    config.projectName,
    "--env-file",
    paths.envPath,
    "--file",
    paths.composePath,
  ];
}

export async function dockerPull(image: string): Promise<void> {
  await execa("docker", ["pull", image], { stdio: "inherit" });
}

export async function composeUp(
  paths: RuntimePaths,
  config: CliConfig,
  opts?: { forceRecreate?: boolean },
): Promise<void> {
  const args = [...composeBaseArgs(paths, config), "up", "-d"];
  if (opts?.forceRecreate) {
    args.push("--force-recreate");
  }
  await execa("docker", args, { stdio: "inherit" });
}

export async function composeDown(
  paths: RuntimePaths,
  config: CliConfig,
  opts?: { volumes?: boolean; removeOrphans?: boolean },
): Promise<void> {
  const args = [...composeBaseArgs(paths, config), "down"];
  if (opts?.volumes) {
    args.push("--volumes");
  }
  if (opts?.removeOrphans) {
    args.push("--remove-orphans");
  }

  await execa("docker", args, { stdio: "inherit" });
}

export async function composePs(paths: RuntimePaths, config: CliConfig): Promise<string> {
  const args = [...composeBaseArgs(paths, config), "ps"];
  const { stdout } = await execa("docker", args);
  return stdout;
}

export async function composeLogs(
  paths: RuntimePaths,
  config: CliConfig,
  opts?: { service?: string; tail?: number; since?: string },
): Promise<void> {
  const args = [...composeBaseArgs(paths, config), "logs", "-f"];
  if (opts?.tail !== undefined) {
    args.push("--tail", String(opts.tail));
  }
  if (opts?.since) {
    args.push("--since", opts.since);
  }
  if (opts?.service) {
    args.push(opts.service);
  }
  await execa("docker", args, { stdio: "inherit" });
}
