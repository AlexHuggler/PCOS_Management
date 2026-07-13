import assert from "node:assert/strict";
import { spawnSync } from "node:child_process";
import { mkdtempSync, mkdirSync, rmSync, symlinkSync, writeFileSync } from "node:fs";
import { tmpdir } from "node:os";
import { dirname, join, resolve } from "node:path";
import test from "node:test";
import { fileURLToPath } from "node:url";

import {
  assertPrivateImageMapPaths,
  parseRunnerArguments,
  runEvaluationCommand,
} from "../src/command.mjs";

const argumentsFixture = [
  "--manifest", "/private/evaluation/manifest.json",
  "--image-map", "/private/evaluation/image-map.json",
  "--output", "/private/evaluation/results.json",
  "--stability-output", "/private/evaluation/stability-results.json",
  "--qualitative-template", "/private/evaluation/qualitative-review.json",
];
const toolkitDirectory = resolve(dirname(fileURLToPath(import.meta.url)), "..");
const runnerPath = resolve(toolkitDirectory, "run-evaluation.mjs");
const candidate = Object.freeze({
  modelVersion: "gemini-3.1-flash-lite",
  promptVersion: "meal-scan-prompt-v1",
  schemaVersion: "meal-scan-gemini-v1",
  normalizerVersion: "imageio-960-jpeg078-v1",
  sourceCommit: "a".repeat(40),
});

test("runner arguments require one absolute manifest image map and output path", () => {
  assert.deepEqual(parseRunnerArguments(argumentsFixture), {
    manifestPath: "/private/evaluation/manifest.json",
    imageMapPath: "/private/evaluation/image-map.json",
    outputPath: "/private/evaluation/results.json",
    stabilityOutputPath: "/private/evaluation/stability-results.json",
    qualitativeTemplatePath: "/private/evaluation/qualitative-review.json",
  });
  assert.throws(() => parseRunnerArguments(argumentsFixture.slice(0, -2)), /usage/i);
  assert.throws(
    () => parseRunnerArguments(["--manifest", "relative.json", ...argumentsFixture.slice(2)]),
    /absolute/i,
  );
});

test("missing paid confirmation stops before files cloud state or secrets are read", async () => {
  const calls = [];

  await assert.rejects(
    runEvaluationCommand({
      argv: argumentsFixture,
      environment: {},
      readText: () => calls.push("read"),
      validateBundlePaths: () => calls.push("paths"),
      validateCandidate: () => calls.push("candidate"),
      preflightService: () => calls.push("preflight"),
      loadAPIKey: () => calls.push("secret"),
      evaluate: () => calls.push("evaluate"),
      writeResults: () => calls.push("write"),
    }),
    /CONFIRM_PAID_PUBLIC_BENCHMARK=YES/,
  );
  assert.deepEqual(calls, []);
});

test("preflights and postflights the disabled private service before publishing final results", async () => {
  const calls = [];
  const manifest = { version: 2, candidate, records: [] };
  const imageMap = { version: 1, records: [] };
  const primaryResults = [{ id: "public_meal_001", structuredSuccess: false }];
  const stabilityResults = [
    { id: "public_meal_001", structuredSuccess: false },
    { id: "public_meal_001", structuredSuccess: false },
  ];
  const qualitativeTemplate = { version: 2, records: [] };

  const summary = await runEvaluationCommand({
    argv: argumentsFixture,
    environment: { CONFIRM_PAID_PUBLIC_BENCHMARK: "YES" },
    readText: (path) => {
      calls.push(`read:${path}`);
      return JSON.stringify(path.includes("image-map") ? imageMap : manifest);
    },
    validateBundlePaths: () => calls.push("paths"),
    validateCandidate: (actual) => {
      calls.push("candidate");
      assert.deepEqual(actual, candidate);
    },
    preflightService: () => { calls.push("preflight"); return { geminiSecretVersion: "2" }; },
    postflightService: () => { calls.push("postflight"); return { geminiSecretVersion: "2" }; },
    buildReviewTemplate: (actualCandidate, actualResults) => {
      calls.push("review-template");
      assert.deepEqual(actualCandidate, candidate);
      assert.deepEqual(actualResults, primaryResults);
      return qualitativeTemplate;
    },
    loadAPIKey: (secretVersion) => {
      calls.push("secret");
      assert.equal(secretVersion, "2");
      return "secret-value-in-memory";
    },
    evaluate: async (input) => {
      calls.push("evaluate");
      assert.equal(input.apiKey, "secret-value-in-memory");
      assert.deepEqual(input.manifest, manifest);
      assert.deepEqual(input.imageMap, imageMap);
      return { primaryResults, stabilityResults };
    },
    writeResults: (path, value) => {
      calls.push(`write:${path}`);
      assert.deepEqual(
        value,
        path.includes("stability")
          ? stabilityResults
          : path.includes("qualitative") ? qualitativeTemplate : primaryResults,
      );
    },
  });

  assert.deepEqual(calls, [
    "read:/private/evaluation/manifest.json",
    "read:/private/evaluation/image-map.json",
    "paths",
    "candidate",
    "preflight",
    "secret",
    "evaluate",
    "candidate",
    "postflight",
    "review-template",
    "write:/private/evaluation/results.json",
    "write:/private/evaluation/stability-results.json",
    "write:/private/evaluation/qualitative-review.json",
  ]);
  assert.deepEqual(summary, {
    evaluatedRecordCount: 1,
    stabilityRunCount: 2,
    outputPath: "/private/evaluation/results.json",
    stabilityOutputPath: "/private/evaluation/stability-results.json",
    qualitativeTemplatePath: "/private/evaluation/qualitative-review.json",
  });
  assert.equal(JSON.stringify(summary).includes("secret-value-in-memory"), false);
});

test("postflight failure publishes no evaluation output", async () => {
  const calls = [];
  await assert.rejects(
    runEvaluationCommand({
      argv: argumentsFixture,
      environment: { CONFIRM_PAID_PUBLIC_BENCHMARK: "YES" },
      readText: (path) => JSON.stringify(path.includes("image-map")
        ? { version: 1, records: [] }
        : { version: 2, candidate, records: [] }),
      validateBundlePaths: () => {},
      validateCandidate: () => calls.push("candidate"),
      preflightService: () => ({ geminiSecretVersion: "2" }),
      postflightService: () => { throw new Error("service changed during benchmark"); },
      loadAPIKey: () => "secret-value-in-memory",
      evaluate: async () => ({ primaryResults: [], stabilityResults: [] }),
      writeResults: () => calls.push("write"),
    }),
    /service changed during benchmark/i,
  );
  assert.deepEqual(calls, ["candidate", "candidate"]);
});

test("secret-version drift across the postflight fails closed before publication", async () => {
  let writes = 0;
  await assert.rejects(
    runEvaluationCommand({
      argv: argumentsFixture,
      environment: { CONFIRM_PAID_PUBLIC_BENCHMARK: "YES" },
      readText: (path) => JSON.stringify(path.includes("image-map")
        ? { version: 1, records: [] }
        : { version: 2, candidate, records: [] }),
      validateBundlePaths: () => {},
      validateCandidate: () => {},
      preflightService: () => ({ geminiSecretVersion: "2" }),
      postflightService: () => ({ geminiSecretVersion: "3" }),
      loadAPIKey: () => "secret-value-in-memory",
      evaluate: async () => ({ primaryResults: [], stabilityResults: [] }),
      writeResults: () => { writes += 1; },
    }),
    /secret version changed/i,
  );
  assert.equal(writes, 0);
});

test("image map paths are confined to regular non-symlink files in the bundle images directory", (t) => {
  const root = mkdtempSync(join(tmpdir(), "cyclebalance-image-root-"));
  const bundle = join(root, "bundle");
  const imageRoot = join(bundle, "images");
  const imageMapPath = join(bundle, "image-map.json");
  const imagePath = join(imageRoot, "public_meal_001.jpg");
  const outsidePath = join(root, "outside.jpg");
  const symlinkPath = join(imageRoot, "linked.jpg");
  t.after(() => rmSync(root, { recursive: true, force: true }));
  mkdirSync(imageRoot, { recursive: true });
  writeFileSync(imagePath, "jpeg");
  writeFileSync(outsidePath, "jpeg");
  symlinkSync(outsidePath, symlinkPath);

  assert.doesNotThrow(() => assertPrivateImageMapPaths({
    imageMap: { version: 1, records: [{ normalizedImagePath: imagePath }] },
    imageMapPath,
  }));
  assert.throws(() => assertPrivateImageMapPaths({
    imageMap: { version: 1, records: [{ normalizedImagePath: outsidePath }] },
    imageMapPath,
  }), /inside.*images/i);
  assert.throws(() => assertPrivateImageMapPaths({
    imageMap: { version: 1, records: [{ normalizedImagePath: symlinkPath }] },
    imageMapPath,
  }), /symlink/i);
});

test("private bundle images directory must not be a symlink", (t) => {
  const root = mkdtempSync(join(tmpdir(), "cyclebalance-evaluation-image-root-"));
  const bundle = join(root, "bundle");
  const outsideImageRoot = join(root, "outside-images");
  const imageMapPath = join(bundle, "image-map.json");
  const outsideImagePath = join(outsideImageRoot, "public_meal_001.jpg");
  mkdirSync(bundle);
  mkdirSync(outsideImageRoot);
  writeFileSync(outsideImagePath, "jpeg");
  symlinkSync(outsideImageRoot, join(bundle, "images"));
  t.after(() => rmSync(root, { recursive: true, force: true }));

  assert.throws(() => assertPrivateImageMapPaths({
    imageMap: {
      version: 1,
      records: [{ normalizedImagePath: join(bundle, "images", "public_meal_001.jpg") }],
    },
    imageMapPath,
  }), /images directory must not be a symlink/i);
});

test("CLI refuses a paid run before touching gcloud when confirmation is absent", () => {
  const result = spawnSync(process.execPath, [runnerPath, ...argumentsFixture], {
    encoding: "utf8",
    env: { ...process.env, CONFIRM_PAID_PUBLIC_BENCHMARK: "" },
  });

  assert.equal(result.status, 1);
  assert.equal(result.stdout, "");
  assert.match(result.stderr, /^meal-scan-quality-evaluation: set CONFIRM_PAID_PUBLIC_BENCHMARK=YES/);
  assert.equal(result.stderr.includes("secret"), false);
});
