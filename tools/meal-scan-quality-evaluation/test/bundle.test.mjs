import assert from "node:assert/strict";
import crypto from "node:crypto";
import test from "node:test";

import { buildEvaluationBundle } from "../src/bundle.mjs";
import { validateManifest } from "../src/evaluation.mjs";
import { validateImageMap } from "../src/runner.mjs";

const jpeg = Buffer.from([0xff, 0xd8, 0xff, 0xd9]);
const jpegHash = crypto.createHash("sha256").update(jpeg).digest("hex");
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

function sourceIndexFixture() {
  return {
    version: 1,
    records: Array.from({ length: 80 }, (_, index) => {
      const id = `public_meal_${String(index + 1).padStart(3, "0")}`;
      return {
        id,
        source: sourceForIndex(index),
        sourceUrl: `https://data.example.invalid/${id}`,
        license: "Verified public dataset license",
        sourceImagePath: `/source/public/${id}.png`,
        groundTruth: { calories: 500, protein: 20, carbs: 50, fat: 20 },
        referenceType: "dataset_annotation",
        samplingReason: "deterministic public benchmark sample",
        mealType: "lunch",
        locale: "en_US",
      };
    }),
  };
}

test("builds a deterministic source-balanced private bundle without leaking image paths", async () => {
  const sourceIndex = sourceIndexFixture();
  const normalizedPaths = [];

  const bundle = await buildEvaluationBundle({
    sourceIndex,
    candidate,
    normalizedImageDirectory: "/private/evaluation/images",
    normalizeImage: async (sourcePath, outputPath) => {
      normalizedPaths.push({ sourcePath, outputPath });
      return jpeg;
    },
  });

  const manifestByID = validateManifest(bundle.manifest);
  validateImageMap(bundle.imageMap, manifestByID);
  assert.equal(normalizedPaths.length, 80);
  assert.equal(bundle.manifest.records.every((record) => record.imageSha256 === jpegHash), true);
  assert.deepEqual(
    bundle.manifest.records.reduce((counts, record) => {
      if (record.holdout) counts[record.source] += 1;
      return counts;
    }, { Nutrition5k: 0, SNAPMe: 0, MFDS: 0 }),
    { Nutrition5k: 10, SNAPMe: 7, MFDS: 3 },
  );
  assert.equal(JSON.stringify(bundle.manifest).includes("/source/public"), false);
  assert.equal(JSON.stringify(bundle.manifest).includes("/private/evaluation"), false);
  assert.equal(bundle.imageMap.records[0].normalizedImagePath, "/private/evaluation/images/public_meal_001.jpg");

  const reversedBundle = await buildEvaluationBundle({
    sourceIndex: { ...sourceIndex, records: [...sourceIndex.records].reverse() },
    candidate,
    normalizedImageDirectory: "/private/evaluation/images",
    normalizeImage: async () => jpeg,
  });
  assert.deepEqual(reversedBundle.manifest, bundle.manifest);
  assert.deepEqual(reversedBundle.imageMap, bundle.imageMap);
});

test("validates all source records before normalizing the first image", async () => {
  const sourceIndex = sourceIndexFixture();
  sourceIndex.records[0].sourceImagePath = "relative.png";
  let normalizationCalls = 0;

  await assert.rejects(
    buildEvaluationBundle({
      sourceIndex,
      candidate,
      normalizedImageDirectory: "/private/evaluation/images",
      normalizeImage: async () => {
        normalizationCalls += 1;
        return jpeg;
      },
    }),
    /absolute/i,
  );
  assert.equal(normalizationCalls, 0);
});

test("rejects normalized output that is not a bounded JPEG", async () => {
  await assert.rejects(
    buildEvaluationBundle({
      sourceIndex: sourceIndexFixture(),
      candidate,
      normalizedImageDirectory: "/private/evaluation/images",
      normalizeImage: async () => Buffer.from("not-a-jpeg"),
    }),
    /JPEG/i,
  );
});
