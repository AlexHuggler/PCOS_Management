import assert from "node:assert/strict";
import { readFileSync } from "node:fs";
import path from "node:path";
import test from "node:test";
import { fileURLToPath } from "node:url";

const proxyDirectory = path.resolve(path.dirname(fileURLToPath(import.meta.url)), "..");
const readme = readFileSync(path.join(proxyDirectory, "README.md"), "utf8");

test("README documents the active StoreKit rolling quota and cost contract", () => {
  assert.match(readme, /signedTransactionJWS/);
  assert.match(readme, /App Store Server API/);
  assert.match(readme, /rolling 24-hour/i);
  assert.match(readme, /warning at 8/i);
  assert.match(readme, /2[,.]2(?:00[,.]000)?\s*(?:MB|bytes)/i);
  assert.match(readme, /\$15[\s\S]*\$20[\s\S]*\$25/);
  assert.match(readme, /mealScanRollingQuota/);
  assert.match(readme, /mealScanIdempotency/);
  assert.match(readme, /mealScanPrincipalAttempts/);
  assert.match(readme, /3 attempts\/minute[\s\S]*30 attempts\/rolling 24 hours/i);
  assert.match(readme, /60 fresh dispatches\/minute[\s\S]*1,000 fresh dispatches\/rolling 24 hours/i);
  assert.match(readme, /6760353511/);
  assert.match(readme, /TTL/);
  assert.doesNotMatch(readme, /REVENUECAT|RevenueCat/);
  assert.doesNotMatch(readme, /remainingToday|remainingTrial|mealScanDailyQuota/);
});

test("README keeps activation explicit and approval gated", () => {
  assert.match(readme, /MEAL_SCAN_ENABLED=true ALLOW_UNAUTHENTICATED=true/);
  assert.match(readme, /approval/i);
  assert.match(readme, /MEAL_SCAN_ENABLED=false/);
  assert.match(readme, /ALLOW_UNAUTHENTICATED=false/);
});
