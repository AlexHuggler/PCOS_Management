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
