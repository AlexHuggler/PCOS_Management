import crypto from "node:crypto";

const REQUIRED_RECORD_COUNT = 80;
const REQUIRED_HOLDOUT_COUNT = 20;
const SOURCE_COUNTS = Object.freeze({ Nutrition5k: 40, SNAPMe: 30, MFDS: 10 });
const SOURCES = Object.freeze(Object.keys(SOURCE_COUNTS));
const NUTRIENTS = Object.freeze(["calories", "protein", "carbs", "fat"]);
const MACROS = Object.freeze(["protein", "carbs", "fat"]);
const MAX_DOMINANT_FOOD_INTERPRETATION_LENGTH = 1024;
const CANDIDATE_KEYS = Object.freeze([
  "modelVersion",
  "normalizerVersion",
  "promptVersion",
  "schemaVersion",
  "sourceCommit",
]);
const MANIFEST_RECORD_KEYS = Object.freeze([
  "groundTruth",
  "holdout",
  "id",
  "imageSha256",
  "license",
  "referenceType",
  "samplingReason",
  "source",
  "sourceUrl",
]);
const RESULT_KEYS = Object.freeze([
  "calories",
  "carbs",
  "fat",
  "id",
  "latencyMs",
  "modelVersion",
  "normalizerVersion",
  "promptVersion",
  "protein",
  "schemaVersion",
  "sourceCommit",
  "structuredSuccess",
  "dominantFoodInterpretation",
  "interpretationDigest",
]);
const QUALITATIVE_RECORD_KEYS = Object.freeze([
  "acceptableDominantFoodInterpretation",
  "dominantFoodInterpretation",
  "id",
  "interpretationDigest",
  "severeOrUneditableFailure",
  "structuredSuccess",
]);

function fail(message) {
  throw new Error(message);
}

function isPlainObject(value) {
  return value !== null && typeof value === "object" && !Array.isArray(value);
}

function hasExactKeys(value, expectedKeys) {
  if (!isPlainObject(value)) return false;
  const actualKeys = Object.keys(value).sort();
  const sortedExpectedKeys = [...expectedKeys].sort();
  return actualKeys.length === sortedExpectedKeys.length &&
    actualKeys.every((key, index) => key === sortedExpectedKeys[index]);
}

function isNonEmptyString(value) {
  return typeof value === "string" && value.trim().length > 0;
}

function isNonNegativeNumber(value) {
  return Number.isFinite(value) && value >= 0;
}

function isSourceUrl(value) {
  if (!isNonEmptyString(value)) return false;
  try {
    const url = new URL(value);
    return url.protocol === "https:" || url.protocol === "http:";
  } catch {
    return false;
  }
}

function round(value) {
  if (value === null || !Number.isFinite(value)) return null;
  const rounded = Number(value.toFixed(6));
  return Object.is(rounded, -0) ? 0 : rounded;
}

function mean(values) {
  if (values.length === 0) return null;
  return values.reduce((sum, value) => sum + value, 0) / values.length;
}

function median(values) {
  if (values.length === 0) return null;
  const sorted = [...values].sort((left, right) => left - right);
  const middle = Math.floor(sorted.length / 2);
  return sorted.length % 2 === 0
    ? (sorted[middle - 1] + sorted[middle]) / 2
    : sorted[middle];
}

function percentile(values, percentileValue) {
  if (values.length === 0) return null;
  const sorted = [...values].sort((left, right) => left - right);
  return sorted[Math.max(0, Math.ceil(percentileValue * sorted.length) - 1)];
}

function validateGroundTruth(groundTruth) {
  if (!hasExactKeys(groundTruth, NUTRIENTS) ||
      NUTRIENTS.some((nutrient) => !isNonNegativeNumber(groundTruth[nutrient]))) {
    fail("manifest groundTruth must contain non-negative calories, protein, carbs, and fat");
  }
}

function validateManifestRecord(record) {
  if (!hasExactKeys(record, MANIFEST_RECORD_KEYS)) {
    fail("manifest record fields must preserve id, source, holdout, sourceUrl, license, imageSha256, groundTruth, referenceType, and samplingReason");
  }
  if (!isNonEmptyString(record.id) || !/^[A-Za-z0-9][A-Za-z0-9_-]{7,127}$/.test(record.id)) {
    fail("manifest record id must be an opaque 8-128 character ID");
  }
  if (!SOURCES.includes(record.source)) {
    fail("manifest source must be Nutrition5k, SNAPMe, or MFDS");
  }
  if (typeof record.holdout !== "boolean") {
    fail("manifest holdout must be boolean");
  }
  if (!isSourceUrl(record.sourceUrl)) {
    fail("manifest sourceUrl must be an HTTP or HTTPS URL");
  }
  if (!isNonEmptyString(record.license)) {
    fail("manifest license must be a non-empty string");
  }
  if (typeof record.imageSha256 !== "string" || !/^[a-fA-F0-9]{64}$/.test(record.imageSha256)) {
    fail("manifest imageSha256 must be a 64-character hexadecimal hash");
  }
  validateGroundTruth(record.groundTruth);
  if (!isNonEmptyString(record.referenceType)) {
    fail("manifest referenceType must be a non-empty string");
  }
  if (!isNonEmptyString(record.samplingReason)) {
    fail("manifest samplingReason must be a non-empty string");
  }
}

export function validateCandidate(candidate) {
  if (!hasExactKeys(candidate, CANDIDATE_KEYS)) {
    fail("manifest candidate must freeze one model, prompt, schema, normalizer, and source commit");
  }
  for (const key of CANDIDATE_KEYS.filter((key) => key !== "sourceCommit")) {
    if (!isNonEmptyString(candidate[key])) fail(`manifest candidate ${key} must be a non-empty string`);
  }
  if (typeof candidate.sourceCommit !== "string" || !/^[a-fA-F0-9]{40}$/.test(candidate.sourceCommit)) {
    fail("manifest candidate sourceCommit must be a full 40-character Git commit hash");
  }
  return candidate;
}

function sha256JSON(value) {
  return crypto.createHash("sha256").update(JSON.stringify(value), "utf8").digest("hex");
}

function canonicalCandidate(candidate) {
  return Object.fromEntries(CANDIDATE_KEYS.map((key) => [key, candidate?.[key]]));
}

export function buildInterpretationDigest({
  candidate,
  id,
  structuredSuccess,
  dominantFoodInterpretation,
} = {}) {
  return sha256JSON({
    version: 1,
    candidate: canonicalCandidate(candidate),
    id,
    structuredSuccess,
    dominantFoodInterpretation,
  });
}

export function buildPrimaryResultsDigest(results) {
  if (!Array.isArray(results)) fail("primary results digest input must be an array");
  const canonicalResults = [...results]
    .sort((left, right) => String(left?.id).localeCompare(String(right?.id)))
    .map((result) => Object.fromEntries(RESULT_KEYS.map((key) => [key, result?.[key]])));
  return sha256JSON({ version: 1, results: canonicalResults });
}

export function validateManifest(manifest) {
  if (!hasExactKeys(manifest, ["candidate", "version", "records"]) || manifest.version !== 2 || !Array.isArray(manifest.records)) {
    fail("manifest must use schema version 2 with one frozen candidate and a records array");
  }
  validateCandidate(manifest.candidate);
  if (manifest.records.length !== REQUIRED_RECORD_COUNT) {
    fail("manifest must contain exactly 80 records");
  }

  const recordsByID = new Map();
  const sourceCounts = Object.fromEntries(SOURCES.map((source) => [source, 0]));
  let holdoutCount = 0;

  for (const record of manifest.records) {
    validateManifestRecord(record);
    if (recordsByID.has(record.id)) fail("manifest record IDs must be unique");
    recordsByID.set(record.id, record);
    sourceCounts[record.source] += 1;
    if (record.holdout) holdoutCount += 1;
  }

  if (SOURCES.some((source) => sourceCounts[source] !== SOURCE_COUNTS[source])) {
    fail("manifest must contain exactly 40 Nutrition5k, 30 SNAPMe, and 10 MFDS records");
  }
  if (holdoutCount !== REQUIRED_HOLDOUT_COUNT) {
    fail("manifest must contain exactly 20 locked holdout records");
  }

  return recordsByID;
}

export function parseResultsText(text, kind = "results") {
  if (typeof text !== "string" || text.trim() === "") fail(`${kind} file is empty`);
  const trimmed = text.trim();

  try {
    const parsed = JSON.parse(trimmed);
    if (!Array.isArray(parsed)) fail(`${kind} JSON must be an array of result records`);
    return parsed;
  } catch (error) {
    if (error instanceof Error && error.message === `${kind} JSON must be an array of result records`) throw error;
  }

  const records = [];
  for (const [index, line] of trimmed.split(/\r?\n/).entries()) {
    if (line.trim() === "") continue;
    try {
      records.push(JSON.parse(line));
    } catch {
      fail(`${kind} JSONL line ${index + 1} is invalid JSON`);
    }
  }
  if (records.length === 0) fail(`${kind} file is empty`);
  return records;
}

function validateResultShape(result, kind, candidate) {
  if (!hasExactKeys(result, RESULT_KEYS)) {
    fail(`${kind} fields must contain only nutrition output, latency, and frozen candidate provenance`);
  }
  if (!isNonEmptyString(result.id)) fail(`${kind} id must be a non-empty string`);
  if (typeof result.structuredSuccess !== "boolean") fail(`${kind} structuredSuccess must be boolean`);
  if (!isNonEmptyString(result.modelVersion)) fail(`${kind} modelVersion must be a non-empty string`);
  for (const key of CANDIDATE_KEYS) {
    if (result[key] !== candidate[key]) fail(`${kind} candidate provenance must match the frozen manifest candidate`);
  }
  if (!isNonNegativeNumber(result.latencyMs)) fail(`${kind} latencyMs must be non-negative`);

  if (result.structuredSuccess) {
    if (!isNonEmptyString(result.dominantFoodInterpretation) ||
        result.dominantFoodInterpretation.length > MAX_DOMINANT_FOOD_INTERPRETATION_LENGTH) {
      fail(`${kind} dominant-food interpretation must be a bounded non-empty string after structured success`);
    }
  } else if (result.dominantFoodInterpretation !== null) {
    fail(`${kind} dominant-food interpretation must be null after structured failure`);
  }
  const expectedInterpretationDigest = buildInterpretationDigest({
    candidate,
    id: result.id,
    structuredSuccess: result.structuredSuccess,
    dominantFoodInterpretation: result.dominantFoodInterpretation,
  });
  if (typeof result.interpretationDigest !== "string" ||
      !/^[a-f0-9]{64}$/.test(result.interpretationDigest) ||
      result.interpretationDigest !== expectedInterpretationDigest) {
    fail(`${kind} interpretation digest must bind the frozen candidate and dominant-food interpretation`);
  }

  if (result.structuredSuccess) {
    if (NUTRIENTS.some((nutrient) => !isNonNegativeNumber(result[nutrient]))) {
      fail(`${kind} nutrition values must be non-negative numbers after structured success`);
    }
  } else if (NUTRIENTS.some((nutrient) => result[nutrient] !== null)) {
    fail(`${kind} structured failure nutrition values must all be null`);
  }
}

export function createQualitativeReviewTemplate(candidate, primaryResults) {
  validateCandidate(candidate);
  if (!Array.isArray(primaryResults) || primaryResults.length !== REQUIRED_RECORD_COUNT) {
    fail("qualitative review template requires all 80 primary results");
  }
  const reviewedIDs = new Set();
  for (const result of primaryResults) {
    validateResultShape(result, "result", candidate);
    if (reviewedIDs.has(result.id)) fail(`duplicate result ID ${result.id}`);
    reviewedIDs.add(result.id);
  }
  return {
    version: 2,
    candidate: { ...candidate },
    resultsDigest: buildPrimaryResultsDigest(primaryResults),
    records: primaryResults.map((result) => ({
      id: result.id,
      structuredSuccess: result.structuredSuccess,
      dominantFoodInterpretation: result.dominantFoodInterpretation,
      interpretationDigest: result.interpretationDigest,
      acceptableDominantFoodInterpretation: null,
      severeOrUneditableFailure: null,
    })),
  };
}

export function validatePrimaryResults(results, manifestRecordsByID, candidate) {
  if (!Array.isArray(results)) fail("results must be an array");
  const resultsByID = new Map();

  for (const result of results) {
    validateResultShape(result, "result", candidate);
    if (!manifestRecordsByID.has(result.id)) fail(`result contains unknown manifest ID ${result.id}`);
    if (resultsByID.has(result.id)) fail(`duplicate result ID ${result.id}`);
    resultsByID.set(result.id, result);
  }

  if (resultsByID.size !== manifestRecordsByID.size) {
    fail("results must contain exactly one result for each manifest ID");
  }
  return resultsByID;
}

export function validateStabilityResults(results, manifestRecordsByID, candidate) {
  if (!Array.isArray(results) || results.length !== REQUIRED_HOLDOUT_COUNT * 2) {
    fail("stability panel must contain exactly two repeats for each of the 20 locked holdouts");
  }
  const resultsByID = new Map();
  const holdoutIDs = new Set(
    [...manifestRecordsByID.values()].filter(({ holdout }) => holdout).map(({ id }) => id),
  );

  for (const result of results) {
    validateResultShape(result, "stability result", candidate);
    if (!manifestRecordsByID.has(result.id)) fail(`stability result contains unknown manifest ID ${result.id}`);
    if (!holdoutIDs.has(result.id)) fail(`stability result ID ${result.id} is not a locked holdout`);
    if (!result.structuredSuccess) fail(`stability result ID ${result.id} must be a structured-success repeat`);
    const idResults = resultsByID.get(result.id) ?? [];
    idResults.push(result);
    resultsByID.set(result.id, idResults);
  }

  if (resultsByID.size !== REQUIRED_HOLDOUT_COUNT) {
    fail("stability panel must cover every locked holdout and no other record");
  }
  for (const id of holdoutIDs) {
    if (resultsByID.get(id)?.length !== 2) {
      fail(`stability panel ID ${id} must have exactly two structured-success repeats`);
    }
  }
  return resultsByID;
}

export function scoreQualitativeReview(qualitativeReview, manifestRecordsByID, candidate, primaryResultsByID) {
  if (!hasExactKeys(qualitativeReview, ["candidate", "records", "resultsDigest", "version"]) ||
      qualitativeReview.version !== 2 || !Array.isArray(qualitativeReview.records)) {
    fail("qualitative review must use schema version 2 with frozen candidate, results digest, and records");
  }
  validateCandidate(qualitativeReview.candidate);
  if (CANDIDATE_KEYS.some((key) => qualitativeReview.candidate[key] !== candidate[key])) {
    fail("qualitative review candidate must match the frozen manifest candidate");
  }
  const primaryResults = [...primaryResultsByID.values()];
  if (qualitativeReview.resultsDigest !== buildPrimaryResultsDigest(primaryResults)) {
    fail("qualitative review results digest does not match the primary results");
  }
  if (qualitativeReview.records.length !== REQUIRED_RECORD_COUNT) {
    fail("qualitative review must contain exactly one review for all 80 manifest records");
  }
  const reviewedIDs = new Set();
  let acceptableCount = 0;
  let severeOrUneditableFailureCount = 0;
  for (const record of qualitativeReview.records) {
    if (!hasExactKeys(record, QUALITATIVE_RECORD_KEYS)) fail("qualitative review record fields are invalid");
    if (!manifestRecordsByID.has(record.id)) fail(`qualitative review contains unknown manifest ID ${record.id}`);
    if (reviewedIDs.has(record.id)) fail(`duplicate qualitative review ID ${record.id}`);
    const primaryResult = primaryResultsByID.get(record.id);
    if (record.structuredSuccess !== primaryResult?.structuredSuccess ||
        record.dominantFoodInterpretation !== primaryResult?.dominantFoodInterpretation ||
        record.interpretationDigest !== primaryResult?.interpretationDigest) {
      fail(`qualitative review interpretation evidence does not match primary result ID ${record.id}`);
    }
    if (typeof record.acceptableDominantFoodInterpretation !== "boolean" ||
        typeof record.severeOrUneditableFailure !== "boolean") {
      fail("qualitative review decisions must be boolean");
    }
    reviewedIDs.add(record.id);
    if (record.acceptableDominantFoodInterpretation) acceptableCount += 1;
    if (record.severeOrUneditableFailure) severeOrUneditableFailureCount += 1;
  }
  if (reviewedIDs.size !== manifestRecordsByID.size) {
    fail("qualitative review must cover every manifest record exactly once");
  }
  return {
    reviewedCount: reviewedIDs.size,
    acceptableCount,
    minimumAcceptableCount: 72,
    severeOrUneditableFailureCount,
    maximumSevereOrUneditableFailureCount: 0,
    passed: acceptableCount >= 72 && severeOrUneditableFailureCount === 0,
  };
}

function scoreNutrient(rows, nutrient) {
  const scoredRows = rows.filter(({ result }) => result.structuredSuccess);
  const isCalorie = nutrient === "calories";
  const absoluteErrors = scoredRows.map(({ record, result }) => Math.abs(result[nutrient] - record.groundTruth[nutrient]));
  const signedErrors = scoredRows.map(({ record, result }) => result[nutrient] - record.groundTruth[nutrient]);
  const truthTotal = scoredRows.reduce((sum, { record }) => sum + record.groundTruth[nutrient], 0);
  const percentageErrors = scoredRows
    .filter(({ record }) => isCalorie
      ? record.groundTruth[nutrient] > 0
      : record.groundTruth[nutrient] >= 5)
    .map(({ record, result }) => Math.abs(result[nutrient] - record.groundTruth[nutrient]) / record.groundTruth[nutrient] * 100);
  const passCount = scoredRows.filter(({ record, result }) => {
    const truth = record.groundTruth[nutrient];
    const allowedError = isCalorie ? Math.max(100, truth * 0.2) : Math.max(5, truth * 0.25);
    return Math.abs(result[nutrient] - truth) <= allowedError;
  }).length;

  return {
    scoredCount: scoredRows.length,
    mae: round(mean(absoluteErrors)),
    wapePct: truthTotal === 0 ? null : round(absoluteErrors.reduce((sum, value) => sum + value, 0) / truthTotal * 100),
    medianAbsolutePercentageErrorPct: round(median(percentageErrors)),
    signedBiasPct: truthTotal === 0 ? null : round(signedErrors.reduce((sum, value) => sum + value, 0) / truthTotal * 100),
    passCount,
    passRatePct: round(passCount / rows.length * 100),
  };
}

function scoreLatency(rows) {
  const values = rows.map(({ result }) => result.latencyMs);
  return {
    count: values.length,
    mean: round(mean(values)),
    median: round(median(values)),
    p95: round(percentile(values, 0.95)),
  };
}

function scoreGroup(rows) {
  const jsonSuccessCount = rows.filter(({ result }) => result.structuredSuccess).length;
  return {
    recordCount: rows.length,
    jsonSuccessCount,
    jsonSuccessRatePct: round(jsonSuccessCount / rows.length * 100),
    latencyMs: scoreLatency(rows),
    nutrients: Object.fromEntries(NUTRIENTS.map((nutrient) => [nutrient, scoreNutrient(rows, nutrient)])),
  };
}

function maximumGate(actualPct, maximumPct) {
  return { actualPct, maximumPct, passed: actualPct !== null && actualPct <= maximumPct };
}

function minimumGate(actualPct, minimumPct) {
  return { actualPct, minimumPct, passed: actualPct !== null && actualPct >= minimumPct };
}

function buildGates(groups, stabilityPanel, qualitativeReview) {
  const combined = groups.combined;
  const gates = {
    structuredSuccess: minimumGate(combined.jsonSuccessRatePct, 98),
    calorieWape: maximumGate(combined.nutrients.calories.wapePct, 25),
    medianCalorieAbsolutePercentageError: maximumGate(
      combined.nutrients.calories.medianAbsolutePercentageErrorPct,
      20,
    ),
    calorieSignedBias: {
      actualPct: combined.nutrients.calories.signedBiasPct,
      minimumPct: -10,
      maximumPct: 10,
      passed: combined.nutrients.calories.signedBiasPct !== null &&
        combined.nutrients.calories.signedBiasPct >= -10 &&
        combined.nutrients.calories.signedBiasPct <= 10,
    },
    macroWape: Object.fromEntries(MACROS.map((macro) => [
      macro,
      maximumGate(combined.nutrients[macro].wapePct, 30),
    ])),
    caloriePassRate: minimumGate(combined.nutrients.calories.passRatePct, 70),
    macroPassRate: Object.fromEntries(MACROS.map((macro) => [
      macro,
      minimumGate(combined.nutrients[macro].passRatePct, 65),
    ])),
    sourceCalorieWape: {
      Nutrition5k: maximumGate(groups.Nutrition5k.nutrients.calories.wapePct, 35),
      SNAPMe: maximumGate(groups.SNAPMe.nutrients.calories.wapePct, 35),
      MFDS: maximumGate(groups.MFDS.nutrients.calories.wapePct, 35),
    },
    stabilityPanel: { passed: stabilityPanel.gates.allPassed },
    qualitativeReview: { passed: qualitativeReview.passed },
  };

  const requiredGates = [
    gates.structuredSuccess,
    gates.calorieWape,
    gates.medianCalorieAbsolutePercentageError,
    gates.calorieSignedBias,
    ...Object.values(gates.macroWape),
    gates.caloriePassRate,
    ...Object.values(gates.macroPassRate),
    ...Object.values(gates.sourceCalorieWape),
    gates.stabilityPanel,
    gates.qualitativeReview,
  ];
  gates.allPassed = requiredGates.every(({ passed }) => passed);
  return gates;
}

function range(values) {
  return Math.max(...values) - Math.min(...values);
}

function scoreStabilityPanel(stabilityResultsByID) {
  const calorieSpreadPercentages = [];
  const macroSpreads = Object.fromEntries(MACROS.map((macro) => [macro, []]));
  let runCount = 0;
  const modelVersionIDs = new Set();

  for (const idResults of stabilityResultsByID.values()) {
    runCount += idResults.length;
    for (const result of idResults) modelVersionIDs.add(result.modelVersion);
    const successfulResults = idResults.filter(({ structuredSuccess }) => structuredSuccess);
    const calorieValues = successfulResults.map(({ calories }) => calories);
    const medianCalories = median(calorieValues);
    calorieSpreadPercentages.push(medianCalories === 0 ? Number.POSITIVE_INFINITY : range(calorieValues) / medianCalories * 100);
    for (const macro of MACROS) {
      macroSpreads[macro].push(range(successfulResults.map((result) => result[macro])));
    }
  }

  const medianCalorieSpreadPct = round(median(calorieSpreadPercentages));
  const medianMacroSpreadGrams = Object.fromEntries(MACROS.map((macro) => [macro, round(median(macroSpreads[macro]))]));
  const gates = {
    calories: maximumGate(medianCalorieSpreadPct, 10),
    ...Object.fromEntries(MACROS.map((macro) => [macro, {
      actualGrams: medianMacroSpreadGrams[macro],
      maximumGrams: 5,
      passed: medianMacroSpreadGrams[macro] !== null && medianMacroSpreadGrams[macro] <= 5,
    }])),
  };
  gates.allPassed = [gates.calories, ...MACROS.map((macro) => gates[macro])].every(({ passed }) => passed);

  return {
    ids: [...stabilityResultsByID.keys()],
    runCount,
    modelVersionIDs: [...modelVersionIDs].sort(),
    medianCalorieSpreadPct,
    medianMacroSpreadGrams,
    gates,
  };
}

export function scoreEvaluation(manifest, primaryResults, stabilityResults, qualitativeReviewInput) {
  const manifestRecordsByID = validateManifest(manifest);
  const resultsByID = validatePrimaryResults(primaryResults, manifestRecordsByID, manifest.candidate);
  const rows = [...manifestRecordsByID.values()].map((record) => ({ record, result: resultsByID.get(record.id) }));
  const groups = {
    combined: scoreGroup(rows),
    ...Object.fromEntries(SOURCES.map((source) => [source, scoreGroup(rows.filter(({ record }) => record.source === source))])),
  };
  const stabilityPanel = scoreStabilityPanel(
    validateStabilityResults(stabilityResults, manifestRecordsByID, manifest.candidate),
  );
  const qualitativeReview = scoreQualitativeReview(
    qualitativeReviewInput,
    manifestRecordsByID,
    manifest.candidate,
    resultsByID,
  );

  return {
    version: 1,
    evaluatedRecordCount: rows.length,
    candidate: manifest.candidate,
    modelVersionIDs: [...new Set(primaryResults.map(({ modelVersion }) => modelVersion))].sort(),
    groups,
    stabilityPanel,
    qualitativeReview,
    gates: buildGates(groups, stabilityPanel, qualitativeReview),
  };
}
