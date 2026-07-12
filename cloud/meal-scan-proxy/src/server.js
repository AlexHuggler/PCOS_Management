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
  "gemini-3.1-flash-lite": {
    providerId: PROVIDER_ID,
    modelId: "gemini-3.1-flash-lite",
    inputUSDPerMillionTokens: 0.25,
    outputUSDPerMillionTokens: 1.50,
  },
};
const HARD_DAILY_LIMIT = Number.parseInt(process.env.MEAL_SCAN_DAILY_LIMIT ?? "10", 10);
const SOFT_DAILY_LIMIT = Number.parseInt(process.env.MEAL_SCAN_SOFT_DAILY_LIMIT ?? "5", 10);
const TRIAL_DAILY_LIMIT = Number.parseInt(process.env.MEAL_SCAN_TRIAL_DAILY_LIMIT ?? "5", 10);
const TRIAL_TOTAL_LIMIT = Number.parseInt(process.env.MEAL_SCAN_TRIAL_TOTAL_LIMIT ?? "25", 10);
const BUDGET_ALERT_AT_USD = Number.parseFloat(process.env.MEAL_SCAN_MONTHLY_BUDGET_ALERT_USD ?? "50");
const BUDGET_DEGRADE_AT_USD = Number.parseFloat(process.env.MEAL_SCAN_MONTHLY_BUDGET_DEGRADE_USD ?? "75");
const BUDGET_DISABLE_AT_USD = Number.parseFloat(process.env.MEAL_SCAN_MONTHLY_BUDGET_DISABLE_USD ?? "100");

export function createServer(overrides = {}) {
  const environment = overrides.environment ?? process.env;
  const maxBodyBytes = overrides.maxBodyBytes ?? Number.parseInt(environment.MAX_BODY_BYTES ?? String(5 * 1024 * 1024), 10);
  const maxImageBytes =
    overrides.maxImageBytes ?? Number.parseInt(environment.MAX_IMAGE_BYTES ?? String(1_500_000), 10);
  const resultCacheTtlMs =
    overrides.resultCacheTtlMs ??
    Number.parseInt(environment.MEAL_SCAN_RESULT_CACHE_TTL_SECONDS ?? String(24 * 60 * 60), 10) * 1000;
  const scanEnabled =
    overrides.scanEnabled ??
    (environment.NODE_ENV === "production"
      ? environment.MEAL_SCAN_ENABLED === "true"
      : environment.MEAL_SCAN_ENABLED !== "false");
  const requireAppCheck =
    overrides.requireAppCheck ??
    (environment.NODE_ENV === "production"
      ? environment.APP_CHECK_REQUIRED !== "false"
      : environment.APP_CHECK_REQUIRED === "true");
  const appCheckVerifier = overrides.appCheckVerifier ?? createConfiguredFirebaseAppCheckVerifier(environment);
  const budgetStateProvider =
    overrides.getBudgetState ??
    (overrides.budgetState
      ? () => overrides.budgetState
      : createConfiguredBudgetStateProvider(environment));
  const dependencies = {
    verifyAppIntegrity:
      overrides.verifyAppIntegrity ??
      ((input) => verifyAppIntegrity(input, { requireAppCheck, appCheckVerifier, environment })),
    verifyRevenueCatEntitlement:
      overrides.verifyRevenueCatEntitlement ??
      ((input) => verifyRevenueCatEntitlement(input, { environment })),
    quotaStore: overrides.quotaStore ?? createConfiguredQuotaStore(),
    resultCache: overrides.resultCache ?? createConfiguredResultCache({ environment, ttlMs: resultCacheTtlMs }),
    callGemini: overrides.callGemini ?? callGemini,
    getBudgetState: budgetStateProvider,
    logger: overrides.logger ?? console,
  };

  const server = http.createServer(async (request, response) => {
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

      let budget;
      try {
        budget = normalizeBudgetState(await dependencies.getBudgetState());
      } catch {
        dependencies.logger.error?.("meal_scan_budget_control_unavailable");
        return sendJSON(response, 503, {
          error: "meal_scan_unavailable",
          reason: "budget_control_unavailable",
          retryable: true,
        });
      }
      if (budget.mode === "disabled") {
        return sendJSON(response, 503, {
          error: "meal_scan_unavailable",
          reason: "monthly_budget_exceeded",
          retryable: false,
          budget: budgetResponse(budget),
        });
      }

      const payload = await readJSONBody(request, maxBodyBytes);
      const validation = validatePayload(payload, { maxImageBytes });
      if (!validation.ok) {
        return sendJSON(response, 400, { error: "invalid_request", detail: validation.detail });
      }
      const requestedModelId = payload.modelId ?? DEFAULT_MODEL_ID;
      if (!MODEL_CONFIGS[requestedModelId]) {
        return sendJSON(response, 400, {
          error: "unsupported_model",
          reason: "model_not_allowlisted",
          retryable: false,
        });
      }

      const integrityToken = headerValue(request.headers["x-firebase-appcheck"]);
      const integrityResult = normalizeGateResult(await dependencies.verifyAppIntegrity({
        token: integrityToken,
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
        entitlementId: environment.REVENUECAT_ENTITLEMENT_ID ?? "CycleBalance Unlimited",
      }));
      if (!subscriberAccess.allowed) {
        if (
          subscriberAccess.reason === "entitlement_service_unavailable" ||
          subscriberAccess.reason === "entitlement_verifier_unconfigured"
        ) {
          return sendJSON(response, 503, {
            error: "meal_scan_unavailable",
            reason: subscriberAccess.reason,
            retryable: subscriberAccess.retryable === true,
          });
        }
        return sendJSON(response, 403, {
          error: "premium_entitlement_required",
          reason: subscriberAccess.reason ?? "entitlement_inactive",
        });
      }

      const accessTier = subscriberAccess.accessTier === "trial" ? "trial" : "paid";
      const hardLimit = accessTier === "trial" ? TRIAL_DAILY_LIMIT : HARD_DAILY_LIMIT;
      const softLimit = accessTier === "trial" ? TRIAL_DAILY_LIMIT : SOFT_DAILY_LIMIT;
      const modelSelection = selectModel(payload.modelId, budget);
      const modelId = modelSelection.modelId;
      const quotaInput = {
        appUserId: payload.revenueCatAppUserId,
        imageHash: payload.image.sha256,
        accessTier,
        hardLimit,
        softLimit,
        trialTotalLimit: accessTier === "trial" ? TRIAL_TOTAL_LIMIT : null,
      };
      const cacheInput = {
        appUserId: payload.revenueCatAppUserId,
        imageHash: payload.image.sha256,
        modelId,
        schemaVersion: payload.schemaVersion,
        promptVersion: payload.promptVersion,
      };
      let cachedResult = null;
      try {
        cachedResult = await dependencies.resultCache.get(cacheInput);
      } catch (error) {
        dependencies.logger.warn?.("meal_scan_cache_read_error", { message: error?.message });
      }
      if (cachedResult) {
        let cachedQuota = cachedResult.quota;
        if (typeof dependencies.quotaStore.current === "function") {
          try {
            cachedQuota = await dependencies.quotaStore.current(quotaInput);
          } catch (error) {
            dependencies.logger.warn?.("meal_scan_quota_snapshot_error", { message: error?.message });
          }
        }

        dependencies.logger.info?.("meal_scan_estimate", {
          imageHash: payload.image.sha256.slice(0, 12),
          providerId: modelSelection.config.providerId,
          modelId,
          promptTokens: cachedResult.usage?.inputTokens,
          outputTokens: cachedResult.usage?.outputTokens,
          estimatedCostUSD: cachedResult.usage?.estimatedCostUSD,
          quotaUsed: cachedQuota?.used,
          quotaLimit: cachedQuota?.limit,
          accessTier,
          budgetMode: budget.mode,
          cacheHit: true,
        });

        return sendJSON(response, 200, {
          modelId,
          provider: providerResponse(modelSelection),
          estimate: cachedResult.estimate,
          rawEstimateJSON: cachedResult.rawEstimateJSON,
          cacheHit: true,
          usage: cachedResult.usage,
          usageMetadata: cachedResult.usageMetadata ?? null,
          quota: quotaResponse(cachedQuota, accessTier),
          budget: budgetResponse(budget),
        });
      }

      const quota = await dependencies.quotaStore.checkAndConsume(quotaInput);
      if (!quota.allowed) {
        return sendJSON(response, 429, {
          error: "daily_scan_quota_exceeded",
          reason: quota.reason ?? "quota_exceeded",
          quota: quotaResponse(quota, accessTier),
        });
      }

      const geminiPayload = buildGeminiPayload(payload, modelId);
      const geminiResponse = await dependencies.callGemini({
        modelId,
        payload: geminiPayload,
        timeoutMs: Number.parseInt(process.env.GEMINI_TIMEOUT_MS ?? "12000", 10),
      });
      const usage = usageResponse(geminiResponse.usageMetadata, modelSelection.config);
      const rawEstimateJSON = JSON.stringify(geminiResponse.estimate);

      try {
        await dependencies.resultCache.set(cacheInput, {
          estimate: geminiResponse.estimate,
          rawEstimateJSON,
          usage,
          usageMetadata: geminiResponse.usageMetadata ?? null,
          quota,
        });
      } catch (error) {
        dependencies.logger.warn?.("meal_scan_cache_write_error", { message: error?.message });
      }

      dependencies.logger.info?.("meal_scan_estimate", {
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
        rawEstimateJSON,
        cacheHit: false,
        usage,
        usageMetadata: geminiResponse.usageMetadata ?? null,
        quota: quotaResponse(quota, accessTier),
        budget: budgetResponse(budget),
      });
    } catch (error) {
      if (error?.code === "REQUEST_TOO_LARGE") {
        return sendJSON(response, 413, {
          error: "request_too_large",
          reason: "body_size_limit",
          retryable: false,
        });
      }
      if (error?.code === "INVALID_JSON_BODY") {
        return sendJSON(response, 400, {
          error: "invalid_json",
          reason: "request_body_invalid",
          retryable: false,
        });
      }
      if (error?.code === "GEMINI_PARSE_ERROR") {
        return sendJSON(response, 502, {
          error: "meal_scan_parse_error",
          reason: "provider_response_invalid",
          retryable: true,
        });
      }
      if (error?.code === "APP_CHECK_TIMEOUT") {
        return sendJSON(response, 503, {
          error: "meal_scan_unavailable",
          reason: "integrity_service_timeout",
          retryable: true,
        });
      }
      if (error?.code === "REVENUECAT_TIMEOUT") {
        return sendJSON(response, 503, {
          error: "meal_scan_unavailable",
          reason: "entitlement_service_timeout",
          retryable: true,
        });
      }
      if (error?.code === "GEMINI_HTTP_ERROR") {
        return sendJSON(response, 502, {
          error: "meal_scan_provider_error",
          reason: "provider_request_failed",
          retryable: true,
        });
      }
      if (error?.code === "ETIMEDOUT" || error?.name === "AbortError") {
        return sendJSON(response, 504, {
          error: "gemini_timeout",
          reason: "provider_timeout",
          retryable: true,
        });
      }
      dependencies.logger.error?.("meal_scan_proxy_error", {
        code: typeof error?.code === "string" ? error.code : "UNEXPECTED",
        status: Number.isInteger(error?.status) ? error.status : undefined,
      });
      return sendJSON(response, 500, { error: "meal_scan_proxy_error" });
    }
  });

  server.headersTimeout = 10_000;
  server.requestTimeout = 20_000;
  server.keepAliveTimeout = 5_000;
  server.maxRequestsPerSocket = 100;
  return server;
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

export async function callGemini({ modelId, payload, timeoutMs }) {
  const apiKey = process.env.GEMINI_API_KEY;
  if (!apiKey) {
    throw new Error("GEMINI_API_KEY is not configured");
  }

  const controller = new AbortController();
  const timeout = setTimeout(() => controller.abort(), timeoutMs);
  try {
    const response = await fetch(
      `https://generativelanguage.googleapis.com/v1beta/models/${encodeURIComponent(modelId)}:generateContent`,
      {
        method: "POST",
        headers: {
          "content-type": "application/json",
          "x-goog-api-key": apiKey,
        },
        body: JSON.stringify(payload),
        signal: controller.signal,
      }
    );
    if (!response.ok) {
      await response.body?.cancel?.();
      const error = new Error("Gemini request failed");
      error.code = "GEMINI_HTTP_ERROR";
      error.status = response.status;
      throw error;
    }
    let body;
    try {
      body = await response.json();
    } catch {
      throw geminiParseError("Gemini returned a non-JSON response");
    }
    const text = body.candidates?.[0]?.content?.parts?.find((part) => typeof part.text === "string")?.text;
    if (!text) {
      throw geminiParseError("Gemini response did not include structured JSON text");
    }
    let estimate;
    try {
      estimate = JSON.parse(text);
    } catch {
      throw geminiParseError("Gemini did not return valid structured JSON");
    }
    return {
      estimate,
      usageMetadata: body.usageMetadata,
    };
  } finally {
    clearTimeout(timeout);
  }
}

function geminiParseError(message) {
  const error = new Error(message);
  error.code = "GEMINI_PARSE_ERROR";
  return error;
}

async function verifyAppIntegrity(input, { requireAppCheck, appCheckVerifier, environment = process.env } = {}) {
  const { token } = input;
  if (requireAppCheck) {
    if (!token) {
      return { allowed: false, reason: "app_check_required" };
    }
    if (!appCheckVerifier) {
      return { allowed: false, reason: "app_check_verifier_unconfigured" };
    }
    return normalizeGateResult(await appCheckVerifier(token, { consume: true }));
  }

  if (environment.NODE_ENV === "production") {
    return { allowed: false, reason: "app_check_required" };
  }

  const expected = environment.APP_INTEGRITY_SHARED_SECRET;
  if (!expected) {
    return { allowed: false, reason: "shared_secret_unconfigured" };
  }
  return { allowed: token === expected, reason: token === expected ? undefined : "shared_secret_mismatch" };
}

export async function verifyRevenueCatEntitlement(
  { appUserId, entitlementId },
  { environment = process.env, fetchImpl = fetch } = {}
) {
  const apiKey = environment.REVENUECAT_SECRET_API_KEY;
  const projectId = environment.REVENUECAT_PROJECT_ID;
  if (!apiKey || !projectId || !appUserId || !entitlementId) {
    return { allowed: false, reason: "entitlement_verifier_unconfigured" };
  }

  const response = await fetchWithTimeout(
    `https://api.revenuecat.com/v2/projects/${encodeURIComponent(projectId)}/customers/${encodeURIComponent(appUserId)}/subscriptions?limit=100`,
    {
      headers: {
        authorization: `Bearer ${apiKey}`,
        accept: "application/json",
      },
    },
    Number.parseInt(environment.REVENUECAT_TIMEOUT_MS ?? "5000", 10),
    fetchImpl,
    "REVENUECAT_TIMEOUT"
  );
  if (!response.ok) {
    await response.body?.cancel?.();
    return response.status === 404
      ? { allowed: false, reason: "entitlement_inactive" }
      : {
          allowed: false,
          reason: "entitlement_service_unavailable",
          retryable: response.status === 429 || response.status >= 500,
        };
  }

  const body = await response.json();
  return subscriberAccessFromRevenueCatV2(body, entitlementId);
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
    async current({ appUserId, hardLimit, softLimit, accessTier, trialTotalLimit }) {
      const day = new Date().toISOString().slice(0, 10);
      const appUserHash = shortHash(appUserId);
      const currentDailyUsed = dailyCounts.get(`${appUserHash}:${day}`) ?? 0;
      const currentTrialUsed = trialCounts.get(`${appUserHash}:trial`) ?? 0;
      return {
        allowed: true,
        used: currentDailyUsed,
        limit: hardLimit,
        softLimit,
        remainingToday: Math.max(0, hardLimit - currentDailyUsed),
        trialUsed: accessTier === "trial" ? currentTrialUsed : null,
        trialLimit: accessTier === "trial" ? trialTotalLimit : null,
        remainingTrial: accessTier === "trial" ? Math.max(0, trialTotalLimit - currentTrialUsed) : null,
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

export function quotaExpiryDates(now) {
  return {
    daily: new Date(now.getTime() + 3 * 86_400_000),
    trial: new Date(now.getTime() + 30 * 86_400_000),
  };
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
      const expiry = quotaExpiryDates(now);
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
            expiresAt: expiry.daily,
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
              expiresAt: expiry.trial,
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
    async current({ appUserId, hardLimit, softLimit, accessTier, trialTotalLimit }) {
      const db = await firestore();
      const day = new Date().toISOString().slice(0, 10);
      const appUserHash = shortHash(appUserId);
      const [dailySnapshot, trialSnapshot] = await Promise.all([
        db.collection(collectionName).doc(`${appUserHash}_${day}`).get(),
        accessTier === "trial"
          ? db.collection(collectionName).doc(`${appUserHash}_trial`).get()
          : Promise.resolve(null),
      ]);
      const currentUsed = dailySnapshot.exists ? Number(dailySnapshot.get("used") ?? 0) : 0;
      const currentTrialUsed = trialSnapshot?.exists ? Number(trialSnapshot.get("used") ?? 0) : 0;
      return {
        allowed: true,
        used: currentUsed,
        limit: hardLimit,
        softLimit,
        remainingToday: Math.max(0, hardLimit - currentUsed),
        trialUsed: accessTier === "trial" ? currentTrialUsed : null,
        trialLimit: accessTier === "trial" ? trialTotalLimit : null,
        remainingTrial: accessTier === "trial" ? Math.max(0, trialTotalLimit - currentTrialUsed) : null,
        accessTier,
      };
    },
  };
}

function createConfiguredResultCache({ environment, ttlMs }) {
  const backend = environment.MEAL_SCAN_RESULT_CACHE ?? environment.MEAL_SCAN_QUOTA_STORE;
  if (backend === "firestore") {
    return createFirestoreResultCache({
      collectionName: environment.MEAL_SCAN_RESULT_CACHE_COLLECTION ?? "mealScanEstimateCache",
      ttlMs,
    });
  }
  return createInMemoryResultCache({ ttlMs });
}

function createInMemoryResultCache({ ttlMs }) {
  const records = new Map();
  return {
    async get(input) {
      const key = resultCacheKey(input);
      const record = records.get(key);
      if (!record) return null;
      if (record.expiresAt <= Date.now()) {
        records.delete(key);
        return null;
      }
      return record.value;
    },
    async set(input, value) {
      records.set(resultCacheKey(input), {
        value,
        expiresAt: Date.now() + ttlMs,
      });
    },
  };
}

function createFirestoreResultCache({ collectionName, ttlMs }) {
  let firestoreClient;
  async function firestore() {
    if (!firestoreClient) {
      const { Firestore } = await import("@google-cloud/firestore");
      firestoreClient = new Firestore();
    }
    return firestoreClient;
  }

  return {
    async get(input) {
      const db = await firestore();
      const document = db.collection(collectionName).doc(resultCacheKey(input));
      const snapshot = await document.get();
      if (!snapshot.exists) return null;

      const expiresAtValue = snapshot.get("expiresAt");
      const expiresAt = expiresAtValue?.toDate?.() ?? new Date(expiresAtValue);
      if (!Number.isFinite(expiresAt.getTime()) || expiresAt.getTime() <= Date.now()) {
        await document.delete();
        return null;
      }
      return snapshot.get("value") ?? null;
    },
    async set(input, value) {
      const db = await firestore();
      await db.collection(collectionName).doc(resultCacheKey(input)).set({
        appUserHash: shortHash(input.appUserId),
        imageHashPrefix: String(input.imageHash).slice(0, 12),
        modelId: input.modelId,
        schemaVersion: input.schemaVersion ?? null,
        promptVersion: input.promptVersion ?? null,
        value: JSON.parse(JSON.stringify(value)),
        createdAt: new Date(),
        expiresAt: new Date(Date.now() + ttlMs),
      });
    },
  };
}

function resultCacheKey({ appUserId, imageHash, modelId, schemaVersion, promptVersion }) {
  return crypto
    .createHash("sha256")
    .update([appUserId, imageHash, modelId, schemaVersion ?? "", promptVersion ?? ""].join("|"))
    .digest("hex");
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

function subscriberAccessFromRevenueCatV2(body, entitlementId) {
  const subscriptions = Array.isArray(body?.items) ? body.items : [];
  const matchingSubscriptions = subscriptions.filter((subscription) => {
    if (subscription?.gives_access !== true) return false;
    const entitlements = Array.isArray(subscription?.entitlements?.items)
      ? subscription.entitlements.items
      : [];
    return entitlements.some(
      (entitlement) => entitlement?.lookup_key === entitlementId || entitlement?.id === entitlementId
    );
  });

  if (!matchingSubscriptions.length) {
    return { allowed: false, reason: "entitlement_inactive" };
  }

  const trialSubscription = matchingSubscriptions.find((subscription) => subscription?.status === "trialing");
  const accessSubscription = trialSubscription ?? matchingSubscriptions[0];
  return {
    allowed: true,
    accessTier: trialSubscription ? "trial" : "paid",
    entitlementExpiresAt: accessSubscription?.current_period_ends_at ?? accessSubscription?.ends_at ?? null,
  };
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
    source: budget.source ?? null,
    spendUsd: numberOrNull(budget.spendUsd),
    budgetUsd: numberOrNull(budget.budgetUsd),
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

function validatePayload(payload, { maxImageBytes = 1_500_000 } = {}) {
  if (!isPlainObject(payload)) return { ok: false, detail: "body must be JSON object" };
  if (!boundedString(payload.revenueCatAppUserId, 1, 256)) {
    return { ok: false, detail: "revenueCatAppUserId is invalid" };
  }
  if (!new Set(["breakfast", "lunch", "dinner", "snack"]).has(payload.mealType)) {
    return { ok: false, detail: "mealType is invalid" };
  }
  if (!boundedString(payload.locale, 2, 32) || !/^[A-Za-z]{2,3}(?:[-_][A-Za-z0-9]{2,8}){0,3}$/.test(payload.locale)) {
    return { ok: false, detail: "locale is invalid" };
  }
  if (payload.schemaVersion !== "meal-scan-gemini-v1") {
    return { ok: false, detail: "schemaVersion is invalid" };
  }
  if (payload.promptVersion !== "meal-scan-prompt-v1") {
    return { ok: false, detail: "promptVersion is invalid" };
  }
  if (!isPlainObject(payload.image) || payload.image.mimeType !== "image/jpeg") {
    return { ok: false, detail: "jpeg image is required" };
  }
  if (!boundedString(payload.image.base64, 4, Math.ceil(maxImageBytes / 3) * 4 + 4)) {
    return { ok: false, detail: "jpeg image base64 is invalid" };
  }
  if (typeof payload.image.sha256 !== "string" || !/^[a-fA-F0-9]{64}$/.test(payload.image.sha256)) {
    return { ok: false, detail: "image sha256 is invalid" };
  }
  const normalizedBase64 = payload.image.base64.replace(/\s/g, "");
  const imageBytes = Buffer.from(normalizedBase64, "base64");
  if (!imageBytes.length || imageBytes.toString("base64") !== normalizedBase64) {
    return { ok: false, detail: "jpeg image base64 is invalid" };
  }
  if (imageBytes.length > maxImageBytes) {
    return { ok: false, detail: "jpeg image exceeds decoded size limit" };
  }
  if (
    imageBytes.length < 4 ||
    imageBytes[0] !== 0xff ||
    imageBytes[1] !== 0xd8 ||
    imageBytes[imageBytes.length - 2] !== 0xff ||
    imageBytes[imageBytes.length - 1] !== 0xd9
  ) {
    return { ok: false, detail: "jpeg image bytes are invalid" };
  }
  const actualImageHash = crypto.createHash("sha256").update(imageBytes).digest("hex");
  if (actualImageHash !== String(payload.image.sha256).toLowerCase()) {
    return { ok: false, detail: "image sha256 does not match jpeg bytes" };
  }
  return { ok: true };
}

function isPlainObject(value) {
  return value !== null && typeof value === "object" && !Array.isArray(value);
}

function boundedString(value, minimumLength, maximumLength) {
  return typeof value === "string" && value.length >= minimumLength && value.length <= maximumLength;
}

function selectModel(requestedModelId, budget) {
  const requested = requestedModelId ?? DEFAULT_MODEL_ID;
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

function createConfiguredBudgetStateProvider(environment = process.env) {
  if (environment.MEAL_SCAN_BUDGET_STORE === "firestore") {
    return createFirestoreBudgetStateProvider({
      environment,
      ttlMs: Number.parseInt(environment.MEAL_SCAN_CONTROL_CACHE_TTL_MS ?? "30000", 10),
    });
  }
  return () => currentBudgetState(environment);
}

export function createFirestoreBudgetStateProvider({
  environment = process.env,
  ttlMs = 30_000,
  now = Date.now,
  readControl,
} = {}) {
  const loadControl = readControl ?? createFirestoreControlReader(environment);
  let cached;
  let cachedUntil = 0;

  return async () => {
    const timestamp = now();
    if (cached && timestamp < cachedUntil) {
      return cached;
    }

    const control = await loadControl();
    if (!control || typeof control !== "object") {
      throw new Error("meal scan budget control is missing");
    }
    const manualMode = validBudgetMode(control.manualMode) ? control.manualMode : null;
    const billingMode = validBudgetMode(control.billingMode) ? control.billingMode : null;
    if (!manualMode && !billingMode) {
      throw new Error("meal scan budget control mode is invalid");
    }

    cached = normalizeBudgetState({
      ...control,
      mode: manualMode ?? billingMode,
      source: manualMode ? "manual_override" : "cloud_billing_budget",
    });
    cachedUntil = timestamp + ttlMs;
    return cached;
  };
}

function createFirestoreControlReader(environment) {
  let document;
  return async () => {
    if (!document) {
      const { Firestore } = await import("@google-cloud/firestore");
      const firestore = new Firestore();
      document = firestore
        .collection(environment.MEAL_SCAN_CONTROL_COLLECTION ?? "mealScanControls")
        .doc(environment.MEAL_SCAN_CONTROL_DOCUMENT ?? "global");
    }
    const snapshot = await document.get();
    return snapshot.exists ? snapshot.data() : null;
  };
}

function currentBudgetState(environment = process.env) {
  const spendUsd = numberOrNull(environment.MEAL_SCAN_MONTHLY_SPEND_USD) ?? 0;
  return normalizeBudgetState({
    spendUsd,
    alertAtUsd: BUDGET_ALERT_AT_USD,
    degradeAtUsd: BUDGET_DEGRADE_AT_USD,
    disableAtUsd: BUDGET_DISABLE_AT_USD,
    source: "static_environment",
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

  if (!validBudgetMode(mode)) {
    mode = "normal";
  }

  return {
    mode,
    source: typeof input?.source === "string" ? input.source : null,
    spendUsd,
    budgetUsd: numberOrNull(input?.budgetUsd),
    alertAtUsd,
    degradeAtUsd,
    disableAtUsd,
  };
}

function validBudgetMode(mode) {
  return ["normal", "alert", "degraded", "disabled"].includes(mode);
}

function createConfiguredFirebaseAppCheckVerifier(environment = process.env) {
  const expectedAppId = environment.FIREBASE_APP_ID;
  if (!expectedAppId) {
    return null;
  }

  let appCheckServicePromise;
  return async (token, options = { consume: true }) => {
    try {
      appCheckServicePromise ??= loadFirebaseAppCheckService(environment);
      const appCheckService = await appCheckServicePromise;
      const verified = await withTimeout(
        appCheckService.verifyToken(token, options),
        Number.parseInt(environment.APP_CHECK_TIMEOUT_MS ?? "5000", 10),
        "APP_CHECK_TIMEOUT"
      );
      if (verified.alreadyConsumed) {
        return { allowed: false, reason: "app_check_token_replayed" };
      }
      if (verified.appId !== expectedAppId) {
        return { allowed: false, reason: "app_check_app_mismatch" };
      }
      return { allowed: true, appId: verified.appId };
    } catch (error) {
      if (error?.code === "APP_CHECK_TIMEOUT") {
        throw error;
      }
      return { allowed: false, reason: "app_check_rejected" };
    }
  };
}

async function loadFirebaseAppCheckService(environment) {
  const [{ getApp, getApps, initializeApp }, { getAppCheck }] = await Promise.all([
    import("firebase-admin/app"),
    import("firebase-admin/app-check"),
  ]);
  const app = getApps().length
    ? getApp()
    : initializeApp({ projectId: environment.GOOGLE_CLOUD_PROJECT ?? environment.GCLOUD_PROJECT });
  return getAppCheck(app);
}

async function readJSONBody(request, maxBodyBytes) {
  let body = "";
  let bytes = 0;
  for await (const chunk of request) {
    bytes += chunk.length;
    if (bytes > maxBodyBytes) {
      const error = new Error("request too large");
      error.code = "REQUEST_TOO_LARGE";
      throw error;
    }
    body += chunk;
  }
  try {
    return JSON.parse(body || "{}");
  } catch {
    const error = new Error("request body is not valid JSON");
    error.code = "INVALID_JSON_BODY";
    throw error;
  }
}

async function fetchWithTimeout(url, options, timeoutMs, fetchImpl, timeoutCode) {
  const controller = new AbortController();
  const timeout = setTimeout(() => controller.abort(), timeoutMs);
  try {
    return await fetchImpl(url, { ...options, signal: controller.signal });
  } catch (error) {
    if (controller.signal.aborted) {
      const timeoutError = new Error("upstream request timed out");
      timeoutError.code = timeoutCode;
      throw timeoutError;
    }
    throw error;
  } finally {
    clearTimeout(timeout);
  }
}

async function withTimeout(promise, timeoutMs, timeoutCode) {
  let timeout;
  try {
    return await Promise.race([
      promise,
      new Promise((_, reject) => {
        timeout = setTimeout(() => {
          const error = new Error("upstream operation timed out");
          error.code = timeoutCode;
          reject(error);
        }, timeoutMs);
      }),
    ]);
  } finally {
    clearTimeout(timeout);
  }
}

function sendJSON(response, status, body) {
  response.writeHead(status, {
    "cache-control": "no-store",
    "content-type": "application/json",
    "x-content-type-options": "nosniff",
  });
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
