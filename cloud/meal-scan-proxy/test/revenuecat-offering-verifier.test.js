import assert from "node:assert/strict";
import { createHash } from "node:crypto";
import {
  chmodSync,
  cpSync,
  existsSync,
  mkdtempSync,
  mkdirSync,
  readFileSync,
  readdirSync,
  rmSync,
  statSync,
  writeFileSync,
} from "node:fs";
import { tmpdir } from "node:os";
import path from "node:path";
import { spawnSync } from "node:child_process";
import test from "node:test";
import { fileURLToPath } from "node:url";

const testDirectory = path.dirname(fileURLToPath(import.meta.url));
const proxyDirectory = path.resolve(testDirectory, "..");
const scriptPath = path.join(proxyDirectory, "scripts/verify-revenuecat-offering-v2.sh");
const sourceFixtureDirectory = path.join(testDirectory, "fixtures/revenuecat");
const sensitiveKey = "sk_test_REVENUECAT_SENTINEL_MUST_NOT_PERSIST_0123456789";

function runVerifier(environment = {}, options = {}) {
  return spawnSync("bash", [scriptPath], {
    cwd: proxyDirectory,
    encoding: "utf8",
    env: { ...process.env, ...environment },
    ...options,
  });
}

function rewriteJson(filePath, transform) {
  const value = JSON.parse(readFileSync(filePath, "utf8"));
  writeFileSync(filePath, `${JSON.stringify(transform(value), null, 2)}\n`);
}

function createFixtureHarness({ mutate, httpStatus = "200" } = {}) {
  const directory = mkdtempSync(path.join(tmpdir(), "cyclebalance-revenuecat-fixture-"));
  const binDirectory = path.join(directory, "bin");
  const fixtureDirectory = path.join(directory, "fixtures");
  const requestLog = path.join(directory, "requests.log");
  mkdirSync(binDirectory);
  cpSync(sourceFixtureDirectory, fixtureDirectory, { recursive: true });
  if (mutate) {
    mutate(fixtureDirectory);
  }

  const expectedConfig = `header = "Authorization: Bearer ${sensitiveKey}"`;
  const expectedConfigSha256 = createHash("sha256").update(expectedConfig).digest("hex");
  const curlPath = path.join(binDirectory, "curl");
  writeFileSync(
    curlPath,
    `#!/usr/bin/env bash
set -euo pipefail
printf '%s\\n' "$*" >>"$REQUEST_LOG"
config="$(cat)"
actual_config_sha256="$(printf '%s' "$config" | shasum -a 256 | awk '{print $1}')"
unset config
[[ "$actual_config_sha256" == "$EXPECTED_CONFIG_SHA256" ]] || exit 91

output_file=""
url=""
while (( $# > 0 )); do
  case "$1" in
    --output) output_file="$2"; shift 2 ;;
    --output=*) output_file="\${1#--output=}"; shift ;;
    http://*|https://*) url="$1"; shift ;;
    *) shift ;;
  esac
done
[[ -n "$output_file" && -n "$url" ]] || exit 92

status="\${FIXTURE_HTTP_STATUS:-200}"
if [[ "$status" != "200" ]]; then
  printf '{"error":"SENSITIVE_UPSTREAM_BODY_MUST_NOT_BE_PRINTED"}\\n' >"$output_file"
  printf '%s' "$status"
  exit 0
fi

case "$url" in
  *"/offerings?limit=100") fixture="offerings.json" ;;
  *"/offerings/ofrng_cyclebalance_default/packages?limit=100") fixture="packages.json" ;;
  *"/packages/pkge_cyclebalance_monthly/products?limit=100") fixture="monthly-products.json" ;;
  *"/packages/pkge_cyclebalance_annual/products?limit=100") fixture="annual-products.json" ;;
  *"/entitlements?limit=100") fixture="entitlements.json" ;;
  *"/entitlements/entl_cyclebalance_unlimited/products?limit=100") fixture="entitlement-products.json" ;;
  *) exit 93 ;;
esac
cp "$FIXTURE_DIR/$fixture" "$output_file"
printf '200'
`
  );
  chmodSync(curlPath, 0o755);

  return {
    directory,
    fixtureDirectory,
    requestLog,
    environment: {
      DRY_RUN: "false",
      PATH: `${binDirectory}:/opt/homebrew/bin:/usr/local/bin:/usr/bin:/bin`,
      TMPDIR: directory,
      REQUEST_LOG: requestLog,
      FIXTURE_DIR: fixtureDirectory,
      FIXTURE_HTTP_STATUS: httpStatus,
      EXPECTED_CONFIG_SHA256: expectedConfigSha256,
    },
    cleanup() {
      rmSync(directory, { recursive: true, force: true });
    },
  };
}

test("RevenueCat configuration verification defaults to a non-networking dry run", () => {
  assert.equal(existsSync(scriptPath), true, `missing ${scriptPath}`);
  assert.notEqual(statSync(scriptPath).mode & 0o111, 0, "RevenueCat verifier must be executable");

  const directory = mkdtempSync(path.join(tmpdir(), "cyclebalance-revenuecat-dry-run-"));
  const binDirectory = path.join(directory, "bin");
  const commandLog = path.join(directory, "commands.log");
  mkdirSync(binDirectory);
  const curlPath = path.join(binDirectory, "curl");
  writeFileSync(
    curlPath,
    "#!/usr/bin/env bash\nprintf '%s\\n' \"$*\" >>\"$COMMAND_LOG\"\nexit 97\n"
  );
  chmodSync(curlPath, 0o755);

  try {
    const result = runVerifier({
      PATH: `${binDirectory}:/usr/bin:/bin`,
      COMMAND_LOG: commandLog,
    });
    assert.equal(result.status, 0, result.stderr);
    assert.match(result.stdout, /DRY RUN ONLY/i);
    assert.match(result.stdout, /default/);
    assert.match(result.stdout, /monthly.*annual/i);
    assert.match(result.stdout, /CycleBalance Unlimited/);
    const scopeGuidance = result.stdout
      .split("\n")
      .find((line) => line.startsWith("Required shared-key read-only scopes:"));
    assert.match(
      scopeGuidance ?? "",
      /Subscriptions.*Offerings.*Packages.*Entitlements/i,
      "dry-run scope guidance must list the complete shared-key read-only contract"
    );
    assert.doesNotMatch(
      scopeGuidance ?? "",
      /Products/i,
      "the verifier does not use a direct product endpoint or product expansion"
    );
    assert.equal(existsSync(commandLog) ? readFileSync(commandLog, "utf8") : "", "");
  } finally {
    rmSync(directory, { recursive: true, force: true });
  }
});

test("RevenueCat project identity is pinned before any key read or network request", () => {
  const result = runVerifier({ REVENUECAT_PROJECT_ID: "attacker-project" });
  assert.notEqual(result.status, 0);
  assert.match(result.stderr, /pinned/i);
});

test("valid multi-app fixtures prove the exact CycleBalance iOS offering products and entitlement attachments", () => {
  const harness = createFixtureHarness();
  try {
    const result = runVerifier(harness.environment, { input: `${sensitiveKey}\n` });
    assert.equal(result.status, 0, result.stderr);
    assert.match(result.stdout, /RevenueCat configuration verified/i);
    assert.match(result.stdout, /default/);
    assert.match(result.stdout, /monthly.*annual/i);
    assert.match(result.stdout, /CycleBalance Unlimited/);

    const requests = readFileSync(harness.requestLog, "utf8").trim().split("\n");
    assert.equal(requests.length, 6);
    assert.ok(
      requests.every((request) => request.startsWith("--disable --config - ")),
      "curl must disable user curlrc before loading the memory-only authorization config"
    );
    for (const expectedPath of [
      "/projects/proj8da4e000/offerings?limit=100",
      "/projects/proj8da4e000/offerings/ofrng_cyclebalance_default/packages?limit=100",
      "/projects/proj8da4e000/packages/pkge_cyclebalance_monthly/products?limit=100",
      "/projects/proj8da4e000/packages/pkge_cyclebalance_annual/products?limit=100",
      "/projects/proj8da4e000/entitlements?limit=100",
      "/projects/proj8da4e000/entitlements/entl_cyclebalance_unlimited/products?limit=100",
    ]) {
      assert.ok(requests.some((request) => request.includes(expectedPath)), `missing ${expectedPath}`);
    }
    assert.doesNotMatch(requests.join("\n"), /--request|\bPOST\b|\bPUT\b|\bPATCH\b|\bDELETE\b|--data/i);
    assert.doesNotMatch(requests.join("\n"), /\/actions\/|\/customers\/|\/subscribers\//);

    const allOutput = `${result.stdout}\n${result.stderr}\n${requests.join("\n")}`;
    assert.doesNotMatch(allOutput, /REVENUECAT_SENTINEL/);
    assert.doesNotMatch(allOutput, /Authorization|Bearer/);
    assert.equal(
      readdirSync(harness.directory).some((entry) => entry.startsWith("cyclebalance-revenuecat-v2.")),
      false,
      "temporary API response directory must be removed"
    );
  } finally {
    harness.cleanup();
  }
});

test("offering verification fails closed on non-current default or pagination", () => {
  for (const scenario of [
    {
      name: "not-current",
      mutate(directory) {
        rewriteJson(path.join(directory, "offerings.json"), (value) => {
          value.items[0].is_current = false;
          return value;
        });
      },
    },
    {
      name: "partial-page",
      mutate(directory) {
        rewriteJson(path.join(directory, "offerings.json"), (value) => {
          value.next_page = "/v2/projects/proj8da4e000/offerings?starting_after=hidden";
          return value;
        });
      },
    },
    {
      name: "missing-page-marker",
      mutate(directory) {
        rewriteJson(path.join(directory, "offerings.json"), (value) => {
          delete value.next_page;
          return value;
        });
      },
    },
  ]) {
    const harness = createFixtureHarness({ mutate: scenario.mutate });
    try {
      const result = runVerifier(harness.environment, { input: `${sensitiveKey}\n` });
      assert.notEqual(result.status, 0, `unsafe offering scenario passed: ${scenario.name}`);
      assert.match(result.stderr, /complete.*active current.*default offering/i);
    } finally {
      harness.cleanup();
    }
  }
});

test("package verification rejects extras and any wrong CycleBalance iOS product identity or duration", () => {
  const scenarios = [
    {
      name: "extra-package",
      mutate(directory) {
        rewriteJson(path.join(directory, "packages.json"), (value) => {
          value.items.push({ object: "package", id: "pkge_weekly", lookup_key: "weekly" });
          return value;
        });
      },
    },
    {
      name: "wrong-monthly-product",
      mutate(directory) {
        rewriteJson(path.join(directory, "monthly-products.json"), (value) => {
          value.items[0].product.store_identifier = "attacker.product";
          return value;
        });
      },
    },
    {
      name: "wrong-annual-duration",
      mutate(directory) {
        rewriteJson(path.join(directory, "annual-products.json"), (value) => {
          value.items[0].product.subscription.duration = "P1M";
          return value;
        });
      },
    },
    {
      name: "extra-cyclebalance-ios-product",
      mutate(directory) {
        rewriteJson(path.join(directory, "monthly-products.json"), (value) => {
          value.items.push({
            product: {
              state: "active",
              object: "product",
              id: "prod_unexpected_cyclebalance_monthly",
              store_identifier: "unexpected.product",
              type: "subscription",
              subscription: { duration: "P1M" },
              app_id: "appca3539a96a",
            },
            eligibility_criteria: "all",
          });
          return value;
        });
      },
    },
    {
      name: "missing-other-app-id",
      mutate(directory) {
        rewriteJson(path.join(directory, "monthly-products.json"), (value) => {
          delete value.items[1].product.app_id;
          return value;
        });
      },
    },
  ];

  for (const scenario of scenarios) {
    const harness = createFixtureHarness({ mutate: scenario.mutate });
    try {
      const result = runVerifier(harness.environment, { input: `${sensitiveKey}\n` });
      assert.notEqual(result.status, 0, `unsafe package scenario passed: ${scenario.name}`);
      assert.match(result.stderr, /exact monthly and annual package configuration/i);
    } finally {
      harness.cleanup();
    }
  }
});

test("entitlement verification requires exactly both CycleBalance iOS package products to be attached", () => {
  for (const scenario of [
    "wrong-lookup",
    "missing-product",
    "mismatched-product-id",
    "extra-cyclebalance-ios-product",
    "missing-other-app-id",
  ]) {
    const harness = createFixtureHarness({
      mutate(directory) {
        if (scenario === "wrong-lookup") {
          rewriteJson(path.join(directory, "entitlements.json"), (value) => {
            value.items[0].lookup_key = "premium";
            return value;
          });
        } else {
          rewriteJson(path.join(directory, "entitlement-products.json"), (value) => {
            if (scenario === "missing-product") {
              value.items = value.items.filter((item) => item.id !== "prod_cyclebalance_annual");
            }
            if (scenario === "mismatched-product-id") value.items[0].id = "prod_other_monthly";
            if (scenario === "extra-cyclebalance-ios-product") {
              value.items.push({
                state: "active",
                object: "product",
                id: "prod_unexpected_cyclebalance_product",
                store_identifier: "unexpected.product",
                type: "subscription",
                subscription: { duration: "P1M" },
                app_id: "appca3539a96a",
              });
            }
            if (scenario === "missing-other-app-id") delete value.items[2].app_id;
            return value;
          });
        }
      },
    });
    try {
      const result = runVerifier(harness.environment, { input: `${sensitiveKey}\n` });
      assert.notEqual(result.status, 0, `unsafe entitlement scenario passed: ${scenario}`);
      assert.match(result.stderr, /CycleBalance Unlimited entitlement.*exact.*products/i);
    } finally {
      harness.cleanup();
    }
  }
});

test("invalid keys and upstream errors fail without persisting or printing secrets or response bodies", () => {
  const invalidKeyHarness = createFixtureHarness();
  try {
    const result = runVerifier(invalidKeyHarness.environment, { input: "short\n" });
    assert.notEqual(result.status, 0);
    assert.match(result.stderr, /API v2 secret key format/i);
    assert.equal(existsSync(invalidKeyHarness.requestLog), false);
  } finally {
    invalidKeyHarness.cleanup();
  }

  const httpHarness = createFixtureHarness({ httpStatus: "403" });
  try {
    const result = runVerifier(httpHarness.environment, { input: `${sensitiveKey}\n` });
    assert.notEqual(result.status, 0);
    assert.match(result.stderr, /HTTP 403/i);
    const allOutput = `${result.stdout}\n${result.stderr}\n${readFileSync(httpHarness.requestLog, "utf8")}`;
    assert.doesNotMatch(allOutput, /REVENUECAT_SENTINEL/);
    assert.doesNotMatch(allOutput, /SENSITIVE_UPSTREAM_BODY/);
  } finally {
    httpHarness.cleanup();
  }
});
