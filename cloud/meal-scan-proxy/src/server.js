import http from "node:http";
import crypto from "node:crypto";
import { readFileSync } from "node:fs";
import path from "node:path";
import { fileURLToPath } from "node:url";
import {
  AppStoreServerAPIClient,
  Environment,
  SignedDataVerifier,
  Status,
  VerificationStatus,
} from "@apple/app-store-server-library";
import sharp from "sharp";

const MODULE_DIRECTORY = path.dirname(fileURLToPath(import.meta.url));

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
const PINNED_APPLE_BUNDLE_ID = "alex.PCOS";
const PINNED_APPLE_APP_ID = 6_760_353_511;
const PINNED_APPLE_PRODUCT_IDS = new Set([
  "cyclebalance.premium.monthly",
  "cyclebalance.premium.annual",
]);
const PINNED_REVENUECAT_PROJECT_ID = "proj8da4e000";
const PINNED_REVENUECAT_ENTITLEMENT_ID = "CycleBalance Unlimited";
const DEFAULT_REVENUECAT_TIMEOUT_MS = 3_000;
const MAX_REVENUECAT_TIMEOUT_MS = 5_000;
const MAX_REVENUECAT_RESPONSE_BYTES = 256_000;
const MAX_PRINCIPAL_ATTEMPTS_PER_MINUTE = 3;
const MAX_PRINCIPAL_ATTEMPTS_PER_24_HOURS = 30;
const MAX_GLOBAL_PROVIDER_DISPATCHES_PER_MINUTE = 60;
const MAX_GLOBAL_PROVIDER_DISPATCHES_PER_24_HOURS = 1_000;
const DEFAULT_BUDGET_STATE_MAX_AGE_SECONDS = 86_400;
const NUTRITION_FALLBACK_BOUNDS = Object.freeze([
  ["calories_kcal", 0, 10_000],
  ["protein_grams", 0, 1_000],
  ["carbs_grams", 0, 2_000],
  ["fat_grams", 0, 1_000],
  ["fiber_grams", 0, 500],
  ["sugar_grams", 0, 1_000],
  ["sodium_mg", 0, 100_000],
]);
const SCANNER_EVENT_SCHEMA_VERSION = "cyclebalance.meal_scan.operation.v1";
const SCANNER_RESPONSE_OBSERVER = Symbol("cyclebalanceScannerResponseObserver");
const SAFE_SCANNER_REASONS = new Set([
  "app_check_app_mismatch",
  "app_check_rejected",
  "app_check_required",
  "app_check_token_replayed",
  "app_check_verifier_unconfigured",
  "app_integrity_required",
  "body_size_limit",
  "budget_control_unavailable",
  "cache_control_unavailable",
  "duplicate_request_in_progress",
  "feature_disabled",
  "global_provider_dispatch_limit_exceeded",
  "global_provider_minute_limit_exceeded",
  "global_provider_rolling_limit_exceeded",
  "global_request_limit_exceeded",
  "idempotency_conflict",
  "integrity_failed",
  "integrity_service_timeout",
  "invalid_json",
  "invalid_request",
  "meal_scan_in_progress",
  "meal_scan_outcome_unknown",
  "meal_scan_parse_error",
  "meal_scan_provider_error",
  "meal_scan_proxy_error",
  "meal_scan_request_rate_limited",
  "meal_scan_unavailable",
  "monthly_budget_exceeded",
  "not_found",
  "other",
  "premium_entitlement_required",
  "previous_dispatch_outcome_unknown",
  "principal_attempt_control_unavailable",
  "principal_attempt_limit_exceeded",
  "principal_attempt_minute_limit_exceeded",
  "principal_attempt_rolling_limit_exceeded",
  "principal_dispatch_in_progress",
  "provider_dispatch_outcome_unknown",
  "provider_dispatch_rate_limited",
  "provider_request_failed",
  "provider_response_invalid",
  "provider_response_out_of_bounds",
  "provider_timeout",
  "quota_control_unavailable",
  "quota_exceeded",
  "request_body_invalid",
  "request_body_mismatch",
  "request_control_unavailable",
  "request_limit_exceeded",
  "request_too_large",
  "revenuecat_subscription_mismatch",
  "revenuecat_subscription_not_synced",
  "revenuecat_subscription_unavailable",
  "revenuecat_subscription_unconfigured",
  "rolling_quota_exceeded",
  "rolling_scan_quota_exceeded",
  "shared_secret_unconfigured",
  "storekit_app_mismatch",
  "storekit_environment_invalid",
  "storekit_product_mismatch",
  "storekit_product_type_invalid",
  "storekit_transaction_invalid",
  "storekit_transaction_mismatch",
  "storekit_verification_unavailable",
  "storekit_verifier_unconfigured",
  "subscription_expired",
  "subscription_inactive",
  "subscription_status_invalid",
  "subscription_status_unavailable",
  "subscription_status_unconfigured",
  "subscription_upgraded",
  "transaction_revoked",
  "trial_dispatch_disabled_by_budget",
  "trial_lifetime_quota_exceeded",
]);
const BUNDLED_APPLE_ROOT_CERTIFICATES = [
  {
    name: "AppleIncRootCertificate.cer.base64",
    sha256: "b0b1730ecbc7ff4505142c49f1295e6eda6bcaed7e2c68c5be91b5a11001f024",
  },
  {
    name: "AppleRootCA-G2.cer.base64",
    sha256: "c2b9b042dd57830e7d117dac55ac8ae19407d38e41d88f3215bc3a890444a050",
  },
  {
    name: "AppleRootCA-G3.cer.base64",
    sha256: "63343abfb89a6a03ebb57e9b3f5fa7be7c4f5c756f3017b3a8c488c3653e9179",
  },
];

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
  const appleStatusTimeoutMs = positiveInteger(environment.APPLE_STATUS_TIMEOUT_MS, 5_000);
  const revenueCatTimeoutMs = boundedPositiveInteger(
    environment.REVENUECAT_TIMEOUT_MS,
    DEFAULT_REVENUECAT_TIMEOUT_MS,
    MAX_REVENUECAT_TIMEOUT_MS,
    "REVENUECAT_TIMEOUT_MS"
  );
  const principalAttemptMinuteLimit = boundedPositiveInteger(
    environment.MEAL_SCAN_PRINCIPAL_ATTEMPTS_PER_MINUTE_LIMIT,
    MAX_PRINCIPAL_ATTEMPTS_PER_MINUTE,
    MAX_PRINCIPAL_ATTEMPTS_PER_MINUTE,
    "MEAL_SCAN_PRINCIPAL_ATTEMPTS_PER_MINUTE_LIMIT"
  );
  const principalAttemptRollingLimit = boundedPositiveInteger(
    environment.MEAL_SCAN_PRINCIPAL_ATTEMPTS_PER_24_HOURS_LIMIT,
    MAX_PRINCIPAL_ATTEMPTS_PER_24_HOURS,
    MAX_PRINCIPAL_ATTEMPTS_PER_24_HOURS,
    "MEAL_SCAN_PRINCIPAL_ATTEMPTS_PER_24_HOURS_LIMIT"
  );
  const globalProviderMinuteLimit = boundedPositiveInteger(
    environment.MEAL_SCAN_GLOBAL_PROVIDER_DISPATCHES_PER_MINUTE_LIMIT,
    MAX_GLOBAL_PROVIDER_DISPATCHES_PER_MINUTE,
    MAX_GLOBAL_PROVIDER_DISPATCHES_PER_MINUTE,
    "MEAL_SCAN_GLOBAL_PROVIDER_DISPATCHES_PER_MINUTE_LIMIT"
  );
  const globalProviderRollingLimit = boundedPositiveInteger(
    environment.MEAL_SCAN_GLOBAL_PROVIDER_DISPATCHES_PER_24_HOURS_LIMIT,
    MAX_GLOBAL_PROVIDER_DISPATCHES_PER_24_HOURS,
    MAX_GLOBAL_PROVIDER_DISPATCHES_PER_24_HOURS,
    "MEAL_SCAN_GLOBAL_PROVIDER_DISPATCHES_PER_24_HOURS_LIMIT"
  );
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
  const bundleId = environment.APPLE_BUNDLE_ID ?? PINNED_APPLE_BUNDLE_ID;
  const allowedProductIds = new Set(
    (environment.APPLE_ALLOWED_PRODUCT_IDS ??
      [...PINNED_APPLE_PRODUCT_IDS].join(","))
      .split(",")
      .map((value) => value.trim())
      .filter(Boolean)
  );
  const principalSecret =
    overrides.principalSecret ??
    environment.MEAL_SCAN_PRINCIPAL_HMAC_SECRET ??
    (environment.NODE_ENV === "production" ? null : "cyclebalance-development-principal-secret");
  const configuredCanaryCorrelationId = normalizedCanaryDigest(
    environment.MEAL_SCAN_CANARY_CORRELATION_SHA256
  );

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
      appleStatusTimeoutMs,
      revenueCatTimeoutMs,
      paidLimit,
      trialLimit,
      trialLifetimeLimit,
      principalAttemptMinuteLimit,
      principalAttemptRollingLimit,
      globalProviderMinuteLimit,
      globalProviderRollingLimit,
    },
  });

  const appCheckVerifier = overrides.appCheckVerifier ?? createConfiguredFirebaseAppCheckVerifier(environment);
  const budgetStateProvider =
    overrides.getBudgetState ??
    (overrides.budgetState
      ? () => overrides.budgetState
      : createConfiguredBudgetStateProvider(environment));
  const storeKitVerifier = Object.hasOwn(overrides, "storeKitVerifier")
    ? overrides.storeKitVerifier
    : createConfiguredStoreKitVerifier(environment);
  const dependencies = {
    verifyAppIntegrity:
      overrides.verifyAppIntegrity ??
      ((input) => verifyAppIntegrity(input, { requireAppCheck, appCheckVerifier, environment })),
    storeKitVerifier,
    currentSubscriptionChecker: Object.hasOwn(overrides, "currentSubscriptionChecker")
      ? overrides.currentSubscriptionChecker
      : createConfiguredCurrentSubscriptionChecker(environment, storeKitVerifier),
    revenueCatSubscriptionVerifier: Object.hasOwn(overrides, "revenueCatSubscriptionVerifier")
      ? overrides.revenueCatSubscriptionVerifier
      : createConfiguredRevenueCatSubscriptionVerifier({
        environment,
        allowedProductIds,
        timeoutMs: revenueCatTimeoutMs,
      }),
    processImage: overrides.processImage ?? processCanonicalJPEG,
    quotaStore: overrides.quotaStore ?? createConfiguredQuotaStore(environment),
    idempotencyStore:
      overrides.idempotencyStore ??
      createConfiguredIdempotencyStore({
        environment,
        pendingTtlMs: idempotencyPendingTtlMs,
        globalProviderMinuteLimit,
        globalProviderRollingLimit,
      }),
    requestGate: overrides.requestGate ?? createConfiguredRequestGate(environment),
    principalAttemptGate:
      overrides.principalAttemptGate ??
      createConfiguredPrincipalAttemptGate({
        environment,
        minuteLimit: principalAttemptMinuteLimit,
        rollingLimit: principalAttemptRollingLimit,
      }),
    resultCache:
      overrides.resultCache ??
      createConfiguredResultCache({ environment, ttlMs: resultCacheTtlMs, leaseTtlMs: resultLeaseTtlMs }),
    callGemini: overrides.callGemini ?? callGemini,
    getBudgetState: budgetStateProvider,
    logger: overrides.logger ?? console,
  };

  let lastObservedBudgetMode = null;
  const server = http.createServer(async (request, response) => {
    const requestStartedAt = Date.now();
    let idempotencyContext = null;
    let providerDispatched = false;
    let providerEventCompleted = false;
    let providerStartedAt = null;
    let lease = null;
    let cacheInput = null;
    let cacheDisposition = null;
    let canaryContext = null;
    const scannerEvent = (fields) => emitIdentifierFreeScannerEvent(dependencies.logger, {
      ...fields,
      ...(canaryContext
        ? {
            canaryCorrelationId: canaryContext.correlationId,
            canaryOperationTag: canaryContext.operationTag,
            canaryQuotaTag: canaryContext.quotaTag,
          }
        : {}),
    });
    const recordCacheDisposition = (disposition, outcome = "observed") => {
      cacheDisposition = disposition;
      scannerEvent({
        eventType: "cache_decision",
        outcome,
        cacheDisposition: disposition,
        localCacheDisposition: "not_observed",
      });
    };
    response[SCANNER_RESPONSE_OBSERVER] = (status, body) => {
      const rejected = status >= 400;
      scannerEvent({
        eventType: "request_result",
        outcome: status >= 500 ? "failed" : rejected ? "rejected" : "completed",
        reason: rejected ? body?.reason ?? body?.error : null,
        statusCode: status,
        statusClass: `${Math.floor(status / 100)}xx`,
        latencyMs: Math.max(0, Date.now() - requestStartedAt),
        cacheDisposition,
        localCacheDisposition: "not_observed",
      });
    };

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

      if (configuredCanaryCorrelationId) {
        const canaryId = headerValue(request.headers["x-cyclebalance-canary-id"]);
        const operationTag = headerValue(request.headers["x-cyclebalance-canary-operation"]);
        const correlationId = canonicalCanaryId(canaryId)
          ? sha256Hex(canaryId)
          : null;
        if (
          correlationId !== configuredCanaryCorrelationId ||
          !isSha256Hex(operationTag)
        ) {
          return sendJSON(response, 400, {
            error: "invalid_request",
            detail: "request correlation is invalid",
          });
        }
        canaryContext = {
          canaryId,
          correlationId,
          operationTag,
          quotaTag: null,
        };
      }

      if (!scanEnabled) {
        return sendJSON(response, 503, {
          error: "meal_scan_unavailable",
          reason: "feature_disabled",
          retryable: false,
        });
      }

      const integrityToken = headerValue(request.headers["x-firebase-appcheck"]);
      let appCheckAccepted = false;
      if (requireAppCheck && !integrityToken) {
        scannerEvent({
          eventType: "authorization_rejection",
          outcome: "rejected",
          control: "app_check",
          reason: "app_check_required",
        });
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
          scannerEvent({
            eventType: "authorization_rejection",
            outcome: "rejected",
            control: "app_check",
            reason: integrityResult.reason ?? "integrity_failed",
          });
          return sendJSON(response, 401, {
            error: "app_integrity_required",
            reason: integrityResult.reason ?? "integrity_failed",
          });
        }
        appCheckAccepted = true;
      }

      const payload = await readJSONBody(request, maxBodyBytes);
      const validation = validatePayload(payload, { maxImageBytes });
      if (!validation.ok) {
        if (validation.detail === "signedTransactionJWS is invalid") {
          scannerEvent({
            eventType: "authorization_rejection",
            outcome: "rejected",
            control: "storekit_jws",
            reason: "storekit_transaction_invalid",
          });
        }
        return sendJSON(response, 400, { error: "invalid_request", detail: validation.detail });
      }
      if (
        canaryContext &&
        canaryContext.operationTag !== sha256Hex(payload.requestId.toLowerCase())
      ) {
        return sendJSON(response, 400, {
          error: "invalid_request",
          detail: "request correlation is invalid",
        });
      }
      if (appCheckAccepted && canaryContext) {
        scannerEvent({
          eventType: "authorization_acceptance",
          outcome: "accepted",
          control: "app_check",
        });
      }

      if (!requireAppCheck) {
        const integrityResult = normalizeGateResult(
          await dependencies.verifyAppIntegrity({ token: integrityToken, payload })
        );
        if (!integrityResult.allowed) {
          scannerEvent({
            eventType: "authorization_rejection",
            outcome: "rejected",
            control: "app_check",
            reason: integrityResult.reason ?? "integrity_failed",
          });
          return sendJSON(response, 401, {
            error: "app_integrity_required",
            reason: integrityResult.reason ?? "integrity_failed",
          });
        }
        if (canaryContext) {
          scannerEvent({
            eventType: "authorization_acceptance",
            outcome: "accepted",
            control: "app_check",
          });
        }
      }

      if (!principalSecret) {
        return sendJSON(response, 503, {
          error: "meal_scan_unavailable",
          reason: "storekit_verifier_unconfigured",
          retryable: false,
        });
      }

      const submittedEvidenceKey = deriveSubmittedEvidenceGateKey({
        signedTransactionJWS: payload.signedTransactionJWS,
        secret: principalSecret,
      });
      let requestGateResult;
      try {
        requestGateResult = await dependencies.requestGate.checkAndConsume({ appUserId: submittedEvidenceKey });
      } catch {
        scannerEvent({
          eventType: "request_gate_decision",
          outcome: "unavailable",
          control: "pre_verification",
          reason: "request_control_unavailable",
        });
        dependencies.logger.error?.("meal_scan_request_control_unavailable");
        return sendJSON(response, 503, {
          error: "meal_scan_unavailable",
          reason: "request_control_unavailable",
          retryable: true,
        });
      }
      if (!requestGateResult.allowed) {
        scannerEvent({
          eventType: "request_gate_decision",
          outcome: "rejected",
          control: "pre_verification",
          reason: requestGateResult.reason ?? "request_limit_exceeded",
        });
        return sendJSON(response, 429, {
          error: "meal_scan_request_rate_limited",
          reason: requestGateResult.reason ?? "request_limit_exceeded",
          retryable: true,
          retryAfterSeconds: numberOrNull(requestGateResult.retryAfterSeconds),
        });
      }
      scannerEvent({
        eventType: "request_gate_decision",
        outcome: "allowed",
        control: "pre_verification",
      });

      let budget;
      try {
        budget = normalizeBudgetState(await dependencies.getBudgetState(), environment);
      } catch {
        scannerEvent({
          eventType: "budget_state",
          outcome: "unavailable",
          reason: "budget_control_unavailable",
        });
        dependencies.logger.error?.("meal_scan_budget_control_unavailable");
        return sendJSON(response, 503, {
          error: "meal_scan_unavailable",
          reason: "budget_control_unavailable",
          retryable: true,
        });
      }
      const budgetOutcome = budget.stale
        ? "stale"
        : lastObservedBudgetMode !== null && lastObservedBudgetMode !== budget.mode
          ? "transitioned"
          : "observed";
      lastObservedBudgetMode = budget.mode;
      scannerEvent({
        eventType: "budget_state",
        outcome: budgetOutcome,
        budgetMode: budget.mode,
        stateAgeSeconds: budget.stateAgeSeconds,
      });
      if (!dependencies.storeKitVerifier) {
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
        if (isRetryableAppleInfrastructureError(error)) {
          scannerEvent({
            eventType: "authorization_rejection",
            outcome: "unavailable",
            control: "storekit_jws",
            reason: "storekit_verification_unavailable",
          });
          return sendJSON(response, 503, {
            error: "meal_scan_unavailable",
            reason: "storekit_verification_unavailable",
            retryable: true,
          });
        }
        const storeKitReason =
          error?.status === VerificationStatus.INVALID_APP_IDENTIFIER
            ? "storekit_app_mismatch"
            : "storekit_transaction_invalid";
        scannerEvent({
          eventType: "authorization_rejection",
          outcome: "rejected",
          control: "storekit_jws",
          reason: storeKitReason,
        });
        return sendJSON(response, 403, {
          error: "premium_entitlement_required",
          reason: storeKitReason,
        });
      }

      const transactionAccess = validateStoreKitTransaction(transaction, {
        bundleId,
        allowedProductIds,
        now: Date.now(),
      });
      if (!transactionAccess.allowed) {
        scannerEvent({
          eventType: "authorization_rejection",
          outcome: "rejected",
          control: "storekit_jws",
          reason: transactionAccess.reason,
        });
        return sendJSON(response, 403, {
          error: "premium_entitlement_required",
          reason: transactionAccess.reason,
        });
      }
      if (canaryContext) {
        scannerEvent({
          eventType: "authorization_acceptance",
          outcome: "accepted",
          control: "storekit_jws",
        });
      }

      const principal = derivePurchasePrincipal({
        originalTransactionId: transaction.originalTransactionId,
        environment: transaction.environment,
        secret: principalSecret,
      });
      if (canaryContext) {
        canaryContext.quotaTag = sha256Hex(`${canaryContext.canaryId}|${principal}`);
      }

      let principalAttempt;
      try {
        principalAttempt = await dependencies.principalAttemptGate.checkAndConsume({ principal });
      } catch (error) {
        scannerEvent({
          eventType: "request_gate_decision",
          outcome: "unavailable",
          control: "principal_attempt",
          reason: "principal_attempt_control_unavailable",
        });
        dependencies.logger.error?.("meal_scan_principal_attempt_control_unavailable", {
          code: safeErrorCode(error),
        });
        return sendJSON(response, 503, {
          error: "meal_scan_unavailable",
          reason: "principal_attempt_control_unavailable",
          retryable: true,
        });
      }
      if (!principalAttempt?.allowed) {
        scannerEvent({
          eventType: "request_gate_decision",
          outcome: "rejected",
          control: "principal_attempt",
          reason: principalAttempt?.reason ?? "principal_attempt_limit_exceeded",
        });
        return sendJSON(response, 429, {
          error: "meal_scan_request_rate_limited",
          reason: principalAttempt?.reason ?? "principal_attempt_limit_exceeded",
          retryable: true,
          retryAfterSeconds: numberOrNull(principalAttempt?.retryAfterSeconds),
        });
      }
      scannerEvent({
        eventType: "request_gate_decision",
        outcome: "allowed",
        control: "principal_attempt",
      });

      let authoritativeTier = transactionAccess.tier;
      let currentVerifiedTransaction = null;
      if (dependencies.currentSubscriptionChecker) {
        let currentAccess;
        try {
          currentAccess = await withTimeout(
            dependencies.currentSubscriptionChecker.check({ transaction }),
            appleStatusTimeoutMs,
            "APPLE_STATUS_TIMEOUT"
          );
        } catch (error) {
          if (isRetryableAppleInfrastructureError(error)) {
            scannerEvent({
              eventType: "authorization_rejection",
              outcome: "unavailable",
              control: "storekit_jws",
              reason: "subscription_status_unavailable",
            });
            return sendJSON(response, 503, {
              error: "meal_scan_unavailable",
              reason: "subscription_status_unavailable",
              retryable: true,
            });
          }
          scannerEvent({
            eventType: "authorization_rejection",
            outcome: "rejected",
            control: "storekit_jws",
            reason: "subscription_status_invalid",
          });
          return sendJSON(response, 403, {
            error: "premium_entitlement_required",
            reason: "subscription_status_invalid",
          });
        }
        if (!currentAccess?.allowed) {
          scannerEvent({
            eventType: "authorization_rejection",
            outcome: "rejected",
            control: "storekit_jws",
            reason: currentAccess?.reason ?? "subscription_inactive",
          });
          return sendJSON(response, 403, {
            error: "premium_entitlement_required",
            reason: currentAccess?.reason ?? "subscription_inactive",
          });
        }
        if (!new Set(["trial", "paid"]).has(currentAccess.tier)) {
          scannerEvent({
            eventType: "authorization_rejection",
            outcome: "rejected",
            control: "storekit_jws",
            reason: "subscription_status_invalid",
          });
          return sendJSON(response, 403, {
            error: "premium_entitlement_required",
            reason: "subscription_status_invalid",
          });
        }
        authoritativeTier = currentAccess.tier;
        currentVerifiedTransaction = currentAccess.transaction;
        if (canaryContext) {
          scannerEvent({
            eventType: "authorization_acceptance",
            outcome: "accepted",
            control: "apple_current_status",
          });
        }
      } else if (
        environment.NODE_ENV === "production" ||
        dependencies.revenueCatSubscriptionVerifier
      ) {
        scannerEvent({
          eventType: "authorization_rejection",
          outcome: "unavailable",
          control: "storekit_jws",
          reason: "subscription_status_unconfigured",
        });
        return sendJSON(response, 503, {
          error: "meal_scan_unavailable",
          reason: "subscription_status_unconfigured",
          retryable: false,
        });
      }

      if (dependencies.revenueCatSubscriptionVerifier) {
        if (
          !boundedString(currentVerifiedTransaction?.transactionId, 1, 255) ||
          !boundedString(currentVerifiedTransaction?.productId, 1, 200) ||
          !allowedProductIds.has(currentVerifiedTransaction.productId) ||
          !new Set([Environment.PRODUCTION, Environment.SANDBOX]).has(
            currentVerifiedTransaction?.environment
          )
        ) {
          scannerEvent({
            eventType: "authorization_rejection",
            outcome: "rejected",
            control: "revenuecat_subscription",
            reason: "revenuecat_subscription_mismatch",
          });
          return sendJSON(response, 403, {
            error: "premium_entitlement_required",
            reason: "revenuecat_subscription_mismatch",
          });
        }

        let revenueCatAccess;
        try {
          revenueCatAccess = await withTimeout(
            dependencies.revenueCatSubscriptionVerifier.check({
              transaction: {
                transactionId: currentVerifiedTransaction.transactionId,
                environment: currentVerifiedTransaction.environment,
                productId: currentVerifiedTransaction.productId,
              },
            }),
            revenueCatTimeoutMs,
            "REVENUECAT_TIMEOUT"
          );
        } catch (error) {
          scannerEvent({
            eventType: "authorization_rejection",
            outcome: "unavailable",
            control: "revenuecat_subscription",
            reason: "revenuecat_subscription_unavailable",
          });
          return sendJSON(response, 503, {
            error: "meal_scan_unavailable",
            reason: "revenuecat_subscription_unavailable",
            retryable: error?.retryable !== false,
          });
        }

        if (!revenueCatAccess?.allowed) {
          const retryable = revenueCatAccess?.retryable === true;
          const reason = retryable && revenueCatAccess?.reason === "revenuecat_subscription_not_synced"
            ? "revenuecat_subscription_not_synced"
            : retryable
              ? "revenuecat_subscription_unavailable"
              : "revenuecat_subscription_mismatch";
          scannerEvent({
            eventType: "authorization_rejection",
            outcome: retryable ? "unavailable" : "rejected",
            control: "revenuecat_subscription",
            reason,
          });
          return sendJSON(response, retryable ? 503 : 403, retryable
            ? { error: "meal_scan_unavailable", reason, retryable: true }
            : { error: "premium_entitlement_required", reason });
        }
        if (canaryContext) {
          scannerEvent({
            eventType: "authorization_acceptance",
            outcome: "accepted",
            control: "revenuecat_subscription",
          });
        }
      } else if (environment.NODE_ENV === "production") {
        scannerEvent({
          eventType: "authorization_rejection",
          outcome: "unavailable",
          control: "revenuecat_subscription",
          reason: "revenuecat_subscription_unconfigured",
        });
        return sendJSON(response, 503, {
          error: "meal_scan_unavailable",
          reason: "revenuecat_subscription_unconfigured",
          retryable: false,
        });
      }

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

      const tier = authoritativeTier;
      const limit = tier === "paid"
        ? (budget.mode === "degraded" ? Math.min(paidLimit, 5) : paidLimit)
        : trialLimit;
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

      const usesAtomicQuotaReservation =
        typeof dependencies.idempotencyStore.claimAndConsumeQuota === "function";
      idempotencyContext = await dependencies.idempotencyStore[
        usesAtomicQuotaReservation ? "inspect" : "claim"
      ]({
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
        recordCacheDisposition("idempotency_replay");
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
      if (idempotencyContext.state !== "missing" && !idempotencyContext.acquired) {
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
      const completeCacheHit = async (body) => {
        if (usesAtomicQuotaReservation) {
          const completion = await dependencies.idempotencyStore.completeFromCache({
            requestId: payload.requestId,
            requestHash,
            response: body,
          });
          if (completion.state !== "completed") return completion;
          idempotencyContext = null;
          return { state: "completed", response: completion.response ?? body };
        }
        await dependencies.idempotencyStore.complete(idempotencyContext, body);
        return { state: "completed", response: body };
      };
      const sendCacheCompletionFailure = (completion) => {
        if (completion.state === "mismatch") {
          return sendJSON(response, 409, {
            error: "idempotency_conflict",
            reason: "request_body_mismatch",
            retryable: false,
            idempotency: { state: "unknown" },
          });
        }
        if (completion.state === "unknown") {
          return sendJSON(response, 409, {
            error: "meal_scan_outcome_unknown",
            reason: "previous_dispatch_outcome_unknown",
            retryable: false,
            idempotency: { state: "unknown" },
          });
        }
        return sendJSON(response, 409, {
          error: "meal_scan_in_progress",
          reason: "duplicate_request_in_progress",
          retryable: true,
          idempotency: { state: "pending" },
        });
      };

      let cachedResult;
      try {
        cachedResult = await dependencies.resultCache.get(cacheInput);
      } catch (error) {
        recordCacheDisposition("server_unavailable", "unavailable");
        await abandonIdempotency();
        dependencies.logger.warn?.("meal_scan_cache_read_error", { code: safeErrorCode(error) });
        return sendJSON(response, 503, {
          error: "meal_scan_unavailable",
          reason: "cache_control_unavailable",
          retryable: true,
        });
      }
      if (cachedResult) {
        recordCacheDisposition("server_hit");
        let quota = cachedResult.quota;
        if (typeof dependencies.quotaStore.current === "function") {
          try {
            quota = await dependencies.quotaStore.current(quotaInput);
          } catch (error) {
            dependencies.logger.warn?.("meal_scan_quota_snapshot_error", { code: safeErrorCode(error) });
          }
        }
        const body = buildSuccessBody(cachedResult, quota, true);
        const completion = await completeCacheHit(body);
        if (completion.state !== "completed") return sendCacheCompletionFailure(completion);
        dependencies.logger.info?.("meal_scan_estimate", identifierFreeMetric({
          modelId: DEFAULT_MODEL_ID,
          usage: cachedResult.usage,
          quota,
          tier,
          budget,
          cacheHit: true,
        }));
        return sendJSON(response, 200, completion.response);
      }

      if (budget.mode === "disabled") {
        recordCacheDisposition("server_miss");
        await abandonIdempotency();
        return sendJSON(response, 503, {
          error: "meal_scan_unavailable",
          reason: "monthly_budget_exceeded",
          retryable: false,
          budget: budgetResponse(budget),
        });
      }
      if (budget.mode === "degraded" && tier === "trial") {
        recordCacheDisposition("server_miss");
        await abandonIdempotency();
        return sendJSON(response, 503, {
          error: "meal_scan_unavailable",
          reason: "trial_dispatch_disabled_by_budget",
          retryable: false,
          budget: budgetResponse(budget),
        });
      }

      if (typeof dependencies.resultCache.acquireLease === "function") {
        try {
          lease = await dependencies.resultCache.acquireLease(cacheInput);
        } catch (error) {
          recordCacheDisposition("server_unavailable", "unavailable");
          await abandonIdempotency();
          dependencies.logger.warn?.("meal_scan_cache_lease_error", { code: safeErrorCode(error) });
          return sendJSON(response, 503, {
            error: "meal_scan_unavailable",
            reason: "cache_control_unavailable",
            retryable: true,
          });
        }
        if (lease.value) {
          recordCacheDisposition("server_hit_after_lease");
          const body = buildSuccessBody(lease.value, lease.value.quota, true);
          const completion = await completeCacheHit(body);
          if (completion.state !== "completed") return sendCacheCompletionFailure(completion);
          return sendJSON(response, 200, completion.response);
        }
        if (!lease.acquired) {
          const completedResult = await waitForCachedResult(dependencies.resultCache, cacheInput);
          if (completedResult) {
            recordCacheDisposition("server_hit_after_wait");
            const body = buildSuccessBody(completedResult, completedResult.quota, true);
            const completion = await completeCacheHit(body);
            if (completion.state !== "completed") return sendCacheCompletionFailure(completion);
            return sendJSON(response, 200, completion.response);
          }
          recordCacheDisposition("server_miss_in_progress");
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
      let freshQuotaConsumed = false;
      try {
        if (usesAtomicQuotaReservation) {
          const reservation = await dependencies.idempotencyStore.claimAndConsumeQuota({
            requestId: payload.requestId,
            requestHash,
            quota: quotaInput,
          });
          if (reservation.state === "mismatch") {
            return sendJSON(response, 409, {
              error: "idempotency_conflict",
              reason: "request_body_mismatch",
              retryable: false,
              idempotency: { state: "unknown" },
            });
          }
          if (reservation.state === "completed") {
            recordCacheDisposition("idempotency_replay");
            return sendJSON(response, 200, reservation.response);
          }
          if (reservation.state === "unknown") {
            return sendJSON(response, 409, {
              error: "meal_scan_outcome_unknown",
              reason: "previous_dispatch_outcome_unknown",
              retryable: false,
              idempotency: { state: "unknown" },
            });
          }
          if (reservation.state === "principal_busy") {
            return sendJSON(response, 409, {
              error: "meal_scan_in_progress",
              reason: reservation.reason ?? "principal_dispatch_in_progress",
              retryable: true,
              retryAfterSeconds: numberOrNull(reservation.retryAfterSeconds),
              idempotency: { state: "pending" },
            });
          }
          if (reservation.state === "provider_limit_denied") {
            scannerEvent({
              eventType: "global_dispatch_decision",
              outcome: "rejected",
              reason: reservation.reason ?? "global_provider_dispatch_limit_exceeded",
            });
            return sendJSON(response, 429, {
              error: "provider_dispatch_rate_limited",
              reason: reservation.reason ?? "global_provider_dispatch_limit_exceeded",
              retryable: true,
              retryAfterSeconds: numberOrNull(reservation.retryAfterSeconds),
            });
          }
          if (reservation.state === "pending" && !reservation.acquired) {
            return sendJSON(response, 409, {
              error: "meal_scan_in_progress",
              reason: "duplicate_request_in_progress",
              retryable: true,
              idempotency: { state: "pending" },
            });
          }
          if (reservation.state === "quota_denied") {
            quota = reservation.quota;
          } else {
            idempotencyContext = reservation;
            quota = reservation.quota;
            freshQuotaConsumed = reservation.acquired === true;
            scannerEvent({
              eventType: "global_dispatch_decision",
              outcome: "allowed",
            });
          }
        } else {
          quota = await dependencies.quotaStore.checkAndConsume(quotaInput);
          freshQuotaConsumed = quota?.allowed === true;
        }
      } catch (error) {
        scannerEvent({
          eventType: "quota_decision",
          outcome: "unavailable",
          reason: "quota_control_unavailable",
        });
        await abandonIdempotency();
        dependencies.logger.error?.("meal_scan_quota_control_unavailable", { code: safeErrorCode(error) });
        return sendJSON(response, 503, {
          error: "meal_scan_unavailable",
          reason: "quota_control_unavailable",
          retryable: true,
        });
      }
      if (!quota.allowed) {
        scannerEvent({
          eventType: "quota_decision",
          outcome: "rejected",
          reason: quota.reason ?? "quota_exceeded",
          tier,
          quotaUsed: quota.used,
          quotaLimit: quota.limit,
          quotaRemaining: quota.remaining ?? quota.remainingToday,
        });
        if (cacheDisposition === null) recordCacheDisposition("server_miss");
        await abandonIdempotency();
        return sendJSON(response, 429, {
          error: "rolling_scan_quota_exceeded",
          reason: quota.reason ?? "quota_exceeded",
          retryable: quota.reason !== "trial_lifetime_quota_exceeded",
          quota: quotaResponse(quota, tier),
        });
      }
      scannerEvent({
        eventType: "quota_decision",
        outcome: "allowed",
        tier,
        quotaUsed: quota.used,
        quotaLimit: quota.limit,
        quotaRemaining: quota.remaining ?? quota.remainingToday,
        quotaDelta: canaryContext && freshQuotaConsumed ? 1 : null,
      });
      if (cacheDisposition === null) recordCacheDisposition("fresh_dispatch");

      const providerPayload = buildGeminiPayload({
        ...payload,
        image: {
          mimeType: "image/jpeg",
          base64: canonicalImage.data.toString("base64"),
          sha256: canonicalImageHash,
        },
      });
      providerStartedAt = Date.now();
      scannerEvent({
        eventType: "provider_call",
        outcome: "started",
        providerId: PROVIDER_ID,
        modelId: DEFAULT_MODEL_ID,
      });
      providerDispatched = true;
      const geminiResponse = await dependencies.callGemini({
        modelId: DEFAULT_MODEL_ID,
        payload: providerPayload,
        timeoutMs: geminiTimeoutMs,
      });
      assertEstimateBounds(geminiResponse.estimate);
      const usage = usageResponse(geminiResponse.usageMetadata, MODEL_CONFIGS[DEFAULT_MODEL_ID]);
      scannerEvent({
        eventType: "provider_call",
        outcome: "completed",
        providerId: PROVIDER_ID,
        modelId: DEFAULT_MODEL_ID,
        inputTokens: usage.inputTokens,
        outputTokens: usage.outputTokens,
        totalTokens: usage.totalTokens,
        estimatedCostUSD: usage.estimatedCostUSD,
        latencyMs: Math.max(0, Date.now() - providerStartedAt),
      });
      providerEventCompleted = true;
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
      if (providerDispatched && !providerEventCompleted) {
        scannerEvent({
          eventType: "provider_call",
          outcome: "failed",
          reason: providerFailureReason(error),
          providerId: PROVIDER_ID,
          modelId: DEFAULT_MODEL_ID,
          latencyMs: providerStartedAt === null ? null : Math.max(0, Date.now() - providerStartedAt),
        });
      }
      if (providerDispatched && idempotencyContext?.acquired) {
        try {
          await dependencies.idempotencyStore.markUnknown(idempotencyContext);
        } catch (markError) {
          dependencies.logger.error?.("meal_scan_idempotency_unknown_write_error", {
            code: safeErrorCode(markError),
          });
        }
      } else if (idempotencyContext?.acquired) {
        await abandonIdempotency();
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
        scannerEvent({
          eventType: "authorization_rejection",
          outcome: "unavailable",
          control: "app_check",
          reason: "integrity_service_timeout",
        });
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

  const configuredProducts = new Set(
    String(environment.APPLE_ALLOWED_PRODUCT_IDS ?? "")
      .split(",")
      .map((value) => value.trim())
      .filter(Boolean)
  );
  if (
    environment.APPLE_BUNDLE_ID !== PINNED_APPLE_BUNDLE_ID ||
    environment.APPLE_APP_ID !== String(PINNED_APPLE_APP_ID) ||
    !sameStringSet(configuredProducts, PINNED_APPLE_PRODUCT_IDS)
  ) {
    throw new Error(
      "production meal scan configuration violates the pinned CycleBalance Apple identity"
    );
  }
  if (
    (environment.REVENUECAT_PROJECT_ID &&
      environment.REVENUECAT_PROJECT_ID !== PINNED_REVENUECAT_PROJECT_ID) ||
    (environment.REVENUECAT_ENTITLEMENT_ID &&
      environment.REVENUECAT_ENTITLEMENT_ID !== PINNED_REVENUECAT_ENTITLEMENT_ID)
  ) {
    throw new Error(
      "production meal scan configuration violates the pinned CycleBalance RevenueCat configuration " +
      "(REVENUECAT_PROJECT_ID, REVENUECAT_ENTITLEMENT_ID)"
    );
  }

  const missing = [];
  if (environment.APP_CHECK_REQUIRED !== "true") missing.push("APP_CHECK_REQUIRED=true");
  if (!boundedString(environment.FIREBASE_APP_ID, 1, 256)) missing.push("FIREBASE_APP_ID");
  if (!boundedString(environment.APPLE_BUNDLE_ID, 1, 256)) missing.push("APPLE_BUNDLE_ID");
  if (!/^\d{5,20}$/.test(environment.APPLE_APP_ID ?? "")) missing.push("APPLE_APP_ID");
  if (!boundedString(environment.APPLE_ALLOWED_PRODUCT_IDS, 1, 1024)) missing.push("APPLE_ALLOWED_PRODUCT_IDS");
  if (!boundedString(environment.APPLE_IAP_PRIVATE_KEY, 32, 16_384)) missing.push("APPLE_IAP_PRIVATE_KEY");
  if (!boundedString(environment.APPLE_IAP_KEY_ID, 4, 128)) missing.push("APPLE_IAP_KEY_ID");
  if (!/^[0-9a-fA-F-]{36}$/.test(environment.APPLE_IAP_ISSUER_ID ?? "")) {
    missing.push("APPLE_IAP_ISSUER_ID");
  }
  if (!boundedString(environment.REVENUECAT_SECRET_API_KEY, 16, 4096)) {
    missing.push("REVENUECAT_SECRET_API_KEY");
  }
  if (!boundedString(environment.REVENUECAT_PROJECT_ID, 1, 255)) {
    missing.push("REVENUECAT_PROJECT_ID");
  }
  if (!boundedString(environment.REVENUECAT_ENTITLEMENT_ID, 1, 200)) {
    missing.push("REVENUECAT_ENTITLEMENT_ID");
  }
  if (!boundedString(environment.MEAL_SCAN_PRINCIPAL_HMAC_SECRET, 32, 4096)) {
    missing.push("MEAL_SCAN_PRINCIPAL_HMAC_SECRET");
  }
  if (!boundedString(environment.GEMINI_API_KEY, 1, 4096)) missing.push("GEMINI_API_KEY");
  if (environment.MEAL_SCAN_QUOTA_STORE !== "firestore") missing.push("MEAL_SCAN_QUOTA_STORE=firestore");
  if (environment.MEAL_SCAN_RESULT_CACHE !== "firestore") missing.push("MEAL_SCAN_RESULT_CACHE=firestore");
  if (environment.MEAL_SCAN_IDEMPOTENCY_STORE !== "firestore") missing.push("MEAL_SCAN_IDEMPOTENCY_STORE=firestore");
  if (environment.MEAL_SCAN_REQUEST_GATE !== "firestore") missing.push("MEAL_SCAN_REQUEST_GATE=firestore");
  if (environment.MEAL_SCAN_PRINCIPAL_ATTEMPT_STORE !== "firestore") {
    missing.push("MEAL_SCAN_PRINCIPAL_ATTEMPT_STORE=firestore");
  }
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
    "MEAL_SCAN_PRINCIPAL_ATTEMPTS_PER_MINUTE_LIMIT",
    "MEAL_SCAN_PRINCIPAL_ATTEMPTS_PER_24_HOURS_LIMIT",
    "MEAL_SCAN_GLOBAL_PROVIDER_DISPATCHES_PER_MINUTE_LIMIT",
    "MEAL_SCAN_GLOBAL_PROVIDER_DISPATCHES_PER_24_HOURS_LIMIT",
    "APP_CHECK_TIMEOUT_MS",
    "APPLE_STATUS_TIMEOUT_MS",
    "REVENUECAT_TIMEOUT_MS",
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

function sameStringSet(left, right) {
  return left.size === right.size && [...left].every((value) => right.has(value));
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
        minItems: 1,
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
              properties: Object.fromEntries(
                NUTRITION_FALLBACK_BOUNDS.map(([field, minimum, maximum]) => [
                  field,
                  { type: "number", minimum, maximum },
                ])
              ),
              required: NUTRITION_FALLBACK_BOUNDS.map(([field]) => field),
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

export function loadBundledAppleRootCertificates(
  certificateDirectory = path.resolve(MODULE_DIRECTORY, "../certs")
) {
  return BUNDLED_APPLE_ROOT_CERTIFICATES.map(({ name, sha256 }) => {
    const encoded = readFileSync(path.join(certificateDirectory, name), "utf8").trim();
    const certificate = Buffer.from(encoded, "base64");
    // Parsing at construction time proves the bundled trust anchors are valid DER X.509 certificates.
    new crypto.X509Certificate(certificate);
    const actualFingerprint = crypto.createHash("sha256").update(certificate).digest("hex");
    if (actualFingerprint !== sha256) {
      throw new Error(`bundled Apple root fingerprint mismatch: ${name}`);
    }
    return certificate;
  });
}

export function createConfiguredStoreKitVerifier(environment = process.env) {
  const rootCertificates = loadBundledAppleRootCertificates();
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

function createConfiguredCurrentSubscriptionChecker(environment, storeKitVerifier) {
  if (
    !storeKitVerifier ||
    !environment.APPLE_IAP_PRIVATE_KEY ||
    !environment.APPLE_IAP_KEY_ID ||
    !environment.APPLE_IAP_ISSUER_ID ||
    !environment.APPLE_BUNDLE_ID
  ) {
    return null;
  }
  const clientOptions = [
    environment.APPLE_IAP_PRIVATE_KEY,
    environment.APPLE_IAP_KEY_ID,
    environment.APPLE_IAP_ISSUER_ID,
    environment.APPLE_BUNDLE_ID,
  ];
  return createCurrentSubscriptionChecker({
    clients: {
      production: new AppStoreServerAPIClient(...clientOptions, Environment.PRODUCTION),
      sandbox: new AppStoreServerAPIClient(...clientOptions, Environment.SANDBOX),
    },
    storeKitVerifier,
    bundleId: environment.APPLE_BUNDLE_ID,
    appAppleId: Number(environment.APPLE_APP_ID),
    allowedProductIds: new Set(
      String(environment.APPLE_ALLOWED_PRODUCT_IDS ?? "")
        .split(",")
        .map((value) => value.trim())
        .filter(Boolean)
    ),
  });
}

function createConfiguredRevenueCatSubscriptionVerifier({
  environment,
  allowedProductIds,
  timeoutMs,
}) {
  const apiKey = environment.REVENUECAT_SECRET_API_KEY;
  const projectId = environment.REVENUECAT_PROJECT_ID;
  const entitlementLookupKey = environment.REVENUECAT_ENTITLEMENT_ID;
  if (!apiKey || !projectId || !entitlementLookupKey) return null;
  return createRevenueCatSubscriptionVerifier({
    apiKey,
    projectId,
    entitlementLookupKey,
    allowedProductIds,
    timeoutMs,
  });
}

export function createCurrentSubscriptionChecker({
  clients,
  storeKitVerifier,
  bundleId,
  appAppleId,
  allowedProductIds,
  now = Date.now,
}) {
  return {
    async check({ transaction }) {
      const client = transaction.environment === Environment.PRODUCTION
        ? clients?.production
        : transaction.environment === Environment.SANDBOX
          ? clients?.sandbox
          : null;
      if (!client) throw new Error("App Store Server API environment is not configured");

      const response = await client.getAllSubscriptionStatuses(transaction.originalTransactionId);
      if (
        response?.environment !== transaction.environment ||
        response?.bundleId !== bundleId ||
        (transaction.environment === Environment.PRODUCTION && Number(response?.appAppleId) !== appAppleId)
      ) {
        return { allowed: false, reason: "storekit_app_mismatch" };
      }

      const matchingItems = (Array.isArray(response.data) ? response.data : [])
        .flatMap((group) => Array.isArray(group?.lastTransactions) ? group.lastTransactions : [])
        .filter((item) => item?.originalTransactionId === transaction.originalTransactionId);
      if (matchingItems.length === 0) {
        return { allowed: false, reason: "subscription_inactive" };
      }

      let revoked = false;
      for (const item of matchingItems) {
        if (!boundedString(item.signedTransactionInfo, 3, 32_768)) {
          throw new Error("current subscription status omitted signed transaction info");
        }
        const currentTransaction = await storeKitVerifier.verifyAndDecodeTransaction(item.signedTransactionInfo);
        if (
          currentTransaction.originalTransactionId !== transaction.originalTransactionId ||
          currentTransaction.environment !== transaction.environment ||
          currentTransaction.bundleId !== transaction.bundleId ||
          currentTransaction.productId !== transaction.productId
        ) {
          return { allowed: false, reason: "storekit_transaction_mismatch" };
        }
        const currentAccess = validateStoreKitTransaction(currentTransaction, {
          bundleId,
          allowedProductIds,
          now: numericTimestamp(now()),
        });
        if (item.status === Status.REVOKED || currentAccess.reason === "transaction_revoked") {
          revoked = true;
          continue;
        }
        if (
          new Set([Status.ACTIVE, Status.BILLING_GRACE_PERIOD]).has(item.status) &&
          currentAccess.allowed
        ) {
          return { allowed: true, tier: currentAccess.tier, transaction: currentTransaction };
        }
      }
      return { allowed: false, reason: revoked ? "transaction_revoked" : "subscription_expired" };
    },
  };
}

export function createRevenueCatSubscriptionVerifier({
  apiKey,
  projectId,
  entitlementLookupKey,
  allowedProductIds,
  timeoutMs = 3_000,
  fetchImpl = fetch,
}) {
  if (
    !boundedString(apiKey, 16, 4096) ||
    apiKey.trim() !== apiKey ||
    !/^proj[A-Za-z0-9]{1,251}$/.test(projectId ?? "") ||
    !boundedString(entitlementLookupKey, 1, 200) ||
    entitlementLookupKey.trim() !== entitlementLookupKey ||
    !(allowedProductIds instanceof Set) ||
    allowedProductIds.size === 0 ||
    allowedProductIds.size > 10 ||
    [...allowedProductIds].some((value) => (
      !boundedString(value, 1, 200) || value.trim() !== value
    )) ||
    !Number.isSafeInteger(timeoutMs) ||
    timeoutMs <= 0 ||
    timeoutMs > MAX_REVENUECAT_TIMEOUT_MS ||
    typeof fetchImpl !== "function"
  ) {
    throw new Error("RevenueCat verifier configuration is invalid");
  }
  return {
    async check({ transaction }) {
      if (
        !boundedString(transaction?.transactionId, 1, 255) ||
        !boundedString(transaction?.productId, 1, 200) ||
        !allowedProductIds.has(transaction.productId) ||
        !new Set([Environment.PRODUCTION, Environment.SANDBOX]).has(transaction?.environment)
      ) {
        return { allowed: false, reason: "revenuecat_subscription_mismatch" };
      }
      const url = new URL(
        `https://api.revenuecat.com/v2/projects/${encodeURIComponent(projectId)}/subscriptions`
      );
      url.searchParams.set("store_subscription_identifier", transaction.transactionId);
      const startedAt = Date.now();
      let response;
      try {
        response = await fetchWithTimeout(
          url,
          {
            method: "GET",
            headers: {
              authorization: `Bearer ${apiKey}`,
              accept: "application/json",
            },
          },
          timeoutMs,
          fetchImpl,
          "REVENUECAT_TIMEOUT"
        );
      } catch {
        throw revenueCatVerificationError("REVENUECAT_UNAVAILABLE", true);
      }
      if (!response.ok) {
        await response.body?.cancel?.();
        throw revenueCatVerificationError(
          "REVENUECAT_UNAVAILABLE",
          response.status === 429 || response.status >= 500
        );
      }
      const remainingTimeoutMs = Math.max(1, timeoutMs - (Date.now() - startedAt));
      const text = await readBoundedRevenueCatResponse(response, remainingTimeoutMs);
      let body;
      try {
        body = JSON.parse(text);
      } catch {
        throw revenueCatVerificationError("REVENUECAT_RESPONSE_INVALID", true);
      }
      if (!isPlainObject(body) || body.object !== "list" || !Array.isArray(body.items)) {
        throw revenueCatVerificationError("REVENUECAT_RESPONSE_INVALID", true);
      }
      const subscriptions = body.items;
      if (body.next_page !== null) {
        return { allowed: false, reason: "revenuecat_subscription_mismatch" };
      }
      if (subscriptions.length === 0) {
        return {
          allowed: false,
          reason: "revenuecat_subscription_not_synced",
          retryable: true,
        };
      }
      if (subscriptions.length !== 1) {
        return { allowed: false, reason: "revenuecat_subscription_mismatch" };
      }
      const subscription = subscriptions[0];
      const expectedEnvironment = transaction.environment === Environment.PRODUCTION
        ? "production"
        : transaction.environment === Environment.SANDBOX
          ? "sandbox"
          : null;
      const entitlements = Array.isArray(subscription?.entitlements?.items)
        ? subscription.entitlements.items
        : [];
      const matchingEntitlements = entitlements.filter((item) => item?.lookup_key === entitlementLookupKey);
      const entitlement = matchingEntitlements[0];
      const products = Array.isArray(entitlement?.products?.items)
        ? entitlement.products.items
        : [];
      const matchingProducts = products.filter((product) => (
        product?.id === subscription?.product_id &&
        product?.store_identifier === transaction.productId &&
        allowedProductIds.has(product.store_identifier)
      ));
      const product = matchingProducts[0];
      if (
        expectedEnvironment === null ||
        subscription?.object !== "subscription" ||
        subscription?.store !== "app_store" ||
        subscription?.environment !== expectedEnvironment ||
        subscription?.store_subscription_identifier !== transaction.transactionId ||
        subscription?.gives_access !== true ||
        subscription?.entitlements?.object !== "list" ||
        subscription?.entitlements?.next_page !== null ||
        matchingEntitlements.length !== 1 ||
        entitlement?.object !== "entitlement" ||
        entitlement?.state !== "active" ||
        entitlement?.project_id !== projectId ||
        entitlement?.products?.object !== "list" ||
        entitlement?.products?.next_page !== null ||
        matchingProducts.length !== 1 ||
        product?.object !== "product" ||
        product?.state !== "active"
      ) {
        return { allowed: false, reason: "revenuecat_subscription_mismatch" };
      }
      return { allowed: true };
    },
  };
}

function revenueCatVerificationError(code, retryable) {
  const error = new Error("RevenueCat subscription verification failed");
  error.code = code;
  error.retryable = retryable;
  return error;
}

async function readBoundedRevenueCatResponse(response, timeoutMs) {
  const declaredLength = Number(response.headers?.get?.("content-length"));
  if (Number.isFinite(declaredLength) && declaredLength > MAX_REVENUECAT_RESPONSE_BYTES) {
    await response.body?.cancel?.();
    throw revenueCatVerificationError("REVENUECAT_RESPONSE_INVALID", true);
  }
  const reader = response.body?.getReader?.();
  if (!reader) throw revenueCatVerificationError("REVENUECAT_RESPONSE_INVALID", true);
  const chunks = [];
  let byteCount = 0;
  let timedOut = false;
  const timeout = setTimeout(() => {
    timedOut = true;
    try {
      reader.cancel().catch(() => {});
    } catch {
      // The standardized unavailable result below remains authoritative.
    }
  }, timeoutMs);
  try {
    while (true) {
      const { done, value } = await reader.read();
      if (done) break;
      if (!(value instanceof Uint8Array)) {
        await reader.cancel();
        throw revenueCatVerificationError("REVENUECAT_RESPONSE_INVALID", true);
      }
      byteCount += value.byteLength;
      if (byteCount > MAX_REVENUECAT_RESPONSE_BYTES) {
        await reader.cancel();
        throw revenueCatVerificationError("REVENUECAT_RESPONSE_INVALID", true);
      }
      chunks.push(Buffer.from(value));
    }
    if (timedOut) throw revenueCatVerificationError("REVENUECAT_UNAVAILABLE", true);
  } catch (error) {
    if (
      error?.code === "REVENUECAT_RESPONSE_INVALID" ||
      error?.code === "REVENUECAT_UNAVAILABLE"
    ) {
      throw error;
    }
    throw revenueCatVerificationError("REVENUECAT_UNAVAILABLE", true);
  } finally {
    clearTimeout(timeout);
    reader.releaseLock();
  }
  return Buffer.concat(chunks, byteCount).toString("utf8");
}

function isRetryableAppleInfrastructureError(error) {
  if (error?.status === VerificationStatus.RETRYABLE_VERIFICATION_FAILURE) return true;
  if (error?.retryable === true || error?.code === "APPLE_STATUS_TIMEOUT") return true;
  const httpStatus = Number(error?.httpStatusCode ?? error?.statusCode);
  if (httpStatus === 429 || httpStatus >= 500) return true;
  return new Set([
    "ECONNABORTED",
    "ECONNREFUSED",
    "ECONNRESET",
    "EHOSTUNREACH",
    "ENETUNREACH",
    "ETIMEDOUT",
  ]).has(error?.code);
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

export function deriveSubmittedEvidenceGateKey({ signedTransactionJWS, secret }) {
  if (!boundedString(signedTransactionJWS, 3, 32_768) || !boundedString(secret, 32, 4096)) {
    throw new Error("submitted StoreKit evidence gate input is invalid");
  }
  let stableEvidence = `jws:${crypto.createHash("sha256").update(signedTransactionJWS).digest("hex")}`;
  try {
    const payloadSegment = signedTransactionJWS.split(".")[1];
    const decoded = JSON.parse(Buffer.from(payloadSegment, "base64url").toString("utf8"));
    if (
      boundedString(decoded?.originalTransactionId, 1, 128) &&
      new Set([Environment.PRODUCTION, Environment.SANDBOX]).has(decoded?.environment)
    ) {
      stableEvidence = `purchase:${String(decoded.environment).toLowerCase()}:${decoded.originalTransactionId}`;
    }
  } catch {
    // A malformed or forged JWS still receives a bounded pseudonymous key before signature verification.
  }
  return crypto.createHmac("sha256", secret).update(`request-gate:${stableEvidence}`).digest("hex");
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

export function assertEstimateBounds(estimate) {
  const fail = () => {
    const error = new Error("provider response exceeds the public response contract");
    error.code = "PROVIDER_RESPONSE_OUT_OF_BOUNDS";
    throw error;
  };
  if (!isPlainObject(estimate)) fail();
  if (!boundedString(estimate.meal_name, 1, 120)) fail();
  if (!new Set(["low", "medium", "high", "unknown"]).has(estimate.confidence)) fail();
  if (!Array.isArray(estimate.warnings) || estimate.warnings.length > 8) fail();
  if (!Array.isArray(estimate.items) || estimate.items.length < 1 || estimate.items.length > 20) fail();
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
    if (item.nutrition_fallback !== undefined && item.nutrition_fallback !== null) {
      if (!isPlainObject(item.nutrition_fallback)) fail();
      for (const [field, minimum, maximum] of NUTRITION_FALLBACK_BOUNDS) {
        const value = item.nutrition_fallback[field];
        if (!Number.isFinite(value) || value < minimum || value > maximum) fail();
      }
    }
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

function emitIdentifierFreeScannerEvent(logger, fields) {
  const event = identifierFreeScannerEvent(fields);
  try {
    if (logger === console) {
      console.info(JSON.stringify(event));
    } else {
      logger?.info?.("meal_scan_scanner_event", event);
    }
  } catch {
    // Operational logging must never change the scanner response path.
  }
  return event;
}

function identifierFreeScannerEvent(fields = {}) {
  const event = {
    event: "meal_scan_scanner_event",
    severity: "INFO",
    schemaVersion: SCANNER_EVENT_SCHEMA_VERSION,
    eventType: safeScannerDimension(fields.eventType, "other"),
    outcome: safeScannerDimension(fields.outcome, "other"),
  };
  for (const field of [
    "control",
    "cacheDisposition",
    "localCacheDisposition",
    "providerId",
    "modelId",
    "tier",
    "budgetMode",
    "statusClass",
  ]) {
    if (fields[field] != null) event[field] = safeScannerDimension(fields[field], "other");
  }
  for (const field of [
    "canaryCorrelationId",
    "canaryOperationTag",
    "canaryQuotaTag",
  ]) {
    if (isSha256Hex(fields[field])) event[field] = fields[field];
  }
  if (fields.reason != null) event.reason = safeScannerReason(fields.reason);
  for (const field of [
    "statusCode",
    "latencyMs",
    "inputTokens",
    "outputTokens",
    "totalTokens",
    "estimatedCostUSD",
    "quotaUsed",
    "quotaLimit",
    "quotaRemaining",
    "stateAgeSeconds",
  ]) {
    const value = numberOrNull(fields[field]);
    if (value !== null && value >= 0) event[field] = value;
  }
  if (fields.quotaDelta === 1) event.quotaDelta = 1;
  return event;
}

function safeScannerDimension(value, fallback) {
  return typeof value === "string" && /^[a-z0-9][a-z0-9_.-]{0,63}$/.test(value)
    ? value
    : fallback;
}

function safeScannerReason(value) {
  return SAFE_SCANNER_REASONS.has(value) ? value : "other";
}

function providerFailureReason(error) {
  if (error?.code === "PROVIDER_RESPONSE_OUT_OF_BOUNDS") return "provider_response_out_of_bounds";
  if (error?.code === "GEMINI_PARSE_ERROR") return "provider_response_invalid";
  if (error?.code === "GEMINI_HTTP_ERROR") return "provider_request_failed";
  if (error?.code === "ETIMEDOUT" || error?.name === "AbortError") return "provider_timeout";
  return "provider_dispatch_outcome_unknown";
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

function createConfiguredPrincipalAttemptGate({ environment, minuteLimit, rollingLimit }) {
  if (environment.MEAL_SCAN_PRINCIPAL_ATTEMPT_STORE === "firestore") {
    return createFirestorePrincipalAttemptGate({
      collectionName:
        environment.MEAL_SCAN_PRINCIPAL_ATTEMPT_COLLECTION ?? "mealScanPrincipalAttempts",
      minuteLimit,
      rollingLimit,
    });
  }
  return createInMemoryPrincipalAttemptGate({ minuteLimit, rollingLimit });
}

export function createInMemoryPrincipalAttemptGate({
  minuteLimit = MAX_PRINCIPAL_ATTEMPTS_PER_MINUTE,
  rollingLimit = MAX_PRINCIPAL_ATTEMPTS_PER_24_HOURS,
  now = Date.now,
} = {}) {
  const records = new Map();
  return {
    async checkAndConsume({ principal }) {
      const timestamp = numericTimestamp(now());
      const decision = principalAttemptDecision({
        events: records.get(principal) ?? [],
        timestamp,
        minuteLimit,
        rollingLimit,
      });
      records.set(principal, decision.events);
      return decision.response;
    },
  };
}

export function createFirestorePrincipalAttemptGate({
  collectionName,
  minuteLimit = MAX_PRINCIPAL_ATTEMPTS_PER_MINUTE,
  rollingLimit = MAX_PRINCIPAL_ATTEMPTS_PER_24_HOURS,
  firestore: injectedFirestore,
  now = Date.now,
}) {
  let firestoreClient = injectedFirestore;
  async function firestore() {
    if (!firestoreClient) {
      const { Firestore } = await import("@google-cloud/firestore");
      firestoreClient = new Firestore();
    }
    return firestoreClient;
  }

  return {
    async checkAndConsume({ principal }) {
      const db = await firestore();
      const document = db.collection(collectionName).doc(principal);
      return db.runTransaction(async (transaction) => {
        const snapshot = await transaction.get(document);
        const timestamp = numericTimestamp(now());
        const decision = principalAttemptDecision({
          events: snapshot.exists && Array.isArray(snapshot.get("attemptTimestamps"))
            ? snapshot.get("attemptTimestamps")
            : [],
          timestamp,
          minuteLimit,
          rollingLimit,
        });
        if (decision.response.allowed) {
          transaction.set(document, {
            attemptTimestamps: decision.events.map((value) => new Date(value)),
            minuteLimit,
            rollingLimit,
            updatedAt: new Date(timestamp),
            expiresAt: new Date(timestamp + 3 * ROLLING_WINDOW_SECONDS * 1_000),
          });
        }
        return decision.response;
      });
    },
  };
}

function principalAttemptDecision({ events, timestamp, minuteLimit, rollingLimit }) {
  const activeEvents = activeRollingEvents(events, timestamp);
  const minuteCutoff = timestamp - 60_000;
  const minuteEvents = activeEvents.filter((value) => value > minuteCutoff);
  const minuteAllowed = minuteEvents.length < minuteLimit;
  const rollingAllowed = activeEvents.length < rollingLimit;
  const allowed = minuteAllowed && rollingAllowed;
  if (allowed) activeEvents.push(timestamp);
  const reason = allowed
    ? null
    : !rollingAllowed
      ? "principal_attempt_rolling_limit_exceeded"
      : "principal_attempt_minute_limit_exceeded";
  const retryAt = !rollingAllowed
    ? activeEvents[0] + ROLLING_WINDOW_SECONDS * 1_000
    : !minuteAllowed
      ? minuteEvents[0] + 60_000
      : null;
  return {
    events: activeEvents,
    response: {
      allowed,
      reason,
      remainingMinute: Math.max(0, minuteLimit - minuteEvents.length - (allowed ? 1 : 0)),
      remaining24Hours: Math.max(0, rollingLimit - activeEvents.length),
      retryAfterSeconds: retryAt === null
        ? null
        : Math.max(1, Math.ceil((retryAt - timestamp) / 1_000)),
    },
  };
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
        lifetimeUsed: allowed && input.lifetimeLimit !== null
          ? existing.lifetimeUsed + 1
          : existing.lifetimeUsed,
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
        lifetimeUsed: existing.lifetimeUsed,
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
          expiresAt: rollingQuotaExpiresAt(input.lifetimeLimit, timestamp),
        };
        transaction.set(document, record, { merge: true });
        return rollingQuotaSnapshot({
          ...input,
          events: activeEvents,
          lifetimeUsed: record.lifetimeUsed,
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
      const lifetimeUsed = snapshot.exists ? Number(snapshot.get("lifetimeUsed") ?? 0) : 0;
      return rollingQuotaSnapshot({
        ...input,
        events: activeRollingEvents(storedEvents, timestamp),
        lifetimeUsed,
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

function rollingQuotaExpiresAt(lifetimeLimit, timestamp) {
  return lifetimeLimit === null
    ? new Date(timestamp + 3 * ROLLING_WINDOW_SECONDS * 1_000)
    : null;
}

function numericTimestamp(value) {
  if (Number.isFinite(value)) return Number(value);
  const date = value?.toDate?.() ?? new Date(value);
  return date.getTime();
}

function rollingQuotaSnapshot({ tier, limit, lifetimeLimit, lifetimeUsed = 0, events, timestamp, allowed, reason }) {
  const used = events.length;
  const resetTimestamp = used > 0 ? events[0] + ROLLING_WINDOW_SECONDS * 1_000 : null;
  const exhausted = used >= limit;
  const lifetimeExhausted = lifetimeLimit !== null && lifetimeUsed >= lifetimeLimit;
  const rollingRemaining = Math.max(0, limit - used);
  const remaining = lifetimeLimit === null
    ? rollingRemaining
    : Math.min(rollingRemaining, Math.max(0, lifetimeLimit - lifetimeUsed));
  return {
    allowed,
    reason: allowed ? null : reason,
    tier,
    used,
    limit,
    remaining,
    windowSeconds: ROLLING_WINDOW_SECONDS,
    resetAt: lifetimeExhausted || resetTimestamp === null ? null : new Date(resetTimestamp).toISOString(),
    retryAfterSeconds:
      !lifetimeExhausted && exhausted && resetTimestamp !== null
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

function createConfiguredIdempotencyStore({
  environment,
  pendingTtlMs,
  globalProviderMinuteLimit,
  globalProviderRollingLimit,
}) {
  if (environment.MEAL_SCAN_IDEMPOTENCY_STORE === "firestore") {
    return createFirestoreIdempotencyStore({
      collectionName: environment.MEAL_SCAN_IDEMPOTENCY_COLLECTION ?? "mealScanIdempotency",
      quotaCollectionName: environment.MEAL_SCAN_QUOTA_COLLECTION ?? "mealScanRollingQuota",
      pendingTtlMs,
      globalProviderMinuteLimit,
      globalProviderRollingLimit,
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

export function createFirestoreIdempotencyStore({
  collectionName,
  quotaCollectionName = "mealScanRollingQuota",
  pendingTtlMs,
  globalProviderMinuteLimit = MAX_GLOBAL_PROVIDER_DISPATCHES_PER_MINUTE,
  globalProviderRollingLimit = MAX_GLOBAL_PROVIDER_DISPATCHES_PER_24_HOURS,
  globalProviderDocumentId = "__globalProviderDispatch__",
  firestore: injectedFirestore,
  now = Date.now,
  randomUUID = crypto.randomUUID,
}) {
  let firestoreClient = injectedFirestore;
  async function firestore() {
    if (!firestoreClient) {
      const { Firestore } = await import("@google-cloud/firestore");
      firestoreClient = new Firestore();
    }
    return firestoreClient;
  }
  const documentId = (requestId) => crypto.createHash("sha256").update(requestId).digest("hex");

  return {
    async inspect({ requestId, requestHash }) {
      const db = await firestore();
      const document = db.collection(collectionName).doc(documentId(requestId));
      return db.runTransaction(async (transaction) => {
        const snapshot = await transaction.get(document);
        if (!snapshot.exists) return { state: "missing", acquired: false };
        if (snapshot.get("requestHash") !== requestHash) {
          return { state: "mismatch", acquired: false };
        }
        let state = snapshot.get("state");
        const timestamp = numericTimestamp(now());
        if (state === "pending" && numericTimestamp(snapshot.get("pendingExpiresAt")) <= timestamp) {
          state = "unknown";
          transaction.set(document, { state, updatedAt: new Date(timestamp) }, { merge: true });
        }
        return state === "completed"
          ? { state, acquired: false, response: snapshot.get("response") }
          : { state, acquired: false };
      });
    },
    async claim({ requestId, requestHash }) {
      const db = await firestore();
      const document = db.collection(collectionName).doc(documentId(requestId));
      return db.runTransaction(async (transaction) => {
        const snapshot = await transaction.get(document);
        const timestamp = numericTimestamp(now());
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
        const claimId = randomUUID();
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
    async claimAndConsumeQuota({ requestId, requestHash, quota }) {
      const db = await firestore();
      const idempotencyDocument = db.collection(collectionName).doc(documentId(requestId));
      const quotaDocument = db.collection(quotaCollectionName).doc(quota.principal);
      const globalProviderDocument = db.collection(quotaCollectionName).doc(globalProviderDocumentId);
      return db.runTransaction(async (transaction) => {
        const existingClaim = await transaction.get(idempotencyDocument);
        const timestamp = numericTimestamp(now());
        if (existingClaim.exists) {
          if (existingClaim.get("requestHash") !== requestHash) {
            return { state: "mismatch", acquired: false };
          }
          let state = existingClaim.get("state");
          if (state === "pending" && numericTimestamp(existingClaim.get("pendingExpiresAt")) <= timestamp) {
            state = "unknown";
            transaction.set(
              idempotencyDocument,
              { state, updatedAt: new Date(timestamp) },
              { merge: true }
            );
          }
          return state === "completed"
            ? { state, acquired: false, response: existingClaim.get("response") }
            : { state, acquired: false };
        }

        const quotaSnapshot = await transaction.get(quotaDocument);
        const globalProviderSnapshot = await transaction.get(globalProviderDocument);
        const activeLeaseExpiresAt = numericTimestamp(quotaSnapshot.get("providerLeaseExpiresAt"));
        if (
          quotaSnapshot.exists &&
          boundedString(quotaSnapshot.get("providerLeaseClaimId"), 1, 256) &&
          Number.isFinite(activeLeaseExpiresAt) &&
          activeLeaseExpiresAt > timestamp
        ) {
          return {
            state: "principal_busy",
            acquired: false,
            reason: "principal_dispatch_in_progress",
            retryAfterSeconds: Math.max(1, Math.ceil((activeLeaseExpiresAt - timestamp) / 1_000)),
          };
        }

        const globalProviderDecision = providerDispatchDecision({
          events:
            globalProviderSnapshot.exists &&
            Array.isArray(globalProviderSnapshot.get("dispatchTimestamps"))
              ? globalProviderSnapshot.get("dispatchTimestamps")
              : [],
          timestamp,
          minuteLimit: globalProviderMinuteLimit,
          rollingLimit: globalProviderRollingLimit,
        });
        if (!globalProviderDecision.allowed) {
          return {
            state: "provider_limit_denied",
            acquired: false,
            reason: globalProviderDecision.reason,
            retryAfterSeconds: globalProviderDecision.retryAfterSeconds,
          };
        }

        const storedEvents = quotaSnapshot.exists && Array.isArray(quotaSnapshot.get("dispatchTimestamps"))
          ? quotaSnapshot.get("dispatchTimestamps")
          : [];
        const activeEvents = activeRollingEvents(storedEvents, timestamp);
        const lifetimeUsed = quotaSnapshot.exists ? Number(quotaSnapshot.get("lifetimeUsed") ?? 0) : 0;
        const rollingAllowed = activeEvents.length < quota.limit;
        const lifetimeAllowed = quota.lifetimeLimit === null || lifetimeUsed < quota.lifetimeLimit;
        const allowed = rollingAllowed && lifetimeAllowed;
        if (!allowed) {
          const deniedQuota = rollingQuotaSnapshot({
            ...quota,
            events: activeEvents,
            lifetimeUsed,
            timestamp,
            allowed: false,
            reason: rollingAllowed ? "trial_lifetime_quota_exceeded" : "rolling_quota_exceeded",
          });
          return { state: "quota_denied", acquired: false, quota: deniedQuota };
        }

        activeEvents.push(timestamp);
        const nextLifetimeUsed = quota.lifetimeLimit === null ? lifetimeUsed : lifetimeUsed + 1;
        const claimId = randomUUID();
        transaction.set(
          quotaDocument,
          {
            tier: quota.tier,
            dispatchTimestamps: activeEvents.map((value) => new Date(value)),
            lifetimeUsed: nextLifetimeUsed,
            rollingLimit: quota.limit,
            lifetimeLimit: quota.lifetimeLimit,
            providerLeaseRequestId: requestId,
            providerLeaseClaimId: claimId,
            providerLeaseExpiresAt: new Date(timestamp + pendingTtlMs),
            updatedAt: new Date(timestamp),
            expiresAt: rollingQuotaExpiresAt(quota.lifetimeLimit, timestamp),
          },
          { merge: true }
        );
        transaction.set(
          globalProviderDocument,
          {
            scope: "global_provider_dispatch",
            dispatchTimestamps: globalProviderDecision.events.map((value) => new Date(value)),
            minuteLimit: globalProviderMinuteLimit,
            rollingLimit: globalProviderRollingLimit,
            updatedAt: new Date(timestamp),
            expiresAt: new Date(timestamp + 3 * ROLLING_WINDOW_SECONDS * 1_000),
          },
          { merge: true }
        );
        transaction.create(idempotencyDocument, {
          requestHash,
          principal: quota.principal,
          claimId,
          state: "pending",
          quotaReserved: true,
          createdAt: new Date(timestamp),
          updatedAt: new Date(timestamp),
          pendingExpiresAt: new Date(timestamp + pendingTtlMs),
          expiresAt: new Date(timestamp + 7 * ROLLING_WINDOW_SECONDS * 1_000),
        });
        return {
          requestId,
          requestHash,
          documentId: idempotencyDocument.id,
          principal: quota.principal,
          claimId,
          state: "pending",
          acquired: true,
          quota: rollingQuotaSnapshot({
            ...quota,
            events: activeEvents,
            lifetimeUsed: nextLifetimeUsed,
            timestamp,
            allowed: true,
            reason: null,
          }),
        };
      });
    },
    async completeFromCache({ requestId, requestHash, response }) {
      const db = await firestore();
      const document = db.collection(collectionName).doc(documentId(requestId));
      return db.runTransaction(async (transaction) => {
        const snapshot = await transaction.get(document);
        if (snapshot.exists && snapshot.get("requestHash") !== requestHash) {
          return { state: "mismatch", acquired: false };
        }
        if (snapshot.exists && snapshot.get("state") === "completed") {
          return { state: "completed", response: snapshot.get("response"), acquired: false };
        }
        if (snapshot.exists) {
          let state = snapshot.get("state");
          const timestamp = numericTimestamp(now());
          if (state === "pending" && numericTimestamp(snapshot.get("pendingExpiresAt")) <= timestamp) {
            state = "unknown";
            transaction.set(document, { state, updatedAt: new Date(timestamp) }, { merge: true });
          }
          return { state, acquired: false };
        }
        const timestamp = numericTimestamp(now());
        transaction.set(document, {
          requestHash,
          state: "completed",
          response: structuredClone(response),
          createdAt: new Date(timestamp),
          updatedAt: new Date(timestamp),
          expiresAt: new Date(timestamp + 7 * ROLLING_WINDOW_SECONDS * 1_000),
        });
        return { state: "completed", response, acquired: false };
      });
    },
    async complete(context, response) {
      await finalizeFirestoreIdempotencyClaim({
        firestore: await firestore(),
        collectionName,
        quotaCollectionName,
        documentId: context.documentId,
        context,
        update: { state: "completed", response: structuredClone(response) },
        now,
      });
    },
    async markUnknown(context) {
      await finalizeFirestoreIdempotencyClaim({
        firestore: await firestore(),
        collectionName,
        quotaCollectionName,
        documentId: context.documentId,
        context,
        update: { state: "unknown" },
        now,
      });
    },
    async abandon(context) {
      await finalizeFirestoreIdempotencyClaim({
        firestore: await firestore(),
        collectionName,
        quotaCollectionName,
        documentId: context.documentId,
        context,
        deleteClaim: true,
        now,
      });
    },
  };
}

async function finalizeFirestoreIdempotencyClaim({
  firestore,
  collectionName,
  quotaCollectionName,
  documentId,
  context,
  update,
  deleteClaim = false,
  now = Date.now,
}) {
  const document = firestore.collection(collectionName).doc(documentId);
  const quotaDocument = context.principal
    ? firestore.collection(quotaCollectionName).doc(context.principal)
    : null;
  await firestore.runTransaction(async (transaction) => {
    const snapshot = await transaction.get(document);
    const quotaSnapshot = quotaDocument ? await transaction.get(quotaDocument) : null;
    if (
      !snapshot.exists ||
      snapshot.get("state") !== "pending" ||
      snapshot.get("claimId") !== context.claimId ||
      snapshot.get("requestHash") !== context.requestHash
    ) {
      throw idempotencyClaimError();
    }
    if (deleteClaim) {
      transaction.delete(document);
    } else {
      transaction.set(
        document,
        { ...update, updatedAt: new Date(numericTimestamp(now())) },
        { merge: true }
      );
    }
    if (
      quotaDocument &&
      quotaSnapshot?.exists &&
      quotaSnapshot.get("providerLeaseRequestId") === context.requestId &&
      quotaSnapshot.get("providerLeaseClaimId") === context.claimId
    ) {
      transaction.set(
        quotaDocument,
        {
          providerLeaseRequestId: null,
          providerLeaseClaimId: null,
          providerLeaseExpiresAt: null,
        },
        { merge: true }
      );
    }
  });
}

function providerDispatchDecision({ events, timestamp, minuteLimit, rollingLimit }) {
  const activeEvents = activeRollingEvents(events, timestamp);
  const minuteEvents = activeEvents.filter((value) => value > timestamp - 60_000);
  const minuteAllowed = minuteEvents.length < minuteLimit;
  const rollingAllowed = activeEvents.length < rollingLimit;
  if (!minuteAllowed || !rollingAllowed) {
    const rollingDenied = !rollingAllowed;
    const retryAt = rollingDenied
      ? activeEvents[0] + ROLLING_WINDOW_SECONDS * 1_000
      : minuteEvents[0] + 60_000;
    return {
      allowed: false,
      events: activeEvents,
      reason: rollingDenied
        ? "global_provider_rolling_limit_exceeded"
        : "global_provider_minute_limit_exceeded",
      retryAfterSeconds: Math.max(1, Math.ceil((retryAt - timestamp) / 1_000)),
    };
  }
  activeEvents.push(timestamp);
  return { allowed: true, events: activeEvents, reason: null, retryAfterSeconds: null };
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

export function createFirestoreResultCache({
  collectionName,
  ttlMs,
  leaseTtlMs,
  firestore: injectedFirestore,
  now = Date.now,
}) {
  let firestoreClient = injectedFirestore;
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
      return db.runTransaction(async (transaction) => {
        const snapshot = await transaction.get(document);
        if (!snapshot.exists) return null;

        const expiresAtValue = snapshot.get("expiresAt");
        const expiresAt = expiresAtValue?.toDate?.() ?? new Date(expiresAtValue);
        if (!Number.isFinite(expiresAt.getTime()) || expiresAt.getTime() <= now()) {
          transaction.delete(document);
          return null;
        }
        return snapshot.get("value") ?? null;
      });
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

function normalizedCanaryDigest(value) {
  if (value === undefined || value === null || value === "") return null;
  if (!isSha256Hex(value)) {
    throw new Error("MEAL_SCAN_CANARY_CORRELATION_SHA256 must be a SHA-256 hex digest");
  }
  return value.toLowerCase();
}

function canonicalCanaryId(value) {
  return typeof value === "string" &&
    /^[0-9a-f]{8}-[0-9a-f]{4}-[1-8][0-9a-f]{3}-[89ab][0-9a-f]{3}-[0-9a-f]{12}$/.test(value);
}

function isSha256Hex(value) {
  return typeof value === "string" && /^[a-f0-9]{64}$/i.test(value);
}

function sha256Hex(value) {
  return crypto.createHash("sha256").update(value).digest("hex");
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
  const maxStateAgeSeconds = positiveInteger(
    environment.MEAL_SCAN_BUDGET_STATE_MAX_AGE_SECONDS,
    DEFAULT_BUDGET_STATE_MAX_AGE_SECONDS
  );
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
    const spendUsd = numberOrNull(control.spendUsd);
    if (spendUsd === null || spendUsd < 0) {
      throw new Error("meal scan budget control spendUsd is invalid");
    }
    if (control.manualMode != null && !validBudgetMode(control.manualMode)) {
      throw new Error("meal scan budget control manualMode is invalid");
    }
    if (control.billingMode != null && !validBudgetMode(control.billingMode)) {
      throw new Error("meal scan budget control billingMode is invalid");
    }
    const manualMode = validBudgetMode(control.manualMode) ? control.manualMode : null;
    const billingMode = validBudgetMode(control.billingMode) ? control.billingMode : null;
    if (!manualMode && !billingMode) {
      throw new Error("meal scan budget control mode is invalid");
    }

    const billingIsMoreRestrictive =
      manualMode && billingMode && budgetModeRank(billingMode) > budgetModeRank(manualMode);
    const normalized = normalizeBudgetState({
      ...control,
      spendUsd,
      mode: mostRestrictiveBudgetMode(manualMode, billingMode),
      source: billingIsMoreRestrictive
        ? "fail_closed_combined_control"
        : (manualMode ? "manual_override" : "cloud_billing_budget"),
    }, environment);
    const updatedAt = numericTimestamp(control.updatedAt);
    const stateAgeSeconds = Number.isFinite(updatedAt)
      ? Math.max(0, (timestamp - updatedAt) / 1_000)
      : null;
    cached = {
      ...normalized,
      stale: stateAgeSeconds === null || stateAgeSeconds > maxStateAgeSeconds,
      stateAgeSeconds,
    };
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
    numberOrNull(environment.MEAL_SCAN_MONTHLY_BUDGET_ALERT_USD) ??
    numberOrNull(input?.alertAtUsd) ??
    DEFAULT_BUDGET_ALERT_USD;
  const degradeAtUsd =
    numberOrNull(environment.MEAL_SCAN_MONTHLY_BUDGET_DEGRADE_USD) ??
    numberOrNull(input?.degradeAtUsd) ??
    DEFAULT_BUDGET_DEGRADE_USD;
  const disableAtUsd =
    numberOrNull(environment.MEAL_SCAN_MONTHLY_BUDGET_DISABLE_USD) ??
    numberOrNull(input?.disableAtUsd) ??
    DEFAULT_BUDGET_DISABLE_USD;
  if (
    alertAtUsd < 0 ||
    degradeAtUsd < alertAtUsd ||
    disableAtUsd < degradeAtUsd ||
    disableAtUsd <= 0
  ) {
    throw new Error("meal scan budget control thresholds are invalid");
  }
  const storedMode = validBudgetMode(input?.mode) ? input.mode : "normal";
  const spendMode = spendUsd >= disableAtUsd
    ? "disabled"
    : spendUsd >= degradeAtUsd
      ? "degraded"
      : spendUsd >= alertAtUsd
        ? "alert"
        : "normal";
  const mode = mostRestrictiveBudgetMode(storedMode, spendMode);
  const inputSource = typeof input?.source === "string" ? input.source : null;
  const source = budgetModeRank(spendMode) > budgetModeRank(storedMode) && inputSource !== "static_environment"
    ? "fail_closed_spend_control"
    : inputSource;

  const state = {
    mode,
    source,
    spendUsd,
    budgetUsd: numberOrNull(input?.budgetUsd),
    alertAtUsd,
    degradeAtUsd,
    disableAtUsd,
  };
  if (Object.hasOwn(input ?? {}, "stale")) state.stale = input.stale === true;
  if (Object.hasOwn(input ?? {}, "stateAgeSeconds")) {
    state.stateAgeSeconds = numberOrNull(input.stateAgeSeconds);
  }
  return state;
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
  response[SCANNER_RESPONSE_OBSERVER]?.(status, body);
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
