import { mkdir, readFile, writeFile, copyFile, access } from "node:fs/promises";
import path from "node:path";
import { fileURLToPath } from "node:url";
import { z } from "zod";
import { CliError, ExitCode } from "./ui.js";

const configSchema = z.object({
  projectName: z.string().min(1).default("cachepuppy"),
  composeFile: z.string().min(1).default("docker-compose.runtime.yml"),
  imageRepo: z.string().min(1).default("cachepuppy/cachepuppy"),
  channel: z.enum(["stable"]).default("stable"),
  currentTag: z.string().min(1),
  httpPort: z.number().int().positive().default(4000),
  nodePorts: z.array(z.number().int().positive()).default([4001, 4002, 4003]),
  volumeName: z.string().min(1).default("cachepuppy_cache_shards_data"),
});

export type CliConfig = z.infer<typeof configSchema>;

export interface RuntimePaths {
  rootDir: string;
  stateDir: string;
  configPath: string;
  composePath: string;
  envPath: string;
  nginxDir: string;
  nginxConfigPath: string;
}

export function resolveRuntimePaths(rootDir: string = process.cwd()): RuntimePaths {
  const stateDir = path.join(rootDir, ".cachepuppy");
  const configPath = path.join(stateDir, "config.json");
  const composePath = path.join(stateDir, "docker-compose.runtime.yml");
  const envPath = path.join(stateDir, ".env");
  const nginxDir = path.join(stateDir, "nginx");
  const nginxConfigPath = path.join(nginxDir, "nginx.conf");

  return { rootDir, stateDir, configPath, composePath, envPath, nginxDir, nginxConfigPath };
}

export async function ensureStateDir(paths: RuntimePaths): Promise<void> {
  await mkdir(paths.stateDir, { recursive: true });
}

export async function loadConfig(paths: RuntimePaths): Promise<CliConfig> {
  try {
    const raw = await readFile(paths.configPath, "utf8");
    const parsed = JSON.parse(raw) as unknown;
    return configSchema.parse(parsed);
  } catch (error: unknown) {
    if (error instanceof Error && "code" in error && error.code === "ENOENT") {
      throw new CliError(
        "Configuration missing. Run `cachepuppy init` first.",
        ExitCode.ConfigInvalid,
      );
    }

    if (error instanceof z.ZodError) {
      throw new CliError(
        `Invalid configuration at ${paths.configPath}. Run \`cachepuppy init\` to regenerate.`,
        ExitCode.ConfigInvalid,
      );
    }

    throw error;
  }
}

export async function saveConfig(paths: RuntimePaths, config: CliConfig): Promise<void> {
  await ensureStateDir(paths);
  await writeFile(paths.configPath, `${JSON.stringify(config, null, 2)}\n`, "utf8");
}

export async function writeComposeEnv(paths: RuntimePaths, config: CliConfig): Promise<void> {
  const image = `${config.imageRepo}:${config.currentTag}`;
  const content = [
    `CACHEPUPPY_IMAGE=${image}`,
    `CACHEPUPPY_HTTP_PORT=${config.httpPort}`,
    `CACHEPUPPY_NODE1_PORT=${config.nodePorts[0] ?? 4001}`,
    `CACHEPUPPY_NODE2_PORT=${config.nodePorts[1] ?? 4002}`,
    `CACHEPUPPY_NODE3_PORT=${config.nodePorts[2] ?? 4003}`,
    `CACHEPUPPY_VOLUME_NAME=${config.volumeName}`,
    "",
  ].join("\n");

  await writeFile(paths.envPath, content, "utf8");
}

export async function ensureRuntimeCompose(paths: RuntimePaths): Promise<void> {
  await ensureStateDir(paths);
  await mkdir(paths.nginxDir, { recursive: true });
  const templatePath = path.join(resolveCliRoot(), "templates", "docker-compose.runtime.yml");
  const nginxTemplatePath = path.join(resolveCliRoot(), "templates", "nginx.conf");

  try {
    await access(paths.composePath);
  } catch (error: unknown) {
    if (error instanceof Error && "code" in error && error.code === "ENOENT") {
      await copyFile(templatePath, paths.composePath);
      return;
    }

    throw error;
  }

  try {
    await access(paths.nginxConfigPath);
  } catch (error: unknown) {
    if (error instanceof Error && "code" in error && error.code === "ENOENT") {
      await copyFile(nginxTemplatePath, paths.nginxConfigPath);
      return;
    }

    throw error;
  }
}

function resolveCliRoot(): string {
  const thisFile = fileURLToPath(import.meta.url);
  const libDir = path.dirname(thisFile);
  return path.resolve(libDir, "..", "..");
}
