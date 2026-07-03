import assert from "node:assert/strict";
import test from "node:test";
import { createServer } from "../src/server.js";

const validPayload = {
  revenueCatAppUserId: "user_123",
  mealType: "lunch",
  locale: "en_US",
  modelId: "gemini-2.5-flash-lite",
  schemaVersion: "meal-scan-gemini-v1",
  promptVersion: "meal-scan-prompt-v1",
  image: {
    mimeType: "image/jpeg",
    base64: Buffer.from("jpeg").toString("base64"),
    sha256: "abc123",
  },
};

test("rejects missing app integrity token before entitlement or Gemini calls", async () => {
  const calls = [];
  const server = createServer({
    verifyAppIntegrity: async () => false,
    verifyRevenueCatEntitlement: async () => {
      calls.push("entitlement");
      return true;
    },
    quotaStore: allowQuotaStore(),
    callGemini: async () => {
      calls.push("gemini");
      return successGeminiResponse();
    },
  });

  const response = await request(server, validPayload);

  assert.equal(response.status, 401);
  assert.deepEqual(calls, []);
});

test("rejects inactive RevenueCat entitlement before quota or Gemini calls", async () => {
  const calls = [];
  const server = createServer({
    verifyAppIntegrity: async () => true,
    verifyRevenueCatEntitlement: async () => false,
    quotaStore: {
      checkAndConsume: async () => {
        calls.push("quota");
        return { allowed: true, used: 1, limit: 10 };
      },
    },
    callGemini: async () => {
      calls.push("gemini");
      return successGeminiResponse();
    },
  });

  const response = await request(server, validPayload, { "x-cyclebalance-app-integrity": "token" });

  assert.equal(response.status, 403);
  assert.deepEqual(calls, []);
});

test("enforces daily quota before Gemini call", async () => {
  const calls = [];
  const server = createServer({
    verifyAppIntegrity: async () => true,
    verifyRevenueCatEntitlement: async () => true,
    quotaStore: {
      checkAndConsume: async () => ({ allowed: false, used: 10, limit: 10 }),
    },
    callGemini: async () => {
      calls.push("gemini");
      return successGeminiResponse();
    },
  });

  const response = await request(server, validPayload, { "x-cyclebalance-app-integrity": "token" });

  assert.equal(response.status, 429);
  assert.deepEqual(calls, []);
  assert.equal(response.body.quota.limit, 10);
  assert.equal(response.body.reason, "quota_exceeded");
});

test("returns structured estimate and quota metadata on success", async () => {
  const server = createServer({
    verifyAppIntegrity: async () => true,
    verifyRevenueCatEntitlement: async () => true,
    quotaStore: allowQuotaStore(),
    callGemini: async ({ modelId, payload }) => {
      assert.equal(modelId, "gemini-2.5-flash-lite");
      assert.equal(payload.generationConfig.responseMimeType, "application/json");
      assert.equal(payload.tools, undefined);
      return successGeminiResponse();
    },
  });

  const response = await request(server, validPayload, { "x-cyclebalance-app-integrity": "token" });

  assert.equal(response.status, 200);
  assert.equal(response.body.modelId, "gemini-2.5-flash-lite");
  assert.equal(response.body.quota.used, 1);
  assert.equal(response.body.quota.remainingToday, 9);
  assert.equal(response.body.quota.remainingTrial, null);
  assert.equal(response.body.cacheHit, false);
  assert.equal(response.body.usage.inputTokens, 2448);
  assert.equal(response.body.usage.outputTokens, 750);
  assert.equal(response.body.usage.estimatedCostUSD, 0.0005448);
  assert.equal(response.body.provider.id, "google-gemini");
  assert.equal(response.body.provider.modelId, "gemini-2.5-flash-lite");
  assert.equal(response.body.budget.mode, "normal");
  assert.equal(response.body.estimate.meal_name, "Rice bowl");
});

test("monthly budget disables scans before integrity entitlement quota or Gemini calls", async () => {
  const calls = [];
  const server = createServer({
    budgetState: { mode: "disabled", spendUsd: 101, disableAtUsd: 100 },
    verifyAppIntegrity: async () => {
      calls.push("integrity");
      return true;
    },
    verifyRevenueCatEntitlement: async () => {
      calls.push("entitlement");
      return true;
    },
    quotaStore: {
      checkAndConsume: async () => {
        calls.push("quota");
        return { allowed: true, used: 1, limit: 10 };
      },
    },
    callGemini: async () => {
      calls.push("gemini");
      return successGeminiResponse();
    },
  });

  const response = await request(server, validPayload, { "x-cyclebalance-app-integrity": "token" });

  assert.equal(response.status, 503);
  assert.equal(response.body.error, "meal_scan_unavailable");
  assert.equal(response.body.reason, "monthly_budget_exceeded");
  assert.equal(response.body.budget.mode, "disabled");
  assert.deepEqual(calls, []);
});

test("monthly budget degraded mode forces flash requests back to flash lite", async () => {
  const requestedFlashPayload = { ...validPayload, modelId: "gemini-2.5-flash" };
  const server = createServer({
    budgetState: { mode: "degraded", spendUsd: 80, degradeAtUsd: 75 },
    verifyAppIntegrity: async () => true,
    verifyRevenueCatEntitlement: async () => true,
    quotaStore: allowQuotaStore(),
    callGemini: async ({ modelId }) => {
      assert.equal(modelId, "gemini-2.5-flash-lite");
      return successGeminiResponse();
    },
  });

  const response = await request(server, requestedFlashPayload, { "x-cyclebalance-app-integrity": "token" });

  assert.equal(response.status, 200);
  assert.equal(response.body.modelId, "gemini-2.5-flash-lite");
  assert.equal(response.body.provider.requestedModelId, "gemini-2.5-flash");
  assert.equal(response.body.provider.selectionReason, "budget_degraded_to_lite");
  assert.equal(response.body.budget.mode, "degraded");
});

test("allows trial subscribers with five daily scans and twenty five total trial scans", async () => {
  const seenQuota = [];
  const server = createServer({
    verifyAppIntegrity: async () => true,
    verifyRevenueCatEntitlement: async () => ({ allowed: true, accessTier: "trial" }),
    quotaStore: {
      checkAndConsume: async (input) => {
        seenQuota.push(input);
        return {
          allowed: true,
          used: 3,
          limit: 5,
          softLimit: 5,
          remainingToday: 2,
          trialUsed: 11,
          trialLimit: 25,
          remainingTrial: 14,
          accessTier: "trial",
        };
      },
    },
    callGemini: async () => successGeminiResponse(),
  });

  const response = await request(server, validPayload, { "x-cyclebalance-app-integrity": "token" });

  assert.equal(response.status, 200);
  assert.equal(seenQuota[0].accessTier, "trial");
  assert.equal(seenQuota[0].hardLimit, 5);
  assert.equal(seenQuota[0].trialTotalLimit, 25);
  assert.equal(response.body.quota.limit, 5);
  assert.equal(response.body.quota.remainingToday, 2);
  assert.equal(response.body.quota.trialLimit, 25);
  assert.equal(response.body.quota.remainingTrial, 14);
});

test("enforces total trial quota before Gemini call", async () => {
  const calls = [];
  const server = createServer({
    verifyAppIntegrity: async () => true,
    verifyRevenueCatEntitlement: async () => ({ allowed: true, accessTier: "trial" }),
    quotaStore: {
      checkAndConsume: async (input) => {
        assert.equal(input.accessTier, "trial");
        assert.equal(input.trialTotalLimit, 25);
        return {
          allowed: false,
          reason: "trial_quota_exceeded",
          used: 5,
          limit: 5,
          softLimit: 5,
          remainingToday: 0,
          trialUsed: 25,
          trialLimit: 25,
          remainingTrial: 0,
          accessTier: "trial",
        };
      },
    },
    callGemini: async () => {
      calls.push("gemini");
      return successGeminiResponse();
    },
  });

  const response = await request(server, validPayload, { "x-cyclebalance-app-integrity": "token" });

  assert.equal(response.status, 429);
  assert.equal(response.body.reason, "trial_quota_exceeded");
  assert.equal(response.body.quota.remainingTrial, 0);
  assert.deepEqual(calls, []);
});

test("kill switch disables scans before entitlement quota or Gemini calls", async () => {
  const calls = [];
  const server = createServer({
    scanEnabled: false,
    verifyAppIntegrity: async () => {
      calls.push("integrity");
      return true;
    },
    verifyRevenueCatEntitlement: async () => {
      calls.push("entitlement");
      return true;
    },
    quotaStore: {
      checkAndConsume: async () => {
        calls.push("quota");
        return { allowed: true, used: 1, limit: 10 };
      },
    },
    callGemini: async () => {
      calls.push("gemini");
      return successGeminiResponse();
    },
  });

  const response = await request(server, validPayload, { "x-cyclebalance-app-integrity": "token" });

  assert.equal(response.status, 503);
  assert.equal(response.body.error, "meal_scan_unavailable");
  assert.equal(response.body.reason, "feature_disabled");
  assert.deepEqual(calls, []);
});

test("production App Attest mode rejects legacy shared secret header", async () => {
  const server = createServer({
    requireAppAttest: true,
    verifyAppIntegrity: undefined,
    verifyRevenueCatEntitlement: async () => {
      throw new Error("entitlement should not run");
    },
    quotaStore: allowQuotaStore(),
    callGemini: async () => {
      throw new Error("gemini should not run");
    },
  });

  const response = await request(server, validPayload, { "x-cyclebalance-app-integrity": "legacy-secret" });

  assert.equal(response.status, 401);
  assert.equal(response.body.error, "app_integrity_required");
  assert.equal(response.body.reason, "app_attest_required");
});

test("production App Attest mode accepts configured verifier result", async () => {
  const verifierInputs = [];
  const server = createServer({
    requireAppAttest: true,
    appAttestVerifier: async (input) => {
      verifierInputs.push(input);
      return { allowed: true };
    },
    verifyRevenueCatEntitlement: async () => ({ allowed: true, accessTier: "paid" }),
    quotaStore: allowQuotaStore(),
    callGemini: async () => successGeminiResponse(),
  });

  const response = await request(server, validPayload, {
    "x-cyclebalance-app-attest-key-id": "key-id",
    "x-cyclebalance-app-attest-attestation": "attestation",
    "x-cyclebalance-app-attest-assertion": "assertion",
    "x-cyclebalance-app-attest-challenge": "challenge",
  });

  assert.equal(response.status, 200);
  assert.equal(verifierInputs[0].appAttestKeyId, "key-id");
  assert.equal(verifierInputs[0].appAttestAttestation, "attestation");
  assert.equal(verifierInputs[0].appAttestAssertion, "assertion");
  assert.equal(verifierInputs[0].appAttestChallenge, "challenge");
  assert.equal(verifierInputs[0].payload.image.sha256, validPayload.image.sha256);
});

test("maps Gemini timeout to retryable gateway timeout", async () => {
  const server = createServer({
    verifyAppIntegrity: async () => true,
    verifyRevenueCatEntitlement: async () => true,
    quotaStore: allowQuotaStore(),
    callGemini: async () => {
      const error = new Error("deadline exceeded");
      error.code = "ETIMEDOUT";
      throw error;
    },
  });

  const response = await request(server, validPayload, { "x-cyclebalance-app-integrity": "token" });

  assert.equal(response.status, 504);
  assert.equal(response.body.retryable, true);
});

function allowQuotaStore() {
  return {
    checkAndConsume: async () => ({ allowed: true, used: 1, limit: 10, softLimit: 5, remainingToday: 9, accessTier: "paid" }),
  };
}

function successGeminiResponse() {
  return {
    estimate: {
      meal_name: "Rice bowl",
      confidence: "medium",
      warnings: [],
      items: [],
    },
    usageMetadata: {
      promptTokenCount: 2448,
      candidatesTokenCount: 750,
      totalTokenCount: 3198,
    },
  };
}

async function request(server, payload, headers = {}) {
  await new Promise((resolve) => server.listen(0, "127.0.0.1", resolve));
  try {
    const { port } = server.address();
    const response = await fetch(`http://127.0.0.1:${port}/v1/meal-scans/estimate`, {
      method: "POST",
      headers: {
        "content-type": "application/json",
        ...headers,
      },
      body: JSON.stringify(payload),
    });
    const body = await response.json();
    return { status: response.status, body };
  } finally {
    await new Promise((resolve, reject) => {
      server.close((error) => (error ? reject(error) : resolve()));
    });
  }
}
