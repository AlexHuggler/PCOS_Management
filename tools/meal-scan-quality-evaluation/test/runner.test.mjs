import assert from "node:assert/strict";
import crypto from "node:crypto";
import { existsSync, mkdtempSync, readFileSync, rmSync, statSync, writeFileSync } from "node:fs";
import { tmpdir } from "node:os";
import { join } from "node:path";
import test from "node:test";

import {
  assertCurrentEvaluationCandidate,
  assertSafeProductionService,
  evaluatePublicBenchmark,
  evaluatePublicBenchmarkSuite,
  loadPinnedGeminiAPIKey,
  publishPrivateFile,
  preflightPinnedProductionService,
  requirePaidEvaluationConfirmation,
  validateImageMap,
  writePrivateJSON,
} from "../src/runner.mjs";
import { buildInterpretationDigest, validateManifest } from "../src/evaluation.mjs";

const jpeg = Buffer.from([0xff, 0xd8, 0xff, 0xd9]);
const jpegHash = crypto.createHash("sha256").update(jpeg).digest("hex");
const candidate = Object.freeze({
  modelVersion: "gemini-3.1-flash-lite",
  promptVersion: "meal-scan-prompt-v1",
  schemaVersion: "meal-scan-gemini-v1",
  normalizerVersion: "imageio-960-jpeg078-v1",
  sourceCommit: "a".repeat(40),
});

function estimateFixture({ calories = 500, protein = 20, carbs = 50, fat = 20 } = {}) {
  return {
    meal_name: "Benchmark meal",
    confidence: "medium",
    warnings: [],
    items: [{
      display_name: "Benchmark item",
      canonical_query: "benchmark item",
      estimated_grams: 350,
      confidence: "medium",
      is_mixed_dish: false,
      nutrition_fallback: {
        calories_kcal: calories,
        protein_grams: protein,
        carbs_grams: carbs,
        fat_grams: fat,
        fiber_grams: 8,
        sugar_grams: 6,
        sodium_mg: 500,
      },
    }],
  };
}

function sourceForIndex(index) {
  if (index < 40) return "Nutrition5k";
  if (index < 70) return "SNAPMe";
  return "MFDS";
}

function manifestFixture() {
  return {
    version: 2,
    candidate: { ...candidate },
    records: Array.from({ length: 80 }, (_, index) => {
      const id = `public_meal_${String(index + 1).padStart(3, "0")}`;
      return {
        id,
        source: sourceForIndex(index),
        holdout: index % 4 === 0,
        sourceUrl: `https://data.example.invalid/${id}`,
        license: "Verified public dataset license",
        imageSha256: jpegHash,
        groundTruth: { calories: 500, protein: 20, carbs: 50, fat: 20 },
        referenceType: "dataset_annotation",
        samplingReason: "deterministic public benchmark sample",
      };
    }),
  };
}

function imageMapFixture(manifest = manifestFixture()) {
  return {
    version: 1,
    records: manifest.records.map(({ id }) => ({
      id,
      normalizedImagePath: `/private/benchmark/${id}.jpg`,
      mealType: "lunch",
      locale: "en_US",
    })),
  };
}

test("requires the production service to remain disabled private and Secret Manager backed", () => {
  const service = {
    spec: {
      template: {
        spec: {
          containers: [{
            env: [
              { name: "MEAL_SCAN_ENABLED", value: "false" },
              { name: "GEMINI_API_KEY", valueFrom: { secretKeyRef: { name: "cyclebalance-gemini-api-key", key: "2" } } },
            ],
          }],
        },
      },
    },
  };

  assert.deepEqual(assertSafeProductionService(service, { bindings: [] }), { geminiSecretVersion: "2" });
  assert.throws(
    () => assertSafeProductionService({ ...service, spec: { template: { spec: { containers: [{ env: [{ name: "MEAL_SCAN_ENABLED", value: "true" }] }] } } } }, { bindings: [] }),
    /disabled/i,
  );
  assert.throws(
    () => assertSafeProductionService(service, { bindings: [{ role: "roles/run.invoker", members: ["allUsers"] }] }),
    /private/i,
  );
  assert.throws(
    () => assertSafeProductionService({
      ...service,
      metadata: { annotations: { "run.googleapis.com/invoker-iam-disabled": "true" } },
    }, { bindings: [] }),
    /invoker.*disabled|public/i,
  );
  assert.throws(
    () => assertSafeProductionService({ ...service, spec: { template: { spec: { containers: [{ env: [{ name: "MEAL_SCAN_ENABLED", value: "false" }, { name: "GEMINI_API_KEY", value: "plaintext" }] }] } } } }, { bindings: [] }),
    /Secret Manager/i,
  );
});

test("binds the paid run to clean candidate sources at the exact manifest commit", () => {
  const calls = [];
  assert.deepEqual(assertCurrentEvaluationCandidate(candidate, (command, args, options) => {
    calls.push({ command, args, options });
    return args.includes("status") ? "" : `${candidate.sourceCommit}\n`;
  }), candidate);
  assert.equal(calls.length, 2);
  const statusArguments = calls.find(({ args }) => args.includes("status"))?.args ?? [];
  assert.equal(statusArguments.includes("tools/meal-scan-quality-evaluation/score.mjs"), true);
  assert.equal(statusArguments.includes("tools/meal-scan-quality-evaluation/prepare-bundle.mjs"), true);
  assert.throws(
    () => assertCurrentEvaluationCandidate(candidate, (_command, args) => (
      args.includes("status") ? " M tools/meal-scan-quality-evaluation/src/runner.mjs\n" : `${candidate.sourceCommit}\n`
    )),
    /clean and committed/i,
  );
  assert.throws(
    () => assertCurrentEvaluationCandidate(candidate, (_command, args) => (
      args.includes("status") ? "" : `${"b".repeat(40)}\n`
    )),
    /source commit/i,
  );
});

test("loads only the deployed numeric production secret version through argument-safe gcloud execution", () => {
  const calls = [];
  const key = loadPinnedGeminiAPIKey("2", (command, args, options) => {
    calls.push({ command, args, options });
    return "  secret-value-in-memory  \n";
  });

  assert.equal(key, "secret-value-in-memory");
  assert.deepEqual(calls, [{
    command: "gcloud",
    args: [
      "secrets", "versions", "access", "2",
      "--secret=cyclebalance-gemini-api-key",
      "--project=cyclebalance-prod-20260710",
      "--quiet",
    ],
    options: { encoding: "utf8", stdio: ["ignore", "pipe", "pipe"] },
  }]);
});

test("reads back the pinned Cloud Run service and IAM policy before evaluation", () => {
  const calls = [];
  const service = {
    metadata: { annotations: {} },
    spec: { template: { spec: { containers: [{ env: [
      { name: "MEAL_SCAN_ENABLED", value: "false" },
      { name: "GEMINI_API_KEY", valueFrom: { secretKeyRef: { name: "cyclebalance-gemini-api-key", key: "2" } } },
    ] }] } } },
    status: {
      url: "https://cyclebalance-meal-scan-proxy.example.run.app",
      traffic: [{ percent: 100, revisionName: "cyclebalance-meal-scan-proxy-00001" }],
    },
  };
  const revision = service.spec.template;
  const responses = [JSON.stringify(service), JSON.stringify({ bindings: [] }), JSON.stringify(revision)];

  const preflight = preflightPinnedProductionService((command, args, options) => {
    calls.push({ command, args, options });
    if (command === "curl") return "403";
    return responses.shift();
  });

  assert.deepEqual(calls.map(({ command, args }) => ({ command, args })), [
    {
      command: "gcloud",
      args: [
        "run", "services", "describe", "cyclebalance-meal-scan-proxy",
        "--project=cyclebalance-prod-20260710",
        "--region=us-central1",
        "--format=json",
        "--quiet",
      ],
    },
    {
      command: "gcloud",
      args: [
        "run", "services", "get-iam-policy", "cyclebalance-meal-scan-proxy",
        "--project=cyclebalance-prod-20260710",
        "--region=us-central1",
        "--format=json",
        "--quiet",
      ],
    },
    {
      command: "gcloud",
      args: [
        "run", "revisions", "describe", "cyclebalance-meal-scan-proxy-00001",
        "--project=cyclebalance-prod-20260710",
        "--region=us-central1",
        "--format=json",
        "--quiet",
      ],
    },
    {
      command: "curl",
      args: [
        "--silent", "--show-error", "--max-time", "5",
        "--output", "/dev/null",
        "--write-out", "%{http_code}",
        "--request", "POST",
        "https://cyclebalance-meal-scan-proxy.example.run.app/v1/meal-scans/estimate",
      ],
    },
  ]);
  assert.deepEqual(calls.map(({ options }) => options), [
    { encoding: "utf8", stdio: ["ignore", "pipe", "pipe"] },
    { encoding: "utf8", stdio: ["ignore", "pipe", "pipe"] },
    { encoding: "utf8", stdio: ["ignore", "pipe", "pipe"] },
    { encoding: "utf8", stdio: ["ignore", "pipe", "pipe"] },
  ]);
  assert.deepEqual(preflight, { geminiSecretVersion: "2" });
});

test("preflight requires the Cloud Run IAM boundary to return 403 for anonymous transport", () => {
  const service = {
    metadata: { annotations: {} },
    spec: { template: { spec: { containers: [{ env: [
      { name: "MEAL_SCAN_ENABLED", value: "false" },
      { name: "GEMINI_API_KEY", valueFrom: { secretKeyRef: { name: "cyclebalance-gemini-api-key", key: "2" } } },
    ] }] } } },
    status: {
      url: "https://cyclebalance-meal-scan-proxy.example.run.app",
      traffic: [{ percent: 100, revisionName: "cyclebalance-meal-scan-proxy-00001" }],
    },
  };
  const revision = service.spec.template;
  const responses = [JSON.stringify(service), JSON.stringify({ bindings: [] }), JSON.stringify(revision)];
  for (const anonymousStatus of ["200", "404"]) {
    const attemptResponses = [...responses];
    assert.throws(
      () => preflightPinnedProductionService(
        (command) => command === "curl" ? anonymousStatus : attemptResponses.shift(),
      ),
      /anonymous transport|private/i,
    );
  }
});

test("preflight rejects traffic routed to an older enabled revision", () => {
  const service = {
    metadata: { annotations: {} },
    spec: { template: { spec: { containers: [{ env: [
      { name: "MEAL_SCAN_ENABLED", value: "false" },
      { name: "GEMINI_API_KEY", valueFrom: { secretKeyRef: { name: "cyclebalance-gemini-api-key", key: "2" } } },
    ] }] } } },
    status: { traffic: [{ percent: 100, revisionName: "cyclebalance-meal-scan-proxy-older" }] },
  };
  const enabledRevision = {
    spec: { containers: [{ env: [
      { name: "MEAL_SCAN_ENABLED", value: "true" },
      { name: "GEMINI_API_KEY", valueFrom: { secretKeyRef: { name: "cyclebalance-gemini-api-key", key: "2" } } },
    ] }] },
  };
  const responses = [JSON.stringify(service), JSON.stringify({ bindings: [] }), JSON.stringify(enabledRevision)];
  assert.throws(
    () => preflightPinnedProductionService(() => responses.shift()),
    /disabled/i,
  );
});

test("preflight rejects an enabled revision exposed only through a zero-percent traffic tag", () => {
  const service = {
    metadata: { annotations: {} },
    spec: { template: { spec: { containers: [{ env: [
      { name: "MEAL_SCAN_ENABLED", value: "false" },
      { name: "GEMINI_API_KEY", valueFrom: { secretKeyRef: { name: "cyclebalance-gemini-api-key", key: "2" } } },
    ] }] } } },
    status: {
      url: "https://cyclebalance-meal-scan-proxy.example.run.app",
      traffic: [
        { percent: 100, revisionName: "cyclebalance-meal-scan-proxy-current" },
        {
          percent: 0,
          revisionName: "cyclebalance-meal-scan-proxy-tagged",
          tag: "review",
          url: "https://review---cyclebalance-meal-scan-proxy.example.run.app",
        },
      ],
    },
  };
  const disabledRevision = service.spec.template;
  const enabledRevision = {
    spec: { containers: [{ env: [
      { name: "MEAL_SCAN_ENABLED", value: "true" },
      { name: "GEMINI_API_KEY", valueFrom: { secretKeyRef: { name: "cyclebalance-gemini-api-key", key: "2" } } },
    ] }] },
  };
  const responses = [
    JSON.stringify(service),
    JSON.stringify({ bindings: [] }),
    JSON.stringify(disabledRevision),
    JSON.stringify(enabledRevision),
  ];

  assert.throws(
    () => preflightPinnedProductionService((command) => command === "curl" ? "403" : responses.shift()),
    /disabled/i,
  );
});

test("requires explicit paid-run confirmation and writes owner-only results without overwrite", (t) => {
  assert.doesNotThrow(() => requirePaidEvaluationConfirmation("YES"));
  assert.throws(() => requirePaidEvaluationConfirmation("yes"), /CONFIRM_PAID_PUBLIC_BENCHMARK=YES/);

  const directory = mkdtempSync(join(tmpdir(), "cyclebalance-public-eval-"));
  const outputPath = join(directory, "results.json");
  t.after(() => rmSync(directory, { recursive: true, force: true }));

  writePrivateJSON(outputPath, [{ id: "public_meal_001" }]);

  assert.deepEqual(JSON.parse(readFileSync(outputPath, "utf8")), [{ id: "public_meal_001" }]);
  assert.equal(statSync(outputPath).mode & 0o777, 0o600);
  assert.throws(() => writePrivateJSON(outputPath, []), /already exists/i);
});

test("private output publication atomically refuses an existing destination", (t) => {
  const directory = mkdtempSync(join(tmpdir(), "cyclebalance-public-eval-publish-"));
  const temporaryPath = join(directory, ".results.tmp");
  const outputPath = join(directory, "results.json");
  t.after(() => rmSync(directory, { recursive: true, force: true }));
  writeFileSync(temporaryPath, "new results", { mode: 0o600 });
  writeFileSync(outputPath, "existing results", { mode: 0o600 });

  assert.throws(() => publishPrivateFile(temporaryPath, outputPath), (error) => error?.code === "EEXIST");
  assert.equal(readFileSync(outputPath, "utf8"), "existing results");
  assert.equal(existsSync(temporaryPath), true);
});

test("image map must cover the validated manifest exactly with absolute normalized JPEG paths", () => {
  const manifest = manifestFixture();
  const manifestByID = validateManifest(manifest);
  const imageMap = imageMapFixture(manifest);

  assert.equal(validateImageMap(imageMap, manifestByID).size, 80);

  imageMap.records.pop();
  assert.throws(() => validateImageMap(imageMap, manifestByID), /exactly one/i);

  const relativeMap = imageMapFixture(manifest);
  relativeMap.records[0].normalizedImagePath = "relative.jpg";
  assert.throws(() => validateImageMap(relativeMap, manifestByID), /absolute/i);
});

test("refuses a non-pinned candidate before reading an image or calling Gemini", async () => {
  const manifest = manifestFixture();
  manifest.candidate.modelVersion = "unapproved-model";
  let imageReads = 0;
  let providerCalls = 0;

  await assert.rejects(
    evaluatePublicBenchmark({
      manifest,
      imageMap: imageMapFixture(manifest),
      apiKey: "secret-never-returned",
      readFile: async () => { imageReads += 1; return jpeg; },
      callGemini: async () => { providerCalls += 1; },
    }),
    /pinned production evaluation candidate/i,
  );
  assert.equal(imageReads, 0);
  assert.equal(providerCalls, 0);
});

test("runs a bounded sequential benchmark with the exact production payload and bounded review evidence", async () => {
  const manifest = manifestFixture();
  const imageMap = imageMapFixture(manifest);
  const payloads = [];
  let activeCalls = 0;
  let maximumActiveCalls = 0;
  let clockValue = 1_000;

  const results = await evaluatePublicBenchmark({
    manifest,
    imageMap,
    apiKey: "secret-never-returned",
    readFile: async () => jpeg,
    clock: () => {
      clockValue += 10;
      return clockValue;
    },
    callGemini: async (input) => {
      activeCalls += 1;
      maximumActiveCalls = Math.max(maximumActiveCalls, activeCalls);
      payloads.push(input);
      await Promise.resolve();
      activeCalls -= 1;
      return {
        estimate: estimateFixture(),
        usageMetadata: { promptTokenCount: 100, candidatesTokenCount: 50 },
      };
    },
  });

  assert.equal(results.length, 80);
  assert.equal(payloads.length, 80);
  assert.equal(maximumActiveCalls, 1);
  const dominantFoodInterpretation = "Benchmark meal — Benchmark item";
  assert.deepEqual(results[0], {
    id: "public_meal_001",
    structuredSuccess: true,
    calories: 500,
    protein: 20,
    carbs: 50,
    fat: 20,
    modelVersion: "gemini-3.1-flash-lite",
    promptVersion: "meal-scan-prompt-v1",
    schemaVersion: "meal-scan-gemini-v1",
    normalizerVersion: "imageio-960-jpeg078-v1",
    sourceCommit: "a".repeat(40),
    latencyMs: 10,
    dominantFoodInterpretation,
    interpretationDigest: buildInterpretationDigest({
      candidate,
      id: "public_meal_001",
      structuredSuccess: true,
      dominantFoodInterpretation,
    }),
  });
  assert.equal(payloads[0].modelId, "gemini-3.1-flash-lite");
  assert.equal(payloads[0].timeoutMs, 12_000);
  assert.equal(payloads[0].apiKey, "secret-never-returned");
  assert.match(payloads[0].payload.contents[0].parts[0].text, /Schema: meal-scan-gemini-v1/);
  assert.equal(payloads[0].payload.contents[0].parts[1].inlineData.data, jpeg.toString("base64"));
  assert.equal(payloads[0].payload.generationConfig.responseMimeType, "application/json");

  const serializedResults = JSON.stringify(results);
  assert.equal(serializedResults.includes("/private/benchmark"), false);
  assert.equal(serializedResults.includes("secret-never-returned"), false);
  assert.equal(serializedResults.includes("nutrition_fallback"), false);
  assert.equal(results.every(({ dominantFoodInterpretation: value }) => value.length <= 1024), true);
});

test("marks an estimate as failed when the production response-bounds contract rejects it", async () => {
  const manifest = manifestFixture();
  const results = await evaluatePublicBenchmark({
    manifest,
    imageMap: imageMapFixture(manifest),
    apiKey: "secret-never-returned",
    readFile: async () => jpeg,
    clock: (() => { let value = 0; return () => value += 1; })(),
    callGemini: async () => ({
      estimate: {
        meal_name: "Looks plausible but is not production-valid",
        confidence: "medium",
        warnings: [],
        items: [{
          display_name: "Incomplete fallback",
          canonical_query: "incomplete fallback",
          estimated_grams: 350,
          confidence: "medium",
          is_mixed_dish: false,
          nutrition_fallback: {
            calories_kcal: 500,
            protein_grams: 20,
            carbs_grams: 50,
            fat_grams: 20,
          },
        }],
      },
    }),
  });

  assert.equal(results.every(({ structuredSuccess }) => structuredSuccess === false), true);
});

test("records a structured failure without leaking model errors or image paths", async () => {
  const manifest = manifestFixture();
  const imageMap = imageMapFixture(manifest);
  let calls = 0;

  const results = await evaluatePublicBenchmark({
    manifest,
    imageMap,
    apiKey: "secret-never-returned",
    readFile: async () => jpeg,
    clock: (() => {
      let value = 0;
      return () => value += 5;
    })(),
    callGemini: async () => {
      calls += 1;
      if (calls === 1) throw new Error("secret-never-returned /private/benchmark/image.jpg");
      return {
        estimate: estimateFixture(),
      };
    },
  });

  assert.deepEqual(results[0], {
    id: "public_meal_001",
    structuredSuccess: false,
    calories: null,
    protein: null,
    carbs: null,
    fat: null,
    modelVersion: "gemini-3.1-flash-lite",
    promptVersion: "meal-scan-prompt-v1",
    schemaVersion: "meal-scan-gemini-v1",
    normalizerVersion: "imageio-960-jpeg078-v1",
    sourceCommit: "a".repeat(40),
    latencyMs: 5,
    dominantFoodInterpretation: null,
    interpretationDigest: buildInterpretationDigest({
      candidate,
      id: "public_meal_001",
      structuredSuccess: false,
      dominantFoodInterpretation: null,
    }),
  });
  assert.equal(JSON.stringify(results).includes("secret-never-returned"), false);
  assert.equal(JSON.stringify(results).includes("/private/benchmark"), false);
});

test("complete suite adds exactly two sequential stability runs for each locked holdout", async () => {
  const manifest = manifestFixture();
  const imageMap = imageMapFixture(manifest);
  let calls = 0;
  let activeCalls = 0;
  let maximumActiveCalls = 0;

  const suite = await evaluatePublicBenchmarkSuite({
    manifest,
    imageMap,
    apiKey: "secret-never-returned",
    readFile: async () => jpeg,
    clock: (() => {
      let value = 0;
      return () => value += 1;
    })(),
    callGemini: async () => {
      calls += 1;
      activeCalls += 1;
      maximumActiveCalls = Math.max(maximumActiveCalls, activeCalls);
      await Promise.resolve();
      activeCalls -= 1;
      return {
        estimate: estimateFixture(),
      };
    },
  });

  assert.equal(calls, 120);
  assert.equal(maximumActiveCalls, 1);
  assert.equal(suite.primaryResults.length, 80);
  assert.equal(suite.stabilityResults.length, 40);
  const holdoutIDs = new Set(manifest.records.filter(({ holdout }) => holdout).map(({ id }) => id));
  assert.equal(suite.stabilityResults.every(({ id }) => holdoutIDs.has(id)), true);
  for (const id of holdoutIDs) {
    assert.equal(suite.stabilityResults.filter((result) => result.id === id).length, 2);
  }
});
