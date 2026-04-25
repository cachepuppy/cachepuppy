import pc from "picocolors";

export enum ExitCode {
  Success = 0,
  GenericFailure = 1,
  PrerequisiteMissing = 2,
  ConfigInvalid = 3,
  HealthTimeout = 4,
  UserCancelled = 5,
}

export class CliError extends Error {
  readonly exitCode: ExitCode;

  constructor(message: string, exitCode: ExitCode = ExitCode.GenericFailure) {
    super(message);
    this.name = "CliError";
    this.exitCode = exitCode;
  }
}

export function info(message: string): void {
  console.log(pc.cyan(message));
}

export function success(message: string): void {
  console.log(pc.green(message));
}

export function warn(message: string): void {
  console.warn(pc.yellow(message));
}

export function errorMessage(message: string): void {
  console.error(pc.red(message));
}

export function handleFatalError(error: unknown): never {
  if (error instanceof CliError) {
    errorMessage(error.message);
    process.exit(error.exitCode);
  }

  if (error instanceof Error) {
    errorMessage(error.message);
  } else {
    errorMessage("Unknown failure.");
  }

  process.exit(ExitCode.GenericFailure);
}
