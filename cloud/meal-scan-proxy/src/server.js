import http from "node:http";
import crypto from "node:crypto";

const DEFAULT_MODEL_ID = "gemini-2.5-flash-lite";
const PROVIDER_ID = "google-gemini";
const MODEL_CONFIGS = {
  "gemini-2.5-flash-lite": {
    providerId: PROVIDER_ID,
    modelId: "gemini-2.5-flash-lite",
    inputUSDPerMillionTokens: 0.10,
    outputUSDPerMillionTokens: 0.40,
  },
  "gemini-2.5-flash": {
    providerId: PROVIDER_ID,
    modelId: "gemini-2.5-flash",
    inputUSDPerMillionTokens: 0.30,
    outputUSDPerMillionTokens: 2.50,
  },
};
const HARD_DAILY_LIMIT = Number.parseInt(process.env.MEAL_SCAN_DAILY_LIMIT ?? "10", 10);
const SOFT_DAILY_LIMIT = Number.parseInt(process.env.MEAL_SCAN_SOFT_DAILY_LIMIT ?? "5", 10);
const TRIAL_DAILY_LIMIT = Number.parseInt(process.env.MEAL_SCAN_TRIAL_DAILY_LIMIT ?? "5", 10);
const TRIAL_TOTAL_LIMIT = Number.parseInt(process.env.MEAL_SCAN_TRIAL_TOTAL_LIMIT ?? "25", 10);
const MAX_BODY_BYTES = Number.parseInt(process.env.MAX_BODY_BYTES ?? String(5 * 1024 * 1024), 10);
const BUDGET_ALERT_AT_USD = Number.parseFloat(process.env.MEAL_SCAN_MONTHLY_BUDGET_ALERT_USD ?? "50");
const BUDGET_DEGRADE_AT_USD = Number.parseFloat(process.env.MEAL_SCAN_MONTHLY_BUDGET_DEGRADE_USD ?? "75");
const BUDGET_DISABLE_AT_USD = Number.parseFloat(process.env.MEAL_SCAN_MONTHLY_BUDGET_DISABLE_USD ?? "100");

export function createServer(overrides = {}) {
  const scanEnabled = overrides.scanEnabled ?? process.env.MEAL_SCAN_ENABLED !== "false";
  const requireAppAttest = overrides.requireAppAttest ?? process.env.APP_ATTEST_REQUIRED === "true";
  const appAttestVerifier = overrides.appAttestVerifier ?? createConfiguredAppAttestVerifier();
  const dependencies = {
    verifyAppIntegrity:
      overrides.verifyAppIntegrity ??
      ((input) => verifyAppIntegrity(input, { requireAppAttest, appAttestVerifier })),
    verifyRevenueCatEntitlement: overrides.verifyRevenueCatEntitlement ?? verifyRevenueCatEntitlement,
    quotaStore: overrides.quotaStore ?? createConfiguredQuotaStore(),
    callGemini: overrides.callGemini ?? callGemini,
    getBudgetState: overrides.getBudgetState ?? (() => overrides.budgetState ?? currentBudgetState()),
    logger: overrides.logger ?? console,
  };

  return http.createServer(async (request, response) => {
    try {
      if (request.method !== "POST" || request.url !== "/v1/meal-scans/estimate") {
        return sendJSON(response, 404, { error: "not_found" });
      }

      if (!scanEnabled) {
        return sendJSON(response, 503, {
          error: "meal_scan_unavailable",
          reason: "feature_disabled",
          retryable: false,
        });
      }

      const budget = normalizeBudgetState(await dependencies.getBudgetState());
      if (budget.mode === "disabled") {
        return sendJSON(response, 503, {
          error: "meal_scan_unavailable",
          reason: "monthly_budget_exceeded",
          retryable: false,
          budget: budgetResponse(budget),
        });
      }

      const payload = await readJSONBody(request);
      const validation = validatePayload(payload);
      if (!validation.ok) {
        return sendJSON(response, 400, { error: "invalid_request", detail: validation.detail });
      }

      const integrityToken = request.headers["x-cyclebalance-app-integrity"];
      const integrityResult = normalizeGateResult(await dependencies.verifyAppIntegrity({
        token: typeof integrityToken === "string" ? integrityToken : undefined,
        appAttestKeyId: headerValue(request.headers["x-cyclebalance-app-attest-key-id"]),
        appAttestAttestation: headerValue(request.headers["x-cyclebalance-app-attest-attestation"]),
        appAttestAssertion: headerValue(request.headers["x-cyclebalance-app-attest-assertion"]),
        appAttestChallenge: headerValue(request.headers["x-cyclebalance-app-attest-challenge"]),
        payload,
      }));
      if (!integrityResult.allowed) {
        return sendJSON(response, 401, {
          error: "app_integrity_required",
          reason: integrityResult.reason ?? "integrity_failed",
        });
      }

      const subscriberAccess = normalizeSubscriberAccess(await dependencies.verifyRevenueCatEntitlement({
        appUserId: payload.revenueCatAppUserId,
        entitlementId: process.env.REVENUECAT_ENTITLEMENT_ID ?? "CycleBalance Unlimited",
      }));
      if (!subscriberAccess.allowed) {
        return sendJSON(response, 403, {
          error: "premium_entitlement_required",
          reason: subscriberAccess.reason ?? "entitlement_inactive",
        });
      }

      const accessTier = subscriberAccess.accessTier === "trial" ? "trial" : "paid";
      const hardLimit = accessTier === "trial" ? TRIAL_DAILY_LIMIT : HARD_DAILY_LIMIT;
      const softLimit = accessTier === "trial" ? TRIAL_DAILY_LIMIT : SOFT_DAILY_LIMIT;
      const quota = await dependencies.quotaStore.checkAndConsume({
        appUserId: payload.revenueCatAppUserId,
        imageHash: payload.image.sha256,
        accessTier,
        hardLimit,
        softLimit,
        trialTotalLimit: accessTier === "trial" ? TRIAL_TOTAL_LIMIT : null,
      });
      if (!quota.allowed) {
        return sendJSON(response, 429, {
          error: "daily_scan_quota_exceeded",
          reason: quota.reason ?? "quota_exceeded",
          quota: quotaResponse(quota, accessTier),
        });
      }

      const modelSelection = selectModel(payload.modelId, budget);
      const modelId = modelSelection.modelId;
      const geminiPayload = buildGeminiPayload(payload, modelId);
      const geminiResponse = await dependencies.callGemini({
        modelId,
        payload: geminiPayload,
        timeoutMs: Number.parseInt(process.env.GEMINI_TIMEOUT_MS ?? "12000", 10),
      });
      const usage = usageResponse(geminiResponse.usageMetadata, modelSelection.config);

      dependencies.logger.info?.("meal_scan_estimate", {
        appUserHash: shortHash(payload.revenueCatAppUserId),
        imageHash: payload.image.sha256.slice(0, 12),
        providerId: modelSelection.config.providerId,
        modelId,
        promptTokens: geminiResponse.usageMetadata?.promptTokenCount,
        outputTokens: geminiResponse.usageMetadata?.candidatesTokenCount,
        estimatedCostUSD: usage.estimatedCostUSD,
        quotaUsed: quota.used,
        quotaLimit: quota.limit,
        accessTier,
        budgetMode: budget.mode,
        cacheHit: false,
      });

      return sendJSON(response, 200, {
        modelId,
        provider: providerResponse(modelSelection),
        estimate: geminiResponse.estimate,
        rawEstimateJSON: JSON.stringify(geminiResponse.estimate),
        cacheHit: false,
        usage,
        usageMetadata: geminiResponse.usageMetadata ?? null,
        quota: quotaResponse(quota, accessTier),
        budget: budgetResponse(budget),
      });
    } catch (error) {
      if (error?.code === "REQUEST_TOO_LARGE") {
        return sendJSON(response, 413, { error: "request_too_large" });
      }
      if (error instanceof SyntaxError) {
        return sendJSON(response, 400, { error: "invalid_json" });
      }
      if (error?.code === "ETIMEDOUT" || error?.name === "AbortError") {
        return sendJSON(response, 504, { error: "gemini_timeout", retryable: true });
      }
      dependencies.logger.error?.("meal_scan_proxy_error", { message: error?.message });
      return sendJSON(response, 500, { error: "meal_scan_proxy_error" });
    }
  });
}

export function buildGeminiPayload(payload, modelId = DEFAULT_MODEL_ID) {
  return {
    contents: [
      {
        role: "user",
        parts: [
          {
            text: [
              "Estimate visible foods and portions in this meal photo for an editable nutrition draft.",
              "Return JSON only. Do not provide medical advice. Call out uncertainty around oil, sauce, dressing, restaurant prep, mixed dishes, and hidden ingredients.",
              `Meal type: ${payload.mealType}. Locale: ${payload.locale}. Schema: ${payload.schemaVersion}. Prompt: ${payload.promptVersion}. Model: ${modelId}.`,
            ].join("\n"),
          },
          {
            inlineData: {
              mimeType: payload.image.mimeType,
              data: payload.image.base64,
            },
          },
        ],
      },
    ],
    generationConfig: {
      temperature: 0.2,
      responseMimeType: "application/json",
      responseSchema: mealEstimateSchema(),
    },
  };
}

function mealEstimateSchema() {
  return {
    type: "object",
    properties: {
      meal_name: { type: "string" },
      confidence: { type: "string", enum: ["low", "medium", "high", "unknown"] },
      warnings: {
        type: "array",
        items: {
          type: "object",
          properties: {
            code: { type: "string" },
            message: { type: "string" },
          },
          required: ["code", "message"],
        },
      },
      items: {
        type: "array",
        items: {
          type: "object",
          properties: {
            display_name: { type: "string" },
            canonical_query: { type: "string" },
            estimated_grams: { type: "number" },
            serving_description: { type: "string" },
            confidence: { type: "string", enum: ["low", "medium", "high", "unknown"] },
            is_mixed_dish: { type: "boolean" },
            warning: { type: "string" },
            nutrition_fallback: {
              type: "object",
              nullable: true,
              properties: {
                calories_kcal: { type: "number" },
                protein_grams: { type: "number" },
                carbs_grams: { type: "number" },
                fat_grams: { type: "number" },
                fiber_grams: { type: "number" },
                sugar_grams: { type: "number" },
                sodium_mg: { type: "number" },
              },
            },
          },
          required: ["display_name", "canonical_query", "estimated_grams", "confidence", "is_mixed_dish"],
        },
      },
    },
    required: ["meal_name", "confidence", "warnings", "items"],
  };
}

async function callGemini({ modelId, payload, timeoutMs }) {
  const apiKey = process.env.GEMINI_API_KEY;
  if (!apiKey) {
    throw new Error("GEMINI_API_KEY is not configured");
  }

  const controller = new AbortController();
  const timeout = setTimeout(() => controller.abort(), timeoutMs);
  try {
    const response = await fetch(
      `https://generativelanguage.googleapis.com/v1beta/models/${encodeURIComponent(modelId)}:generateContent?key=${encodeURIComponent(apiKey)}`,
      {
        method: "POST",
        headers: { "content-type": "application/json" },
        body: JSON.stringify(payload),
        signal: controller.signal,
      }
    );
    if (!response.ok) {
      const body = await response.text();
      throw new Error(`Gemini request failed: ${response.status} ${body.slice(0, 200)}`);
    }
    const body = await response.json();
    const text = body.candidates?.[0]?.content?.parts?.find((part) => typeof part.text === "string")?.text;
    if (!text) {
      throw new Error("Gemini returned no JSON text");
    }
    return {
      estimate: JSON.parse(text),
      usageMetadata: body.usageMetadata,
    };
  } finally {
    clearTimeout(timeout);
  }
}

async function verifyAppIntegrity(input, { requireAppAttest, appAttestVerifier } = {}) {
  const { token, appAttestKeyId, appAttestAssertion } = input;
  if (requireAppAttest) {
    if (!appAttestKeyId || !appAttestAssertion) {
      return { allowed: false, reason: "app_attest_required" };
    }

    if (appAttestVerifier) {
      return normalizeGateResult(await appAttestVerifier(input));
    }

    if (process.env.APP_ATTEST_ACCEPT_UNVERIFIED_ASSERTIONS === "true") {
      return { allowed: true, reason: "app_attest_dev_bypass" };
    }

    return { allowed: false, reason: "app_attest_verifier_unconfigured" };
  }

  const expected = process.env.APP_INTEGRITY_SHARED_SECRET;
  if (!expected) {
    return { allowed: false, reason: "shared_secret_unconfigured" };
  }
  return { allowed: token === expected, reason: token === expected ? undefined : "shared_secret_mismatch" };
}

async function verifyRevenueCatEntitlement({ appUserId, entitlementId }) {
  const apiKey = process.env.REVENUECAT_SECRET_API_KEY;
  if (!apiKey || !appUserId) {
    return false;
  }

  const response = await fetch(`https://api.revenuecat.com/v1/subscribers/${encodeURIComponent(appUserId)}`, {
    headers: {
      authorization: `Bearer ${apiKey}`,
      accept: "application/json",
    },
  });
  if (!response.ok) {
    return false;
  }

  const body = await response.json();
  return subscriberAccessFromRevenueCat(body, entitlementId);
}

function createInMemoryQuotaStore() {
  const dailyCounts = new Map();
  const trialCounts = new Map();
  return {
    async checkAndConsume({ appUserId, hardLimit, softLimit, accessTier, trialTotalLimit }) {
      const day = new Date().toISOString().slice(0, 10);
      const appUserHash = shortHash(appUserId);
      const dailyKey = `${appUserHash}:${day}`;
      const trialKey = `${appUserHash}:trial`;
      const currentDailyUsed = dailyCounts.get(dailyKey) ?? 0;
      const currentTrialUsed = trialCounts.get(trialKey) ?? 0;
      const nextDailyUsed = currentDailyUsed + 1;
      const nextTrialUsed = accessTier === "trial" ? currentTrialUsed + 1 : currentTrialUsed;
      const dailyAllowed = nextDailyUsed <= hardLimit;
      const trialAllowed = accessTier !== "trial" || nextTrialUsed <= trialTotalLimit;
      const allowed = dailyAllowed && trialAllowed;

      if (allowed) {
        dailyCounts.set(dailyKey, nextDailyUsed);
        if (accessTier === "trial") {
          trialCounts.set(trialKey, nextTrialUsed);
        }
      }

      return {
        allowed,
        reason: dailyAllowed ? "trial_quota_exceeded" : "daily_quota_exceeded",
        used: allowed ? nextDailyUsed : currentDailyUsed,
        limit: hardLimit,
        softLimit,
        remainingToday: Math.max(0, hardLimit - (allowed ? nextDailyUsed : currentDailyUsed)),
        trialUsed: accessTier === "trial" ? (allowed ? nextTrialUsed : currentTrialUsed) : null,
        trialLimit: accessTier === "trial" ? trialTotalLimit : null,
        remainingTrial:
          accessTier === "trial" ? Math.max(0, trialTotalLimit - (allowed ? nextTrialUsed : currentTrialUsed)) : null,
        accessTier,
      };
    },
  };
}

function createConfiguredQuotaStore() {
  if (process.env.MEAL_SCAN_QUOTA_STORE === "firestore") {
    return createFirestoreQuotaStore({
      collectionName: process.env.MEAL_SCAN_QUOTA_COLLECTION ?? "mealScanDailyQuota",
    });
  }
  return createInMemoryQuotaStore();
}

function createFirestoreQuotaStore({ collectionName }) {
  let firestoreClient;
  async function firestore() {
    if (!firestoreClient) {
      const { Firestore } = await import("@google-cloud/firestore");
      firestoreClient = new Firestore();
    }
    return firestoreClient;
  }

  return {
    async checkAndConsume({ appUserId, hardLimit, softLimit, accessTier, trialTotalLimit }) {
      const db = await firestore();
      const now = new Date();
      const day = now.toISOString().slice(0, 10);
      const appUserHash = shortHash(appUserId);
      const dailyDoc = db.collection(collectionName).doc(`${appUserHash}_${day}`);
      const trialDoc = db.collection(collectionName).doc(`${appUserHash}_trial`);

      return db.runTransaction(async (transaction) => {
        const [dailySnapshot, trialSnapshot] = await Promise.all([
          transaction.get(dailyDoc),
          accessTier === "trial" ? transaction.get(trialDoc) : Promise.resolve(null),
        ]);
        const currentUsed = dailySnapshot.exists ? Number(dailySnapshot.get("used") ?? 0) : 0;
        const currentRejected = dailySnapshot.exists ? Number(dailySnapshot.get("rejectedCount") ?? 0) : 0;
        const currentTrialUsed = trialSnapshot?.exists ? Number(trialSnapshot.get("used") ?? 0) : 0;
        const nextUsed = currentUsed + 1;
        const nextTrialUsed = accessTier === "trial" ? currentTrialUsed + 1 : currentTrialUsed;
        const dailyAllowed = nextUsed <= hardLimit;
        const trialAllowed = accessTier !== "trial" || nextTrialUsed <= trialTotalLimit;
        const allowed = dailyAllowed && trialAllowed;

        transaction.set(
          dailyDoc,
          {
            appUserHash,
            day,
            used: allowed ? nextUsed : currentUsed,
            rejectedCount: allowed ? currentRejected : currentRejected + 1,
            limit: hardLimit,
            softLimit,
            updatedAt: now.toISOString(),
            expiresAt: new Date(now.getTime() + 3 * 86_400_000).toISOString(),
          },
          { merge: true }
        );

        if (accessTier === "trial") {
          transaction.set(
            trialDoc,
            {
              appUserHash,
              used: allowed ? nextTrialUsed : currentTrialUsed,
              limit: trialTotalLimit,
              rejectedCount: allowed ? Number(trialSnapshot?.get("rejectedCount") ?? 0) : Number(trialSnapshot?.get("rejectedCount") ?? 0) + 1,
              updatedAt: now.toISOString(),
              expiresAt: new Date(now.getTime() + 30 * 86_400_000).toISOString(),
            },
            { merge: true }
          );
        }

        return {
          allowed,
          reason: dailyAllowed ? "trial_quota_exceeded" : "daily_quota_exceeded",
          used: allowed ? nextUsed : currentUsed,
          limit: hardLimit,
          softLimit,
          remainingToday: Math.max(0, hardLimit - (allowed ? nextUsed : currentUsed)),
          trialUsed: accessTier === "trial" ? (allowed ? nextTrialUsed : currentTrialUsed) : null,
          trialLimit: accessTier === "trial" ? trialTotalLimit : null,
          remainingTrial:
            accessTier === "trial" ? Math.max(0, trialTotalLimit - (allowed ? nextTrialUsed : currentTrialUsed)) : null,
          accessTier,
        };
      });
    },
  };
}

function normalizeGateResult(result) {
  if (typeof result === "boolean") {
    return { allowed: result };
  }
  if (result && typeof result === "object" && typeof result.allowed === "boolean") {
    return result;
  }
  return { allowed: false };
}

function normalizeSubscriberAccess(result) {
  if (typeof result === "boolean") {
    return { allowed: result, accessTier: result ? "paid" : undefined };
  }
  if (result && typeof result === "object" && typeof result.allowed === "boolean") {
    return {
      ...result,
      accessTier: result.allowed ? result.accessTier ?? "paid" : result.accessTier,
    };
  }
  return { allowed: false };
}

function subscriberAccessFromRevenueCat(body, entitlementId, now = Date.now()) {
  const subscriber = body?.subscriber;
  const entitlement = subscriber?.entitlements?.[entitlementId];
  const entitlementActive = isRevenueCatGrantActive(entitlement, now);
  const activeSubscriptions = Object.values(subscriber?.subscriptions ?? {}).filter((subscription) =>
    isRevenueCatGrantActive(subscription, now)
  );
  const hasActiveTrial = activeSubscriptions.some((subscription) => subscription?.period_type === "trial");

  if (entitlementActive || hasActiveTrial) {
    return {
      allowed: true,
      accessTier: hasActiveTrial ? "trial" : "paid",
      entitlementExpiresAt: entitlement?.expires_date ?? null,
    };
  }

  return { allowed: false, reason: "entitlement_inactive" };
}

function isRevenueCatGrantActive(grant, now) {
  if (!grant) {
    return false;
  }
  if (grant.expires_date === null) {
    return true;
  }
  return Number.isFinite(Date.parse(grant.expires_date)) && Date.parse(grant.expires_date) > now;
}

function quotaResponse(quota, accessTier) {
  const limit = numberOrNull(quota.limit);
  const used = numberOrNull(quota.used);
  const softLimit = numberOrNull(quota.softLimit);
  const remainingToday =
    quota.remainingToday ?? (limit !== null && used !== null ? Math.max(0, limit - Math.min(used, limit)) : null);
  const trialLimit = accessTier === "trial" ? numberOrNull(quota.trialLimit ?? TRIAL_TOTAL_LIMIT) : null;
  const trialUsed = accessTier === "trial" ? numberOrNull(quota.trialUsed) : null;
  const remainingTrial =
    accessTier === "trial"
      ? quota.remainingTrial ?? (trialLimit !== null && trialUsed !== null ? Math.max(0, trialLimit - trialUsed) : null)
      : null;

  return {
    accessTier,
    used,
    limit,
    softLimit,
    remainingToday,
    trialUsed,
    trialLimit,
    remainingTrial,
  };
}

function providerResponse(modelSelection) {
  return {
    id: modelSelection.config.providerId,
    modelId: modelSelection.modelId,
    requestedModelId: modelSelection.requestedModelId,
    selectionReason: modelSelection.selectionReason,
    inputUSDPerMillionTokens: modelSelection.config.inputUSDPerMillionTokens,
    outputUSDPerMillionTokens: modelSelection.config.outputUSDPerMillionTokens,
  };
}

function budgetResponse(budget) {
  return {
    mode: budget.mode,
    spendUsd: numberOrNull(budget.spendUsd),
    alertAtUsd: numberOrNull(budget.alertAtUsd),
    degradeAtUsd: numberOrNull(budget.degradeAtUsd),
    disableAtUsd: numberOrNull(budget.disableAtUsd),
  };
}

function usageResponse(usageMetadata, modelConfig = MODEL_CONFIGS[DEFAULT_MODEL_ID]) {
  if (!usageMetadata) {
    return { inputTokens: null, outputTokens: null, totalTokens: null, estimatedCostUSD: null };
  }
  const inputTokens = numberOrNull(usageMetadata.promptTokenCount ?? usageMetadata.total_input_tokens);
  const outputTokens = numberOrNull(usageMetadata.candidatesTokenCount ?? usageMetadata.total_output_tokens);
  const estimatedCostUSD =
    inputTokens === null || outputTokens === null
      ? null
      : roundCurrency(
          (inputTokens / 1_000_000) * modelConfig.inputUSDPerMillionTokens +
            (outputTokens / 1_000_000) * modelConfig.outputUSDPerMillionTokens
        );
  return {
    inputTokens,
    outputTokens,
    totalTokens: numberOrNull(usageMetadata.totalTokenCount ?? usageMetadata.total_tokens),
    estimatedCostUSD,
  };
}

function numberOrNull(value) {
  return Number.isFinite(Number(value)) ? Number(value) : null;
}

function roundCurrency(value) {
  return Number(value.toFixed(10));
}

function headerValue(value) {
  return Array.isArray(value) ? value[0] : typeof value === "string" ? value : undefined;
}

function validatePayload(payload) {
  if (!payload || typeof payload !== "object") return { ok: false, detail: "body must be JSON object" };
  if (!payload.revenueCatAppUserId) return { ok: false, detail: "revenueCatAppUserId is required" };
  if (!payload.image?.base64 || payload.image?.mimeType !== "image/jpeg") return { ok: false, detail: "jpeg image is required" };
  if (!payload.image?.sha256) return { ok: false, detail: "image sha256 is required" };
  return { ok: true };
}

function selectModel(requestedModelId, budget) {
  const requested = MODEL_CONFIGS[requestedModelId] ? requestedModelId : DEFAULT_MODEL_ID;
  if (budget.mode === "degraded" && requested !== DEFAULT_MODEL_ID) {
    return {
      modelId: DEFAULT_MODEL_ID,
      requestedModelId: requestedModelId ?? null,
      selectionReason: "budget_degraded_to_lite",
      config: MODEL_CONFIGS[DEFAULT_MODEL_ID],
    };
  }

  return {
    modelId: requested,
    requestedModelId: requestedModelId ?? null,
    selectionReason: requested === requestedModelId ? "requested_model_allowed" : "default_lite",
    config: MODEL_CONFIGS[requested],
  };
}

function currentBudgetState() {
  const spendUsd = numberOrNull(process.env.MEAL_SCAN_MONTHLY_SPEND_USD) ?? 0;
  return normalizeBudgetState({
    spendUsd,
    alertAtUsd: BUDGET_ALERT_AT_USD,
    degradeAtUsd: BUDGET_DEGRADE_AT_USD,
    disableAtUsd: BUDGET_DISABLE_AT_USD,
  });
}

function normalizeBudgetState(input) {
  const spendUsd = numberOrNull(input?.spendUsd) ?? 0;
  const alertAtUsd = numberOrNull(input?.alertAtUsd) ?? BUDGET_ALERT_AT_USD;
  const degradeAtUsd = numberOrNull(input?.degradeAtUsd) ?? BUDGET_DEGRADE_AT_USD;
  const disableAtUsd = numberOrNull(input?.disableAtUsd) ?? BUDGET_DISABLE_AT_USD;
  let mode = input?.mode;

  if (!mode) {
    if (spendUsd >= disableAtUsd) {
      mode = "disabled";
    } else if (spendUsd >= degradeAtUsd) {
      mode = "degraded";
    } else if (spendUsd >= alertAtUsd) {
      mode = "alert";
    } else {
      mode = "normal";
    }
  }

  if (!["normal", "alert", "degraded", "disabled"].includes(mode)) {
    mode = "normal";
  }

  return { mode, spendUsd, alertAtUsd, degradeAtUsd, disableAtUsd };
}

function createConfiguredAppAttestVerifier() {
  const verifierURL = process.env.APP_ATTEST_VERIFIER_URL;
  if (!verifierURL) {
    return null;
  }

  return async (input) => {
    const response = await fetch(verifierURL, {
      method: "POST",
      headers: {
        "content-type": "application/json",
        ...(process.env.APP_ATTEST_VERIFIER_BEARER
          ? { authorization: `Bearer ${process.env.APP_ATTEST_VERIFIER_BEARER}` }
          : {}),
      },
      body: JSON.stringify({
        keyId: input.appAttestKeyId,
        attestation: input.appAttestAttestation,
        assertion: input.appAttestAssertion,
        challenge: input.appAttestChallenge,
        imageHash: input.payload?.image?.sha256,
        revenueCatAppUserId: input.payload?.revenueCatAppUserId,
      }),
    });

    if (!response.ok) {
      return { allowed: false, reason: "app_attest_verifier_rejected" };
    }

    const body = await response.json();
    return normalizeGateResult(body);
  };
}

async function readJSONBody(request) {
  let body = "";
  let bytes = 0;
  for await (const chunk of request) {
    bytes += chunk.length;
    if (bytes > MAX_BODY_BYTES) {
      const error = new Error("request too large");
      error.code = "REQUEST_TOO_LARGE";
      throw error;
    }
    body += chunk;
  }
  return JSON.parse(body || "{}");
}

function sendJSON(response, status, body) {
  response.writeHead(status, { "content-type": "application/json" });
  response.end(JSON.stringify(body));
}

function shortHash(value) {
  return crypto.createHash("sha256").update(String(value)).digest("hex").slice(0, 16);
}

if (import.meta.url === `file://${process.argv[1]}`) {
  const port = Number.parseInt(process.env.PORT ?? "8080", 10);
  createServer().listen(port, () => {
    console.log(`Meal scan proxy listening on ${port}`);
  });
}
