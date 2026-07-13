import crypto from "node:crypto";
import { execFileSync } from "node:child_process";
import {
  chmodSync,
  closeSync,
  existsSync,
  linkSync,
  openSync,
  unlinkSync,
  writeFileSync,
} from "node:fs";
import { readFile as readFileFromDisk } from "node:fs/promises";
import { basename, dirname, isAbsolute, join, resolve } from "node:path";
import { fileURLToPath } from "node:url";

import {
  assertEstimateBounds,
  buildGeminiPayload,
  callGemini as callProductionGemini,
} from "../../../cloud/meal-scan-proxy/src/server.js";
import { buildInterpretationDigest, validateManifest } from "./evaluation.mjs";

export const EVALUATION_PROJECT_ID = "cyclebalance-prod-20260710";
export const EVALUATION_REGION = "us-central1";
export const EVALUATION_SERVICE = "cyclebalance-meal-scan-proxy";
export const EVALUATION_SECRET = "cyclebalance-gemini-api-key";
export const EVALUATION_MODEL = "gemini-3.1-flash-lite";
export const EVALUATION_PROMPT_VERSION = "meal-scan-prompt-v1";
export const EVALUATION_SCHEMA_VERSION = "meal-scan-gemini-v1";
export const EVALUATION_NORMALIZER_VERSION = "imageio-960-jpeg078-v1";
export const EVALUATION_TIMEOUT_MS = 12_000;

const MAX_IMAGE_BYTES = 1_500_000;
const MAX_DOMINANT_FOOD_INTERPRETATION_LENGTH = 1024;
const IMAGE_MAP_KEYS = Object.freeze(["id", "locale", "mealType", "normalizedImagePath"]);
const MEAL_TYPES = new Set(["breakfast", "lunch", "dinner", "snack"]);
const REPOSITORY_ROOT = resolve(dirname(fileURLToPath(import.meta.url)), "../../..");
const CANDIDATE_SOURCE_PATHS = Object.freeze([
  "cloud/meal-scan-proxy/src",
  "tools/meal-scan-quality-evaluation/normalize-image.swift",
  "tools/meal-scan-quality-evaluation/prepare-bundle.mjs",
  "tools/meal-scan-quality-evaluation/run-evaluation.mjs",
  "tools/meal-scan-quality-evaluation/score.mjs",
  "tools/meal-scan-quality-evaluation/src",
]);

function fail(message) {
  throw new Error(message);
}

function isPlainObject(value) {
  return value !== null && typeof value === "object" && !Array.isArray(value);
}

function hasExactKeys(value, expectedKeys) {
  if (!isPlainObject(value)) return false;
  const actual = Object.keys(value).sort();
  const expected = [...expectedKeys].sort();
  return actual.length === expected.length && actual.every((key, index) => key === expected[index]);
}

export function pinnedEvaluationCandidate(sourceCommit) {
  if (typeof sourceCommit !== "string" || !/^[a-fA-F0-9]{40}$/.test(sourceCommit)) {
    fail("a full 40-character source commit is required to freeze the evaluation candidate");
  }
  return {
    modelVersion: EVALUATION_MODEL,
    promptVersion: EVALUATION_PROMPT_VERSION,
    schemaVersion: EVALUATION_SCHEMA_VERSION,
    normalizerVersion: EVALUATION_NORMALIZER_VERSION,
    sourceCommit: sourceCommit.toLowerCase(),
  };
}

export function assertPinnedEvaluationCandidate(candidate) {
  const expected = pinnedEvaluationCandidate(candidate?.sourceCommit);
  if (!hasExactKeys(candidate, Object.keys(expected)) ||
      Object.keys(expected).some((key) => candidate[key] !== expected[key])) {
    fail("manifest candidate does not match the pinned production evaluation candidate");
  }
  return expected;
}

function readCandidateRepositoryState(execFile) {
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
    fail("evaluation model, prompt, schema, normalizer, and runner sources must be clean and committed before evaluation");
  }
  return pinnedEvaluationCandidate(typeof sourceCommit === "string" ? sourceCommit.trim() : "");
}

export function loadCurrentEvaluationCandidate(execFile = execFileSync) {
  return readCandidateRepositoryState(execFile);
}

export function assertCurrentEvaluationCandidate(candidate, execFile = execFileSync) {
  const expected = assertPinnedEvaluationCandidate(candidate);
  const current = readCandidateRepositoryState(execFile);
  if (current.sourceCommit !== expected.sourceCommit) {
    fail("manifest candidate source commit does not match the clean current checkout");
  }
  return expected;
}

export function assertSafeProductionService(service, iamPolicy) {
  const environment = service?.spec?.template?.spec?.containers?.[0]?.env;
  if (!Array.isArray(environment)) fail("production service configuration is unavailable");
  const annotations = [service?.metadata?.annotations, service?.spec?.template?.metadata?.annotations];
  if (annotations.some((values) => values?.["run.googleapis.com/invoker-iam-disabled"] === "true")) {
    fail("production service is public because the Cloud Run invoker IAM check is disabled");
  }

  const environmentByName = new Map(environment.map((entry) => [entry?.name, entry]));
  if (environmentByName.get("MEAL_SCAN_ENABLED")?.value !== "false") {
    fail("production meal scan service must remain disabled during evaluation");
  }

  const geminiSecret = environmentByName.get("GEMINI_API_KEY");
  if (
    geminiSecret?.value !== undefined ||
    geminiSecret?.valueFrom?.secretKeyRef?.name !== EVALUATION_SECRET ||
    !/^[1-9][0-9]*$/.test(geminiSecret?.valueFrom?.secretKeyRef?.key ?? "")
  ) {
    fail("production Gemini key must remain backed by a numeric Secret Manager version");
  }

  const publicMember = (iamPolicy?.bindings ?? [])
    .flatMap((binding) => binding?.members ?? [])
    .find((member) => member === "allUsers" || member === "allAuthenticatedUsers");
  if (publicMember) fail("production meal scan service must remain private during evaluation");
  return { geminiSecretVersion: geminiSecret.valueFrom.secretKeyRef.key };
}

function assertSafeProductionRevision(revision) {
  const environment = revision?.spec?.containers?.[0]?.env;
  if (!Array.isArray(environment)) fail("routed production revision configuration is unavailable");
  if (revision?.metadata?.annotations?.["run.googleapis.com/invoker-iam-disabled"] === "true") {
    fail("routed production revision is public because the Cloud Run invoker IAM check is disabled");
  }
  const environmentByName = new Map(environment.map((entry) => [entry?.name, entry]));
  if (environmentByName.get("MEAL_SCAN_ENABLED")?.value !== "false") {
    fail("every routed production meal scan revision must remain disabled during evaluation");
  }
  const geminiSecret = environmentByName.get("GEMINI_API_KEY");
  if (
    geminiSecret?.value !== undefined ||
    geminiSecret?.valueFrom?.secretKeyRef?.name !== EVALUATION_SECRET ||
    !/^[1-9][0-9]*$/.test(geminiSecret?.valueFrom?.secretKeyRef?.key ?? "")
  ) {
    fail("every routed production revision must use a numeric-pinned Gemini Secret Manager version");
  }
  return { geminiSecretVersion: geminiSecret.valueFrom.secretKeyRef.key };
}

function runGcloudJSON(execFile, args, kind) {
  try {
    const output = execFile("gcloud", args, { encoding: "utf8", stdio: ["ignore", "pipe", "pipe"] });
    return JSON.parse(output);
  } catch {
    fail(`unable to read the pinned ${kind}`);
  }
}

function assertAnonymousTransportPrivate(execFile, serviceURL) {
  let endpoint;
  try {
    const url = new URL(serviceURL);
    if (url.protocol !== "https:") fail("production Cloud Run service URL must use HTTPS");
    endpoint = new URL("/v1/meal-scans/estimate", url).href;
  } catch (error) {
    if (error instanceof Error && error.message === "production Cloud Run service URL must use HTTPS") throw error;
    fail("production Cloud Run service URL is unavailable");
  }
  let status;
  try {
    status = execFile(
      "curl",
      [
        "--silent", "--show-error", "--max-time", "5",
        "--output", "/dev/null",
        "--write-out", "%{http_code}",
        "--request", "POST",
        endpoint,
      ],
      { encoding: "utf8", stdio: ["ignore", "pipe", "pipe"] },
    );
  } catch {
    fail("unable to prove the production Cloud Run anonymous transport is private");
  }
  if (typeof status !== "string" || status.trim() !== "403") {
    fail("production Cloud Run anonymous transport must remain private");
  }
}

export function preflightPinnedProductionService(execFile = execFileSync) {
  const commonArguments = [
    `--project=${EVALUATION_PROJECT_ID}`,
    `--region=${EVALUATION_REGION}`,
    "--format=json",
    "--quiet",
  ];
  const service = runGcloudJSON(
    execFile,
    ["run", "services", "describe", EVALUATION_SERVICE, ...commonArguments],
    "Cloud Run service",
  );
  const iamPolicy = runGcloudJSON(
    execFile,
    ["run", "services", "get-iam-policy", EVALUATION_SERVICE, ...commonArguments],
    "Cloud Run IAM policy",
  );
  const serviceState = assertSafeProductionService(service, iamPolicy);
  const routedRevisionNames = [...new Set((service?.status?.traffic ?? [])
    .filter(({ percent, tag, url }) => (
      percent === undefined || percent > 0 ||
      (typeof tag === "string" && tag.length > 0) ||
      (typeof url === "string" && url.length > 0)
    ))
    .map(({ revisionName }) => revisionName))];
  if (routedRevisionNames.length === 0 || routedRevisionNames.some((name) => typeof name !== "string" || name.length === 0)) {
    fail("unable to prove every routed production revision is disabled");
  }
  for (const revisionName of routedRevisionNames) {
    const revision = runGcloudJSON(
      execFile,
      ["run", "revisions", "describe", revisionName, ...commonArguments],
      `routed Cloud Run revision ${revisionName}`,
    );
    const revisionState = assertSafeProductionRevision(revision);
    if (revisionState.geminiSecretVersion !== serviceState.geminiSecretVersion) {
      fail("all routed production revisions must use the same numeric-pinned Gemini secret version");
    }
  }
  assertAnonymousTransportPrivate(execFile, service?.status?.url);
  return serviceState;
}

export function requirePaidEvaluationConfirmation(value) {
  if (value !== "YES") {
    fail("set CONFIRM_PAID_PUBLIC_BENCHMARK=YES to authorize the bounded paid evaluation");
  }
}

export function publishPrivateFile(temporaryPath, outputPath) {
  linkSync(temporaryPath, outputPath);
  unlinkSync(temporaryPath);
}

export function writePrivateJSON(outputPath, value) {
  if (typeof outputPath !== "string" || !isAbsolute(outputPath)) fail("output path must be absolute");
  if (existsSync(outputPath)) fail("evaluation output already exists");

  const temporaryPath = join(
    dirname(outputPath),
    `.${basename(outputPath)}.${crypto.randomBytes(8).toString("hex")}.tmp`,
  );
  let descriptor;
  try {
    descriptor = openSync(temporaryPath, "wx", 0o600);
    writeFileSync(descriptor, `${JSON.stringify(value, null, 2)}\n`, "utf8");
    closeSync(descriptor);
    descriptor = undefined;
    publishPrivateFile(temporaryPath, outputPath);
    chmodSync(outputPath, 0o600);
  } catch (error) {
    if (descriptor !== undefined) closeSync(descriptor);
    try {
      unlinkSync(temporaryPath);
    } catch {
      // The temporary file may not have been created or may already have been published.
    }
    throw error;
  }
}

export function loadPinnedGeminiAPIKey(secretVersion, execFile = execFileSync) {
  if (typeof secretVersion !== "string" || !/^[1-9][0-9]*$/.test(secretVersion)) {
    fail("a reviewed numeric Gemini secret version is required");
  }
  let output;
  try {
    output = execFile(
      "gcloud",
      [
        "secrets", "versions", "access", secretVersion,
        `--secret=${EVALUATION_SECRET}`,
        `--project=${EVALUATION_PROJECT_ID}`,
        "--quiet",
      ],
      { encoding: "utf8", stdio: ["ignore", "pipe", "pipe"] },
    );
  } catch {
    fail("unable to load the pinned Gemini evaluation secret");
  }

  const apiKey = typeof output === "string" ? output.trim() : "";
  if (apiKey.length < 16 || apiKey.length > 1024 || /[\r\n]/.test(apiKey)) {
    fail("pinned Gemini evaluation secret is invalid");
  }
  return apiKey;
}

export function validateImageMap(imageMap, manifestRecordsByID) {
  if (!hasExactKeys(imageMap, ["version", "records"]) || imageMap.version !== 1 || !Array.isArray(imageMap.records)) {
    fail("image map must use schema version 1 with a records array");
  }

  const recordsByID = new Map();
  for (const record of imageMap.records) {
    if (!hasExactKeys(record, IMAGE_MAP_KEYS)) fail("image map record fields are invalid");
    if (!manifestRecordsByID.has(record.id)) fail("image map contains an unknown manifest ID");
    if (recordsByID.has(record.id)) fail("image map IDs must be unique");
    if (typeof record.normalizedImagePath !== "string" || !isAbsolute(record.normalizedImagePath)) {
      fail("normalized image paths must be absolute");
    }
    if (!MEAL_TYPES.has(record.mealType)) fail("image map mealType is invalid");
    if (typeof record.locale !== "string" || !/^[A-Za-z]{2,3}(?:[-_][A-Za-z0-9]{2,8}){0,3}$/.test(record.locale)) {
      fail("image map locale is invalid");
    }
    recordsByID.set(record.id, record);
  }

  if (recordsByID.size !== manifestRecordsByID.size) {
    fail("image map must contain exactly one record for each manifest ID");
  }
  return recordsByID;
}

function validatedJPEG(bytes, expectedHash) {
  if (!Buffer.isBuffer(bytes)) fail("normalized image reader must return bytes");
  if (bytes.length < 4 || bytes.length > MAX_IMAGE_BYTES) fail("normalized JPEG size is invalid");
  if (bytes[0] !== 0xff || bytes[1] !== 0xd8 || bytes.at(-2) !== 0xff || bytes.at(-1) !== 0xd9) {
    fail("normalized image must be a JPEG");
  }
  const actualHash = crypto.createHash("sha256").update(bytes).digest("hex");
  if (actualHash !== expectedHash.toLowerCase()) fail("normalized image hash does not match the manifest");
  return bytes;
}

function nutritionTotals(estimate) {
  if (!Array.isArray(estimate?.items) || estimate.items.length === 0) fail("estimate contains no nutrition items");
  const totals = { calories: 0, protein: 0, carbs: 0, fat: 0 };
  const fields = {
    calories: "calories_kcal",
    protein: "protein_grams",
    carbs: "carbs_grams",
    fat: "fat_grams",
  };

  for (const item of estimate.items) {
    const fallback = item?.nutrition_fallback;
    if (!isPlainObject(fallback)) fail("estimate item is missing nutrition fallback values");
    for (const [nutrient, field] of Object.entries(fields)) {
      const value = fallback[field];
      if (!Number.isFinite(value) || value < 0) fail("estimate nutrition fallback is invalid");
      totals[nutrient] += value;
    }
  }
  return totals;
}

function dominantFoodInterpretation(estimate) {
  const mealName = estimate.meal_name.trim();
  const itemNames = estimate.items.map(({ display_name: displayName }) => displayName.trim());
  const interpretation = `${mealName} — ${itemNames.join(", ")}`;
  return interpretation.slice(0, MAX_DOMINANT_FOOD_INTERPRETATION_LENGTH);
}

async function prepareBenchmark({ manifest, imageMap, apiKey, readFile }) {
  if (typeof apiKey !== "string" || apiKey.length < 16) fail("Gemini evaluation key is required");
  const manifestRecordsByID = validateManifest(manifest);
  const candidate = assertPinnedEvaluationCandidate(manifest.candidate);
  const imageRecordsByID = validateImageMap(imageMap, manifestRecordsByID);

  const preparedImages = new Map();
  for (const record of manifest.records) {
    const imageRecord = imageRecordsByID.get(record.id);
    const bytes = await readFile(imageRecord.normalizedImagePath);
    preparedImages.set(record.id, validatedJPEG(bytes, record.imageSha256));
  }

  return { imageRecordsByID, preparedImages, candidate };
}

async function evaluateRecords({ records, imageRecordsByID, preparedImages, candidate, apiKey, clock, callGemini }) {
  const results = [];
  for (const record of records) {
    const imageRecord = imageRecordsByID.get(record.id);
    const imageBytes = preparedImages.get(record.id);
    const requestPayload = {
      mealType: imageRecord.mealType,
      locale: imageRecord.locale,
      schemaVersion: candidate.schemaVersion,
      promptVersion: candidate.promptVersion,
      image: {
        mimeType: "image/jpeg",
        base64: imageBytes.toString("base64"),
        sha256: record.imageSha256.toLowerCase(),
      },
    };
    const startedAt = clock();
    let totals = null;
    let interpretation = null;
    try {
      const response = await callGemini({
        modelId: candidate.modelVersion,
        payload: buildGeminiPayload(requestPayload, candidate.modelVersion),
        timeoutMs: EVALUATION_TIMEOUT_MS,
        apiKey,
      });
      assertEstimateBounds(response.estimate);
      totals = nutritionTotals(response.estimate);
      interpretation = dominantFoodInterpretation(response.estimate);
    } catch {
      totals = null;
      interpretation = null;
    }
    const latencyMs = Math.max(0, clock() - startedAt);
    const structuredSuccess = totals !== null;
    results.push({
      id: record.id,
      structuredSuccess,
      calories: totals?.calories ?? null,
      protein: totals?.protein ?? null,
      carbs: totals?.carbs ?? null,
      fat: totals?.fat ?? null,
      modelVersion: candidate.modelVersion,
      promptVersion: candidate.promptVersion,
      schemaVersion: candidate.schemaVersion,
      normalizerVersion: candidate.normalizerVersion,
      sourceCommit: candidate.sourceCommit,
      latencyMs,
      dominantFoodInterpretation: interpretation,
      interpretationDigest: buildInterpretationDigest({
        candidate,
        id: record.id,
        structuredSuccess,
        dominantFoodInterpretation: interpretation,
      }),
    });
  }
  return results;
}

export async function evaluatePublicBenchmark({
  manifest,
  imageMap,
  apiKey,
  readFile = readFileFromDisk,
  clock = Date.now,
  callGemini = callProductionGemini,
} = {}) {
  const prepared = await prepareBenchmark({ manifest, imageMap, apiKey, readFile });
  return evaluateRecords({
    records: manifest.records,
    ...prepared,
    apiKey,
    clock,
    callGemini,
  });
}

export async function evaluatePublicBenchmarkSuite({
  manifest,
  imageMap,
  apiKey,
  readFile = readFileFromDisk,
  clock = Date.now,
  callGemini = callProductionGemini,
} = {}) {
  const prepared = await prepareBenchmark({ manifest, imageMap, apiKey, readFile });
  const common = { ...prepared, apiKey, clock, callGemini };
  const primaryResults = await evaluateRecords({ records: manifest.records, ...common });
  const holdoutRecords = manifest.records.filter(({ holdout }) => holdout);
  const stabilityResults = [];
  for (let run = 0; run < 2; run += 1) {
    stabilityResults.push(...await evaluateRecords({ records: holdoutRecords, ...common }));
  }
  return { primaryResults, stabilityResults };
}
