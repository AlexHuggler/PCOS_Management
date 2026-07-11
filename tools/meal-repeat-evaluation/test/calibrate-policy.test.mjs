import assert from "node:assert/strict";
import { spawnSync } from "node:child_process";
import { mkdtempSync, readFileSync, rmSync, writeFileSync } from "node:fs";
import { tmpdir } from "node:os";
import { dirname, join, resolve } from "node:path";
import test from "node:test";
import { fileURLToPath } from "node:url";

const toolkitDirectory = resolve(dirname(fileURLToPath(import.meta.url)), "..");
const calibratorPath = join(toolkitDirectory, "calibrate-policy.mjs");

function makeSyntheticEvaluation({ imageCount = 100, unsafeCrossMatches = 0, highRisk = false } = {}) {
  const images = Array.from({ length: imageCount }, (_, index) => ({
    id: `sample_${String(index + 1).padStart(3, "0")}`,
    label: `meal_${String(Math.floor(index / 2) + 1).padStart(2, "0")}`,
    highRisk: false,
  }));
  const distances = [];

  for (let first = 0; first < images.length; first += 1) {
    for (let second = first + 1; second < images.length; second += 1) {
      distances.push({
        firstID: images[first].id,
        secondID: images[second].id,
        distance: Math.floor(first / 2) === Math.floor(second / 2) ? 0.1 : 0.15,
      });
    }
  }

  for (let match = 0; match < unsafeCrossMatches; match += 1) {
    const first = match * 4;
    const second = first + 2;
    const pair = distances.find(({ firstID, secondID }) => (
      firstID === images[first].id && secondID === images[second].id
    ));
    pair.distance = 0.05;
    if (highRisk) images[first].highRisk = true;
  }

  return {
    manifest: { version: 1, images },
    report: { version: 1, evaluatedImageCount: imageCount, images, pairs: distances },
  };
}

function writeEvaluationFixture(evaluation) {
  const directory = mkdtempSync(join(tmpdir(), "cyclebalance-repeat-evaluation-"));
  const manifestPath = join(directory, "manifest.json");
  const reportPath = join(directory, "distances.json");
  const policyPath = join(directory, "policy.json");
  writeFileSync(manifestPath, JSON.stringify(evaluation.manifest));
  writeFileSync(reportPath, JSON.stringify(evaluation.report));
  return { directory, manifestPath, reportPath, policyPath };
}

function runCalibrator(fixture) {
  return spawnSync(process.execPath, [
    calibratorPath,
    "--manifest", fixture.manifestPath,
    "--report", fixture.reportPath,
    "--policy", fixture.policyPath,
  ], { encoding: "utf8" });
}

test("selects the highest-recall policy that meets every release gate", (t) => {
  const fixture = writeEvaluationFixture(makeSyntheticEvaluation());
  t.after(() => rmSync(fixture.directory, { recursive: true, force: true }));

  const result = runCalibrator(fixture);

  assert.equal(result.status, 0, result.stderr);
  assert.deepEqual(JSON.parse(readFileSync(fixture.policyPath, "utf8")), {
    version: 1,
    enabled: true,
    maximumDistance: 0.1,
    minimumNeighborMargin: 0.05,
    evaluatedImageCount: 100,
    precision: 1,
    highRiskFalseMatches: 0,
  });
});

test("refuses unsafe or incomplete evaluations without writing a policy", (t) => {
  const cases = [
    ["sub-95-percent precision", makeSyntheticEvaluation({ unsafeCrossMatches: 3 })],
    ["high-risk cross-meal match", makeSyntheticEvaluation({ unsafeCrossMatches: 1, highRisk: true })],
    ["incomplete dataset", makeSyntheticEvaluation({ imageCount: 99 })],
  ];

  for (const [name, evaluation] of cases) {
    const fixture = writeEvaluationFixture(evaluation);
    t.after(() => rmSync(fixture.directory, { recursive: true, force: true }));
    const result = runCalibrator(fixture);

    assert.notEqual(result.status, 0, name);
    assert.match(result.stderr, /release gate|exactly 100/i, name);
    assert.throws(() => readFileSync(fixture.policyPath), name);
  }
});
