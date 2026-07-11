import { readFileSync, renameSync, writeFileSync } from "node:fs";
import { dirname, join } from "node:path";

const REQUIRED_IMAGE_COUNT = 100;
const MINIMUM_PRECISION = 0.95;
const EPSILON = 1e-9;

function fail(message) {
  throw new Error(message);
}

function round(value) {
  return Number(value.toFixed(6));
}

function parseArguments(argumentsList) {
  const options = {};
  for (let index = 0; index < argumentsList.length; index += 2) {
    const flag = argumentsList[index];
    const value = argumentsList[index + 1];
    if (!value || !["--manifest", "--report", "--policy"].includes(flag) || options[flag]) {
      fail("usage: node calibrate-policy.mjs --manifest <file> --report <file> --policy <file>");
    }
    options[flag] = value;
  }

  if (Object.keys(options).length !== 3) {
    fail("usage: node calibrate-policy.mjs --manifest <file> --report <file> --policy <file>");
  }
  return options;
}

function readJSON(filePath, kind) {
  try {
    return JSON.parse(readFileSync(filePath, "utf8"));
  } catch {
    fail(`invalid ${kind} JSON`);
  }
}

function validateOpaqueID(id) {
  return typeof id === "string" && /^[A-Za-z0-9][A-Za-z0-9_-]{7,127}$/.test(id);
}

function validateManifest(manifest) {
  if (manifest?.version !== 1 || !Array.isArray(manifest.images)) {
    fail("invalid manifest schema");
  }
  if (manifest.images.length !== REQUIRED_IMAGE_COUNT) {
    fail("release gate failed: manifest must contain exactly 100 evaluated images");
  }

  const images = new Map();
  for (const image of manifest.images) {
    if (!validateOpaqueID(image?.id) || typeof image.label !== "string" || !image.label.trim()) {
      fail("invalid manifest image metadata");
    }
    if (images.has(image.id)) fail("manifest IDs must be unique");
    if (image.highRisk !== undefined && typeof image.highRisk !== "boolean") {
      fail("invalid manifest high-risk flag");
    }
    images.set(image.id, { label: image.label, highRisk: image.highRisk === true });
  }
  return images;
}

function pairKey(firstID, secondID) {
  return [firstID, secondID].sort().join("\u0000");
}

function validateReport(report, manifestImages) {
  if (report?.version !== 1 || report.evaluatedImageCount !== REQUIRED_IMAGE_COUNT ||
      !Array.isArray(report.images) || !Array.isArray(report.pairs)) {
    fail("release gate failed: report must describe exactly 100 evaluated images");
  }
  if (report.images.length !== REQUIRED_IMAGE_COUNT) {
    fail("release gate failed: report must describe exactly 100 evaluated images");
  }

  const reportIDs = new Set();
  for (const image of report.images) {
    const manifestImage = manifestImages.get(image?.id);
    if (!manifestImage || reportIDs.has(image.id) || image.label !== manifestImage.label ||
        image.highRisk !== undefined && image.highRisk !== manifestImage.highRisk) {
      fail("report images do not match manifest metadata");
    }
    reportIDs.add(image.id);
  }
  if (reportIDs.size !== manifestImages.size) fail("report images do not match manifest IDs");

  const expectedPairCount = (REQUIRED_IMAGE_COUNT * (REQUIRED_IMAGE_COUNT - 1)) / 2;
  if (report.pairs.length !== expectedPairCount) fail("report must contain every pairwise distance");

  const distances = new Map();
  for (const pair of report.pairs) {
    if (!manifestImages.has(pair?.firstID) || !manifestImages.has(pair.secondID) ||
        pair.firstID === pair.secondID || !Number.isFinite(pair.distance) || pair.distance < 0) {
      fail("invalid report pair");
    }
    const key = pairKey(pair.firstID, pair.secondID);
    if (distances.has(key)) fail("report contains duplicate pair distances");
    distances.set(key, pair.distance);
  }
  return distances;
}

function scoreNearestNeighbors(images, distances) {
  const scored = [];
  for (const [id, image] of images) {
    const neighbors = [];
    for (const [otherID, otherImage] of images) {
      if (id === otherID) continue;
      const distance = distances.get(pairKey(id, otherID));
      if (distance === undefined) fail("report is missing a pairwise distance");
      neighbors.push({ id: otherID, ...otherImage, distance });
    }
    neighbors.sort((left, right) => left.distance - right.distance || left.id.localeCompare(right.id));
    const nearest = neighbors[0];
    const runnerUp = neighbors[1];
    scored.push({
      id,
      ...image,
      nearest,
      neighborMargin: round(runnerUp.distance - nearest.distance),
    });
  }
  return scored;
}

function evaluateCandidate(scoredImages, maximumDistance, minimumNeighborMargin, repeatableCount) {
  let trueMatches = 0;
  let falseMatches = 0;
  let highRiskFalseMatches = 0;
  for (const image of scoredImages) {
    if (image.nearest.distance > maximumDistance + EPSILON ||
        image.neighborMargin + EPSILON < minimumNeighborMargin) {
      continue;
    }
    if (image.label === image.nearest.label) {
      trueMatches += 1;
    } else {
      falseMatches += 1;
      if (image.highRisk || image.nearest.highRisk) highRiskFalseMatches += 1;
    }
  }
  const matches = trueMatches + falseMatches;
  return {
    maximumDistance,
    minimumNeighborMargin,
    precision: matches === 0 ? 0 : trueMatches / matches,
    recall: repeatableCount === 0 ? 0 : trueMatches / repeatableCount,
    highRiskFalseMatches,
  };
}

function isBetter(candidate, current) {
  if (!current) return true;
  if (candidate.recall > current.recall + EPSILON) return true;
  if (Math.abs(candidate.recall - current.recall) > EPSILON) return false;
  if (candidate.precision > current.precision + EPSILON) return true;
  if (Math.abs(candidate.precision - current.precision) > EPSILON) return false;
  if (candidate.maximumDistance < current.maximumDistance - EPSILON) return true;
  if (Math.abs(candidate.maximumDistance - current.maximumDistance) > EPSILON) return false;
  return candidate.minimumNeighborMargin > current.minimumNeighborMargin + EPSILON;
}

function selectPolicy(scoredImages) {
  const labelCounts = new Map();
  for (const image of scoredImages) labelCounts.set(image.label, (labelCounts.get(image.label) ?? 0) + 1);
  const repeatableCount = scoredImages.filter(({ label }) => labelCounts.get(label) > 1).length;
  const distances = [...new Set(scoredImages.map(({ nearest }) => round(nearest.distance)))].sort((a, b) => a - b);
  const margins = [...new Set(scoredImages.map(({ neighborMargin }) => neighborMargin))].sort((a, b) => b - a);
  let best = null;

  for (const maximumDistance of distances) {
    for (const minimumNeighborMargin of margins) {
      const candidate = evaluateCandidate(scoredImages, maximumDistance, minimumNeighborMargin, repeatableCount);
      if (candidate.precision + EPSILON < MINIMUM_PRECISION || candidate.highRiskFalseMatches !== 0) continue;
      if (isBetter(candidate, best)) best = candidate;
    }
  }
  if (!best) fail("release gate failed: no threshold pair meets precision and high-risk requirements");
  return best;
}

function writePolicyAtomically(policyPath, policy) {
  const temporaryPath = join(dirname(policyPath), `.${process.pid}-${Date.now()}-policy.tmp`);
  writeFileSync(temporaryPath, `${JSON.stringify(policy, null, 2)}\n`, { encoding: "utf8", mode: 0o600 });
  renameSync(temporaryPath, policyPath);
}

function main() {
  const options = parseArguments(process.argv.slice(2));
  const manifestImages = validateManifest(readJSON(options["--manifest"], "manifest"));
  const distances = validateReport(readJSON(options["--report"], "report"), manifestImages);
  const selected = selectPolicy(scoreNearestNeighbors(manifestImages, distances));
  const policy = {
    version: 1,
    enabled: true,
    maximumDistance: selected.maximumDistance,
    minimumNeighborMargin: selected.minimumNeighborMargin,
    evaluatedImageCount: REQUIRED_IMAGE_COUNT,
    precision: round(selected.precision),
    highRiskFalseMatches: selected.highRiskFalseMatches,
  };
  writePolicyAtomically(options["--policy"], policy);
  process.stdout.write(`policy selected: precision=${policy.precision} recall=${round(selected.recall)}\n`);
}

try {
  main();
} catch (error) {
  process.stderr.write(`${error.message}\n`);
  process.exitCode = 1;
}
