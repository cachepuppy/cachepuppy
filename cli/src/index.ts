#!/usr/bin/env node

import { Command } from "commander";
import { registerInitCommand } from "./commands/init.js";
import { registerLogsCommand } from "./commands/logs.js";
import { registerResetCommand } from "./commands/reset.js";
import { registerStartCommand } from "./commands/start.js";
import { registerStatusCommand } from "./commands/status.js";
import { registerStopCommand } from "./commands/stop.js";
import { registerUpdateCommand } from "./commands/update.js";
import { handleFatalError } from "./lib/ui.js";

const program = new Command();

program
  .name("cachepuppy")
  .description("Run CachePuppy locally using Docker")
  .version("0.1.0");

registerInitCommand(program);
registerStartCommand(program);
registerStopCommand(program);
registerResetCommand(program);
registerUpdateCommand(program);
registerStatusCommand(program);
registerLogsCommand(program);

program.parseAsync(process.argv).catch((error: unknown) => {
  handleFatalError(error);
});
