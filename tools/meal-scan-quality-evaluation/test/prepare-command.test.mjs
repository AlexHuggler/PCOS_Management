import assert from "node:assert/strict";
import { spawnSync } from "node:child_process";
import { existsSync, mkdirSync, mkdtempSync, readFileSync, rmSync, statSync, symlinkSync, writeFileSync } from "node:fs";
import { tmpdir } from "node:os";
import { dirname, join, resolve } from "node:path";
import test from "node:test";
import { fileURLToPath } from "node:url";

import {
  assertSourceImagePaths,
  loadFrozenEvaluationCandidate,
  parsePrepareArguments,
  runPrepareBundleCommand,
} from "../src/prepare-command.mjs";
import { validateManifest } from "../src/evaluation.mjs";
import { validateImageMap } from "../src/runner.mjs";

const jpeg = Buffer.from([0xff, 0xd8, 0xff, 0xd9]);
const toolkitDirectory = resolve(dirname(fileURLToPath(import.meta.url)), "..");
const prepareRunnerPath = resolve(toolkitDirectory, "prepare-bundle.mjs");
const sourceCommit = "a".repeat(40);
const candidate = Object.freeze({
  modelVersion: "gemini-3.1-flash-lite",
  promptVersion: "meal-scan-prompt-v1",
  schemaVersion: "meal-scan-gemini-v1",
  normalizerVersion: "imageio-960-jpeg078-v1",
  sourceCommit,
});

function prepareArguments(sourceIndexPath, sourceRoot, outputDirectory) {
  return [
    "--source-index", sourceIndexPath,
    "--source-root", sourceRoot,
    "--output-dir", outputDirectory,
  ];
}

function sourceForIndex(index) {
  if (index < 40) return "Nutrition5k";
  if (index < 70) return "SNAPMe";
  return "MFDS";
}

function sourceIndexFixture(root) {
  return {
    version: 1,
    records: Array.from({ length: 80 }, (_, index) => {
      const id = `public_meal_${String(index + 1).padStart(3, "0")}`;
      return {
        id,
        source: sourceForIndex(index),
        sourceUrl: `https://data.example.invalid/${id}`,
        license: "Verified public dataset license",
        sourceImagePath: join(root, `${id}.png`),
        groundTruth: { calories: 500, protein: 20, carbs: 50, fat: 20 },
        referenceType: "dataset_annotation",
        samplingReason: "deterministic public benchmark sample",
        mealType: "lunch",
        locale: "en_US",
      };
    }),
  };
}

function createSourceImages(sourceIndex) {
  for (const record of sourceIndex.records) writeFileSync(record.sourceImagePath, jpeg, { mode: 0o600 });
}

test("prepare arguments require one absolute source index source root and new output directory", () => {
  assert.deepEqual(
    parsePrepareArguments([
      "--source-index", "/private/source-index.json",
      "--source-root", "/private/public-datasets",
      "--output-dir", "/private/bundle",
    ]),
    {
      sourceIndexPath: "/private/source-index.json",
      sourceRoot: "/private/public-datasets",
      outputDirectory: "/private/bundle",
    },
  );
  assert.throws(() => parsePrepareArguments([
    "--source-index", "relative.json",
    "--source-root", "/private/public-datasets",
    "--output-dir", "/private/bundle",
  ]), /absolute/i);
  assert.throws(() => parsePrepareArguments(["--output-dir", "/private/bundle"]), /usage/i);
});

test("freezes only clean committed model prompt schema normalizer and runner sources", () => {
  const calls = [];
  const frozen = loadFrozenEvaluationCandidate((command, args, options) => {
    calls.push({ command, args, options });
    return args.includes("status") ? "" : `${sourceCommit}\n`;
  });

  assert.deepEqual(frozen, candidate);
  assert.equal(calls.length, 2);
  assert.equal(calls.every(({ command }) => command === "git"), true);
  assert.equal(calls[0].args.includes("--porcelain"), true);
  assert.equal(calls[0].args.includes("cloud/meal-scan-proxy/src"), true);
  assert.equal(calls[1].args.includes("HEAD^{commit}"), true);
  assert.throws(
    () => loadFrozenEvaluationCandidate((_command, args) => args.includes("status") ? " M cloud/meal-scan-proxy/src/server.js\n" : `${sourceCommit}\n`),
    /clean and committed/i,
  );
});

test("source image paths are confined to regular non-symlink files inside the declared source root", (t) => {
  const root = mkdtempSync(join(tmpdir(), "cyclebalance-source-paths-"));
  const sourceRoot = join(root, "public-datasets");
  const insidePath = join(sourceRoot, "inside.jpg");
  const outsidePath = join(root, "outside.jpg");
  const symlinkPath = join(sourceRoot, "linked.jpg");
  mkdirSync(sourceRoot);
  writeFileSync(insidePath, jpeg);
  writeFileSync(outsidePath, jpeg);
  symlinkSync(insidePath, symlinkPath);
  t.after(() => rmSync(root, { recursive: true, force: true }));

  assert.doesNotThrow(() => assertSourceImagePaths({
    sourceIndex: { records: [{ sourceImagePath: insidePath }] },
    sourceRoot,
  }));
  assert.throws(() => assertSourceImagePaths({
    sourceIndex: { records: [{ sourceImagePath: outsidePath }] },
    sourceRoot,
  }), /inside the declared source root/i);
  assert.throws(() => assertSourceImagePaths({
    sourceIndex: { records: [{ sourceImagePath: symlinkPath }] },
    sourceRoot,
  }), /symlink/i);
});

test("creates a private complete bundle and removes compiler scratch data", async (t) => {
  const root = mkdtempSync(join(tmpdir(), "cyclebalance-prepare-bundle-"));
  const sourceIndexPath = join(root, "source-index.json");
  const outputDirectory = join(root, "bundle");
  const scratchDirectories = [];
  t.after(() => rmSync(root, { recursive: true, force: true }));
  const sourceIndex = sourceIndexFixture(root);
  createSourceImages(sourceIndex);
  writeFileSync(sourceIndexPath, JSON.stringify(sourceIndex));

  const summary = await runPrepareBundleCommand({
    argv: prepareArguments(sourceIndexPath, root, outputDirectory),
    loadCandidate: () => candidate,
    makeTemporaryDirectory: () => {
      const path = join(root, "compiler-scratch");
      scratchDirectories.push(path);
      return path;
    },
    compileNormalizer: ({ temporaryDirectory }) => {
      assert.equal(temporaryDirectory, scratchDirectories[0]);
      return (_sourcePath, outputPath) => {
        writeFileSync(outputPath, jpeg, { mode: 0o600 });
        return jpeg;
      };
    },
  });

  const manifest = JSON.parse(readFileSync(summary.manifestPath, "utf8"));
  const imageMap = JSON.parse(readFileSync(summary.imageMapPath, "utf8"));
  const manifestByID = validateManifest(manifest);
  validateImageMap(imageMap, manifestByID);
  assert.equal(statSync(outputDirectory).mode & 0o777, 0o700);
  assert.equal(statSync(join(outputDirectory, "images")).mode & 0o777, 0o700);
  assert.equal(statSync(summary.manifestPath).mode & 0o777, 0o600);
  assert.equal(statSync(summary.imageMapPath).mode & 0o777, 0o600);
  assert.equal(existsSync(scratchDirectories[0]), false);
});

test("removes a newly-created partial bundle when normalization fails", async (t) => {
  const root = mkdtempSync(join(tmpdir(), "cyclebalance-prepare-failure-"));
  const sourceIndexPath = join(root, "source-index.json");
  const outputDirectory = join(root, "bundle");
  t.after(() => rmSync(root, { recursive: true, force: true }));
  const sourceIndex = sourceIndexFixture(root);
  createSourceImages(sourceIndex);
  writeFileSync(sourceIndexPath, JSON.stringify(sourceIndex));

  await assert.rejects(
    runPrepareBundleCommand({
      argv: prepareArguments(sourceIndexPath, root, outputDirectory),
      loadCandidate: () => candidate,
      makeTemporaryDirectory: () => join(root, "compiler-scratch"),
      compileNormalizer: () => () => {
        throw new Error("normalization failed");
      },
    }),
    /normalization failed/,
  );
  assert.equal(existsSync(outputDirectory), false);
});

test("rejects an out-of-root source image before compiling or creating output", async (t) => {
  const root = mkdtempSync(join(tmpdir(), "cyclebalance-prepare-source-reject-"));
  const sourceRoot = join(root, "public-datasets");
  const sourceIndexPath = join(root, "source-index.json");
  const outputDirectory = join(root, "bundle");
  mkdirSync(sourceRoot);
  const sourceIndex = sourceIndexFixture(sourceRoot);
  createSourceImages(sourceIndex);
  const outsidePath = join(root, "outside.jpg");
  writeFileSync(outsidePath, jpeg);
  sourceIndex.records[0].sourceImagePath = outsidePath;
  writeFileSync(sourceIndexPath, JSON.stringify(sourceIndex));
  let compilerCalls = 0;
  t.after(() => rmSync(root, { recursive: true, force: true }));

  await assert.rejects(
    runPrepareBundleCommand({
      argv: prepareArguments(sourceIndexPath, sourceRoot, outputDirectory),
      loadCandidate: () => candidate,
      compileNormalizer: () => {
        compilerCalls += 1;
        return () => jpeg;
      },
    }),
    /inside the declared source root/i,
  );
  assert.equal(compilerCalls, 0);
  assert.equal(existsSync(outputDirectory), false);
});

test("prepare CLI reports sanitized usage without creating output", () => {
  const result = spawnSync(process.execPath, [prepareRunnerPath], { encoding: "utf8" });

  assert.equal(result.status, 1);
  assert.equal(result.stdout, "");
  assert.match(result.stderr, /^meal-scan-quality-evaluation: usage:/);
});
