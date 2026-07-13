import crypto from "node:crypto";
import { isAbsolute, join } from "node:path";

import { validateCandidate } from "./evaluation.mjs";

const SOURCE_COUNTS = Object.freeze({ Nutrition5k: 40, SNAPMe: 30, MFDS: 10 });
const HOLDOUT_COUNTS = Object.freeze({ Nutrition5k: 10, SNAPMe: 7, MFDS: 3 });
const SOURCE_RECORD_KEYS = Object.freeze([
  "groundTruth",
  "id",
  "license",
  "locale",
  "mealType",
  "referenceType",
  "samplingReason",
  "source",
  "sourceImagePath",
  "sourceUrl",
]);
const NUTRIENTS = Object.freeze(["calories", "protein", "carbs", "fat"]);
const MEAL_TYPES = new Set(["breakfast", "lunch", "dinner", "snack"]);
const MAX_IMAGE_BYTES = 1_500_000;

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

function nonEmptyString(value) {
  return typeof value === "string" && value.trim().length > 0;
}

function validSourceURL(value) {
  if (!nonEmptyString(value)) return false;
  try {
    const url = new URL(value);
    return url.protocol === "https:" || url.protocol === "http:";
  } catch {
    return false;
  }
}

function validateSourceIndex(sourceIndex, normalizedImageDirectory) {
  if (!isAbsolute(normalizedImageDirectory)) fail("normalized image directory must be absolute");
  if (!hasExactKeys(sourceIndex, ["version", "records"]) || sourceIndex.version !== 1 || !Array.isArray(sourceIndex.records)) {
    fail("source index must use schema version 1 with a records array");
  }

  const ids = new Set();
  const counts = Object.fromEntries(Object.keys(SOURCE_COUNTS).map((source) => [source, 0]));
  for (const record of sourceIndex.records) {
    if (!hasExactKeys(record, SOURCE_RECORD_KEYS)) fail("source index record fields are invalid");
    if (!/^[A-Za-z0-9][A-Za-z0-9_-]{7,127}$/.test(record.id ?? "") || ids.has(record.id)) {
      fail("source index IDs must be unique opaque IDs");
    }
    ids.add(record.id);
    if (!(record.source in SOURCE_COUNTS)) fail("source index source is invalid");
    counts[record.source] += 1;
    if (!validSourceURL(record.sourceUrl)) fail("source index sourceUrl is invalid");
    if (!nonEmptyString(record.license) || !nonEmptyString(record.referenceType) || !nonEmptyString(record.samplingReason)) {
      fail("source index provenance fields are invalid");
    }
    if (!isAbsolute(record.sourceImagePath)) fail("source image paths must be absolute");
    if (!hasExactKeys(record.groundTruth, NUTRIENTS) || NUTRIENTS.some((key) => !Number.isFinite(record.groundTruth[key]) || record.groundTruth[key] < 0)) {
      fail("source index groundTruth is invalid");
    }
    if (!MEAL_TYPES.has(record.mealType)) fail("source index mealType is invalid");
    if (!/^[A-Za-z]{2,3}(?:[-_][A-Za-z0-9]{2,8}){0,3}$/.test(record.locale ?? "")) fail("source index locale is invalid");
  }
  if (Object.keys(SOURCE_COUNTS).some((source) => counts[source] !== SOURCE_COUNTS[source])) {
    fail("source index must contain exactly 40 Nutrition5k, 30 SNAPMe, and 10 MFDS records");
  }
}

function lockedHoldoutIDs(records) {
  const selected = new Set();
  for (const source of Object.keys(SOURCE_COUNTS)) {
    const ranked = records
      .filter((record) => record.source === source)
      .map((record) => ({
        id: record.id,
        rank: crypto.createHash("sha256").update(`cyclebalance-public-holdout-v1:${record.id}`).digest("hex"),
      }))
      .sort((left, right) => left.rank.localeCompare(right.rank) || left.id.localeCompare(right.id));
    for (const record of ranked.slice(0, HOLDOUT_COUNTS[source])) selected.add(record.id);
  }
  return selected;
}

function validateNormalizedJPEG(bytes) {
  if (!Buffer.isBuffer(bytes) || bytes.length < 4 || bytes.length > MAX_IMAGE_BYTES) {
    fail("normalized output must be a bounded JPEG");
  }
  if (bytes[0] !== 0xff || bytes[1] !== 0xd8 || bytes.at(-2) !== 0xff || bytes.at(-1) !== 0xd9) {
    fail("normalized output must be a JPEG");
  }
}

export async function buildEvaluationBundle({ sourceIndex, normalizedImageDirectory, normalizeImage, candidate } = {}) {
  if (typeof normalizeImage !== "function") fail("image normalizer is required");
  validateCandidate(candidate);
  validateSourceIndex(sourceIndex, normalizedImageDirectory);

  const sortedRecords = [...sourceIndex.records].sort((left, right) => left.id.localeCompare(right.id));
  const holdoutIDs = lockedHoldoutIDs(sortedRecords);
  const manifestRecords = [];
  const imageMapRecords = [];

  for (const record of sortedRecords) {
    const normalizedImagePath = join(normalizedImageDirectory, `${record.id}.jpg`);
    const bytes = await normalizeImage(record.sourceImagePath, normalizedImagePath);
    validateNormalizedJPEG(bytes);
    const imageSha256 = crypto.createHash("sha256").update(bytes).digest("hex");
    manifestRecords.push({
      id: record.id,
      source: record.source,
      holdout: holdoutIDs.has(record.id),
      sourceUrl: record.sourceUrl,
      license: record.license,
      imageSha256,
      groundTruth: record.groundTruth,
      referenceType: record.referenceType,
      samplingReason: record.samplingReason,
    });
    imageMapRecords.push({
      id: record.id,
      normalizedImagePath,
      mealType: record.mealType,
      locale: record.locale,
    });
  }

  return {
    manifest: { version: 2, candidate, records: manifestRecords },
    imageMap: { version: 1, records: imageMapRecords },
  };
}
