#!/usr/bin/env node

import { readFileSync } from "node:fs";
import { parseResultsText, scoreEvaluation } from "./src/evaluation.mjs";

const USAGE = "usage: node score.mjs --manifest <manifest.json> --results <results.json|results.jsonl> --stability <results.json|results.jsonl> --qualitative <qualitative-review.json>";

function fail(message) {
  throw new Error(message);
}

function parseArguments(argumentsList) {
  if (argumentsList.length !== 8) fail(USAGE);
  const options = {};
  for (let index = 0; index < argumentsList.length; index += 2) {
    const flag = argumentsList[index];
    const value = argumentsList[index + 1];
    if (!["--manifest", "--results", "--stability", "--qualitative"].includes(flag) || !value || options[flag]) fail(USAGE);
    options[flag] = value;
  }
  if (!options["--manifest"] || !options["--results"] || !options["--stability"] || !options["--qualitative"]) fail(USAGE);
  return options;
}

function readText(path, kind) {
  try {
    return readFileSync(path, "utf8");
  } catch {
    fail(`unable to read ${kind} file`);
  }
}

function readManifest(path) {
  try {
    return JSON.parse(readText(path, "manifest"));
  } catch (error) {
    if (error instanceof SyntaxError) fail("manifest file is invalid JSON");
    throw error;
  }
}

function readJSON(path, kind) {
  try {
    return JSON.parse(readText(path, kind));
  } catch (error) {
    if (error instanceof SyntaxError) fail(`${kind} file is invalid JSON`);
    throw error;
  }
}

try {
  const options = parseArguments(process.argv.slice(2));
  const manifest = readManifest(options["--manifest"]);
  const results = parseResultsText(readText(options["--results"], "results"));
  const stabilityResults = parseResultsText(readText(options["--stability"], "stability panel"), "stability panel");
  const qualitativeReview = readJSON(options["--qualitative"], "qualitative review");
  const report = scoreEvaluation(manifest, results, stabilityResults, qualitativeReview);
  process.stdout.write(`${JSON.stringify(report, null, 2)}\n`);
  if (!report.gates.allPassed) process.exitCode = 1;
} catch (error) {
  process.stderr.write(`meal-scan-quality-evaluation: ${error.message}\n`);
  process.exitCode = 1;
}
