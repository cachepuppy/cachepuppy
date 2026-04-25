import net from "node:net";
import { execa } from "execa";
import { CliError, ExitCode } from "./ui.js";

export async function assertDockerReady(): Promise<void> {
  await assertCommand("docker", ["--version"], "Docker CLI is not installed.");
  await assertCommand(
    "docker",
    ["compose", "version"],
    "Docker Compose plugin is not available.",
  );
  await assertCommand(
    "docker",
    ["info"],
    "Docker daemon is not running. Start Docker Desktop and retry.",
  );
}

async function assertCommand(binary: string, args: string[], message: string): Promise<void> {
  try {
    await execa(binary, args);
  } catch {
    throw new CliError(message, ExitCode.PrerequisiteMissing);
  }
}

export async function assertPortsAvailable(ports: number[]): Promise<void> {
  for (const port of ports) {
    const available = await isPortAvailable(port);
    if (!available) {
      throw new CliError(
        `Port ${port} is already in use. Stop the conflicting process or choose another port.`,
        ExitCode.PrerequisiteMissing,
      );
    }
  }
}

async function isPortAvailable(port: number): Promise<boolean> {
  return new Promise((resolve) => {
    const server = net.createServer();
    server.once("error", () => resolve(false));
    server.once("listening", () => {
      server.close(() => resolve(true));
    });
    server.listen(port, "127.0.0.1");
  });
}
