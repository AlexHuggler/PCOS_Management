import http from "node:http";
import crypto from "node:crypto";
import { Environment, SignedDataVerifier, VerificationStatus } from "@apple/app-store-server-library";
import sharp from "sharp";

const DEFAULT_MODEL_ID = "gemini-3.1-flash-lite";
const PROVIDER_ID = "google-gemini";
const MODEL_CONFIGS = {
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
const MAX_PUBLIC_BODY_BYTES = 2_200_000;
const MAX_DECODED_IMAGE_BYTES = 1_500_000;
const MAX_SOURCE_IMAGE_PIXELS = 12_000_000;
const MAX_CANONICAL_IMAGE_BYTES = 750_000;
const CANONICAL_IMAGE_LONG_EDGE = 960;
const ROLLING_WINDOW_SECONDS = 86_400;
const ABSOLUTE_PAID_ROLLING_LIMIT = 15;
const DEFAULT_PAID_ROLLING_LIMIT = 10;
const DEFAULT_TRIAL_ROLLING_LIMIT = 5;
const DEFAULT_TRIAL_LIFETIME_LIMIT = 25;
const DEFAULT_BUDGET_ALERT_USD = 15;
const DEFAULT_BUDGET_DEGRADE_USD = 20;
const DEFAULT_BUDGET_DISABLE_USD = 25;

export function createServer(overrides = {}) {
  const environment = overrides.environment ?? process.env;
  const maxBodyBytes = boundedPositiveInteger(
    overrides.maxBodyBytes ?? environment.MAX_BODY_BYTES,
    MAX_PUBLIC_BODY_BYTES,
    MAX_PUBLIC_BODY_BYTES,
    "MAX_BODY_BYTES"
  );
  const maxImageBytes = boundedPositiveInteger(
    overrides.maxImageBytes ?? environment.MAX_IMAGE_BYTES,
    MAX_DECODED_IMAGE_BYTES,
    MAX_DECODED_IMAGE_BYTES,
    "MAX_IMAGE_BYTES"
  );
  const maxImagePixels = boundedPositiveInteger(
    overrides.maxImagePixels ?? environment.MAX_IMAGE_PIXELS,
    MAX_SOURCE_IMAGE_PIXELS,
    MAX_SOURCE_IMAGE_PIXELS,
    "MAX_IMAGE_PIXELS"
  );
  const maxCanonicalImageBytes = boundedPositiveInteger(
    overrides.maxCanonicalImageBytes ?? environment.MAX_CANONICAL_IMAGE_BYTES,
    MAX_CANONICAL_IMAGE_BYTES,
    MAX_CANONICAL_IMAGE_BYTES,
    "MAX_CANONICAL_IMAGE_BYTES"
  );
  const paidLimit = positiveInteger(environment.MEAL_SCAN_DAILY_LIMIT, DEFAULT_PAID_ROLLING_LIMIT);
  if (paidLimit > ABSOLUTE_PAID_ROLLING_LIMIT) {
    throw new Error(`MEAL_SCAN_DAILY_LIMIT must not exceed ${ABSOLUTE_PAID_ROLLING_LIMIT}`);
  }
  const trialLimit = positiveInteger(environment.MEAL_SCAN_TRIAL_DAILY_LIMIT, DEFAULT_TRIAL_ROLLING_LIMIT);
  const trialLifetimeLimit = positiveInteger(
    environment.MEAL_SCAN_TRIAL_TOTAL_LIMIT,
    DEFAULT_TRIAL_LIFETIME_LIMIT
  );
  const resultCacheTtlMs =
    positiveInteger(environment.MEAL_SCAN_RESULT_CACHE_TTL_SECONDS, 24 * 60 * 60) * 1_000;
  const resultLeaseTtlMs = positiveInteger(environment.MEAL_SCAN_RESULT_LEASE_TTL_MS, 30_000);
  const idempotencyPendingTtlMs = positiveInteger(environment.MEAL_SCAN_IDEMPOTENCY_PENDING_TTL_MS, 30_000);
  const geminiTimeoutMs = positiveInteger(environment.GEMINI_TIMEOUT_MS, 12_000);
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
  const bundleId = environment.APPLE_BUNDLE_ID ?? "alex.PCOS";
  const allowedProductIds = new Set(
    (environment.APPLE_ALLOWED_PRODUCT_IDS ??
      "cyclebalance.premium.monthly,cyclebalance.premium.annual")
      .split(",")
      .map((value) => value.trim())
      .filter(Boolean)
  );
  const principalSecret =
    overrides.principalSecret ??
    environment.MEAL_SCAN_PRINCIPAL_HMAC_SECRET ??
    (environment.NODE_ENV === "production" ? null : "cyclebalance-development-principal-secret");

  validateProductionMealScanConfiguration({
    environment,
    scanEnabled,
    numericConfiguration: {
      maxBodyBytes,
      maxImageBytes,
      maxImagePixels,
      maxCanonicalImageBytes,
      resultCacheTtlMs,
      resultLeaseTtlMs,
      idempotencyPendingTtlMs,
      geminiTimeoutMs,
      paidLimit,
      trialLimit,
      trialLifetimeLimit,
    },
  });

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
    storeKitVerifier: overrides.storeKitVerifier ?? createConfiguredStoreKitVerifier(environment),
    processImage: overrides.processImage ?? processCanonicalJPEG,
    quotaStore: overrides.quotaStore ?? createConfiguredQuotaStore(environment),
    idempotencyStore:
      overrides.idempotencyStore ??
      createConfiguredIdempotencyStore({ environment, pendingTtlMs: idempotencyPendingTtlMs }),
    requestGate: overrides.requestGate ?? createConfiguredRequestGate(environment),
    resultCache:
      overrides.resultCache ??
      createConfiguredResultCache({ environment, ttlMs: resultCacheTtlMs, leaseTtlMs: resultLeaseTtlMs }),
    callGemini: overrides.callGemini ?? callGemini,
    getBudgetState: budgetStateProvider,
    logger: overrides.logger ?? console,
  };

  const server = http.createServer(async (request, response) => {
    let idempotencyContext = null;
    let providerDispatched = false;
    let lease = null;
    let cacheInput = null;

    const abandonIdempotency = async () => {
      if (!idempotencyContext?.acquired || typeof dependencies.idempotencyStore.abandon !== "function") return;
      try {
        await dependencies.idempotencyStore.abandon(idempotencyContext);
      } catch (error) {
        dependencies.logger.warn?.("meal_scan_idempotency_abandon_error", { code: safeErrorCode(error) });
      }
      idempotencyContext = null;
    };

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

      const integrityToken = headerValue(request.headers["x-firebase-appcheck"]);
      if (requireAppCheck && !integrityToken) {
        return sendJSON(response, 401, {
          error: "app_integrity_required",
          reason: "app_check_required",
        });
      }
      if (requireAppCheck) {
        const integrityResult = normalizeGateResult(
          await dependencies.verifyAppIntegrity({ token: integrityToken })
        );
        if (!integrityResult.allowed) {
          return sendJSON(response, 401, {
            error: "app_integrity_required",
            reason: integrityResult.reason ?? "integrity_failed",
          });
        }
      }

      const payload = await readJSONBody(request, maxBodyBytes);
      const validation = validatePayload(payload, { maxImageBytes });
      if (!validation.ok) {
        return sendJSON(response, 400, { error: "invalid_request", detail: validation.detail });
      }

      if (!requireAppCheck) {
        const integrityResult = normalizeGateResult(
          await dependencies.verifyAppIntegrity({ token: integrityToken, payload })
        );
        if (!integrityResult.allowed) {
          return sendJSON(response, 401, {
            error: "app_integrity_required",
            reason: integrityResult.reason ?? "integrity_failed",
          });
        }
      }

      let budget;
      try {
        budget = normalizeBudgetState(await dependencies.getBudgetState(), environment);
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

      if (!dependencies.storeKitVerifier || !principalSecret) {
        return sendJSON(response, 503, {
          error: "meal_scan_unavailable",
          reason: "storekit_verifier_unconfigured",
          retryable: false,
        });
      }

      let transaction;
      try {
        transaction = await dependencies.storeKitVerifier.verifyAndDecodeTransaction(
          payload.signedTransactionJWS
        );
      } catch (error) {
        return sendJSON(response, 403, {
          error: "premium_entitlement_required",
          reason:
            error?.status === VerificationStatus.INVALID_APP_IDENTIFIER
              ? "storekit_app_mismatch"
              : "storekit_transaction_invalid",
        });
      }

      const transactionAccess = validateStoreKitTransaction(transaction, {
        bundleId,
        allowedProductIds,
        now: Date.now(),
      });
      if (!transactionAccess.allowed) {
        return sendJSON(response, 403, {
          error: "premium_entitlement_required",
          reason: transactionAccess.reason,
        });
      }

      const principal = derivePurchasePrincipal({
        originalTransactionId: transaction.originalTransactionId,
        environment: transaction.environment,
        secret: principalSecret,
      });

      let canonicalImage;
      try {
        canonicalImage = await dependencies.processImage({
          bytes: validation.imageBytes,
          maxPixels: maxImagePixels,
          maxCanonicalBytes: maxCanonicalImageBytes,
          longEdge: CANONICAL_IMAGE_LONG_EDGE,
        });
      } catch (error) {
        return sendJSON(response, 400, {
          error: "invalid_request",
          detail: error?.detail ?? "jpeg image could not be decoded",
        });
      }
      const sourcePixels = Number(canonicalImage?.sourceWidth) * Number(canonicalImage?.sourceHeight);
      if (!Number.isSafeInteger(sourcePixels) || sourcePixels <= 0) {
        return sendJSON(response, 400, {
          error: "invalid_request",
          detail: "jpeg image dimensions are invalid",
        });
      }
      if (sourcePixels > maxImagePixels) {
        return sendJSON(response, 400, {
          error: "invalid_request",
          detail: "jpeg image exceeds pixel limit",
        });
      }
      if (!Buffer.isBuffer(canonicalImage.data) || canonicalImage.data.length > maxCanonicalImageBytes) {
        return sendJSON(response, 400, {
          error: "invalid_request",
          detail: "canonical jpeg exceeds size limit",
        });
      }
      const canonicalImageHash = crypto.createHash("sha256").update(canonicalImage.data).digest("hex");

      let requestGateResult;
      try {
        requestGateResult = await dependencies.requestGate.checkAndConsume({ appUserId: principal });
      } catch {
        dependencies.logger.error?.("meal_scan_request_control_unavailable");
        return sendJSON(response, 503, {
          error: "meal_scan_unavailable",
          reason: "request_control_unavailable",
          retryable: true,
        });
      }
      if (!requestGateResult.allowed) {
        return sendJSON(response, 429, {
          error: "meal_scan_request_rate_limited",
          reason: requestGateResult.reason ?? "request_limit_exceeded",
          retryable: true,
          retryAfterSeconds: numberOrNull(requestGateResult.retryAfterSeconds),
        });
      }

      const tier = transactionAccess.tier;
      const limit = tier === "paid" ? paidLimit : trialLimit;
      const lifetimeLimit = tier === "paid" ? null : trialLifetimeLimit;
      const quotaInput = { principal, tier, limit, lifetimeLimit };
      cacheInput = {
        appUserId: principal,
        imageHash: canonicalImageHash,
        modelId: DEFAULT_MODEL_ID,
        schemaVersion: payload.schemaVersion,
        promptVersion: payload.promptVersion,
        mealType: payload.mealType,
        locale: payload.locale,
      };
      const requestHash = canonicalRequestHash({
        principal,
        imageHash: canonicalImageHash,
        mealType: payload.mealType,
        locale: payload.locale,
        schemaVersion: payload.schemaVersion,
        promptVersion: payload.promptVersion,
      });

      idempotencyContext = await dependencies.idempotencyStore.claim({
        requestId: payload.requestId,
        requestHash,
      });
      if (idempotencyContext.state === "mismatch") {
        return sendJSON(response, 409, {
          error: "idempotency_conflict",
          reason: "request_body_mismatch",
          retryable: false,
          idempotency: { state: "unknown" },
        });
      }
      if (idempotencyContext.state === "completed") {
        return sendJSON(response, 200, idempotencyContext.response);
      }
      if (idempotencyContext.state === "unknown") {
        return sendJSON(response, 409, {
          error: "meal_scan_outcome_unknown",
          reason: "previous_dispatch_outcome_unknown",
          retryable: false,
          idempotency: { state: "unknown" },
        });
      }
      if (!idempotencyContext.acquired) {
        return sendJSON(response, 409, {
          error: "meal_scan_in_progress",
          reason: "duplicate_request_in_progress",
          retryable: true,
          idempotency: { state: "pending" },
        });
      }

      const modelSelection = fixedModelSelection();
      const buildSuccessBody = (result, quota, cacheHit) => ({
        modelId: DEFAULT_MODEL_ID,
        provider: providerResponse(modelSelection),
        estimate: result.estimate,
        rawEstimateJSON: result.rawEstimateJSON,
        cacheHit,
        usage: result.usage,
        usageMetadata: result.usageMetadata ?? null,
        quota: quotaResponse(quota, tier),
        budget: budgetResponse(budget),
        idempotency: { state: "completed" },
      });

      let cachedResult;
      try {
        cachedResult = await dependencies.resultCache.get(cacheInput);
      } catch (error) {
        await abandonIdempotency();
        dependencies.logger.warn?.("meal_scan_cache_read_error", { code: safeErrorCode(error) });
        return sendJSON(response, 503, {
          error: "meal_scan_unavailable",
          reason: "cache_control_unavailable",
          retryable: true,
        });
      }
      if (cachedResult) {
        let quota = cachedResult.quota;
        if (typeof dependencies.quotaStore.current === "function") {
          try {
            quota = await dependencies.quotaStore.current(quotaInput);
          } catch (error) {
            dependencies.logger.warn?.("meal_scan_quota_snapshot_error", { code: safeErrorCode(error) });
          }
        }
        const body = buildSuccessBody(cachedResult, quota, true);
        await dependencies.idempotencyStore.complete(idempotencyContext, body);
        dependencies.logger.info?.("meal_scan_estimate", identifierFreeMetric({
          modelId: DEFAULT_MODEL_ID,
          usage: cachedResult.usage,
          quota,
          tier,
          budget,
          cacheHit: true,
        }));
        return sendJSON(response, 200, body);
      }

      if (typeof dependencies.resultCache.acquireLease === "function") {
        try {
          lease = await dependencies.resultCache.acquireLease(cacheInput);
        } catch (error) {
          await abandonIdempotency();
          dependencies.logger.warn?.("meal_scan_cache_lease_error", { code: safeErrorCode(error) });
          return sendJSON(response, 503, {
            error: "meal_scan_unavailable",
            reason: "cache_control_unavailable",
            retryable: true,
          });
        }
        if (lease.value) {
          const body = buildSuccessBody(lease.value, lease.value.quota, true);
          await dependencies.idempotencyStore.complete(idempotencyContext, body);
          return sendJSON(response, 200, body);
        }
        if (!lease.acquired) {
          const completedResult = await waitForCachedResult(dependencies.resultCache, cacheInput);
          if (completedResult) {
            const body = buildSuccessBody(completedResult, completedResult.quota, true);
            await dependencies.idempotencyStore.complete(idempotencyContext, body);
            return sendJSON(response, 200, body);
          }
          await abandonIdempotency();
          return sendJSON(response, 409, {
            error: "meal_scan_in_progress",
            reason: "duplicate_request_in_progress",
            retryable: true,
            idempotency: { state: "pending" },
          });
        }
      }

      let quota;
      try {
        quota = await dependencies.quotaStore.checkAndConsume(quotaInput);
      } catch (error) {
        await abandonIdempotency();
        dependencies.logger.error?.("meal_scan_quota_control_unavailable", { code: safeErrorCode(error) });
        return sendJSON(response, 503, {
          error: "meal_scan_unavailable",
          reason: "quota_control_unavailable",
          retryable: true,
        });
      }
      if (!quota.allowed) {
        await abandonIdempotency();
        return sendJSON(response, 429, {
          error: "rolling_scan_quota_exceeded",
          reason: quota.reason ?? "quota_exceeded",
          retryable: true,
          quota: quotaResponse(quota, tier),
        });
      }

      const providerPayload = buildGeminiPayload({
        ...payload,
        image: {
          mimeType: "image/jpeg",
          base64: canonicalImage.data.toString("base64"),
          sha256: canonicalImageHash,
        },
      });
      providerDispatched = true;
      const geminiResponse = await dependencies.callGemini({
        modelId: DEFAULT_MODEL_ID,
        payload: providerPayload,
        timeoutMs: geminiTimeoutMs,
      });
      assertEstimateBounds(geminiResponse.estimate);
      const usage = usageResponse(geminiResponse.usageMetadata, MODEL_CONFIGS[DEFAULT_MODEL_ID]);
      const rawEstimateJSON = JSON.stringify(geminiResponse.estimate);
      const result = {
        estimate: geminiResponse.estimate,
        rawEstimateJSON,
        usage,
        usageMetadata: geminiResponse.usageMetadata ?? null,
        quota,
      };

      try {
        await dependencies.resultCache.set(cacheInput, result, { leaseId: lease?.leaseId });
      } catch (error) {
        dependencies.logger.warn?.("meal_scan_cache_write_error", { code: safeErrorCode(error) });
      }
      const body = buildSuccessBody(result, quota, false);
      await dependencies.idempotencyStore.complete(idempotencyContext, body);
      idempotencyContext = null;

      dependencies.logger.info?.("meal_scan_estimate", identifierFreeMetric({
        modelId: DEFAULT_MODEL_ID,
        usage,
        quota,
        tier,
        budget,
        cacheHit: false,
      }));
      return sendJSON(response, 200, body);
    } catch (error) {
      if (providerDispatched && idempotencyContext?.acquired) {
        try {
          await dependencies.idempotencyStore.markUnknown(idempotencyContext);
        } catch (markError) {
          dependencies.logger.error?.("meal_scan_idempotency_unknown_write_error", {
            code: safeErrorCode(markError),
          });
        }
      }
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
      if (providerDispatched) {
        const idempotency = { state: "unknown" };
        if (error?.code === "PROVIDER_RESPONSE_OUT_OF_BOUNDS") {
          return sendJSON(response, 502, {
            error: "meal_scan_parse_error",
            reason: "provider_response_out_of_bounds",
            retryable: false,
            idempotency,
          });
        }
        if (error?.code === "GEMINI_PARSE_ERROR") {
          return sendJSON(response, 502, {
            error: "meal_scan_parse_error",
            reason: "provider_response_invalid",
            retryable: false,
            idempotency,
          });
        }
        if (error?.code === "GEMINI_HTTP_ERROR") {
          return sendJSON(response, 502, {
            error: "meal_scan_provider_error",
            reason: "provider_request_failed",
            retryable: false,
            idempotency,
          });
        }
        if (error?.code === "ETIMEDOUT" || error?.name === "AbortError") {
          return sendJSON(response, 504, {
            error: "meal_scan_outcome_unknown",
            reason: "provider_timeout",
            retryable: false,
            idempotency,
          });
        }
        dependencies.logger.error?.("meal_scan_dispatch_outcome_unknown", { code: safeErrorCode(error) });
        return sendJSON(response, 503, {
          error: "meal_scan_outcome_unknown",
          reason: "provider_dispatch_outcome_unknown",
          retryable: false,
          idempotency,
        });
      }
      if (error?.code === "APP_CHECK_TIMEOUT") {
        return sendJSON(response, 503, {
          error: "meal_scan_unavailable",
          reason: "integrity_service_timeout",
          retryable: true,
        });
      }
      dependencies.logger.error?.("meal_scan_proxy_error", { code: safeErrorCode(error) });
      return sendJSON(response, 500, { error: "meal_scan_proxy_error" });
    } finally {
      if (lease?.acquired && cacheInput && typeof dependencies.resultCache.releaseLease === "function") {
        try {
          await dependencies.resultCache.releaseLease(cacheInput, lease.leaseId);
        } catch (error) {
          dependencies.logger.warn?.("meal_scan_cache_lease_release_error", { code: safeErrorCode(error) });
        }
      }
    }
  });

  server.headersTimeout = 10_000;
  server.requestTimeout = 20_000;
  server.keepAliveTimeout = 5_000;
  server.maxRequestsPerSocket = 100;
  return server;
}

function validateProductionMealScanConfiguration({ environment, scanEnabled, numericConfiguration }) {
  if (environment.NODE_ENV !== "production" || !scanEnabled) return;

  const missing = [];
  if (environment.APP_CHECK_REQUIRED !== "true") missing.push("APP_CHECK_REQUIRED=true");
  if (!boundedString(environment.FIREBASE_APP_ID, 1, 256)) missing.push("FIREBASE_APP_ID");
  if (!boundedString(environment.APPLE_BUNDLE_ID, 1, 256)) missing.push("APPLE_BUNDLE_ID");
  if (!/^\d{5,20}$/.test(environment.APPLE_APP_ID ?? "")) missing.push("APPLE_APP_ID");
  if (!boundedString(environment.APPLE_ALLOWED_PRODUCT_IDS, 1, 1024)) missing.push("APPLE_ALLOWED_PRODUCT_IDS");
  if (!boundedString(environment.APPLE_ROOT_CA_BASE64, 1, 16_384)) missing.push("APPLE_ROOT_CA_BASE64");
  if (!boundedString(environment.MEAL_SCAN_PRINCIPAL_HMAC_SECRET, 32, 4096)) {
    missing.push("MEAL_SCAN_PRINCIPAL_HMAC_SECRET");
  }
  if (!boundedString(environment.GEMINI_API_KEY, 1, 4096)) missing.push("GEMINI_API_KEY");
  if (environment.MEAL_SCAN_QUOTA_STORE !== "firestore") missing.push("MEAL_SCAN_QUOTA_STORE=firestore");
  if (environment.MEAL_SCAN_RESULT_CACHE !== "firestore") missing.push("MEAL_SCAN_RESULT_CACHE=firestore");
  if (environment.MEAL_SCAN_IDEMPOTENCY_STORE !== "firestore") missing.push("MEAL_SCAN_IDEMPOTENCY_STORE=firestore");
  if (environment.MEAL_SCAN_REQUEST_GATE !== "firestore") missing.push("MEAL_SCAN_REQUEST_GATE=firestore");
  if (environment.MEAL_SCAN_BUDGET_STORE !== "firestore") missing.push("MEAL_SCAN_BUDGET_STORE=firestore");

  if (missing.length > 0) {
    throw new Error(`production meal scan configuration is incomplete: ${missing.join(", ")}`);
  }

  const numericEnvironmentKeys = [
    "MAX_BODY_BYTES",
    "MAX_IMAGE_BYTES",
    "MAX_IMAGE_PIXELS",
    "MAX_CANONICAL_IMAGE_BYTES",
    "MEAL_SCAN_RESULT_CACHE_TTL_SECONDS",
    "MEAL_SCAN_RESULT_LEASE_TTL_MS",
    "MEAL_SCAN_IDEMPOTENCY_PENDING_TTL_MS",
    "MEAL_SCAN_DAILY_LIMIT",
    "MEAL_SCAN_TRIAL_DAILY_LIMIT",
    "MEAL_SCAN_TRIAL_TOTAL_LIMIT",
    "MEAL_SCAN_REQUESTS_PER_MINUTE_LIMIT",
    "MEAL_SCAN_REQUESTS_PER_DAY_LIMIT",
    "MEAL_SCAN_GLOBAL_REQUESTS_PER_MINUTE_LIMIT",
    "MEAL_SCAN_GLOBAL_REQUESTS_PER_DAY_LIMIT",
    "APP_CHECK_TIMEOUT_MS",
    "GEMINI_TIMEOUT_MS",
  ];
  const invalid = numericEnvironmentKeys.filter((key) => {
    if (environment[key] === undefined) return false;
    const value = Number(environment[key]);
    return !Number.isSafeInteger(value) || value <= 0;
  });
  for (const [key, value] of Object.entries(numericConfiguration ?? {})) {
    if (!Number.isSafeInteger(value) || value <= 0) invalid.push(key);
  }
  if (
    Number.isSafeInteger(numericConfiguration?.resultLeaseTtlMs) &&
    Number.isSafeInteger(numericConfiguration?.geminiTimeoutMs) &&
    numericConfiguration.resultLeaseTtlMs < numericConfiguration.geminiTimeoutMs + 5_000
  ) {
    invalid.push("MEAL_SCAN_RESULT_LEASE_TTL_MS must exceed GEMINI_TIMEOUT_MS by at least 5000 ms");
  }
  if (
    Number.isSafeInteger(numericConfiguration?.idempotencyPendingTtlMs) &&
    Number.isSafeInteger(numericConfiguration?.geminiTimeoutMs) &&
    numericConfiguration.idempotencyPendingTtlMs < numericConfiguration.geminiTimeoutMs + 5_000
  ) {
    invalid.push("MEAL_SCAN_IDEMPOTENCY_PENDING_TTL_MS must exceed GEMINI_TIMEOUT_MS by at least 5000 ms");
  }
  if (numericConfiguration?.paidLimit > ABSOLUTE_PAID_ROLLING_LIMIT) {
    invalid.push(`MEAL_SCAN_DAILY_LIMIT must not exceed ${ABSOLUTE_PAID_ROLLING_LIMIT}`);
  }
  if (invalid.length > 0) {
    throw new Error(`production meal scan numeric configuration is invalid: ${[...new Set(invalid)].join(", ")}`);
  }
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
      maxOutputTokens: 1_600,
      responseMimeType: "application/json",
      responseSchema: mealEstimateSchema(),
    },
  };
}

function mealEstimateSchema() {
  return {
    type: "object",
    properties: {
      meal_name: { type: "string", minLength: 1, maxLength: 120 },
      confidence: { type: "string", enum: ["low", "medium", "high", "unknown"] },
      warnings: {
        type: "array",
        maxItems: 8,
        items: {
          type: "object",
          properties: {
            code: { type: "string", minLength: 1, maxLength: 32 },
            message: { type: "string", minLength: 1, maxLength: 240 },
          },
          required: ["code", "message"],
        },
      },
      items: {
        type: "array",
        maxItems: 20,
        items: {
          type: "object",
          properties: {
            display_name: { type: "string", minLength: 1, maxLength: 120 },
            canonical_query: { type: "string", minLength: 1, maxLength: 120 },
            estimated_grams: { type: "number", minimum: 1, maximum: 5_000 },
            serving_description: { type: "string", maxLength: 160 },
            confidence: { type: "string", enum: ["low", "medium", "high", "unknown"] },
            is_mixed_dish: { type: "boolean" },
            warning: { type: "string", maxLength: 240 },
            nutrition_fallback: {
              type: "object",
              nullable: true,
              properties: {
                calories_kcal: { type: "number", minimum: 0, maximum: 10_000 },
                protein_grams: { type: "number", minimum: 0, maximum: 1_000 },
                carbs_grams: { type: "number", minimum: 0, maximum: 2_000 },
                fat_grams: { type: "number", minimum: 0, maximum: 1_000 },
                fiber_grams: { type: "number", minimum: 0, maximum: 500 },
                sugar_grams: { type: "number", minimum: 0, maximum: 1_000 },
                sodium_mg: { type: "number", minimum: 0, maximum: 100_000 },
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

export async function callGemini({ modelId, payload, timeoutMs, apiKey = process.env.GEMINI_API_KEY }) {
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

function createConfiguredStoreKitVerifier(environment = process.env) {
  if (!environment.APPLE_ROOT_CA_BASE64) return null;
  const rootCertificates = environment.APPLE_ROOT_CA_BASE64
    .split(",")
    .map((value) => value.trim())
    .filter(Boolean)
    .map((value) => Buffer.from(value, "base64"));
  if (!rootCertificates.length || rootCertificates.some((certificate) => !certificate.length)) {
    throw new Error("APPLE_ROOT_CA_BASE64 is invalid");
  }
  const bundleId = environment.APPLE_BUNDLE_ID;
  if (!bundleId) return null;
  const appAppleId = Number(environment.APPLE_APP_ID);
  const verifiers = [];
  if (Number.isSafeInteger(appAppleId) && appAppleId > 0) {
    verifiers.push(
      new SignedDataVerifier(
        rootCertificates,
        true,
        Environment.PRODUCTION,
        bundleId,
        appAppleId
      )
    );
  }
  verifiers.push(
    new SignedDataVerifier(rootCertificates, true, Environment.SANDBOX, bundleId)
  );

  return {
    async verifyAndDecodeTransaction(signedTransactionJWS) {
      let firstError;
      for (const verifier of verifiers) {
        try {
          return await verifier.verifyAndDecodeTransaction(signedTransactionJWS);
        } catch (error) {
          firstError ??= error;
        }
      }
      throw firstError ?? new Error("StoreKit transaction verification failed");
    },
  };
}

function validateStoreKitTransaction(transaction, { bundleId, allowedProductIds, now }) {
  if (!isPlainObject(transaction)) {
    return { allowed: false, reason: "storekit_transaction_invalid" };
  }
  if (transaction.bundleId !== bundleId) {
    return { allowed: false, reason: "storekit_app_mismatch" };
  }
  if (!allowedProductIds.has(transaction.productId)) {
    return { allowed: false, reason: "storekit_product_mismatch" };
  }
  if (transaction.type !== "Auto-Renewable Subscription") {
    return { allowed: false, reason: "storekit_product_type_invalid" };
  }
  if (!boundedString(transaction.originalTransactionId, 1, 128)) {
    return { allowed: false, reason: "storekit_transaction_invalid" };
  }
  if (!new Set([Environment.PRODUCTION, Environment.SANDBOX]).has(transaction.environment)) {
    return { allowed: false, reason: "storekit_environment_invalid" };
  }
  if (Number.isFinite(transaction.revocationDate)) {
    return { allowed: false, reason: "transaction_revoked" };
  }
  if (transaction.isUpgraded === true) {
    return { allowed: false, reason: "subscription_upgraded" };
  }
  if (!Number.isFinite(transaction.expiresDate) || transaction.expiresDate <= now) {
    return { allowed: false, reason: "subscription_expired" };
  }
  return {
    allowed: true,
    tier:
      transaction.environment === Environment.SANDBOX || transaction.offerDiscountType === "FREE_TRIAL"
        ? "trial"
        : "paid",
  };
}

export function derivePurchasePrincipal({ originalTransactionId, environment, secret }) {
  if (!boundedString(originalTransactionId, 1, 128)) {
    throw new Error("verified originalTransactionId is required");
  }
  if (!new Set([Environment.PRODUCTION, Environment.SANDBOX]).has(environment)) {
    throw new Error("verified Apple environment is required");
  }
  if (!boundedString(secret, 32, 4096)) {
    throw new Error("purchase principal HMAC secret is invalid");
  }
  return crypto
    .createHmac("sha256", secret)
    .update(`storekit:${environment.toLowerCase()}:${originalTransactionId}`)
    .digest("hex");
}

async function processCanonicalJPEG({ bytes, maxPixels, maxCanonicalBytes, longEdge }) {
  try {
    const metadata = await sharp(bytes, {
      failOn: "error",
      limitInputPixels: false,
      sequentialRead: true,
    }).metadata();
    const sourceWidth = Number(metadata.width);
    const sourceHeight = Number(metadata.height);
    const sourcePixels = sourceWidth * sourceHeight;
    if (!Number.isSafeInteger(sourcePixels) || sourcePixels <= 0) {
      throw imageValidationError("jpeg image dimensions are invalid");
    }
    if (sourcePixels > maxPixels) {
      throw imageValidationError("jpeg image exceeds pixel limit");
    }
    const data = await sharp(bytes, {
      failOn: "error",
      limitInputPixels: maxPixels,
      sequentialRead: true,
    })
      .rotate()
      .resize({
        width: longEdge,
        height: longEdge,
        fit: "inside",
        withoutEnlargement: true,
      })
      .jpeg({
        quality: 82,
        chromaSubsampling: "4:2:0",
        progressive: false,
        optimiseCoding: true,
      })
      .toBuffer();
    if (data.length > maxCanonicalBytes) {
      throw imageValidationError("canonical jpeg exceeds size limit");
    }
    return { data, sourceWidth, sourceHeight };
  } catch (error) {
    if (error?.detail) throw error;
    throw imageValidationError("jpeg image could not be decoded");
  }
}

function imageValidationError(detail) {
  const error = new Error(detail);
  error.code = "INVALID_IMAGE";
  error.detail = detail;
  return error;
}

function canonicalRequestHash({ principal, imageHash, mealType, locale, schemaVersion, promptVersion }) {
  return crypto
    .createHash("sha256")
    .update(JSON.stringify({
      principal,
      imageHash,
      mealType,
      locale,
      schemaVersion,
      promptVersion,
      modelId: DEFAULT_MODEL_ID,
    }))
    .digest("hex");
}

function fixedModelSelection() {
  return {
    modelId: DEFAULT_MODEL_ID,
    requestedModelId: null,
    selectionReason: "server_pinned_model",
    config: MODEL_CONFIGS[DEFAULT_MODEL_ID],
  };
}

function assertEstimateBounds(estimate) {
  const fail = () => {
    const error = new Error("provider response exceeds the public response contract");
    error.code = "PROVIDER_RESPONSE_OUT_OF_BOUNDS";
    throw error;
  };
  if (!isPlainObject(estimate)) fail();
  if (!boundedString(estimate.meal_name, 1, 120)) fail();
  if (!new Set(["low", "medium", "high", "unknown"]).has(estimate.confidence)) fail();
  if (!Array.isArray(estimate.warnings) || estimate.warnings.length > 8) fail();
  if (!Array.isArray(estimate.items) || estimate.items.length > 20) fail();
  for (const warning of estimate.warnings) {
    if (
      !isPlainObject(warning) ||
      !boundedString(warning.code, 1, 32) ||
      !boundedString(warning.message, 1, 240)
    ) fail();
  }
  for (const item of estimate.items) {
    if (
      !isPlainObject(item) ||
      !boundedString(item.display_name, 1, 120) ||
      !boundedString(item.canonical_query, 1, 120) ||
      !Number.isFinite(item.estimated_grams) ||
      item.estimated_grams < 1 ||
      item.estimated_grams > 5_000 ||
      !new Set(["low", "medium", "high", "unknown"]).has(item.confidence) ||
      typeof item.is_mixed_dish !== "boolean" ||
      (item.serving_description !== undefined && !boundedString(item.serving_description, 0, 160)) ||
      (item.warning !== undefined && !boundedString(item.warning, 0, 240))
    ) fail();
  }
  if (Buffer.byteLength(JSON.stringify(estimate), "utf8") > 65_536) fail();
}

function identifierFreeMetric({ modelId, usage, quota, tier, budget, cacheHit }) {
  return {
    providerId: PROVIDER_ID,
    modelId,
    promptTokens: numberOrNull(usage?.inputTokens),
    outputTokens: numberOrNull(usage?.outputTokens),
    estimatedCostUSD: numberOrNull(usage?.estimatedCostUSD),
    quotaUsed: numberOrNull(quota?.used),
    quotaLimit: numberOrNull(quota?.limit),
    tier,
    budgetMode: budget.mode,
    cacheHit,
  };
}

function safeErrorCode(error) {
  return typeof error?.code === "string" ? error.code : "UNEXPECTED";
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

function createConfiguredRequestGate(environment = process.env) {
  const minuteLimit = positiveInteger(environment.MEAL_SCAN_REQUESTS_PER_MINUTE_LIMIT, 30);
  const dayLimit = positiveInteger(environment.MEAL_SCAN_REQUESTS_PER_DAY_LIMIT, 200);
  const globalMinuteLimit = positiveInteger(environment.MEAL_SCAN_GLOBAL_REQUESTS_PER_MINUTE_LIMIT, 300);
  const globalDayLimit = positiveInteger(environment.MEAL_SCAN_GLOBAL_REQUESTS_PER_DAY_LIMIT, 3_000);
  if (environment.MEAL_SCAN_REQUEST_GATE === "firestore") {
    return createFirestoreRequestGate({
      collectionName: requestGateCollectionName(environment),
      minuteLimit,
      dayLimit,
      globalMinuteLimit,
      globalDayLimit,
    });
  }
  return createInMemoryRequestGate({ minuteLimit, dayLimit, globalMinuteLimit, globalDayLimit });
}

export function requestGateCollectionName(environment = process.env) {
  return environment.MEAL_SCAN_REQUEST_GATE_COLLECTION?.trim() || "mealScanRequestGate";
}

export function createInMemoryRequestGate({ minuteLimit, dayLimit, globalMinuteLimit, globalDayLimit }) {
  const records = new Map();
  let globalRecord;
  return {
    async checkAndConsume({ appUserId }) {
      const now = new Date();
      const minute = now.toISOString().slice(0, 16);
      const day = now.toISOString().slice(0, 10);
      const key = shortHash(appUserId);
      const existing = records.get(key);
      const minuteCount = existing?.minute === minute ? existing.minuteCount : 0;
      const dayCount = existing?.day === day ? existing.dayCount : 0;
      const globalMinuteCount = globalRecord?.minute === minute ? globalRecord.minuteCount : 0;
      const globalDayCount = globalRecord?.day === day ? globalRecord.dayCount : 0;
      const userAllowed = minuteCount + 1 <= minuteLimit && dayCount + 1 <= dayLimit;
      const globalAllowed =
        globalMinuteCount + 1 <= globalMinuteLimit && globalDayCount + 1 <= globalDayLimit;
      const allowed = userAllowed && globalAllowed;
      if (allowed) {
        records.set(key, {
          minute,
          minuteCount: minuteCount + 1,
          day,
          dayCount: dayCount + 1,
        });
        globalRecord = {
          minute,
          minuteCount: globalMinuteCount + 1,
          day,
          dayCount: globalDayCount + 1,
        };
      }
      return {
        allowed,
        reason: allowed ? null : (globalAllowed ? "request_limit_exceeded" : "global_request_limit_exceeded"),
        remainingMinute: Math.max(0, minuteLimit - (allowed ? minuteCount + 1 : minuteCount)),
        remainingDay: Math.max(0, dayLimit - (allowed ? dayCount + 1 : dayCount)),
        remainingGlobalMinute: Math.max(
          0,
          globalMinuteLimit - (allowed ? globalMinuteCount + 1 : globalMinuteCount)
        ),
        remainingGlobalDay: Math.max(0, globalDayLimit - (allowed ? globalDayCount + 1 : globalDayCount)),
        retryAfterSeconds: requestRetryAfterSeconds({
          now,
          minuteExceeded: minuteCount + 1 > minuteLimit || globalMinuteCount + 1 > globalMinuteLimit,
        }),
      };
    },
  };
}

function createFirestoreRequestGate({
  collectionName,
  minuteLimit,
  dayLimit,
  globalMinuteLimit,
  globalDayLimit,
}) {
  let firestoreClient;
  async function firestore() {
    if (!firestoreClient) {
      const { Firestore } = await import("@google-cloud/firestore");
      firestoreClient = new Firestore();
    }
    return firestoreClient;
  }

  return {
    async checkAndConsume({ appUserId }) {
      const db = await firestore();
      const now = new Date();
      const day = now.toISOString().slice(0, 10);
      const minute = now.toISOString().slice(0, 16);
      const appUserHash = shortHash(appUserId);
      const dailyDoc = db.collection(collectionName).doc(`${appUserHash}_${day}`);
      const globalDoc = db.collection(collectionName).doc(`global_${day}`);

      return db.runTransaction(async (transaction) => {
        const snapshot = await transaction.get(dailyDoc);
        const globalSnapshot = await transaction.get(globalDoc);
        const currentMinuteCount = snapshot.exists && snapshot.get("requestMinute") === minute
          ? Number(snapshot.get("requestMinuteCount") ?? 0)
          : 0;
        const currentDayCount = snapshot.exists ? Number(snapshot.get("requestCount") ?? 0) : 0;
        const nextMinuteCount = currentMinuteCount + 1;
        const nextDayCount = currentDayCount + 1;
        const currentGlobalMinuteCount =
          globalSnapshot.exists && globalSnapshot.get("requestMinute") === minute
            ? Number(globalSnapshot.get("requestMinuteCount") ?? 0)
            : 0;
        const currentGlobalDayCount = globalSnapshot.exists
          ? Number(globalSnapshot.get("requestCount") ?? 0)
          : 0;
        const nextGlobalMinuteCount = currentGlobalMinuteCount + 1;
        const nextGlobalDayCount = currentGlobalDayCount + 1;
        const minuteAllowed = nextMinuteCount <= minuteLimit;
        const dayAllowed = nextDayCount <= dayLimit;
        const globalMinuteAllowed = nextGlobalMinuteCount <= globalMinuteLimit;
        const globalDayAllowed = nextGlobalDayCount <= globalDayLimit;
        const globalAllowed = globalMinuteAllowed && globalDayAllowed;
        const allowed = minuteAllowed && dayAllowed && globalAllowed;

        if (allowed) {
          transaction.set(
            dailyDoc,
            {
              appUserHash,
              day,
              requestMinute: minute,
              requestMinuteCount: nextMinuteCount,
              requestCount: nextDayCount,
              requestMinuteLimit: minuteLimit,
              requestDayLimit: dayLimit,
              updatedAt: now.toISOString(),
              expiresAt: retainedExpiry(snapshot.get("expiresAt"), quotaExpiryDates(now).daily),
            },
            { merge: true }
          );
          transaction.set(
            globalDoc,
            {
              scope: "global",
              day,
              requestMinute: minute,
              requestMinuteCount: nextGlobalMinuteCount,
              requestCount: nextGlobalDayCount,
              requestMinuteLimit: globalMinuteLimit,
              requestDayLimit: globalDayLimit,
              updatedAt: now.toISOString(),
              expiresAt: retainedExpiry(globalSnapshot.get("expiresAt"), quotaExpiryDates(now).daily),
            },
            { merge: true }
          );
        }

        return {
          allowed,
          reason: allowed ? null : (globalAllowed ? "request_limit_exceeded" : "global_request_limit_exceeded"),
          remainingMinute: Math.max(0, minuteLimit - (allowed ? nextMinuteCount : currentMinuteCount)),
          remainingDay: Math.max(0, dayLimit - (allowed ? nextDayCount : currentDayCount)),
          remainingGlobalMinute: Math.max(
            0,
            globalMinuteLimit - (allowed ? nextGlobalMinuteCount : currentGlobalMinuteCount)
          ),
          remainingGlobalDay: Math.max(
            0,
            globalDayLimit - (allowed ? nextGlobalDayCount : currentGlobalDayCount)
          ),
          retryAfterSeconds: requestRetryAfterSeconds({
            now,
            minuteExceeded: !minuteAllowed || !globalMinuteAllowed,
          }),
        };
      });
    },
  };
}

function requestRetryAfterSeconds({ now, minuteExceeded }) {
  if (minuteExceeded) {
    return Math.max(1, 60 - now.getUTCSeconds());
  }
  const nextDay = new Date(now);
  nextDay.setUTCHours(24, 0, 0, 0);
  return Math.max(1, Math.ceil((nextDay.getTime() - now.getTime()) / 1000));
}

function createConfiguredQuotaStore(environment = process.env) {
  if (environment.MEAL_SCAN_QUOTA_STORE === "firestore") {
    return createFirestoreRollingQuotaStore({
      collectionName: environment.MEAL_SCAN_QUOTA_COLLECTION ?? "mealScanRollingQuota",
    });
  }
  return createInMemoryRollingQuotaStore();
}

export function createInMemoryRollingQuotaStore({ now = Date.now } = {}) {
  const records = new Map();
  return {
    async checkAndConsume(input) {
      const timestamp = numericTimestamp(now());
      const existing = records.get(input.principal) ?? { events: [], lifetimeUsed: 0 };
      const activeEvents = activeRollingEvents(existing.events, timestamp);
      const rollingAllowed = activeEvents.length < input.limit;
      const lifetimeAllowed =
        input.lifetimeLimit === null || existing.lifetimeUsed < input.lifetimeLimit;
      const allowed = rollingAllowed && lifetimeAllowed;
      if (allowed) {
        activeEvents.push(timestamp);
        records.set(input.principal, {
          events: activeEvents,
          lifetimeUsed:
            input.lifetimeLimit === null ? existing.lifetimeUsed : existing.lifetimeUsed + 1,
        });
      } else {
        records.set(input.principal, { ...existing, events: activeEvents });
      }
      return rollingQuotaSnapshot({
        ...input,
        events: activeEvents,
        timestamp,
        allowed,
        reason: rollingAllowed ? "trial_lifetime_quota_exceeded" : "rolling_quota_exceeded",
      });
    },
    async current(input) {
      const timestamp = numericTimestamp(now());
      const existing = records.get(input.principal) ?? { events: [], lifetimeUsed: 0 };
      const activeEvents = activeRollingEvents(existing.events, timestamp);
      records.set(input.principal, { ...existing, events: activeEvents });
      return rollingQuotaSnapshot({
        ...input,
        events: activeEvents,
        timestamp,
        allowed: true,
        reason: null,
      });
    },
  };
}

function createFirestoreRollingQuotaStore({ collectionName }) {
  let firestoreClient;
  async function firestore() {
    if (!firestoreClient) {
      const { Firestore } = await import("@google-cloud/firestore");
      firestoreClient = new Firestore();
    }
    return firestoreClient;
  }

  return {
    async checkAndConsume(input) {
      const db = await firestore();
      const document = db.collection(collectionName).doc(input.principal);
      return db.runTransaction(async (transaction) => {
        const snapshot = await transaction.get(document);
        const timestamp = Date.now();
        const storedEvents = snapshot.exists && Array.isArray(snapshot.get("dispatchTimestamps"))
          ? snapshot.get("dispatchTimestamps")
          : [];
        const activeEvents = activeRollingEvents(storedEvents, timestamp);
        const lifetimeUsed = snapshot.exists ? Number(snapshot.get("lifetimeUsed") ?? 0) : 0;
        const rollingAllowed = activeEvents.length < input.limit;
        const lifetimeAllowed = input.lifetimeLimit === null || lifetimeUsed < input.lifetimeLimit;
        const allowed = rollingAllowed && lifetimeAllowed;
        if (allowed) activeEvents.push(timestamp);
        const record = {
          tier: input.tier,
          dispatchTimestamps: activeEvents.map((value) => new Date(value)),
          lifetimeUsed:
            input.lifetimeLimit === null ? lifetimeUsed : lifetimeUsed + (allowed ? 1 : 0),
          rollingLimit: input.limit,
          lifetimeLimit: input.lifetimeLimit,
          updatedAt: new Date(timestamp),
        };
        if (input.lifetimeLimit === null) {
          record.expiresAt = new Date(timestamp + 3 * ROLLING_WINDOW_SECONDS * 1_000);
        }
        transaction.set(document, record, { merge: true });
        return rollingQuotaSnapshot({
          ...input,
          events: activeEvents,
          timestamp,
          allowed,
          reason: rollingAllowed ? "trial_lifetime_quota_exceeded" : "rolling_quota_exceeded",
        });
      });
    },
    async current(input) {
      const db = await firestore();
      const document = db.collection(collectionName).doc(input.principal);
      const snapshot = await document.get();
      const timestamp = Date.now();
      const storedEvents = snapshot.exists && Array.isArray(snapshot.get("dispatchTimestamps"))
        ? snapshot.get("dispatchTimestamps")
        : [];
      return rollingQuotaSnapshot({
        ...input,
        events: activeRollingEvents(storedEvents, timestamp),
        timestamp,
        allowed: true,
        reason: null,
      });
    },
  };
}

function activeRollingEvents(events, timestamp) {
  const cutoff = timestamp - ROLLING_WINDOW_SECONDS * 1_000;
  return events
    .map((value) => numericTimestamp(value))
    .filter((value) => Number.isFinite(value) && value > cutoff && value <= timestamp)
    .sort((left, right) => left - right);
}

function numericTimestamp(value) {
  if (Number.isFinite(value)) return Number(value);
  const date = value?.toDate?.() ?? new Date(value);
  return date.getTime();
}

function rollingQuotaSnapshot({ tier, limit, events, timestamp, allowed, reason }) {
  const used = events.length;
  const resetTimestamp = used > 0 ? events[0] + ROLLING_WINDOW_SECONDS * 1_000 : null;
  const exhausted = used >= limit;
  return {
    allowed,
    reason: allowed ? null : reason,
    tier,
    used,
    limit,
    remaining: Math.max(0, limit - used),
    windowSeconds: ROLLING_WINDOW_SECONDS,
    resetAt: resetTimestamp === null ? null : new Date(resetTimestamp).toISOString(),
    retryAfterSeconds:
      exhausted && resetTimestamp !== null
        ? Math.max(1, Math.ceil((resetTimestamp - timestamp) / 1_000))
        : null,
  };
}

export function quotaExpiryDates(now) {
  return {
    daily: new Date(now.getTime() + 3 * 86_400_000),
    trial: new Date(now.getTime() + 30 * 86_400_000),
  };
}

function retainedExpiry(existingExpiry, fallback) {
  const parsed = existingExpiry?.toDate?.() ?? (existingExpiry ? new Date(existingExpiry) : null);
  return parsed && Number.isFinite(parsed.getTime()) ? parsed : fallback;
}

function createConfiguredIdempotencyStore({ environment, pendingTtlMs }) {
  if (environment.MEAL_SCAN_IDEMPOTENCY_STORE === "firestore") {
    return createFirestoreIdempotencyStore({
      collectionName: environment.MEAL_SCAN_IDEMPOTENCY_COLLECTION ?? "mealScanIdempotency",
      pendingTtlMs,
    });
  }
  return createInMemoryIdempotencyStore({ pendingTtlMs });
}

export function createInMemoryIdempotencyStore({ pendingTtlMs = 30_000, now = Date.now } = {}) {
  const records = new Map();
  return {
    async claim({ requestId, requestHash }) {
      const timestamp = numericTimestamp(now());
      const existing = records.get(requestId);
      if (existing) {
        if (existing.requestHash !== requestHash) return { state: "mismatch", acquired: false };
        if (existing.state === "pending" && existing.pendingExpiresAt <= timestamp) {
          existing.state = "unknown";
          existing.updatedAt = timestamp;
        }
        return existing.state === "completed"
          ? { state: "completed", acquired: false, response: structuredClone(existing.response) }
          : { state: existing.state, acquired: false };
      }
      const claimId = crypto.randomUUID();
      records.set(requestId, {
        requestHash,
        claimId,
        state: "pending",
        pendingExpiresAt: timestamp + pendingTtlMs,
        updatedAt: timestamp,
      });
      return { requestId, requestHash, claimId, state: "pending", acquired: true };
    },
    async complete(context, response) {
      const existing = records.get(context.requestId);
      assertActiveIdempotencyClaim(existing, context);
      records.set(context.requestId, {
        ...existing,
        state: "completed",
        response: structuredClone(response),
        updatedAt: numericTimestamp(now()),
      });
    },
    async markUnknown(context) {
      const existing = records.get(context.requestId);
      assertActiveIdempotencyClaim(existing, context);
      records.set(context.requestId, {
        ...existing,
        state: "unknown",
        updatedAt: numericTimestamp(now()),
      });
    },
    async abandon(context) {
      const existing = records.get(context.requestId);
      if (activeIdempotencyClaim(existing, context)) records.delete(context.requestId);
    },
  };
}

function createFirestoreIdempotencyStore({ collectionName, pendingTtlMs }) {
  let firestoreClient;
  async function firestore() {
    if (!firestoreClient) {
      const { Firestore } = await import("@google-cloud/firestore");
      firestoreClient = new Firestore();
    }
    return firestoreClient;
  }
  const documentId = (requestId) => crypto.createHash("sha256").update(requestId).digest("hex");

  return {
    async claim({ requestId, requestHash }) {
      const db = await firestore();
      const document = db.collection(collectionName).doc(documentId(requestId));
      return db.runTransaction(async (transaction) => {
        const snapshot = await transaction.get(document);
        const timestamp = Date.now();
        if (snapshot.exists) {
          if (snapshot.get("requestHash") !== requestHash) {
            return { state: "mismatch", acquired: false };
          }
          let state = snapshot.get("state");
          const pendingExpiresAt = numericTimestamp(snapshot.get("pendingExpiresAt"));
          if (state === "pending" && pendingExpiresAt <= timestamp) {
            state = "unknown";
            transaction.set(document, { state, updatedAt: new Date(timestamp) }, { merge: true });
          }
          return state === "completed"
            ? { state, acquired: false, response: snapshot.get("response") }
            : { state, acquired: false };
        }
        const claimId = crypto.randomUUID();
        transaction.create(document, {
          requestHash,
          claimId,
          state: "pending",
          createdAt: new Date(timestamp),
          updatedAt: new Date(timestamp),
          pendingExpiresAt: new Date(timestamp + pendingTtlMs),
          expiresAt: new Date(timestamp + 7 * 86_400_000),
        });
        return {
          requestId,
          requestHash,
          documentId: document.id,
          claimId,
          state: "pending",
          acquired: true,
        };
      });
    },
    async complete(context, response) {
      await updateFirestoreIdempotencyClaim({
        firestore: await firestore(),
        collectionName,
        documentId: context.documentId,
        context,
        update: { state: "completed", response: structuredClone(response) },
      });
    },
    async markUnknown(context) {
      await updateFirestoreIdempotencyClaim({
        firestore: await firestore(),
        collectionName,
        documentId: context.documentId,
        context,
        update: { state: "unknown" },
      });
    },
    async abandon(context) {
      const db = await firestore();
      const document = db.collection(collectionName).doc(context.documentId);
      await db.runTransaction(async (transaction) => {
        const snapshot = await transaction.get(document);
        if (
          snapshot.exists &&
          snapshot.get("state") === "pending" &&
          snapshot.get("claimId") === context.claimId &&
          snapshot.get("requestHash") === context.requestHash
        ) {
          transaction.delete(document);
        }
      });
    },
  };
}

async function updateFirestoreIdempotencyClaim({
  firestore,
  collectionName,
  documentId,
  context,
  update,
}) {
  const document = firestore.collection(collectionName).doc(documentId);
  await firestore.runTransaction(async (transaction) => {
    const snapshot = await transaction.get(document);
    if (
      !snapshot.exists ||
      snapshot.get("state") !== "pending" ||
      snapshot.get("claimId") !== context.claimId ||
      snapshot.get("requestHash") !== context.requestHash
    ) {
      throw idempotencyClaimError();
    }
    transaction.set(document, { ...update, updatedAt: new Date() }, { merge: true });
  });
}

function activeIdempotencyClaim(existing, context) {
  return Boolean(
    existing &&
      existing.state === "pending" &&
      existing.claimId === context.claimId &&
      existing.requestHash === context.requestHash
  );
}

function assertActiveIdempotencyClaim(existing, context) {
  if (!activeIdempotencyClaim(existing, context)) throw idempotencyClaimError();
}

function idempotencyClaimError() {
  const error = new Error("idempotency claim is no longer active");
  error.code = "IDEMPOTENCY_CLAIM_LOST";
  return error;
}

function createConfiguredResultCache({ environment, ttlMs, leaseTtlMs }) {
  const backend = environment.MEAL_SCAN_RESULT_CACHE ?? environment.MEAL_SCAN_QUOTA_STORE;
  if (backend === "firestore") {
    return createFirestoreResultCache({
      collectionName: environment.MEAL_SCAN_RESULT_CACHE_COLLECTION ?? "mealScanEstimateCache",
      ttlMs,
      leaseTtlMs,
    });
  }
  return createInMemoryResultCache({ ttlMs, leaseTtlMs });
}

function createInMemoryResultCache({ ttlMs, leaseTtlMs }) {
  const records = new Map();
  const leases = new Map();
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
    async acquireLease(input) {
      const key = resultCacheKey(input);
      const record = records.get(key);
      if (record && record.expiresAt > Date.now()) {
        return { acquired: false, value: record.value };
      }
      const activeLease = leases.get(key);
      if (activeLease && activeLease.expiresAt > Date.now()) {
        return { acquired: false };
      }
      const leaseId = crypto.randomUUID();
      leases.set(key, { leaseId, expiresAt: Date.now() + leaseTtlMs });
      return { acquired: true, leaseId };
    },
    async set(input, value, { leaseId } = {}) {
      const key = resultCacheKey(input);
      const activeLease = leases.get(key);
      if (leaseId && activeLease?.leaseId !== leaseId) {
        return false;
      }
      records.set(key, {
        value,
        expiresAt: Date.now() + ttlMs,
      });
      leases.delete(key);
      return true;
    },
    async releaseLease(input, leaseId) {
      const key = resultCacheKey(input);
      if (leases.get(key)?.leaseId === leaseId) {
        leases.delete(key);
      }
    },
  };
}

function createFirestoreResultCache({ collectionName, ttlMs, leaseTtlMs }) {
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
    async acquireLease(input) {
      const db = await firestore();
      const document = db.collection(collectionName).doc(resultCacheKey(input));
      return db.runTransaction(async (transaction) => {
        const snapshot = await transaction.get(document);
        const now = Date.now();
        const resultExpiresAtValue = snapshot.get("expiresAt");
        const resultExpiresAt = resultExpiresAtValue?.toDate?.() ?? new Date(resultExpiresAtValue);
        const existingValue = snapshot.get("value") ?? null;
        if (existingValue && Number.isFinite(resultExpiresAt.getTime()) && resultExpiresAt.getTime() > now) {
          return { acquired: false, value: existingValue };
        }

        const leaseExpiresAtValue = snapshot.get("leaseExpiresAt");
        const leaseExpiresAt = leaseExpiresAtValue?.toDate?.() ?? new Date(leaseExpiresAtValue);
        if (Number.isFinite(leaseExpiresAt.getTime()) && leaseExpiresAt.getTime() > now) {
          return { acquired: false };
        }

        const leaseId = crypto.randomUUID();
        const leaseExpiry = new Date(now + leaseTtlMs);
        transaction.set(
          document,
          {
            appUserHash: shortHash(input.appUserId),
            imageHashPrefix: String(input.imageHash).slice(0, 12),
            modelId: input.modelId,
            schemaVersion: input.schemaVersion ?? null,
            promptVersion: input.promptVersion ?? null,
            mealType: input.mealType ?? null,
            locale: input.locale ?? null,
            leaseId,
            leaseExpiresAt: leaseExpiry,
            expiresAt: leaseExpiry,
          },
          { merge: true }
        );
        return { acquired: true, leaseId };
      });
    },
    async set(input, value, { leaseId } = {}) {
      const db = await firestore();
      const document = db.collection(collectionName).doc(resultCacheKey(input));
      return db.runTransaction(async (transaction) => {
        const snapshot = await transaction.get(document);
        if (leaseId && snapshot.get("leaseId") !== leaseId) {
          return false;
        }
        transaction.set(document, {
          appUserHash: shortHash(input.appUserId),
          imageHashPrefix: String(input.imageHash).slice(0, 12),
          modelId: input.modelId,
          schemaVersion: input.schemaVersion ?? null,
          promptVersion: input.promptVersion ?? null,
          mealType: input.mealType ?? null,
          locale: input.locale ?? null,
          value: JSON.parse(JSON.stringify(value)),
          createdAt: new Date(),
          expiresAt: new Date(Date.now() + ttlMs),
        });
        return true;
      });
    },
    async releaseLease(input, leaseId) {
      if (!leaseId) return;
      const db = await firestore();
      const document = db.collection(collectionName).doc(resultCacheKey(input));
      await db.runTransaction(async (transaction) => {
        const snapshot = await transaction.get(document);
        if (snapshot.get("leaseId") === leaseId && !snapshot.get("value")) {
          transaction.delete(document);
        }
      });
    },
  };
}

function resultCacheKey({ appUserId, imageHash, modelId, schemaVersion, promptVersion, mealType, locale }) {
  return crypto
    .createHash("sha256")
    .update([
      appUserId,
      imageHash,
      modelId,
      schemaVersion ?? "",
      promptVersion ?? "",
      mealType ?? "",
      locale ?? "",
    ].join("|"))
    .digest("hex");
}

async function waitForCachedResult(resultCache, input, { timeoutMs = 2_000, pollMs = 25 } = {}) {
  const deadline = Date.now() + timeoutMs;
  while (Date.now() < deadline) {
    await new Promise((resolve) => setTimeout(resolve, pollMs));
    const value = await resultCache.get(input);
    if (value) return value;
  }
  return null;
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

function quotaResponse(quota, accessTier) {
  const limit = numberOrNull(quota.limit);
  const used = numberOrNull(quota.used);
  return {
    tier: quota.tier ?? accessTier,
    used,
    limit,
    remaining:
      numberOrNull(quota.remaining ?? quota.remainingToday) ??
      (limit !== null && used !== null ? Math.max(0, limit - Math.min(used, limit)) : null),
    windowSeconds: numberOrNull(quota.windowSeconds) ?? ROLLING_WINDOW_SECONDS,
    resetAt:
      typeof quota.resetAt === "string"
        ? quota.resetAt
        : quota.resetAt instanceof Date
          ? quota.resetAt.toISOString()
          : null,
    retryAfterSeconds: numberOrNull(quota.retryAfterSeconds),
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
  if (value === null || value === undefined || value === "") return null;
  return Number.isFinite(Number(value)) ? Number(value) : null;
}

function positiveInteger(value, fallback) {
  const parsed = Number.parseInt(value ?? String(fallback), 10);
  return Number.isInteger(parsed) && parsed > 0 ? parsed : fallback;
}

function boundedPositiveInteger(value, fallback, maximum, label) {
  const parsed = value === undefined ? fallback : Number(value);
  if (!Number.isSafeInteger(parsed) || parsed <= 0 || parsed > maximum) {
    throw new Error(`${label} must be a positive integer no greater than ${maximum}`);
  }
  return parsed;
}

function roundCurrency(value) {
  return Number(value.toFixed(10));
}

function headerValue(value) {
  return Array.isArray(value) ? value[0] : typeof value === "string" ? value : undefined;
}

function validatePayload(payload, { maxImageBytes = MAX_DECODED_IMAGE_BYTES } = {}) {
  if (!isPlainObject(payload)) return { ok: false, detail: "body must be JSON object" };
  if (Object.hasOwn(payload, "revenueCatAppUserId")) {
    return { ok: false, detail: "revenueCatAppUserId is not allowed" };
  }
  if (Object.hasOwn(payload, "modelId")) {
    return { ok: false, detail: "modelId is not allowed" };
  }
  const allowedKeys = new Set([
    "requestId",
    "signedTransactionJWS",
    "mealType",
    "locale",
    "schemaVersion",
    "promptVersion",
    "image",
  ]);
  if (Object.keys(payload).some((key) => !allowedKeys.has(key))) {
    return { ok: false, detail: "request contains unsupported fields" };
  }
  if (
    !boundedString(payload.requestId, 36, 36) ||
    !/^[0-9a-f]{8}-[0-9a-f]{4}-[1-8][0-9a-f]{3}-[89ab][0-9a-f]{3}-[0-9a-f]{12}$/i.test(payload.requestId)
  ) {
    return { ok: false, detail: "requestId is invalid" };
  }
  if (
    !boundedString(payload.signedTransactionJWS, 3, 32_768) ||
    payload.signedTransactionJWS.split(".").length !== 3
  ) {
    return { ok: false, detail: "signedTransactionJWS is invalid" };
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
  if (
    !isPlainObject(payload.image) ||
    Object.keys(payload.image).some((key) => !new Set(["mimeType", "base64", "sha256"]).has(key)) ||
    payload.image.mimeType !== "image/jpeg"
  ) {
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
  return { ok: true, imageBytes };
}

function isPlainObject(value) {
  return value !== null && typeof value === "object" && !Array.isArray(value);
}

function boundedString(value, minimumLength, maximumLength) {
  return typeof value === "string" && value.length >= minimumLength && value.length <= maximumLength;
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

    const billingIsMoreRestrictive =
      manualMode && billingMode && budgetModeRank(billingMode) > budgetModeRank(manualMode);
    cached = normalizeBudgetState({
      ...control,
      mode: mostRestrictiveBudgetMode(manualMode, billingMode),
      source: billingIsMoreRestrictive
        ? "fail_closed_combined_control"
        : (manualMode ? "manual_override" : "cloud_billing_budget"),
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
    source: "static_environment",
  }, environment);
}

function normalizeBudgetState(input, environment = process.env) {
  const spendUsd = numberOrNull(input?.spendUsd) ?? 0;
  const alertAtUsd =
    numberOrNull(input?.alertAtUsd) ??
    numberOrNull(environment.MEAL_SCAN_MONTHLY_BUDGET_ALERT_USD) ??
    DEFAULT_BUDGET_ALERT_USD;
  const degradeAtUsd =
    numberOrNull(input?.degradeAtUsd) ??
    numberOrNull(environment.MEAL_SCAN_MONTHLY_BUDGET_DEGRADE_USD) ??
    DEFAULT_BUDGET_DEGRADE_USD;
  const disableAtUsd =
    numberOrNull(input?.disableAtUsd) ??
    numberOrNull(environment.MEAL_SCAN_MONTHLY_BUDGET_DISABLE_USD) ??
    DEFAULT_BUDGET_DISABLE_USD;
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

export function classifyBudgetSpend(spendUsd) {
  return normalizeBudgetState({ spendUsd, source: "static_environment" }, {});
}

function validBudgetMode(mode) {
  return ["normal", "alert", "degraded", "disabled"].includes(mode);
}

function budgetModeRank(mode) {
  return ["normal", "alert", "degraded", "disabled"].indexOf(mode);
}

function mostRestrictiveBudgetMode(...modes) {
  return modes
    .filter(validBudgetMode)
    .sort((left, right) => budgetModeRank(right) - budgetModeRank(left))[0] ?? null;
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
