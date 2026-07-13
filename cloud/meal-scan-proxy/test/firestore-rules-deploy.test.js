import assert from "node:assert/strict";
import { existsSync, readFileSync } from "node:fs";
import path from "node:path";
import test from "node:test";
import { fileURLToPath } from "node:url";

const testDirectory = path.dirname(fileURLToPath(import.meta.url));
const proxyDirectory = path.resolve(testDirectory, "..");
const rulesPath = path.join(proxyDirectory, "firestore.rules");
const scriptPath = path.join(proxyDirectory, "scripts/deploy-firestore-rules.sh");
const bootstrapPath = path.join(proxyDirectory, "scripts/bootstrap-gcp.sh");
const cloudRunDeployPath = path.join(proxyDirectory, "scripts/deploy-cloud-run.sh");
const dockerfilePath = path.join(proxyDirectory, "Dockerfile");

test("Firestore mobile and web clients are denied all proxy-owned data", () => {
  assert.equal(existsSync(rulesPath), true, "firestore.rules must be version controlled");
  const rulesSource = readFileSync(rulesPath, "utf8");

  assert.match(rulesSource, /rules_version\s*=\s*['\"]2['\"]/);
  assert.match(rulesSource, /match\s+\/\{document=\*\*\}/);
  assert.match(rulesSource, /allow\s+read\s*,\s*write\s*:\s*if\s+false\s*;/);
  assert.doesNotMatch(rulesSource, /if\s+true\s*;/);
});

test("rules deployment is pinned, token-safe, and verifies the deployed release", () => {
  assert.equal(existsSync(scriptPath), true, "rules deploy script must be version controlled");
  const scriptSource = readFileSync(scriptPath, "utf8");

  assert.match(scriptSource, /cyclebalance-prod-20260710/);
  assert.match(scriptSource, /PROJECT_ID.+pinned to the production project/);
  assert.match(scriptSource, /gcloud auth print-access-token/);
  assert.match(scriptSource, /x-goog-user-project:/);
  assert.match(scriptSource, /auth_header_curl_config/);
  assert.match(scriptSource, /API_ROOT=.*projects\/\$PROJECT_ID/);
  assert.match(scriptSource, /\$API_ROOT\/rulesets/);
  assert.match(scriptSource, /\$API_ROOT\/releases/);
  assert.match(scriptSource, /cloud\.firestore/);
  assert.match(scriptSource, /rulesetName/);
  assert.doesNotMatch(scriptSource, /set -x/);
  assert.doesNotMatch(scriptSource, /Authorization:\s*Bearer\s*\$\{?access_token/i);
});

test("production bootstrap enables and deploys Firebase Rules", () => {
  const bootstrapSource = readFileSync(bootstrapPath, "utf8");

  assert.match(bootstrapSource, /firebaserules\.googleapis\.com/);
  assert.match(bootstrapSource, /deploy-firestore-rules\.sh/);
});

test("request-abuse counters are isolated from billable quota and have TTL cleanup", () => {
  const bootstrapSource = readFileSync(bootstrapPath, "utf8");
  const deploySource = readFileSync(cloudRunDeployPath, "utf8");

  assert.match(bootstrapSource, /REQUEST_GATE_COLLECTION_NAME="\$\{REQUEST_GATE_COLLECTION_NAME:-mealScanRequestGate\}"/);
  assert.match(
    bootstrapSource,
    /--collection-group="\$REQUEST_GATE_COLLECTION_NAME"[\s\S]*?--enable-ttl/
  );
  assert.match(deploySource, /MEAL_SCAN_REQUEST_GATE_COLLECTION=mealScanRequestGate/);
});

test("bootstrap provisions every deployed secret and TTL-managed active collection", () => {
  const bootstrapSource = readFileSync(bootstrapPath, "utf8");

  assert.match(bootstrapSource, /PRINCIPAL_HMAC_SECRET_NAME="\$\{PRINCIPAL_HMAC_SECRET_NAME:-cyclebalance-meal-scan-principal-hmac\}"/);
  assert.match(bootstrapSource, /APPLE_IAP_PRIVATE_KEY_SECRET_NAME="\$\{APPLE_IAP_PRIVATE_KEY_SECRET_NAME:-cyclebalance-app-store-iap-private-key\}"/);
  assert.match(bootstrapSource, /REVENUECAT_SECRET_NAME="\$\{REVENUECAT_SECRET_NAME:-cyclebalance-revenuecat-secret-api-key\}"/);
  assert.match(bootstrapSource, /add_secret_version_from_prompt "\$PRINCIPAL_HMAC_SECRET_NAME"/);
  assert.match(bootstrapSource, /add_secret_version_from_file_prompt "\$APPLE_IAP_PRIVATE_KEY_SECRET_NAME"/);
  assert.match(bootstrapSource, /ensure_secret "\$REVENUECAT_SECRET_NAME"/);
  assert.match(
    bootstrapSource,
    /for secret_name in[\s\S]*"\$REVENUECAT_SECRET_NAME"[\s\S]*roles\/secretmanager\.secretAccessor/
  );
  assert.match(
    bootstrapSource,
    /add_secret_version_from_prompt "\$REVENUECAT_SECRET_NAME"[^\n]*true/
  );
  assert.doesNotMatch(bootstrapSource, /add_secret_version_from_prompt "\$APPLE_IAP_PRIVATE_KEY_SECRET_NAME"/);
  assert.doesNotMatch(bootstrapSource, /add_secret_version_from_file_prompt "\$REVENUECAT_SECRET_NAME"/);

  for (const collection of [
    "mealScanRollingQuota",
    "mealScanIdempotency",
    "mealScanRequestGate",
    "mealScanPrincipalAttempts",
    "mealScanEstimateCache",
  ]) {
    assert.match(bootstrapSource, new RegExp(`:-${collection}\\}`));
  }
  assert.equal((bootstrapSource.match(/gcloud firestore fields ttls update expiresAt/g) ?? []).length, 5);
});

test("activation contract explicitly enables public ingress only with the scanner", () => {
  const deploySource = readFileSync(cloudRunDeployPath, "utf8");

  assert.match(
    deploySource,
    /MEAL_SCAN_ENABLED=true ALLOW_UNAUTHENTICATED=true PROJECT_ID=\$PROJECT_ID REGION=\$REGION/
  );
  assert.match(deploySource, /MEAL_SCAN_ENABLED="\$\{MEAL_SCAN_ENABLED:-false\}"/);
  assert.match(deploySource, /ALLOW_UNAUTHENTICATED="\$\{ALLOW_UNAUTHENTICATED:-false\}"/);
});

test("deploy pins the App Store API private key secret and uses bundled Apple roots", () => {
  const deploySource = readFileSync(cloudRunDeployPath, "utf8");

  assert.match(deploySource, /APPLE_IAP_PRIVATE_KEY_SECRET_VERSION="\$\{APPLE_IAP_PRIVATE_KEY_SECRET_VERSION:-\}"/);
  assert.match(deploySource, /APPLE_IAP_KEY_ID="\$\{APPLE_IAP_KEY_ID:-\}"/);
  assert.match(deploySource, /APPLE_IAP_ISSUER_ID="\$\{APPLE_IAP_ISSUER_ID:-\}"/);
  assert.match(deploySource, /APPLE_IAP_PRIVATE_KEY_SECRET_VERSION.+numeric pinned version/s);
  assert.match(
    deploySource,
    /APPLE_IAP_PRIVATE_KEY=\$\{APPLE_IAP_PRIVATE_KEY_SECRET_NAME\}:\$\{APPLE_IAP_PRIVATE_KEY_SECRET_VERSION\}/
  );
  assert.match(deploySource, /APPLE_IAP_KEY_ID=\$\{APPLE_IAP_KEY_ID\}/);
  assert.match(deploySource, /APPLE_IAP_ISSUER_ID=\$\{APPLE_IAP_ISSUER_ID\}/);
  assert.doesNotMatch(deploySource, /APPLE_ROOT_CA_BASE64/);
  assert.doesNotMatch(deploySource, /APPLE_IAP_PRIVATE_KEY=\$\{APPLE_IAP_PRIVATE_KEY\}/);
});

test("deploy pins the RevenueCat secret and strict secondary-verification identity", () => {
  const deploySource = readFileSync(cloudRunDeployPath, "utf8");

  assert.match(
    deploySource,
    /REVENUECAT_SECRET_NAME="\$\{REVENUECAT_SECRET_NAME:-cyclebalance-revenuecat-secret-api-key\}"/
  );
  assert.match(deploySource, /REVENUECAT_SECRET_VERSION="\$\{REVENUECAT_SECRET_VERSION:-\}"/);
  assert.match(deploySource, /REVENUECAT_PROJECT_ID="\$\{REVENUECAT_PROJECT_ID:-proj8da4e000\}"/);
  assert.match(
    deploySource,
    /REVENUECAT_ENTITLEMENT_ID="\$\{REVENUECAT_ENTITLEMENT_ID:-CycleBalance Unlimited\}"/
  );
  assert.match(deploySource, /REVENUECAT_SECRET_VERSION.+numeric pinned version/s);
  assert.match(deploySource, /pinned CycleBalance RevenueCat configuration/);
  assert.match(
    deploySource,
    /REVENUECAT_SECRET_API_KEY=\$\{REVENUECAT_SECRET_NAME\}:\$\{REVENUECAT_SECRET_VERSION\}/
  );
  assert.match(deploySource, /REVENUECAT_PROJECT_ID=\$\{REVENUECAT_PROJECT_ID\}/);
  assert.match(deploySource, /REVENUECAT_ENTITLEMENT_ID=\$\{REVENUECAT_ENTITLEMENT_ID\}/);
  assert.match(deploySource, /REVENUECAT_TIMEOUT_MS=3000/);
  assert.doesNotMatch(deploySource, /REVENUECAT_SECRET_API_KEY=\$\{REVENUECAT_SECRET_API_KEY\}/);
  assert.doesNotMatch(deploySource, /REVENUECAT_SECRET_VERSION:-latest/);
});

test("Cloud Run image copies the bundled Apple trust anchors required at startup", () => {
  const dockerfileSource = readFileSync(dockerfilePath, "utf8");

  assert.match(dockerfileSource, /COPY --chown=node:node certs \.\/certs/);
});

test("deploy pins Apple identity and durable attempt and provider ceilings", () => {
  const deploySource = readFileSync(cloudRunDeployPath, "utf8");

  assert.match(deploySource, /APPLE_BUNDLE_ID="\$\{APPLE_BUNDLE_ID:-alex\.PCOS\}"/);
  assert.match(deploySource, /APPLE_APP_ID="\$\{APPLE_APP_ID:-6760353511\}"/);
  assert.match(
    deploySource,
    /APPLE_ALLOWED_PRODUCT_IDS="\$\{APPLE_ALLOWED_PRODUCT_IDS:-cyclebalance\.premium\.monthly,cyclebalance\.premium\.annual\}"/
  );
  assert.match(deploySource, /pinned CycleBalance Apple identity/);
  assert.match(deploySource, /MEAL_SCAN_PRINCIPAL_ATTEMPT_STORE=firestore/);
  assert.match(deploySource, /MEAL_SCAN_PRINCIPAL_ATTEMPT_COLLECTION=mealScanPrincipalAttempts/);
  assert.match(deploySource, /MEAL_SCAN_PRINCIPAL_ATTEMPTS_PER_MINUTE_LIMIT=3/);
  assert.match(deploySource, /MEAL_SCAN_PRINCIPAL_ATTEMPTS_PER_24_HOURS_LIMIT=30/);
  assert.match(deploySource, /MEAL_SCAN_GLOBAL_PROVIDER_DISPATCHES_PER_MINUTE_LIMIT=60/);
  assert.match(deploySource, /MEAL_SCAN_GLOBAL_PROVIDER_DISPATCHES_PER_24_HOURS_LIMIT=1000/);
});

test("every Cloud Run deployment first deploys and verifies deny-all Firebase Rules", () => {
  const deploySource = readFileSync(cloudRunDeployPath, "utf8");
  const rulesCall = deploySource.indexOf("deploy-firestore-rules.sh");
  const cloudRunCall = deploySource.indexOf("gcloud run deploy");

  assert.ok(rulesCall >= 0, "Cloud Run deployment must invoke the Firebase Rules deployment");
  assert.ok(cloudRunCall > rulesCall, "Firebase Rules must be verified before Cloud Run deployment");
});

test("Cloud Run deployment explicitly controls both unauthenticated access mechanisms", () => {
  const deploySource = readFileSync(cloudRunDeployPath, "utf8");
  const deployCall = deploySource.indexOf("gcloud run deploy");
  const accessUpdateCall = deploySource.indexOf("gcloud run services update", deployCall);

  assert.match(deploySource, /--allow-unauthenticated/);
  assert.match(deploySource, /--no-allow-unauthenticated/);
  assert.match(deploySource, /--no-invoker-iam-check/);
  assert.match(deploySource, /--invoker-iam-check/);
  assert.match(deploySource, /"\$INVOKER_IAM_CHECK_FLAG"/);
  assert.ok(accessUpdateCall > deployCall, "access mode must be enforced after the source deploy");
  assert.match(deploySource, /wait_for_invoker_access_state/);
  assert.match(deploySource, /expected anonymous HTTP 403 or 404/);
  assert.match(deploySource, /public HTTP 401 App Check challenge/);
});

test("Cloud Run access verification allows a three-minute IAM propagation window", () => {
  const deploySource = readFileSync(cloudRunDeployPath, "utf8");

  assert.match(deploySource, /INVOKER_ACCESS_ATTEMPTS="\$\{INVOKER_ACCESS_ATTEMPTS:-90\}"/);
  assert.match(deploySource, /attempt <= INVOKER_ACCESS_ATTEMPTS/);
});
