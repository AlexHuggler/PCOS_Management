import {
  existsSync,
  lstatSync,
  mkdirSync,
  mkdtempSync,
  readFileSync,
  realpathSync,
  rmSync,
} from "node:fs";
import { execFileSync } from "node:child_process";
import { tmpdir } from "node:os";
import { dirname, isAbsolute, join, resolve, sep } from "node:path";
import { fileURLToPath } from "node:url";

import { buildEvaluationBundle } from "./bundle.mjs";
import { compileSwiftImageNormalizer } from "./normalizer.mjs";
import { pinnedEvaluationCandidate, writePrivateJSON } from "./runner.mjs";

const USAGE = "usage: node prepare-bundle.mjs --source-index <absolute-source-index.json> --source-root <absolute-dataset-directory> --output-dir <new-absolute-directory>";
const REPOSITORY_ROOT = resolve(dirname(fileURLToPath(import.meta.url)), "../../..");
const CANDIDATE_SOURCE_PATHS = Object.freeze([
  "cloud/meal-scan-proxy/src",
  "tools/meal-scan-quality-evaluation/normalize-image.swift",
  "tools/meal-scan-quality-evaluation/run-evaluation.mjs",
  "tools/meal-scan-quality-evaluation/src",
]);

function fail(message) {
  throw new Error(message);
}

export function parsePrepareArguments(argumentsList) {
  if (!Array.isArray(argumentsList) || argumentsList.length !== 6) fail(USAGE);
  const values = new Map();
  for (let index = 0; index < argumentsList.length; index += 2) {
    const flag = argumentsList[index];
    const value = argumentsList[index + 1];
    if (!["--source-index", "--source-root", "--output-dir"].includes(flag) || values.has(flag) || !value) fail(USAGE);
    if (!isAbsolute(value)) fail("bundle preparation paths must be absolute");
    values.set(flag, value);
  }
  if (values.size !== 3) fail(USAGE);
  return {
    sourceIndexPath: values.get("--source-index"),
    sourceRoot: values.get("--source-root"),
    outputDirectory: values.get("--output-dir"),
  };
}

export function loadFrozenEvaluationCandidate(execFile = execFileSync) {
  let status;
  let sourceCommit;
  try {
    status = execFile(
      "git",
      ["-C", REPOSITORY_ROOT, "status", "--porcelain", "--untracked-files=all", "--", ...CANDIDATE_SOURCE_PATHS],
      { encoding: "utf8", stdio: ["ignore", "pipe", "pipe"] },
    );
    sourceCommit = execFile(
      "git",
      ["-C", REPOSITORY_ROOT, "rev-parse", "--verify", "HEAD^{commit}"],
      { encoding: "utf8", stdio: ["ignore", "pipe", "pipe"] },
    );
  } catch {
    fail("unable to freeze the evaluation candidate from the repository");
  }
  if (typeof status !== "string" || status.trim() !== "") {
    fail("evaluation model, prompt, schema, normalizer, and runner sources must be clean and committed before bundle preparation");
  }
  return pinnedEvaluationCandidate(typeof sourceCommit === "string" ? sourceCommit.trim() : "");
}

export function assertSourceImagePaths({ sourceIndex, sourceRoot } = {}) {
  if (!Array.isArray(sourceIndex?.records) || !isAbsolute(sourceRoot)) fail("source image configuration is invalid");

  let sourceRootMetadata;
  let resolvedSourceRoot;
  try {
    sourceRootMetadata = lstatSync(sourceRoot);
    resolvedSourceRoot = realpathSync(sourceRoot);
  } catch {
    fail("declared source root is unavailable");
  }
  if (sourceRootMetadata.isSymbolicLink()) fail("declared source root must not be a symlink");
  if (!sourceRootMetadata.isDirectory()) fail("declared source root must be a directory");

  for (const record of sourceIndex.records) {
    const path = record?.sourceImagePath;
    if (!isAbsolute(path)) fail("source image paths must be absolute");
    let metadata;
    let resolvedPath;
    try {
      metadata = lstatSync(path);
      resolvedPath = realpathSync(path);
    } catch {
      fail("source index contains an unavailable image");
    }
    if (metadata.isSymbolicLink()) fail("source index must not contain symlink images");
    if (!metadata.isFile()) fail("source index must contain regular image files");
    if (!resolvedPath.startsWith(`${resolvedSourceRoot}${sep}`)) {
      fail("source images must stay inside the declared source root");
    }
  }
}

function readSourceIndex(path, readText) {
  let text;
  try {
    text = readText(path, "utf8");
  } catch {
    fail("unable to read source index file");
  }
  try {
    return JSON.parse(text);
  } catch {
    fail("source index file is invalid JSON");
  }
}

export async function runPrepareBundleCommand({
  argv,
  readText = readFileSync,
  makeTemporaryDirectory = () => mkdtempSync(join(tmpdir(), "cyclebalance-image-normalizer-")),
  compileNormalizer = compileSwiftImageNormalizer,
  loadCandidate = loadFrozenEvaluationCandidate,
} = {}) {
  const options = parsePrepareArguments(argv);
  const candidate = loadCandidate();
  const sourceIndex = readSourceIndex(options.sourceIndexPath, readText);
  assertSourceImagePaths({ sourceIndex, sourceRoot: options.sourceRoot });
  if (existsSync(options.outputDirectory)) fail("bundle output directory already exists");

  const normalizedImageDirectory = join(options.outputDirectory, "images");
  const manifestPath = join(options.outputDirectory, "manifest.json");
  const imageMapPath = join(options.outputDirectory, "image-map.json");
  let outputCreated = false;
  let temporaryDirectory;
  try {
    mkdirSync(options.outputDirectory, { mode: 0o700 });
    outputCreated = true;
    mkdirSync(normalizedImageDirectory, { mode: 0o700 });
    temporaryDirectory = makeTemporaryDirectory();
    if (!existsSync(temporaryDirectory)) mkdirSync(temporaryDirectory, { mode: 0o700 });
    const normalizeImage = compileNormalizer({ temporaryDirectory });
    const bundle = await buildEvaluationBundle({ sourceIndex, normalizedImageDirectory, normalizeImage, candidate });
    writePrivateJSON(manifestPath, bundle.manifest);
    writePrivateJSON(imageMapPath, bundle.imageMap);
    return { manifestPath, imageMapPath, normalizedImageDirectory };
  } catch (error) {
    if (outputCreated) rmSync(options.outputDirectory, { recursive: true, force: true });
    throw error;
  } finally {
    if (temporaryDirectory) rmSync(temporaryDirectory, { recursive: true, force: true });
  }
}
