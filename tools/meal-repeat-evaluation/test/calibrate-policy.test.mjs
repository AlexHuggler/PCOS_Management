import assert from "node:assert/strict";
import { spawnSync } from "node:child_process";
import { mkdirSync, mkdtempSync, readFileSync, rmSync, statSync, writeFileSync } from "node:fs";
import { tmpdir } from "node:os";
import { dirname, join, resolve } from "node:path";
import test from "node:test";
import { fileURLToPath } from "node:url";

const toolkitDirectory = resolve(dirname(fileURLToPath(import.meta.url)), "..");
const calibratorPath = join(toolkitDirectory, "calibrate-policy.mjs");
const extractorPath = join(toolkitDirectory, "extract-feature-distances.swift");
const gitignorePath = join(toolkitDirectory, ".gitignore");
const outputDirectory = join(toolkitDirectory, "output");
let policySequence = 0;

function makeSyntheticEvaluation({ imageCount = 100, unsafeCrossMatches = 0, highRisk = false } = {}) {
  const images = Array.from({ length: imageCount }, (_, index) => ({
    id: `sample_${String(index + 1).padStart(3, "0")}`,
    label: index < 80
      ? `meal_${String(Math.floor(index / 4) + 1).padStart(2, "0")}`
      : `negative_${String(index - 79).padStart(2, "0")}`,
    highRisk: false,
  }));
  const distances = [];

  for (let first = 0; first < images.length; first += 1) {
    for (let second = first + 1; second < images.length; second += 1) {
      distances.push({
        firstID: images[first].id,
        secondID: images[second].id,
        distance: first < 80 && second < 80 && Math.floor(first / 4) === Math.floor(second / 4) ? 0.1 : 0.15,
      });
    }
  }

  for (let match = 0; match < unsafeCrossMatches; match += 1) {
    const first = match * 8;
    const second = first + 4;
    const pair = distances.find(({ firstID, secondID }) => (
      firstID === images[first].id && secondID === images[second].id
    ));
    pair.distance = 0.05;
    if (highRisk) images[first].highRisk = true;
  }

  return {
    manifest: { version: 1, images },
    report: {
      version: 1,
      evaluatedImageCount: imageCount,
      images: images.map(({ id, label }) => ({ id, label })),
      pairs: distances,
    },
  };
}

function makeMalformedHundredImageEvaluation() {
  const evaluation = makeSyntheticEvaluation();
  evaluation.manifest.images[99].label = "meal_20";
  evaluation.report.images[99].label = "meal_20";
  return evaluation;
}

function makeZeroDistanceEvaluation() {
  const evaluation = makeSyntheticEvaluation();
  for (const pair of evaluation.report.pairs) {
    const firstIndex = Number(pair.firstID.slice(-3)) - 1;
    const secondIndex = Number(pair.secondID.slice(-3)) - 1;
    if (firstIndex < 80 && secondIndex < 80 && Math.floor(firstIndex / 4) === Math.floor(secondIndex / 4)) {
      pair.distance = 0;
    }
  }
  return evaluation;
}

function writeEvaluationFixture(evaluation) {
  const directory = mkdtempSync(join(tmpdir(), "cyclebalance-repeat-evaluation-"));
  const manifestPath = join(directory, "manifest.json");
  const reportPath = join(directory, "distances.json");
  mkdirSync(outputDirectory, { recursive: true });
  const policyPath = join(outputDirectory, `test-policy-${process.pid}-${Date.now()}-${policySequence += 1}.json`);
  writeFileSync(manifestPath, JSON.stringify(evaluation.manifest));
  writeFileSync(reportPath, JSON.stringify(evaluation.report));
  return { directory, manifestPath, reportPath, policyPath, unsafePolicyPath: join(directory, "policy.json") };
}

function runCalibrator(fixture, policyPath = fixture.policyPath) {
  return spawnSync(process.execPath, [
    calibratorPath,
    "--manifest", fixture.manifestPath,
    "--report", fixture.reportPath,
    "--policy", policyPath,
  ], { encoding: "utf8" });
}

test("selects the highest-recall policy that meets every release gate", (t) => {
  const fixture = writeEvaluationFixture(makeSyntheticEvaluation());
  t.after(() => {
    rmSync(fixture.directory, { recursive: true, force: true });
    rmSync(fixture.policyPath, { force: true });
  });

  const result = runCalibrator(fixture);

  assert.equal(result.status, 0, result.stderr);
  assert.deepEqual(JSON.parse(readFileSync(fixture.policyPath, "utf8")), {
    version: 1,
    enabled: true,
    maximumDistance: 0.1,
    minimumNeighborMargin: 0,
    evaluatedImageCount: 100,
    precision: 1,
    highRiskFalseMatches: 0,
  });
  assert.equal(statSync(outputDirectory).mode & 0o777, 0o700);
});

test("refuses unsafe, incomplete, or malformed evaluations without writing a policy", (t) => {
  const cases = [
    ["sub-95-percent precision", makeSyntheticEvaluation({ unsafeCrossMatches: 3 })],
    ["high-risk cross-meal match", makeSyntheticEvaluation({ unsafeCrossMatches: 1, highRisk: true })],
    ["zero-distance similarity threshold", makeZeroDistanceEvaluation()],
    ["incomplete dataset", makeSyntheticEvaluation({ imageCount: 99 })],
    ["malformed 100-image composition", makeMalformedHundredImageEvaluation()],
  ];

  for (const [name, evaluation] of cases) {
    const fixture = writeEvaluationFixture(evaluation);
    t.after(() => {
      rmSync(fixture.directory, { recursive: true, force: true });
      rmSync(fixture.policyPath, { force: true });
    });
    const result = runCalibrator(fixture);

    assert.notEqual(result.status, 0, name);
    assert.match(result.stderr, /release gate|exactly 100|20 labels|four images|negative labels/i, name);
    assert.throws(() => readFileSync(fixture.policyPath), name);
  }
});

test("private artifact protections cover writers and common image formats", () => {
  const calibratorSource = readFileSync(calibratorPath, "utf8");
  const extractorSource = readFileSync(extractorPath, "utf8");
  const gitignoreSource = readFileSync(gitignorePath, "utf8");

  assert.match(calibratorSource, /chmodSync\(outputDirectory, 0o700\)/);
  assert.match(calibratorSource, /O_EXCL/);
  assert.match(calibratorSource, /O_NOFOLLOW/);
  assert.doesNotMatch(calibratorSource, /Date\.now\(\).*policy\.tmp/);
  assert.match(extractorSource, /\.posixPermissions:\s*0o700/);

  for (const extension of ["webp", "WEBP", "tif", "TIF", "tiff", "TIFF", "avif", "AVIF"]) {
    assert.match(gitignoreSource, new RegExp(`\\*\\.${extension}(?:\\n|$)`));
  }
});

test("refuses report safety metadata and unsafe policy destinations before writing", (t) => {
  const metadataFixture = writeEvaluationFixture(makeSyntheticEvaluation());
  const report = JSON.parse(readFileSync(metadataFixture.reportPath, "utf8"));
  report.images[0].highRisk = true;
  writeFileSync(metadataFixture.reportPath, JSON.stringify(report));
  t.after(() => {
    rmSync(metadataFixture.directory, { recursive: true, force: true });
    rmSync(metadataFixture.policyPath, { force: true });
  });

  const metadataResult = runCalibrator(metadataFixture);

  assert.notEqual(metadataResult.status, 0, metadataResult.stderr);
  assert.match(metadataResult.stderr, /report.*high-risk|report.*metadata/i);
  assert.throws(() => readFileSync(metadataFixture.policyPath));

  const destinationFixture = writeEvaluationFixture(makeSyntheticEvaluation());
  t.after(() => {
    rmSync(destinationFixture.directory, { recursive: true, force: true });
    rmSync(destinationFixture.policyPath, { force: true });
  });
  const destinationResult = runCalibrator(destinationFixture, destinationFixture.unsafePolicyPath);

  assert.notEqual(destinationResult.status, 0, destinationResult.stderr);
  assert.match(destinationResult.stderr, /must be written inside.*output/i);
  assert.throws(() => readFileSync(destinationFixture.unsafePolicyPath));
});
