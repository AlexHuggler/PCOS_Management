import assert from "node:assert/strict";
import { chmodSync, mkdirSync, mkdtempSync, readFileSync, rmSync, writeFileSync } from "node:fs";
import { tmpdir } from "node:os";
import { dirname, join, resolve } from "node:path";
import { spawnSync } from "node:child_process";
import test from "node:test";
import { fileURLToPath } from "node:url";

import {
  buildInterpretationDigest,
  createQualitativeReviewTemplate,
} from "../src/evaluation.mjs";

const toolkitDirectory = resolve(dirname(fileURLToPath(import.meta.url)), "..");
const scorerPath = join(toolkitDirectory, "score.mjs");
const sampleManifestPath = join(toolkitDirectory, "sample-manifest.json");
const nutrients = ["calories", "protein", "carbs", "fat"];
const candidate = Object.freeze({
  modelVersion: "gemini-3.1-flash-lite",
  promptVersion: "meal-scan-prompt-v1",
  schemaVersion: "meal-scan-gemini-v1",
  normalizerVersion: "imageio-960-jpeg078-v1",
  sourceCommit: "a".repeat(40),
});

function sourceForIndex(index) {
  if (index < 40) return "Nutrition5k";
  if (index < 70) return "SNAPMe";
  return "MFDS";
}

function makeManifest() {
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
        license: "Public dataset terms verified for this record",
        imageSha256: (index + 1).toString(16).padStart(64, "0"),
        groundTruth: {
          calories: 500,
          protein: 20,
          carbs: 50,
          fat: 20,
        },
        referenceType: "dataset_annotation",
        samplingReason: "balanced source sample",
      };
    }),
  };
}

function makeResults(manifest, transform = ({ truth }) => truth) {
  return manifest.records.map((record, index) => {
    const prediction = transform({ truth: record.groundTruth, record, index });
    const dominantFoodInterpretation = prediction === null
      ? null
      : `Benchmark meal ${index + 1} — dominant food ${index + 1}`;
    return {
      id: record.id,
      structuredSuccess: prediction !== null,
      calories: prediction?.calories ?? null,
      protein: prediction?.protein ?? null,
      carbs: prediction?.carbs ?? null,
      fat: prediction?.fat ?? null,
      modelVersion: manifest.candidate.modelVersion,
      promptVersion: candidate.promptVersion,
      schemaVersion: candidate.schemaVersion,
      normalizerVersion: candidate.normalizerVersion,
      sourceCommit: candidate.sourceCommit,
      latencyMs: 120 + index,
      dominantFoodInterpretation,
      interpretationDigest: buildInterpretationDigest({
        candidate: manifest.candidate,
        id: record.id,
        structuredSuccess: prediction !== null,
        dominantFoodInterpretation,
      }),
    };
  });
}

function makeStabilityResults(manifest, transform = ({ truth }) => truth) {
  return manifest.records.filter(({ holdout }) => holdout).flatMap((record, holdoutIndex) => (
    Array.from({ length: 2 }, (_, runIndex) => {
      const prediction = transform({ truth: record.groundTruth, record, holdoutIndex, runIndex });
      const dominantFoodInterpretation = prediction === null
        ? null
        : `Holdout meal ${holdoutIndex + 1} — repeat food ${runIndex + 1}`;
      return {
        id: record.id,
        structuredSuccess: prediction !== null,
        calories: prediction?.calories ?? null,
        protein: prediction?.protein ?? null,
        carbs: prediction?.carbs ?? null,
        fat: prediction?.fat ?? null,
        modelVersion: manifest.candidate.modelVersion,
        promptVersion: manifest.candidate.promptVersion,
        schemaVersion: manifest.candidate.schemaVersion,
        normalizerVersion: manifest.candidate.normalizerVersion,
        sourceCommit: manifest.candidate.sourceCommit,
        latencyMs: 100 + runIndex,
        dominantFoodInterpretation,
        interpretationDigest: buildInterpretationDigest({
          candidate: manifest.candidate,
          id: record.id,
          structuredSuccess: prediction !== null,
          dominantFoodInterpretation,
        }),
      };
    })
  ));
}

function makeQualitative(
  manifest,
  transform = () => ({ acceptable: true, severe: false }),
  results = makeResults(manifest),
) {
  const template = createQualitativeReviewTemplate(manifest.candidate, results);
  return {
    ...template,
    records: template.records.map((record, index) => {
      const review = transform({ record, index });
      return {
        ...record,
        acceptableDominantFoodInterpretation: review.acceptable,
        severeOrUneditableFailure: review.severe,
      };
    }),
  };
}

function writeFixture({
  manifest = makeManifest(),
  results = makeResults(manifest),
  resultsFormat = "json",
  stability,
  qualitative,
  omitStability = false,
  omitQualitative = false,
}) {
  const directory = mkdtempSync(join(tmpdir(), "cyclebalance-meal-quality-"));
  const binDirectory = join(directory, "bin");
  mkdirSync(binDirectory);
  const gitPath = join(binDirectory, "git");
  writeFileSync(gitPath, `#!/usr/bin/env node
const args = process.argv.slice(2);
if (args.includes("status")) {
  if (process.env.CYCLEBALANCE_TEST_DIRTY_SCORER === "1") process.stdout.write(" M tools/meal-scan-quality-evaluation/score.mjs\\n");
} else if (args.includes("rev-parse")) {
  process.stdout.write("${candidate.sourceCommit}\\n");
} else {
  process.exitCode = 64;
}
`);
  chmodSync(gitPath, 0o700);
  const manifestPath = join(directory, "manifest.json");
  const resultsPath = join(directory, resultsFormat === "jsonl" ? "results.jsonl" : "results.json");
  writeFileSync(manifestPath, JSON.stringify(manifest));
  writeFileSync(
    resultsPath,
    resultsFormat === "jsonl"
      ? `${results.map((result) => JSON.stringify(result)).join("\n")}\n`
      : JSON.stringify(results),
  );

  let stabilityPath;
  if (!omitStability) {
    stability ??= { format: "json", results: makeStabilityResults(manifest) };
    stabilityPath = join(directory, stability.format === "json" ? "stability.json" : "stability.jsonl");
    writeFileSync(
      stabilityPath,
      stability.format === "json"
        ? JSON.stringify(stability.results)
        : `${stability.results.map((result) => JSON.stringify(result)).join("\n")}\n`,
    );
  }

  let qualitativePath;
  if (!omitQualitative) {
    if (qualitative === undefined) {
      try {
        qualitative = makeQualitative(manifest, undefined, results);
      } catch {
        qualitative = makeQualitative(makeManifest());
      }
    }
    qualitativePath = join(directory, "qualitative.json");
    writeFileSync(qualitativePath, JSON.stringify(qualitative));
  }

  return { directory, binDirectory, manifestPath, resultsPath, stabilityPath, qualitativePath };
}

function runScorer(fixture, { dirtyScorer = false } = {}) {
  const args = [scorerPath, "--manifest", fixture.manifestPath, "--results", fixture.resultsPath];
  if (fixture.stabilityPath) args.push("--stability", fixture.stabilityPath);
  if (fixture.qualitativePath) args.push("--qualitative", fixture.qualitativePath);
  return spawnSync(process.execPath, args, {
    encoding: "utf8",
    env: {
      ...process.env,
      PATH: `${fixture.binDirectory}:${process.env.PATH ?? ""}`,
      CYCLEBALANCE_TEST_DIRTY_SCORER: dirtyScorer ? "1" : "0",
    },
  });
}

function parseSuccessfulRun(result) {
  assert.equal(result.status, 0, result.stderr);
  assert.equal(result.stderr, "");
  return JSON.parse(result.stdout);
}

function parseFailedGateRun(result) {
  assert.equal(result.status, 1, result.stderr);
  assert.equal(result.stderr, "");
  return JSON.parse(result.stdout);
}

test("scores JSONL results separately by source and in combination without leaking manifest metadata", (t) => {
  const manifest = makeManifest();
  const fixture = writeFixture({ manifest, results: makeResults(manifest), resultsFormat: "jsonl" });
  t.after(() => rmSync(fixture.directory, { recursive: true, force: true }));

  const report = parseSuccessfulRun(runScorer(fixture));

  assert.equal(report.version, 1);
  assert.equal(report.evaluatedRecordCount, 80);
  assert.deepEqual(report.modelVersionIDs, [candidate.modelVersion]);
  assert.deepEqual(Object.keys(report.groups).sort(), ["MFDS", "Nutrition5k", "SNAPMe", "combined"].sort());
  assert.equal(report.groups.combined.recordCount, 80);
  assert.equal(report.groups.Nutrition5k.recordCount, 40);
  assert.equal(report.groups.SNAPMe.recordCount, 30);
  assert.equal(report.groups.MFDS.recordCount, 10);

  for (const group of Object.values(report.groups)) {
    assert.equal(group.jsonSuccessRatePct, 100);
    for (const nutrient of nutrients) {
      assert.deepEqual(group.nutrients[nutrient], {
        scoredCount: group.recordCount,
        mae: 0,
        wapePct: 0,
        medianAbsolutePercentageErrorPct: 0,
        signedBiasPct: 0,
        passCount: group.recordCount,
        passRatePct: 100,
      });
    }
  }
  assert.equal(report.gates.allPassed, true);

  const serialized = JSON.stringify(report);
  for (const forbidden of [
    "https://data.example.invalid",
    "Public dataset terms",
    manifest.records[0].imageSha256,
    "dataset_annotation",
    "balanced source sample",
    "sourceUrl",
    "imageSha256",
    "groundTruth",
    "samplingReason",
    "imagePath",
    "dominantFoodInterpretation",
  ]) {
    assert.equal(serialized.includes(forbidden), false, `report leaked ${forbidden}`);
  }
});

test("accepts a JSON array and counts a structured failure against JSON and nutrient pass rates", (t) => {
  const manifest = makeManifest();
  const results = makeResults(manifest);
  results[0] = {
    ...results[0],
    structuredSuccess: false,
    calories: null,
    protein: null,
    carbs: null,
    fat: null,
    dominantFoodInterpretation: null,
    interpretationDigest: buildInterpretationDigest({
      candidate: manifest.candidate,
      id: results[0].id,
      structuredSuccess: false,
      dominantFoodInterpretation: null,
    }),
  };
  const fixture = writeFixture({ manifest, results });
  t.after(() => rmSync(fixture.directory, { recursive: true, force: true }));

  const report = parseSuccessfulRun(runScorer(fixture));

  assert.equal(report.groups.combined.jsonSuccessCount, 79);
  assert.equal(report.groups.combined.jsonSuccessRatePct, 98.75);
  assert.equal(report.groups.combined.nutrients.calories.scoredCount, 79);
  assert.equal(report.groups.combined.nutrients.calories.mae, 0);
  assert.equal(report.groups.combined.nutrients.calories.passCount, 79);
  assert.equal(report.groups.combined.nutrients.calories.passRatePct, 98.75);
  assert.equal(report.gates.structuredSuccess.passed, true);
  assert.equal(report.gates.allPassed, true);
});

test("enforces inclusive calorie and macro pass thresholds", (t) => {
  const manifest = makeManifest();
  const results = makeResults(manifest, ({ truth }) => ({
    calories: truth.calories + 100,
    protein: truth.protein + 5,
    carbs: truth.carbs + 12.5,
    fat: truth.fat + 5,
  }));
  const fixture = writeFixture({ manifest, results });
  t.after(() => rmSync(fixture.directory, { recursive: true, force: true }));

  const report = parseFailedGateRun(runScorer(fixture));

  assert.equal(report.groups.combined.nutrients.calories.passRatePct, 100);
  assert.equal(report.groups.combined.nutrients.protein.passRatePct, 100);
  assert.equal(report.groups.combined.nutrients.carbs.passRatePct, 100);
  assert.equal(report.groups.combined.nutrients.fat.passRatePct, 100);
  assert.equal(report.gates.calorieSignedBias.passed, false);
  assert.equal(report.gates.allPassed, false);
});

test("omits item-level macro percentage error when truth is below five grams", (t) => {
  const manifest = makeManifest();
  for (const record of manifest.records) record.groundTruth.protein = 1;
  const results = makeResults(manifest, ({ truth }) => ({
    ...truth,
    protein: 10,
  }));
  const fixture = writeFixture({ manifest, results });
  t.after(() => rmSync(fixture.directory, { recursive: true, force: true }));

  const report = parseFailedGateRun(runScorer(fixture));

  assert.equal(report.groups.combined.nutrients.protein.medianAbsolutePercentageErrorPct, null);
  assert.equal(report.groups.combined.nutrients.protein.wapePct, 900);
});

test("fails the source guard when Nutrition5k calorie WAPE exceeds 35 percent", (t) => {
  const manifest = makeManifest();
  const results = makeResults(manifest, ({ truth, record }) => ({
    ...truth,
    calories: record.source === "Nutrition5k" ? truth.calories * 1.4 : truth.calories,
  }));
  const fixture = writeFixture({ manifest, results });
  t.after(() => rmSync(fixture.directory, { recursive: true, force: true }));

  const report = parseFailedGateRun(runScorer(fixture));

  assert.equal(report.groups.combined.nutrients.calories.wapePct, 20);
  assert.equal(report.groups.Nutrition5k.nutrients.calories.wapePct, 40);
  assert.equal(report.gates.calorieWape.passed, true);
  assert.equal(report.gates.sourceCalorieWape.Nutrition5k.passed, false);
  assert.equal(report.gates.sourceCalorieWape.SNAPMe.passed, true);
  assert.equal(report.gates.allPassed, false);
});

test("applies the same 35 percent calorie-WAPE guard to MFDS", (t) => {
  const manifest = makeManifest();
  const results = makeResults(manifest, ({ truth, record }) => ({
    ...truth,
    calories: record.source === "MFDS" ? truth.calories * 1.4 : truth.calories,
  }));
  const fixture = writeFixture({ manifest, results });
  t.after(() => rmSync(fixture.directory, { recursive: true, force: true }));

  const report = parseFailedGateRun(runScorer(fixture));

  assert.equal(report.groups.MFDS.nutrients.calories.wapePct, 40);
  assert.equal(report.gates.sourceCalorieWape.MFDS.passed, false);
  assert.equal(report.gates.allPassed, false);
});

test("rejects manifests that do not preserve the exact public-dataset topology and metadata", (t) => {
  const cases = [
    ["exactly 80", (manifest) => manifest.records.pop()],
    ["exactly 40 Nutrition5k", (manifest) => { manifest.records[0].source = "SNAPMe"; }],
    ["exactly 20 locked holdout", (manifest) => { manifest.records[0].holdout = false; }],
    ["sourceUrl", (manifest) => { delete manifest.records[0].sourceUrl; }],
    ["license", (manifest) => { manifest.records[0].license = ""; }],
    ["imageSha256", (manifest) => { manifest.records[0].imageSha256 = "not-a-hash"; }],
    ["groundTruth", (manifest) => { manifest.records[0].groundTruth.calories = -1; }],
    ["referenceType", (manifest) => { delete manifest.records[0].referenceType; }],
    ["samplingReason", (manifest) => { delete manifest.records[0].samplingReason; }],
    ["unique", (manifest) => { manifest.records[1].id = manifest.records[0].id; }],
    ["candidate", (manifest) => { delete manifest.candidate.promptVersion; }],
    ["source.?commit", (manifest) => { manifest.candidate.sourceCommit = "dirty"; }],
  ];

  for (const [expectedMessage, mutate] of cases) {
    const manifest = makeManifest();
    mutate(manifest);
    const fixture = writeFixture({ manifest, results: makeResults(makeManifest()) });
    t.after(() => rmSync(fixture.directory, { recursive: true, force: true }));

    const result = runScorer(fixture);

    assert.notEqual(result.status, 0, expectedMessage);
    assert.match(result.stderr, new RegExp(expectedMessage, "i"), result.stderr);
    assert.equal(result.stdout, "");
  }
});

test("requires both complete stability and qualitative inputs", (t) => {
  const manifest = makeManifest();
  const missingStability = writeFixture({ manifest, omitStability: true });
  const missingQualitative = writeFixture({ manifest, omitQualitative: true });
  t.after(() => rmSync(missingStability.directory, { recursive: true, force: true }));
  t.after(() => rmSync(missingQualitative.directory, { recursive: true, force: true }));

  for (const [fixture, expected] of [[missingStability, /usage/i], [missingQualitative, /usage/i]]) {
    const result = runScorer(fixture);
    assert.equal(result.status, 1);
    assert.match(result.stderr, expected);
    assert.equal(result.stdout, "");
  }
});

test("scorer refuses a dirty candidate checkout before emitting a report", (t) => {
  const fixture = writeFixture({});
  t.after(() => rmSync(fixture.directory, { recursive: true, force: true }));

  const result = runScorer(fixture, { dirtyScorer: true });

  assert.equal(result.status, 1);
  assert.match(result.stderr, /clean and committed/i);
  assert.equal(result.stdout, "");
});

test("requires exactly two structured-success repeats for every and only locked holdout", (t) => {
  const manifest = makeManifest();
  const cases = [
    ["exactly two", (records) => records.pop()],
    ["exactly two", (records) => records.push({ ...records[0] })],
    ["locked holdout", (records) => {
      records[0].id = manifest.records.find(({ holdout }) => !holdout).id;
      records[0].interpretationDigest = buildInterpretationDigest({
        candidate: manifest.candidate,
        id: records[0].id,
        structuredSuccess: records[0].structuredSuccess,
        dominantFoodInterpretation: records[0].dominantFoodInterpretation,
      });
    }],
    ["structured-success", (records) => {
      records[0] = {
        ...records[0],
        structuredSuccess: false,
        calories: null,
        protein: null,
        carbs: null,
        fat: null,
        dominantFoodInterpretation: null,
        interpretationDigest: buildInterpretationDigest({
          candidate: manifest.candidate,
          id: records[0].id,
          structuredSuccess: false,
          dominantFoodInterpretation: null,
        }),
      };
    }],
  ];

  for (const [expected, mutate] of cases) {
    const stabilityResults = makeStabilityResults(manifest);
    mutate(stabilityResults);
    const fixture = writeFixture({ manifest, stability: { format: "json", results: stabilityResults } });
    t.after(() => rmSync(fixture.directory, { recursive: true, force: true }));
    const result = runScorer(fixture);
    assert.equal(result.status, 1);
    assert.match(result.stderr, new RegExp(expected, "i"), result.stderr);
    assert.equal(result.stdout, "");
  }
});

test("rejects mixed model prompt schema normalizer or source-commit provenance", (t) => {
  const manifest = makeManifest();
  const mutations = [
    ["modelVersion", "other-model"],
    ["promptVersion", "other-prompt"],
    ["schemaVersion", "other-schema"],
    ["normalizerVersion", "other-normalizer"],
    ["sourceCommit", "b".repeat(40)],
  ];

  for (const [field, value] of mutations) {
    const results = makeResults(manifest);
    results[0][field] = value;
    const fixture = writeFixture({ manifest, results });
    t.after(() => rmSync(fixture.directory, { recursive: true, force: true }));
    const result = runScorer(fixture);
    assert.equal(result.status, 1);
    assert.match(result.stderr, /candidate provenance/i, `${field}: ${result.stderr}`);
    assert.equal(result.stdout, "");
  }
});

test("requires at least 72 acceptable qualitative reviews and zero severe or uneditable failures", (t) => {
  const manifest = makeManifest();
  const belowThreshold = makeQualitative(manifest, ({ index }) => ({ acceptable: index < 71, severe: false }));
  const severe = makeQualitative(manifest, ({ index }) => ({ acceptable: true, severe: index === 0 }));

  for (const [qualitative, expectedAcceptable, expectedSevere] of [
    [belowThreshold, 71, 0],
    [severe, 80, 1],
  ]) {
    const fixture = writeFixture({ manifest, qualitative });
    t.after(() => rmSync(fixture.directory, { recursive: true, force: true }));
    const report = parseFailedGateRun(runScorer(fixture));
    assert.equal(report.qualitativeReview.acceptableCount, expectedAcceptable);
    assert.equal(report.qualitativeReview.severeOrUneditableFailureCount, expectedSevere);
    assert.equal(report.gates.qualitativeReview.passed, false);
    assert.equal(report.gates.allPassed, false);
  }
});

test("rejects qualitative decisions when interpretation evidence or primary results are changed", (t) => {
  const manifest = makeManifest();
  const results = makeResults(manifest);
  const tamperedInterpretation = makeQualitative(manifest, undefined, results);
  tamperedInterpretation.records[0].dominantFoodInterpretation = "A different dominant food";

  const changedResults = makeResults(manifest);
  changedResults[0].calories += 1;
  const staleReview = makeQualitative(manifest, undefined, results);

  for (const [qualitative, fixtureResults, expected] of [
    [tamperedInterpretation, results, /interpretation evidence/i],
    [staleReview, changedResults, /results digest/i],
  ]) {
    const fixture = writeFixture({ manifest, results: fixtureResults, qualitative });
    t.after(() => rmSync(fixture.directory, { recursive: true, force: true }));
    const result = runScorer(fixture);
    assert.equal(result.status, 1);
    assert.match(result.stderr, expected);
    assert.equal(result.stdout, "");
  }
});

test("rejects missing, duplicate, extra, or malformed result records", (t) => {
  const cases = [
    ["exactly one result", (results) => results.pop()],
    ["duplicate result ID", (results) => {
      results[1].id = results[0].id;
      results[1].interpretationDigest = buildInterpretationDigest({
        candidate,
        id: results[1].id,
        structuredSuccess: results[1].structuredSuccess,
        dominantFoodInterpretation: results[1].dominantFoodInterpretation,
      });
    }],
    ["unknown manifest ID", (results) => {
      results[0].id = "public_meal_999";
      results[0].interpretationDigest = buildInterpretationDigest({
        candidate,
        id: results[0].id,
        structuredSuccess: results[0].structuredSuccess,
        dominantFoodInterpretation: results[0].dominantFoodInterpretation,
      });
    }],
    ["modelVersion", (results) => { results[0].modelVersion = ""; }],
    ["latencyMs", (results) => { results[0].latencyMs = -1; }],
    ["nutrition values", (results) => { results[0].calories = null; }],
    ["structured failure nutrition values", (results) => {
      results[0].structuredSuccess = false;
      results[0].calories = 100;
      results[0].protein = null;
      results[0].carbs = null;
      results[0].fat = null;
      results[0].dominantFoodInterpretation = null;
      results[0].interpretationDigest = buildInterpretationDigest({
        candidate,
        id: results[0].id,
        structuredSuccess: false,
        dominantFoodInterpretation: null,
      });
    }],
  ];

  for (const [expectedMessage, mutate] of cases) {
    const manifest = makeManifest();
    const results = makeResults(manifest);
    mutate(results);
    const fixture = writeFixture({ manifest, results });
    t.after(() => rmSync(fixture.directory, { recursive: true, force: true }));

    const result = runScorer(fixture);

    assert.notEqual(result.status, 0, expectedMessage);
    assert.match(result.stderr, new RegExp(expectedMessage, "i"), result.stderr);
    assert.equal(result.stdout, "");
  }
});

test("scores a passing JSONL stability panel from median within-ID spreads", (t) => {
  const manifest = makeManifest();
  const panelRecords = manifest.records.filter(({ holdout }) => holdout);
  const stabilityResults = makeStabilityResults(manifest, ({ runIndex }) => (
    runIndex === 0
      ? { calories: 100, protein: 10, carbs: 20, fat: 8 }
      : { calories: 110, protein: 15, carbs: 25, fat: 13 }
  ));
  const fixture = writeFixture({
    manifest,
    results: makeResults(manifest),
    stability: { format: "jsonl", results: stabilityResults },
  });
  t.after(() => rmSync(fixture.directory, { recursive: true, force: true }));

  const report = parseSuccessfulRun(runScorer(fixture));

  assert.deepEqual(report.stabilityPanel.ids, panelRecords.map(({ id }) => id));
  assert.equal(report.stabilityPanel.runCount, 40);
  assert.equal(report.stabilityPanel.medianCalorieSpreadPct, 9.52381);
  assert.deepEqual(report.stabilityPanel.medianMacroSpreadGrams, { protein: 5, carbs: 5, fat: 5 });
  assert.equal(report.stabilityPanel.gates.calories.passed, true);
  assert.equal(report.stabilityPanel.gates.protein.passed, true);
  assert.equal(report.stabilityPanel.gates.carbs.passed, true);
  assert.equal(report.stabilityPanel.gates.fat.passed, true);
  assert.equal(report.stabilityPanel.gates.allPassed, true);
  assert.equal(report.gates.stabilityPanel.passed, true);
  assert.equal(report.gates.allPassed, true);
});

test("fails stability when the panel median calorie or macro spread exceeds its gate", (t) => {
  const manifest = makeManifest();
  const stabilityResults = makeStabilityResults(manifest, ({ runIndex }) => (
    runIndex === 0
      ? { calories: 100, protein: 10, carbs: 20, fat: 8 }
      : { calories: 130, protein: 17, carbs: 27, fat: 15 }
  ));
  const fixture = writeFixture({
    manifest,
    results: makeResults(manifest),
    stability: { format: "json", results: stabilityResults },
  });
  t.after(() => rmSync(fixture.directory, { recursive: true, force: true }));

  const report = parseFailedGateRun(runScorer(fixture));

  assert.equal(report.stabilityPanel.medianCalorieSpreadPct, 26.086957);
  assert.equal(report.stabilityPanel.gates.calories.passed, false);
  assert.equal(report.stabilityPanel.gates.protein.passed, false);
  assert.equal(report.stabilityPanel.gates.allPassed, false);
  assert.equal(report.gates.stabilityPanel.passed, false);
  assert.equal(report.gates.allPassed, false);
});

test("ships a structurally valid 80-record sample manifest", (t) => {
  const manifest = JSON.parse(readFileSync(sampleManifestPath, "utf8"));
  const fixture = writeFixture({ manifest, results: makeResults(manifest) });
  t.after(() => rmSync(fixture.directory, { recursive: true, force: true }));

  const report = parseSuccessfulRun(runScorer(fixture));

  assert.equal(report.evaluatedRecordCount, 80);
  assert.equal(report.gates.allPassed, true);
});
