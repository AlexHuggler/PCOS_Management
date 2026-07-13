#!/usr/bin/env node

import { runEvaluationCommand } from "./src/command.mjs";

try {
  const summary = await runEvaluationCommand({ argv: process.argv.slice(2) });
  process.stdout.write(
    `Evaluated ${summary.evaluatedRecordCount} primary records and ${summary.stabilityRunCount} stability runs.\n`,
  );
} catch (error) {
  process.stderr.write(`meal-scan-quality-evaluation: ${error.message}\n`);
  process.exitCode = 1;
}
