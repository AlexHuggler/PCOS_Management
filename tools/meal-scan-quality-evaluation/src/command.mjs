import { existsSync, lstatSync, readFileSync, realpathSync } from "node:fs";
import { dirname, isAbsolute, join, sep } from "node:path";

import {
  evaluatePublicBenchmarkSuite,
  loadPinnedGeminiAPIKey,
  preflightPinnedProductionService,
  requirePaidEvaluationConfirmation,
  writePrivateJSON,
} from "./runner.mjs";

const USAGE = "usage: node run-evaluation.mjs --manifest <absolute-manifest.json> --image-map <absolute-image-map.json> --output <absolute-results.json> --stability-output <absolute-stability-results.json>";

function fail(message) {
  throw new Error(message);
}

export function parseRunnerArguments(argumentsList) {
  if (!Array.isArray(argumentsList) || argumentsList.length !== 8) fail(USAGE);
  const values = new Map();
  for (let index = 0; index < argumentsList.length; index += 2) {
    const flag = argumentsList[index];
    const value = argumentsList[index + 1];
    if (!["--manifest", "--image-map", "--output", "--stability-output"].includes(flag) || values.has(flag) || !value) fail(USAGE);
    if (!isAbsolute(value)) fail("evaluation file paths must be absolute");
    values.set(flag, value);
  }
  if (values.size !== 4) fail(USAGE);
  if (values.get("--output") === values.get("--stability-output")) fail("primary and stability output paths must differ");
  return {
    manifestPath: values.get("--manifest"),
    imageMapPath: values.get("--image-map"),
    outputPath: values.get("--output"),
    stabilityOutputPath: values.get("--stability-output"),
  };
}

function readJSON(path, kind, readText) {
  let text;
  try {
    text = readText(path, "utf8");
  } catch {
    fail(`unable to read ${kind} file`);
  }
  try {
    return JSON.parse(text);
  } catch {
    fail(`${kind} file is invalid JSON`);
  }
}

export function assertPrivateImageMapPaths({ imageMap, imageMapPath } = {}) {
  if (!Array.isArray(imageMap?.records) || !isAbsolute(imageMapPath)) fail("private image map is invalid");
  const imageRootPath = join(dirname(imageMapPath), "images");
  let imageRootMetadata;
  let imageRoot;
  try {
    imageRootMetadata = lstatSync(imageRootPath);
    imageRoot = realpathSync(imageRootPath);
  } catch {
    fail("private bundle images directory is unavailable");
  }
  if (imageRootMetadata.isSymbolicLink()) fail("private bundle images directory must not be a symlink");
  if (!imageRootMetadata.isDirectory()) fail("private bundle images directory must be a directory");

  for (const record of imageMap.records) {
    const path = record?.normalizedImagePath;
    if (!isAbsolute(path)) fail("private image map paths must be absolute");
    let metadata;
    let resolvedPath;
    try {
      metadata = lstatSync(path);
      resolvedPath = realpathSync(path);
    } catch {
      fail("private image map contains an unavailable image");
    }
    if (metadata.isSymbolicLink()) fail("private image map must not contain symlink images");
    if (!metadata.isFile()) fail("private image map must contain regular image files");
    if (!resolvedPath.startsWith(`${imageRoot}${sep}`)) {
      fail("private image map files must stay inside the bundle images directory");
    }
  }
}

export async function runEvaluationCommand({
  argv,
  environment = process.env,
  readText = readFileSync,
  preflightService = preflightPinnedProductionService,
  loadAPIKey = loadPinnedGeminiAPIKey,
  evaluate = evaluatePublicBenchmarkSuite,
  writeResults = writePrivateJSON,
  outputExists = existsSync,
  validateBundlePaths = assertPrivateImageMapPaths,
} = {}) {
  requirePaidEvaluationConfirmation(environment.CONFIRM_PAID_PUBLIC_BENCHMARK);
  const options = parseRunnerArguments(argv);
  const manifest = readJSON(options.manifestPath, "manifest", readText);
  const imageMap = readJSON(options.imageMapPath, "image map", readText);
  validateBundlePaths({ imageMap, imageMapPath: options.imageMapPath });
  if (outputExists(options.outputPath) || outputExists(options.stabilityOutputPath)) {
    fail("evaluation output already exists");
  }

  const preflight = await preflightService();
  let apiKey = loadAPIKey(preflight?.geminiSecretVersion);
  let suite;
  try {
    suite = await evaluate({ manifest, imageMap, apiKey });
  } finally {
    apiKey = undefined;
  }
  writeResults(options.outputPath, suite.primaryResults);
  writeResults(options.stabilityOutputPath, suite.stabilityResults);
  return {
    evaluatedRecordCount: suite.primaryResults.length,
    stabilityRunCount: suite.stabilityResults.length,
    outputPath: options.outputPath,
    stabilityOutputPath: options.stabilityOutputPath,
  };
}
