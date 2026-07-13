#!/usr/bin/env node

import { runPrepareBundleCommand } from "./src/prepare-command.mjs";

try {
  await runPrepareBundleCommand({ argv: process.argv.slice(2) });
  process.stdout.write("Prepared 80 normalized public benchmark records.\n");
} catch (error) {
  process.stderr.write(`meal-scan-quality-evaluation: ${error.message}\n`);
  process.exitCode = 1;
}
