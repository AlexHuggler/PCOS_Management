import assert from "node:assert/strict";
import {
  chmodSync,
  existsSync,
  mkdtempSync,
  mkdirSync,
  readFileSync,
  rmSync,
  statSync,
  symlinkSync,
  writeFileSync,
} from "node:fs";
import { tmpdir } from "node:os";
import path from "node:path";
import { spawnSync } from "node:child_process";
import test from "node:test";
import { fileURLToPath } from "node:url";

const testDirectory = path.dirname(fileURLToPath(import.meta.url));
const proxyDirectory = path.resolve(testDirectory, "..");
const repositoryRoot = path.resolve(proxyDirectory, "../..");
const scriptPath = path.join(proxyDirectory, "scripts/run-positive-general-kenobi-canary.sh");
const projectPath = path.join(repositoryRoot, "project.yml");
const scannerCanaryConfigPath = path.join(repositoryRoot, "Config/ScannerCanary.xcconfig");
const scannerCanaryConfigSource = existsSync(scannerCanaryConfigPath)
  ? readFileSync(scannerCanaryConfigPath, "utf8")
  : "";
const productionSetupPath = path.join(repositoryRoot, "docs/meal_scan_flash_lite_production_setup.md");
const appStoreReadinessPath = path.join(repositoryRoot, "AppStoreReadinessChecklist.md");
const scriptExists = existsSync(scriptPath);
const scriptSource = scriptExists ? readFileSync(scriptPath, "utf8") : "";
const projectSource = readFileSync(projectPath, "utf8");
const productionSetupSource = readFileSync(productionSetupPath, "utf8");
const appStoreReadinessSource = readFileSync(appStoreReadinessPath, "utf8");
const highEntropyGenericValue = "ABCDEFGHIJKLMNOPQRSTUVWXYZabcdefghijklmnopqr";
const genericUuidValue = "90b2ac63-e61f-49e1-a8b0-a5e85f154d4c";
const genericHexValue = "0123456789abcdef".repeat(4);
const identifierBypasses = Object.freeze([
  "00000000-0000-0000-0000-000000000000",
  "90b2ac63-e61f-99e1-a8b0-a5e85f154d4c",
  "90b2ac63-e61f-49e1-78b0-a5e85f154d4c",
  "90b2ac63e61f49e1a8b0a5e85f154d4c",
  `a${genericUuidValue}`, `${genericUuidValue}f`, `a${genericHexValue}`, `${genericHexValue}f`,
]);
const numericTokenAliases = Object.freeze(["input_tokens", "InputTokens", "input.tokens", "input-tokens"]);
const exactConsolePrivacyBypasses = Object.freeze([
  ["authToken", "authToken=private-auth-value"],
  ["session_token", "session_token=private-session-value"],
  ["credential", "credential=private-credential-value"],
  ["image", "image=private-image-value"],
  ["imageBytes", "imageBytes=private-image-bytes"],
  ["foodNames", "foodNames=private breakfast"],
  ["mealTitle", "mealTitle=private breakfast title"],
  ["storeKitPayload", "storeKitPayload=private-storekit-payload"],
]);

function fieldEndingAtLength(length, suffix) {
  assert.ok(length >= suffix.length);
  return `${"x".repeat(length - suffix.length)}${suffix}`;
}

const overlengthAssignmentBypasses = Object.freeze([
  ...[63, 64, 65, 66, 80, 128].map((length) => `${fieldEndingAtLength(length, "authToken")}=abc`),
  `${fieldEndingAtLength(65, "inputTokens")}=120`,
  `${fieldEndingAtLength(80, "outputTokens")}=30`,
  `${fieldEndingAtLength(128, "totalTokens")}=150`,
  `${fieldEndingAtLength(65, "canaryCorrelationId")}=${genericHexValue}`,
  `${fieldEndingAtLength(80, "canaryOperationTag")}=${genericHexValue}`,
  `${fieldEndingAtLength(128, "canaryQuotaTag")}=${genericHexValue}`,
  `${"x".repeat(4096)}authToken=abc`,
  `${"._-".repeat(2048)}1credential=abc`,
]);

const exactWrappedAssignmentControls = Object.freeze([
  "(inputTokens=120)",
  "[outputTokens=30]",
  "{totalTokens=150}",
  `${"x".repeat(4096)}=abc`,
]);

const wrapperAndUnicodeAssignmentBypasses = Object.freeze([
  `["authToken"]=abc`,
  `(authToken)=abc`,
  `{foodName}:breakfast`,
  `['credential']=abc`,
  `outer=(["storeKitPayload"])=abc`,
  `outer=(authToken)=abc`,
  `\n[session_token]=abc`,
  `[[authToken]]=abc`,
  `authTokené=abc`,
  `authToken١=abc`,
  `authToken）=abc`,
  `“authToken”=abc`,
  `authToken\n=abc`,
  `authToken\r=abc`,
  `authToken\v=abc`,
  `"transaction id"=abc`,
  `"storeKit payload"=abc`,
  `"meal name"=breakfast`,
  `"food title"=breakfast`,
  `outer=["authToken"]=abc`,
  `[["authToken"]]=abc`,
  `""authToken""=abc`,
  `\u001b[31mauthToken\u001b[0m=abc`,
  `authToken＝abc`,
  `authToken：abc`,
  `"store kit private payload"=abc`,
  `"store kit very private payload"=abc`,
  `"meal descriptive item name"=breakfast`,
  `"meal descriptive private item name"=breakfast`,
  `"food descriptive item title"=breakfast`,
  `message=mañana store kit private payload=abc`,
  `message=bar meal descriptive item name=breakfast`,
  `message=bar meal descriptive private item name=breakfast`,
  `message=bar display name=abc`,
  `message=bar auth token raw=abc`,
  `message=bar authorization header value=abc`,
  `message=bar store kit payload raw=abc`,
  `message=bar meal name raw=breakfast`,
  `message=bar display name raw=abc`,
  `message=mañana secret credential material=abc`,
  `message=bar auth token inputTokens=120`,
  `message=mañana secret credential inputTokens=120`,
  `message=bar auth token canaryCorrelationId=${genericHexValue}`,
  `message=bar meal name canaryOperationTag=${genericHexValue}`,
  `message=bar auth token mañana raw=abc`,
  `message=bar store kit mañana payload raw=abc`,
  `message=bar meal mañana name raw=breakfast`,
  `message=bar display mañana name raw=abc`,
  `message=a։uthorization raw=abc`,
  `message=a։u：t＝h︓orization raw=abc`,
  `message="a։u：t＝h︓orization：abc"`,
  `message=displayn：ame=abc`,
  `message="displaynःame" raw=abc`,
  `message=transactioni：d:abc`,
  `message=storek：itpayload raw=abc`,
  `message=mealn：ame raw=abc`,
  `message=foodt：itle raw=abc`,
  `\u001b]0; authorization=${"z".repeat(64)}\u0007`,
  `\u001b]0; mealName=${"z".repeat(64)}\u0007`,
  `\u001b]0; transactionId=${"z".repeat(64)}\u0007`,
  `\u001b]0; displayName=${"z".repeat(64)}\u0007`,
  `123456789012345`,
  `transaction completed: 123456789012345`,
  `original transaction 123456789012345`,
  `message=bar authTοken raw=abc`,
  `message=bar status😀 raw=abc`,
  `outer=["store kit payload raw"]=abc`,
  `outer=["meal descriptive name raw"]=breakfast`,
  `outer=store kit payload raw=abc`,
  `outer=meal descriptive name raw=breakfast`,
  `outer=display name raw=abc`,
  `outer=auth token raw=abc`,
  `outer=store kit payload inputTokens=120`,
  `outer=meal name canaryOperationTag=${genericHexValue}`,
  `auth token inputTokens=120`,
  `authToken inputTokens=120`,
  `store kit payload outputTokens=30`,
  `meal name totalTokens=150`,
  `authorization header value inputTokens=120`,
  `meal=foo name=breakfast`,
  `meal='mañana' descriptive name raw=breakfast`,
  `food=foo title=breakfast`,
  `storeKit=foo payload=abc`,
  `store=foo kit=bar payload=abc`,
  `transaction=foo id=abc`,
  `transaction=foo private identifier raw=abc`,
  `display=foo name=abc`,
  `meal=“mañana” name=breakfast`,
  `outer=["meal"]=foo name=breakfast`,
  `message=bar meal=foo name=breakfast`,
  `message=authTοken raw=abc`,
  `message=authTоken raw=abc`,
  `message=ａｕｔｈＴｏｋｅｎ raw=abc`,
  `message=secrεt material=abc`,
  `message=mеal name raw=breakfast`,
  `message=stοre kit payload raw=abc`,
  `message=mеaӏ name raw=breakfast`,
  `message=dispӏay name raw=abc`,
  `message=stӧre kit payload raw=abc`,
  `message=phοtο raw=abc`,
  `message=imagе raw=abc`,
  `message=creԁential raw=abc`,
  `message=ꓮuthorization raw=abc`,
  `message=𐊠ppcheck raw=abc`,
  `message=⍴hoto raw=abc`,
  `message=aυthorization raw=abc`,
  `message=dispΙay name raw=abc`,
  `message=traηsaction raw=abc id=value`,
  `message=ηame raw=abc meal=value`,
  `message=ph0to raw=abc`,
  `message=t0ken raw=abc`,
  `message=credentia1 raw=abc`,
  `message=mea1 name raw=breakfast`,
  `message=disp1ay name raw=abc`,
  `message=dispIay name raw=abc`,
  `message=rneal name raw=breakfast`,
  JSON.stringify({ ph0to: "abc" }),
  JSON.stringify({ t0ken: "abc" }),
  JSON.stringify({ credentia1: "abc" }),
  JSON.stringify({ rneal: { name: "breakfast" } }),
  `message=iΜage raw=abc`,
  `message=Ｍealname raw=breakfast`,
  `message=𜳖uthorization raw=abc`,
  `message=˛mage raw=abc`,
  `message=ⓛmage raw=abc`,
  `message=ẚuthorization raw=abc`,
  `authToken꞉abc`,
  `foodName∶breakfast`,
  `credentialːabc`,
  `image։bytes`,
  `mealTitle᛬breakfast`,
  `secret⹀abc`,
  `photo᐀abc`,
  `token゠abc`,
  `storeKitPayload⩵abc`,
  `authToken≚abc`,
  `foodName⩴breakfast`,
  `credential⧴abc`,
  `secret≐abc`,
  `photo≑abc`,
  `token⩮abc`,
  `𝓧-firebase-appcheck:abc`,
  `message=tokeŉ raw=abc`,
  `message=authorizatioŉ raw=abc`,
  `message=⒯oken raw=abc`,
  `authToken𑷙abc`,
  `foodName𑷙breakfast`,
  `message=foo authToken𑷙abc`,
  `message=credentiaŀ raw=abc`,
  `message=meaŀ name raw=breakfast`,
  `message=aᑗthorization raw=abc`,
  `message=aᑶpcheck raw=abc`,
  `meal=foo,name=breakfast`,
  `meal=foo;name=breakfast`,
  `meal=foo|name=breakfast`,
  `transaction=foo,id=123456789`,
  `transaction=foo;payload=abc`,
  `store=foo;kit=bar;payload=abc`,
  `display=foo|name=Alex`,
  `message=credentia| raw=abc`,
  `message=mea| name raw=breakfast`,
  `message=store kit pay|oad raw=abc`,
  `message=transaction pay|oad raw=abc`,
  `message=disp|ay name raw=Alex`,
  `message=authTοken食 raw=abc`,
  `message=authorization食 raw=abc`,
  `message=token食 raw=abc`,
  `message=meal食 name=breakfast`,
  `message=display食 name=Alex`,
  `message=store食 kit payload=abc`,
  `message=transaction食 id=abc`,
  `message=credentiaŀ食 raw=abc`,
  `message=𜳖uthorization食 raw=abc`,
  `message="authTοken食" raw=abc`,
  `authTοken食：abc`,
  `authorization食𑷙abc`,
  `meal食 name∶breakfast`,
  `display食 name＝Alex`,
  `store食 kit payload⩵abc`,
  `transaction食 id≚abc`,
  `credentiaŀ食꞉abc`,
  `message=ⓘ mage raw=abc`,
  `message="ⓘ mage" raw=abc`,
  `message=ⓟ hoto raw=abc`,
  `message="ⓣ oken" raw=abc`,
  `message=ⓐ uthorization raw=abc`,
  `message=ⓜ eal name=breakfast`,
  `message="ⓓ isplay" name=Alex`,
  `message=ⓒ redential raw=abc`,
  `message="im Ⓐ ge" raw=abc`,
  `message="transa Ⓒ tionid" raw=abc`,
  `message=ⓘmage：abc`,
  `message="ⓣoken"＝abc`,
  `message=ⓐuthorization𑷙abc`,
  `message=ⓜeal name∶breakfast`,
  `message=authorIzation raw=abc`,
  `message="credentIal" raw=abc`,
  `message=dIsplayname raw=abc`,
  `message=Image raw=abc`,
  `message=iMage raw=abc`,
  `message=transactionId raw=abc`,
  `message=storekItpayload raw=abc`,
  `message=Mealname raw=abc`,
  `message=Image：abc`,
  `message=authorＩzation raw=abc`,
  `message="Ｉmage" raw=abc`,
  `message=credent𝐈al raw=abc`,
  `message=d𝗜splayname raw=abc`,
  `message=transaction𝙄d raw=abc`,
  `message=storek𝘐tpayload raw=abc`,
  `message=authorÌzation raw=abc`,
  `message="Ìmage" raw=abc`,
  `message="authToken：abc"`,
  `message=「authToken：abc」`,
  `message="mealName゠breakfast"`,
  `message=『credential𑷙abc』`,
  `message="Image＝raw"`,
  `message=toଃken raw=abc`,
  `message=toంken raw=abc`,
  `message=toಂken raw=abc`,
  `message=toംken raw=abc`,
  `message=toංken raw=abc`,
  `message=toःken：abc`,
  `message=toઃken：abc`,
  `message=t${"ः".repeat(512)}oken：abc`,
  `message=mеaӏ value=foo name=breakfast`,
  `message=dispӏay value=foo name=abc`,
  `message=stӧre value=foo kit=bar payload=abc`,
  `ａｕｔｈＴｏｋｅｎ=abc`,
  `[inputTokens]=120`,
  `[canaryOperationTag]=${genericHexValue}`,
]);

const safeEstimateMetricConsole = `meal_scan_estimate {
  providerId: 'google-gemini',
  modelId: 'gemini-3.1-flash-lite',
  inputTokens: 2448,
  outputTokens: 750,
  estimatedCostUSD: 0.001737,
  quotaUsed: 1,
  quotaLimit: 10,
  tier: 'paid',
  budgetMode: 'normal',
  cacheHit: false
}`;

const nonAsciiEvidenceKeyBypasses = Object.freeze([
  `authTοken=abc`,
  `authTоken=abc`,
  `status😀=abc`,
  `😀status=abc`,
  `ⓘ mage=abc`,
  `"ⓘ mage"=abc`,
  `ⓟ hoto=abc`,
  `ⓣ oken=abc`,
  `ⓐ uthorization=abc`,
  `ⓜ eal name=breakfast`,
  `ⓓ isplay name=Alex`,
  `ⓒ redential=abc`,
  JSON.stringify({ authTοken: "abc" }),
  JSON.stringify({ authTоken: "abc" }),
  JSON.stringify({ "status😀": "abc" }),
]);

const unicodeAssignmentSequenceControls = Object.freeze([
  `message=mañana status=completed`,
  `message=食事 status=completed`,
  `message='déjeuner équilibré' status=completed`,
  `message=bar inputTokens=120`,
  `message=mañana inputTokens=120`,
  `message='mañana comida' status=completed`,
  `message=bar status=completed`,
  `outer=store status=completed`,
  `outer=meal status=completed`,
  `message='meal plan' status=completed`,
  `status inputTokens=120`,
  `message=“mañana” status=completed`,
  `message=‘食事’ status=completed`,
  `message=«déjeuner équilibré» status=completed`,
  `message=PCOS食事 status=completed`,
  `message=clé status=completed`,
  `message=k食y status=completed`,
  `message=j食s status=completed`,
  `message=j食t status=completed`,
  `message=A食事語 status=completed`,
  `message=to食ken status=completed`,
  `transaction=foo message=x食事 status=completed`,
  `message=「食事を記録」 status=completed`,
  `message=『食事を記録』 status=completed`,
  `message=「ジャン゠ジャック」 status=completed`,
  `message=ジャン゠ジャック status=completed`,
  `message='दुःख' status=completed`,
  `message=दुःख status=completed`,
  `message='Բարեւ։' status=completed`,
  `message=Բարեւ։ status=completed`,
  `message=hello：world status=completed`,
  `message="ジャン゠ジャック"`,
  `message=「ジャン゠ジャック」`,
  `message='દુઃખ' status=completed`,
  `message=દુઃખ status=completed`,
  `message=「食事: テスト」 status=completed`,
  `message=『食事=テスト』 status=completed`,
  `message=“comida: prueba” status=completed`,
  `message=«repas = essai» status=completed`,
  `message=“comida, prueba” status=completed`,
  `message=«repas; essai» status=completed`,
  `message=「食事|テスト」 status=completed`,
  `message=『食事,テスト』 status=completed`,
]);

function runScript(environment = {}, options = {}) {
  return spawnSync("bash", [scriptPath], {
    cwd: repositoryRoot,
    encoding: "utf8",
    env: { ...process.env, ...environment },
    ...options,
  });
}

function callSourcedFunction(functionCall, environment = {}) {
  return spawnSync("bash", ["-c", `source "$1"; ${functionCall}`, "positive-canary-test", scriptPath], {
    cwd: repositoryRoot,
    encoding: "utf8",
    env: { ...process.env, ...environment },
  });
}

function withJsonFixture(value, callback) {
  const directory = mkdtempSync(path.join(tmpdir(), "cyclebalance-positive-canary-test-"));
  const fixturePath = path.join(directory, "fixture.json");
  writeFileSync(fixturePath, JSON.stringify(value));
  try {
    return callback(fixturePath);
  } finally {
    rmSync(directory, { recursive: true, force: true });
  }
}

test("positive canary defaults to a complete non-mutating dry run", () => {
  assert.equal(scriptExists, true, `missing ${scriptPath}`);
  assert.notEqual(statSync(scriptPath).mode & 0o111, 0, "positive canary script must be executable");

  const directory = mkdtempSync(path.join(tmpdir(), "cyclebalance-positive-canary-dry-run-"));
  const binDirectory = path.join(directory, "bin");
  const mutationLog = path.join(directory, "mutations.log");
  mkdirSync(binDirectory);
  for (const command of ["gcloud", "curl", "xcodebuild", "xcrun", "codesign", "security", "npm"] ) {
    const commandPath = path.join(binDirectory, command);
    writeFileSync(
      commandPath,
      `#!/usr/bin/env bash\nprintf '%s\\n' '${command}' >> "$MUTATION_LOG"\nexit 97\n`
    );
    chmodSync(commandPath, 0o755);
  }

  try {
    const result = runScript({
      PATH: `${binDirectory}:/usr/bin:/bin`,
      MUTATION_LOG: mutationLog,
    });
    assert.equal(result.status, 0, result.stderr);
    assert.match(result.stdout, /DRY RUN ONLY/i);
    assert.match(result.stdout, /owner-observed UI evidence/i);
    assert.match(result.stdout, /machine-read evidence/i);
    assert.match(result.stdout, /Scan as New/i);
    assert.match(result.stdout, /rollback/i);
    assert.equal(existsSync(mutationLog) ? readFileSync(mutationLog, "utf8") : "", "");
  } finally {
    rmSync(directory, { recursive: true, force: true });
  }
});

test("production, app, endpoint, and General Kenobi identities are pinned", () => {
  const defaultRun = runScript();
  assert.equal(defaultRun.status, 0, defaultRun.stderr);
  for (const expected of [
    "cyclebalance-prod-20260710",
    "cyclebalance-meal-scan-proxy",
    "alex.PCOS",
    "https://cyclebalance-meal-scan-proxy-mdd7lrfyqa-uc.a.run.app",
    "General Kenobi",
    "0C663BE9-3804-587C-BD8A-A2B4D38F998A",
  ]) {
    assert.match(defaultRun.stdout, new RegExp(expected.replace(/[.*+?^${}()|[\]\\]/g, "\\$&")));
  }

  for (const override of [
    { PROJECT_ID: "attacker-project" },
    { SERVICE_NAME: "attacker-service" },
    { APP_BUNDLE_ID: "attacker.bundle" },
    { SERVICE_URL: "https://attacker.example" },
    { DEVICE_NAME: "Ambiguous iPhone" },
    { DEVICE_ID: "00000000-0000-0000-0000-000000000000" },
  ]) {
    const result = runScript(override);
    assert.notEqual(result.status, 0, `override unexpectedly succeeded: ${JSON.stringify(override)}`);
    assert.match(result.stderr, /pinned/i);
  }
});

test("live execution requires the deliberately specific owner confirmation before preflight", () => {
  for (const confirmation of [undefined, "YES", "I_APPROVE"] ) {
    const environment = { DRY_RUN: "false" };
    if (confirmation !== undefined) {
      environment.CONFIRM_GENERAL_KENOBI_POSITIVE_CANARY = confirmation;
    }
    const result = runScript(environment);
    assert.notEqual(result.status, 0);
    assert.match(result.stderr, /I_APPROVE_GENERAL_KENOBI_POSITIVE_CANARY_WITH_TEMPORARY_PUBLIC_CLOUD_RUN/);
    assert.doesNotMatch(`${result.stdout}\n${result.stderr}`, /Checking Google Cloud|Building Release canary/);
  }
});

test("General Kenobi resolves to exactly one available physical Xcode destination", () => {
  withJsonFixture(
    [
      {
        name: "General Kenobi",
        identifier: "00008130-001929003AE2001C",
        available: true,
        simulator: false,
        platform: "com.apple.platform.iphoneos",
      },
      {
        name: "General Kenobi",
        identifier: "SIMULATOR-IGNORED",
        available: true,
        simulator: true,
        platform: "com.apple.platform.iphonesimulator",
      },
    ],
    (fixturePath) => {
      const result = callSourcedFunction(`resolve_xcode_device_udid "${fixturePath}" "General Kenobi"`);
      assert.equal(result.status, 0, result.stderr);
      assert.equal(result.stdout.trim(), "00008130-001929003AE2001C");
    }
  );

  for (const fixture of [
    [],
    [
      {
        name: "General Kenobi",
        identifier: "DEVICE-ONE",
        available: true,
        simulator: false,
        platform: "com.apple.platform.iphoneos",
      },
      {
        name: "General Kenobi",
        identifier: "DEVICE-TWO",
        available: true,
        simulator: false,
        platform: "com.apple.platform.iphoneos",
      },
    ],
  ]) {
    withJsonFixture(fixture, (fixturePath) => {
      const result = callSourcedFunction(`resolve_xcode_device_udid "${fixturePath}" "General Kenobi"`);
      assert.notEqual(result.status, 0, `unsafe fixture passed: ${JSON.stringify(fixture)}`);
    });
  }
});

test("Release canary permits only the two signed scanner-gate overrides", () => {
  const valid = callSourcedFunction(
    "release_override_allowlist_is_valid MEAL_SCAN_RELEASE_UI_ENABLED=YES MEAL_SCAN_RELEASE_GEMINI_ENABLED=YES"
  );
  assert.equal(valid.status, 0, valid.stderr);

  for (const candidate of [
    "MEAL_SCAN_RELEASE_UI_ENABLED=YES",
    "MEAL_SCAN_RELEASE_UI_ENABLED=YES MEAL_SCAN_RELEASE_GEMINI_ENABLED=YES MEAL_SCAN_RELEASE_MOCK_DATA_ENABLED=NO",
    "MEAL_SCAN_RELEASE_UI_ENABLED=YES MEAL_SCAN_RELEASE_DEBUG_DIRECT_ENABLED=YES",
    "MEAL_SCAN_UI_ENABLED=YES GEMINI_MEAL_SCAN_ENABLED=YES",
  ]) {
    const result = callSourcedFunction(`release_override_allowlist_is_valid ${candidate}`);
    assert.notEqual(result.status, 0, `unsafe overrides passed: ${candidate}`);
  }

  const buildFunction = scriptSource.slice(
    scriptSource.indexOf("build_and_inspect_release_canary() {"),
    scriptSource.indexOf("\ninstall_release_canary() {", scriptSource.indexOf("build_and_inspect_release_canary() {"))
  );
  assert.match(buildFunction, /MEAL_SCAN_RELEASE_UI_ENABLED=YES/);
  assert.match(buildFunction, /MEAL_SCAN_RELEASE_GEMINI_ENABLED=YES/);
  assert.doesNotMatch(buildFunction, /MEAL_SCAN_RELEASE_(MOCK_DATA|DEBUG_DIRECT|FALLBACK_MODEL|SIMILARITY)_ENABLED=YES/);
  assert.doesNotMatch(buildFunction, /-allowProvisioningUpdates/);
  assert.doesNotMatch(scriptSource, /\.ipa\b/i);
});

test("canonical Release flags remain NO and are hashed before and after the canary build", () => {
  for (const key of [
    "MEAL_SCAN_RELEASE_UI_ENABLED",
    "MEAL_SCAN_RELEASE_GEMINI_ENABLED",
    "MEAL_SCAN_RELEASE_MOCK_DATA_ENABLED",
    "MEAL_SCAN_RELEASE_DEBUG_DIRECT_ENABLED",
    "MEAL_SCAN_RELEASE_FALLBACK_MODEL_ENABLED",
    "MEAL_SCAN_RELEASE_SIMILARITY_ENABLED",
  ]) {
    const declarations = [
      ...projectSource.matchAll(new RegExp(`^[ \\t]+${key}:[ \\t]*(.*)[ \\t]*$`, "gm")),
    ];
    assert.equal(declarations.length, 1, `${key} must have exactly one canonical declaration`);
    assert.match(declarations[0][1].trim(), /^["']?NO["']?$/, `${key} canonical declaration must remain NO`);
  }
  assert.match(scriptSource, /assert_canonical_release_flags/);
  assert.match(scriptSource, /PROJECT_YML_SHA_BEFORE/);
  assert.match(scriptSource, /require_unchanged.*PROJECT_YML_SHA_BEFORE/);
});

test("rollback is armed before public enablement and verifies the final private kill switch", () => {
  const mainFunction = scriptSource.slice(scriptSource.indexOf("main() {"));
  const rollbackArmed = mainFunction.indexOf("ROLLBACK_ARMED=true");
  const publicMutation = mainFunction.indexOf("deploy_temporarily_enabled_public");
  assert.ok(rollbackArmed >= 0, "rollback was not armed");
  assert.ok(publicMutation > rollbackArmed, "public mutation occurs before rollback is armed");
  assert.match(scriptSource, /trap handle_canary_exit EXIT/);
  assert.match(scriptSource, /trap 'handle_canary_signal INT' INT/);
  assert.match(scriptSource, /trap 'handle_canary_signal TERM' TERM/);

  const rollbackFunction = scriptSource.slice(
    scriptSource.indexOf("rollback() {"),
    scriptSource.indexOf("\nprint_dry_run() {", scriptSource.indexOf("rollback() {"))
  );
  assert.match(rollbackFunction, /deploy_disabled_private/);
  assert.match(rollbackFunction, /verify_final_disabled_private/);

  const finalVerification = scriptSource.slice(
    scriptSource.indexOf("verify_final_disabled_private() {"),
    scriptSource.indexOf("\n", scriptSource.indexOf("verify_final_disabled_private() {") + 40) > 0
      ? scriptSource.indexOf("\nrun_owner_guided_canary() {", scriptSource.indexOf("verify_final_disabled_private() {"))
      : scriptSource.length
  );
  assert.match(finalVerification, /MEAL_SCAN_ENABLED/);
  assert.match(finalVerification, /iam_policy_is_private/);
  assert.match(scriptSource, /allUsers/);
  assert.match(scriptSource, /allAuthenticatedUsers/);
  assert.match(finalVerification, /private_invoker_gate_rejects_status/);
  assert.match(finalVerification, /503/);
  assert.match(finalVerification, /feature_disabled/);
});

test("current RC is staged and qualified disabled/private before any enabled revision", () => {
  const mainFunction = scriptSource.slice(scriptSource.indexOf("main() {"));
  const armed = mainFunction.indexOf("ROLLBACK_ARMED=true");
  const staged = mainFunction.indexOf("deploy_current_rc_disabled_private");
  const enabled = mainFunction.indexOf("deploy_temporarily_enabled_public");
  assert.ok(armed >= 0 && armed < staged, "rollback must be armed before disabled RC staging");
  assert.ok(staged < enabled, "current RC must be qualified disabled/private before enablement");

  const initial = scriptSource.slice(
    scriptSource.indexOf("verify_initial_cloud_state() {"),
    scriptSource.indexOf("\nverify_dormant_window_continuity() {")
  );
  assert.doesNotMatch(initial, /verify_deployed_runtime_and_secret_refs/);
  assert.doesNotMatch(initial, /capture_and_verify_build_provenance/);

  const stage = scriptSource.slice(
    scriptSource.indexOf("deploy_current_rc_disabled_private() {"),
    scriptSource.indexOf("\ndeploy_temporarily_enabled_public() {")
  );
  assert.match(stage, /deploy_environment false false/);
  assert.match(stage, /restore_initial_iam_policy/);
  assert.match(stage, /verify_deployed_runtime_and_secret_refs/);
  assert.match(stage, /verify_deployed_runtime_configuration/);
  assert.match(stage, /capture_and_verify_build_provenance/);
  assert.match(stage, /iam_policy_is_private/);
  assert.match(stage, /private_invoker_gate_rejects_status/);
  assert.match(stage, /503/);
  assert.match(stage, /feature_disabled/);
});

test("prohibited log content is rejected and retained evidence is redacted and restricted", () => {
  withJsonFixture(
    [{ jsonPayload: { event: "meal_scan_scanner_event", eventType: "provider_call", outcome: "completed" } }],
    (fixturePath) => {
      const result = callSourcedFunction(`assert_no_prohibited_content "${fixturePath}"`);
      assert.equal(result.status, 0, result.stderr);
    }
  );

  for (const prohibited of [
    "Authorization: Bearer secret-token",
    "x-firebase-appcheck: app-check-token",
    "signedTransactionJWS=header.payload.signature",
    "originalTransactionId=123456789",
    "meal_name=private meal",
    "token=plain-secret-value",
    "secret=plain-secret-value",
    "photo=private-breakfast-photo",
    "foodName=private breakfast",
    "data:image/jpeg;base64,/9j/4AAQ",
    "AIzaExampleKey",
  ]) {
    withJsonFixture([{ textPayload: prohibited }], (fixturePath) => {
      const result = callSourcedFunction(`assert_no_prohibited_content "${fixturePath}"`);
      assert.notEqual(result.status, 0, `prohibited content passed: ${prohibited}`);
    });
  }

  assert.doesNotMatch(scriptSource, /set -x/);
  assert.match(scriptSource, /secrets versions access "\$REVENUECAT_SECRET_VERSION"/);
  assert.match(scriptSource, /verify-revenuecat-offering-v2\.sh/);
  assert.doesNotMatch(scriptSource, /secrets versions access[^\n]*(gemini|principal|apple)/i);
  assert.doesNotMatch(scriptSource, /auth_config/);
  assert.match(scriptSource, /--config -/);
  assert.match(scriptSource, /chmod 0700/);
  assert.match(scriptSource, /chmod 0600/);
  assert.match(scriptSource, /owner-observed UI evidence/i);
  assert.match(scriptSource, /machine-read evidence/i);

  const captureFunction = scriptSource.slice(
    scriptSource.indexOf("capture_phase_window() {"),
    scriptSource.indexOf("\ncapture_and_verify_phase() {", scriptSource.indexOf("capture_phase_window() {"))
  );
  const loggingFilter = captureFunction.slice(
    captureFunction.indexOf("gcloud logging read"),
    captureFunction.indexOf("--project", captureFunction.indexOf("gcloud logging read"))
  );
  assert.match(loggingFilter, /run\.googleapis\.com%2Fstdout/);
  assert.match(loggingFilter, /run\.googleapis\.com%2Fstderr/);
  assert.doesNotMatch(loggingFilter, /meal_scan_scanner_event/);

  const consoleProjection = scriptSource.slice(
    scriptSource.indexOf("device_console_operation_for_phase() {"),
    scriptSource.indexOf("\ndeploy_environment() {", scriptSource.indexOf("device_console_operation_for_phase() {"))
  );
  assert.match(consoleProjection, /assert_no_prohibited_content "\$segment_file"/);
  assert.match(captureFunction, /assert_no_prohibited_content "\$events_file"/);
});

for (const [label, prohibited] of exactConsolePrivacyBypasses) {
  test(`whole-console checker rejects the ${label} privacy bypass`, () => {
    withJsonFixture([{ textPayload: prohibited }], (fixturePath) => {
      const result = callSourcedFunction(`assert_no_prohibited_content "${fixturePath}"`);
      assert.notEqual(result.status, 0, `${label} escaped the whole-console checker`);
    });
  });
}

test("whole-console checker rejects an arbitrary 44-character high-entropy value", () => {
  assert.equal(highEntropyGenericValue.length, 44);
  withJsonFixture(
    [{ textPayload: `diagnosticValue=${highEntropyGenericValue}` }],
    (fixturePath) => {
      const result = callSourcedFunction(`assert_no_prohibited_content "${fixturePath}"`);
      assert.notEqual(result.status, 0, "high-entropy generic value escaped the whole-console checker");
    }
  );
});

test("whole-console checker preserves the three numeric token-count fields", () => {
  withJsonFixture(
    [{ textPayload: "inputTokens=120 outputTokens=30 totalTokens=150" }],
    (fixturePath) => {
      const result = callSourcedFunction(`assert_no_prohibited_content "${fixturePath}"`);
      assert.equal(result.status, 0, result.stderr);
    }
  );
});

for (const alias of numericTokenAliases) {
  test(`whole-console checker rejects numeric token alias ${alias}`, () => {
    for (const textPayload of [`${alias}=120`, JSON.stringify({ [alias]: 120 })]) {
      withJsonFixture([{ textPayload }], (fixturePath) => {
        const result = callSourcedFunction(`assert_no_prohibited_content "${fixturePath}"`);
        assert.notEqual(result.status, 0, `${alias} escaped the whole-console checker`);
      });
    }
  });
}

test("whole-console checker rejects negative exact token counts", () => {
  for (const field of ["inputTokens", "outputTokens", "totalTokens"]) {
    for (const textPayload of [`${field}=-1`, JSON.stringify({ [field]: -1 })]) {
      withJsonFixture([{ textPayload }], (fixturePath) => {
        const result = callSourcedFunction(`assert_no_prohibited_content "${fixturePath}"`);
        assert.notEqual(result.status, 0, `${field} accepted a negative count`);
      });
    }
  }
});

test("whole-console checker rejects generic 64-hex content", () => {
  assert.equal(genericHexValue.length, 64);
  withJsonFixture([{ textPayload: `diagnosticValue=${genericHexValue}` }], (fixturePath) => {
    const result = callSourcedFunction(`assert_no_prohibited_content "${fixturePath}"`);
    assert.notEqual(result.status, 0, "generic 64-hex value escaped the whole-console checker");
  });
});

for (const field of ["diagnosticValue", "canaryId"]) {
  test(`whole-console checker rejects UUID identifier ${field} in plain and JSON forms`, () => {
    for (const textPayload of [
      `${field}=${genericUuidValue}`,
      JSON.stringify({ [field]: genericUuidValue }),
    ]) {
      withJsonFixture([{ textPayload }], (fixturePath) => {
        const result = callSourcedFunction(`assert_no_prohibited_content "${fixturePath}"`);
        assert.notEqual(result.status, 0, `${field} UUID escaped the whole-console checker`);
      });
    }
  });
}

test("whole-console checker rejects all identifier boundary bypasses in plain and JSON forms", () => {
  for (const value of identifierBypasses) for (const textPayload of [
    `diagnosticValue=${value}`, JSON.stringify({ diagnosticValue: value }),
  ]) withJsonFixture([{ textPayload }], (fixturePath) => {
    const result = callSourcedFunction(`assert_no_prohibited_content "${fixturePath}"`);
    assert.notEqual(result.status, 0, value);
  });
});

test("whole-console checker rejects prefixed and suffixed canonical hash aliases", () => {
  for (const canonical of ["canaryCorrelationId", "canaryOperationTag", "canaryQuotaTag"])
    for (const field of [`_${canonical}`, `.${canonical}`, `-${canonical}`, `${canonical}_`])
      withJsonFixture([{ textPayload: `${field}=${genericHexValue}` }], (fixturePath) => {
        assert.notEqual(callSourcedFunction(`assert_no_prohibited_content "${fixturePath}"`).status, 0, field);
      });
});

test("whole-console checker rejects punctuation-wrapped sensitive assignments", () => {
  for (const value of ["(authToken=abc)", "[session_token=abc]", ";credential=abc", "|foodName=breakfast", "(image=abc)", "[mealTitle=breakfast]", ";storeKitPayload=abc", "|token=abc", "prefix;(authToken=abc)", "\n(authToken=abc)", "outer=(authToken=abc)", "outer=authToken=abc", "outer=token=abc"])
    withJsonFixture([{ textPayload: value }], (fixturePath) => assert.notEqual(callSourcedFunction(`assert_no_prohibited_content "${fixturePath}"`).status, 0, value));
  for (const value of [`(inputTokens=120)`])
    withJsonFixture([{ textPayload: value }], (fixturePath) => assert.equal(callSourcedFunction(`assert_no_prohibited_content "${fixturePath}"`).status, 0, value));
});

test("whole-console checker rejects digit-prefixed sensitive assignments", () => {
  const unsafeAssignments = [
    "1authToken=abc",
    "outer=1authToken=abc",
    "1foodName=breakfast",
    "outer=(1credential=abc)",
    "1token=abc",
    "1inputTokens=120",
    "1outputTokens=30",
    "1totalTokens=150",
    `1canaryCorrelationId=${genericHexValue}`,
    `1canaryOperationTag=${genericHexValue}`,
    `1canaryQuotaTag=${genericHexValue}`,
    "._-1authToken=abc",
    `${".".repeat(128)}1credential=abc`,
    `1${"x".repeat(54)}authToken=abc`,
  ];
  for (const value of unsafeAssignments) {
    withJsonFixture([{ textPayload: value }], (fixturePath) => {
      assert.notEqual(callSourcedFunction(`assert_no_prohibited_content "${fixturePath}"`).status, 0, value);
    });
  }
  for (const value of [
    "(inputTokens=120)",
    "[outputTokens=30]",
    "{totalTokens=150}",
  ]) {
    withJsonFixture([{ textPayload: value }], (fixturePath) => {
      assert.equal(callSourcedFunction(`assert_no_prohibited_content "${fixturePath}"`).status, 0, value);
    });
  }
});

test("whole-console checker rejects overlength sensitive assignments", () => {
  for (const value of exactWrappedAssignmentControls) {
    withJsonFixture([{ textPayload: value }], (fixturePath) => {
      assert.equal(callSourcedFunction(`assert_no_prohibited_content "${fixturePath}"`).status, 0, value);
    });
  }
  for (const value of overlengthAssignmentBypasses) {
    withJsonFixture([{ textPayload: value }], (fixturePath) => {
      assert.notEqual(callSourcedFunction(`assert_no_prohibited_content "${fixturePath}"`).status, 0, value);
    });
  }
});

test("whole-console checker rejects wrapper unicode whitespace and compound assignments", () => {
  for (const value of wrapperAndUnicodeAssignmentBypasses) {
    withJsonFixture([{ textPayload: value }], (fixturePath) => {
      assert.notEqual(callSourcedFunction(`assert_no_prohibited_content "${fixturePath}"`).status, 0, value);
    });
  }
});

test("whole-console checker confines canonical hash exceptions to one occurrence", () => {
  for (const field of ["canaryCorrelationId", "canaryOperationTag", "canaryQuotaTag"]) {
    const value = `${field}=${genericHexValue} diagnosticValue=${genericHexValue}`;
    withJsonFixture([{ textPayload: value }], (fixturePath) => {
      assert.notEqual(callSourcedFunction(`assert_no_prohibited_content "${fixturePath}"`).status, 0, field);
    });
  }
  withJsonFixture([{
    textPayload: `CYCLEBALANCE_CANARY_OPERATION tag=${genericHexValue}`,
  }], (fixturePath) => {
    assert.notEqual(callSourcedFunction(`assert_no_prohibited_content "${fixturePath}"`).status, 0);
  });
});

test("whole-console checker accepts the actual content-free estimate metric", () => {
  withJsonFixture([{ textPayload: safeEstimateMetricConsole }], (fixturePath) => {
    const result = callSourcedFunction(`assert_no_prohibited_content "${fixturePath}"`);
    assert.equal(result.status, 0, result.stderr);
  });
});

test("whole-console checker fails closed on non-ASCII evidence keys", () => {
  for (const value of nonAsciiEvidenceKeyBypasses) {
    withJsonFixture([{ textPayload: value }], (fixturePath) => {
      assert.notEqual(callSourcedFunction(`assert_no_prohibited_content "${fixturePath}"`).status, 0, value);
    });
  }
  withJsonFixture([{ textPayload: JSON.stringify({ message: "café 準備完了" }) }], (fixturePath) => {
    assert.equal(callSourcedFunction(`assert_no_prohibited_content "${fixturePath}"`).status, 0);
  });
});

test("whole-console checker preserves Unicode values before later ASCII assignments", () => {
  for (const value of unicodeAssignmentSequenceControls) {
    withJsonFixture([{ textPayload: value }], (fixturePath) => {
      const result = callSourcedFunction(`assert_no_prohibited_content "${fixturePath}"`);
      assert.equal(result.status, 0, `${value}: ${result.stderr}`);
    });
  }
});

test("device console startup and final tail are scanned across the complete attached lifetime", () => {
  const directory = mkdtempSync(path.join(tmpdir(), "cyclebalance-console-lifetime-"));
  const safeLog = path.join(directory, "safe.log");
  const startupUnsafeLog = path.join(directory, "startup-unsafe.log");
  const tailUnsafeLog = path.join(directory, "tail-unsafe.log");
  writeFileSync(
    safeLog,
    `CycleBalance canary attached\nCYCLEBALANCE_CANARY_OPERATION tag=${genericHexValue}\n`
  );
  writeFileSync(startupUnsafeLog, "token=plain-secret-value\nCycleBalance canary attached\n");
  writeFileSync(tailUnsafeLog, "CycleBalance canary attached\nfoodName=private breakfast\n");
  try {
    const safe = callSourcedFunction(
      `DEVICE_CONSOLE_LOG="${safeLog}"; DEVICE_CONSOLE_PID=""; stop_device_console`
    );
    assert.equal(safe.status, 0, safe.stderr);
    for (const unsafeLog of [startupUnsafeLog, tailUnsafeLog]) {
      const unsafe = callSourcedFunction(
        `DEVICE_CONSOLE_LOG="${unsafeLog}"; DEVICE_CONSOLE_PID=""; stop_device_console`
      );
      assert.notEqual(unsafe.status, 0, `${unsafeLog} escaped the whole-lifetime scan`);
    }
  } finally {
    rmSync(directory, { recursive: true, force: true });
  }

  const launchFunction = scriptSource.slice(
    scriptSource.indexOf("launch_canary_with_console() {"),
    scriptSource.indexOf("\nstop_device_console() {", scriptSource.indexOf("launch_canary_with_console() {"))
  );
  const stopFunction = scriptSource.slice(
    scriptSource.indexOf("stop_device_console() {"),
    scriptSource.indexOf("\ndevice_console_operation_for_phase() {", scriptSource.indexOf("stop_device_console() {"))
  );
  assert.match(launchFunction, /assert_no_prohibited_content "\$DEVICE_CONSOLE_LOG"/);
  assert.match(stopFunction, /assert_no_prohibited_content "\$DEVICE_CONSOLE_LOG"/);
});

test("redacted phase and final-posture evidence is retained with restricted permissions", () => {
  const directory = mkdtempSync(path.join(tmpdir(), "cyclebalance-redacted-evidence-"));
  const evidenceDirectory = path.join(directory, "evidence");
  const safeFile = path.join(directory, "safe.json");
  const unsafeFile = path.join(directory, "unsafe.json");
  const finalPostureFile = path.join(directory, "final-disabled-posture.json");
  mkdirSync(evidenceDirectory, { mode: 0o700 });
  writeFileSync(safeFile, JSON.stringify({ phase: "fresh-scan", requestStatusCode: 200 }), { mode: 0o600 });
  writeFileSync(unsafeFile, JSON.stringify({ authorization: "Bearer secret-token" }), { mode: 0o600 });
  writeFileSync(finalPostureFile, JSON.stringify({
    projectId: "cyclebalance-prod-20260710",
    serviceName: "cyclebalance-meal-scan-proxy",
    revision: "cyclebalance-meal-scan-proxy-00023-abc",
    iamPolicyDigest: genericHexValue,
    mealScanEnabled: false,
    transport: "private",
    authenticatedProbe: "503_feature_disabled",
  }), { mode: 0o600 });
  try {
    const safe = callSourcedFunction(
      `EVIDENCE_DIR="${evidenceDirectory}"; persist_redacted_evidence_file "${safeFile}" "fresh-scan-machine-evidence.json"`
    );
    assert.equal(safe.status, 0, safe.stderr);
    const retained = path.join(evidenceDirectory, "fresh-scan-machine-evidence.json");
    assert.equal(existsSync(retained), true);
    assert.equal(statSync(retained).mode & 0o777, 0o600);

    const finalPosture = callSourcedFunction(
      `EVIDENCE_DIR="${evidenceDirectory}"; persist_redacted_evidence_file "${finalPostureFile}" "final-disabled-posture.json"`
    );
    assert.equal(finalPosture.status, 0, finalPosture.stderr);
    const retainedFinal = path.join(evidenceDirectory, "final-disabled-posture.json");
    assert.equal(existsSync(retainedFinal), true);
    assert.equal(statSync(retainedFinal).mode & 0o777, 0o600);

    const unsafe = callSourcedFunction(
      `EVIDENCE_DIR="${evidenceDirectory}"; persist_redacted_evidence_file "${unsafeFile}" "unsafe.json"`
    );
    assert.notEqual(unsafe.status, 0);
    assert.equal(existsSync(path.join(evidenceDirectory, "unsafe.json")), false);
  } finally {
    rmSync(directory, { recursive: true, force: true });
  }

  assert.match(scriptSource, /persist_redacted_evidence_file "\$evidence_file" "\$\{phase\}-machine-evidence\.json"/);
  assert.match(scriptSource, /final-disabled-posture\.json/);
  assert.match(scriptSource, /FINAL_DISABLED_REVISION/);
  assert.match(scriptSource, /INITIAL_IAM_POLICY_DIGEST/);
});

test("Cloud Logging evidence is requested in explicit ascending order", () => {
  const captureFunction = scriptSource.slice(
    scriptSource.indexOf("capture_phase_window() {"),
    scriptSource.indexOf("\ncapture_and_verify_phase() {", scriptSource.indexOf("capture_phase_window() {"))
  );
  assert.match(captureFunction, /gcloud logging read[\s\S]*--order=asc/);
});

test("authenticated curl probes disable user curl configuration before any other option", () => {
  for (const [start, end] of [
    ["firestore_document_json() {", "\neffective_budget_mode_from_json() {"],
    ["verify_final_disabled_private() {", "\nrun_owner_guided_canary() {"],
    ["capture_quota_documents() {", "\ncapture_phase_window() {"],
  ]) {
    const functionSource = scriptSource.slice(scriptSource.indexOf(start), scriptSource.indexOf(end));
    assert.doesNotMatch(functionSource, /curl --silent/);
    assert.match(functionSource, /curl --disable --silent/);
  }
});

test("machine evidence arithmetic distinguishes exact local reuse from Scan as New", () => {
  withJsonFixture({ phase: "exact-reuse", eventCount: 0, quotaUnchanged: true }, (fixturePath) => {
    const result = callSourcedFunction(`verify_phase_evidence exact-reuse "${fixturePath}"`);
    assert.equal(result.status, 0, result.stderr);
  });

  withJsonFixture(
    {
      phase: "scan-as-new",
      eventCount: 13,
      requestCompleted: 1,
      providerStarted: 1,
      providerCompleted: 1,
      quotaDelta: 1,
      cacheFreshDispatch: 1,
      authorizationControls: [
        "app_check",
        "storekit_jws",
        "apple_current_status",
        "revenuecat_subscription",
      ],
      canaryQuotaTag: "a".repeat(64),
    },
    (fixturePath) => {
      const result = callSourcedFunction(`verify_phase_evidence scan-as-new "${fixturePath}"`);
      assert.equal(result.status, 0, result.stderr);
    }
  );

  const unsafeFixtures = [
    ["exact-reuse", { phase: "exact-reuse", eventCount: 1, quotaUnchanged: true }],
    ["exact-reuse", { phase: "exact-reuse", eventCount: 0, quotaUnchanged: false }],
    ["scan-as-new", {
      phase: "scan-as-new",
      eventCount: 13,
      requestCompleted: 1,
      providerStarted: 0,
      providerCompleted: 1,
      quotaDelta: 1,
      cacheFreshDispatch: 1,
      authorizationControls: ["app_check"],
      canaryQuotaTag: "a".repeat(64),
    }],
  ];
  for (const [phase, fixture] of unsafeFixtures) {
    withJsonFixture(fixture, (fixturePath) => {
      const result = callSourcedFunction(`verify_phase_evidence ${phase} "${fixturePath}"`);
      assert.notEqual(result.status, 0, `unsafe ${phase} evidence passed: ${JSON.stringify(fixture)}`);
    });
  }
});

test("each owner-guided action occurs inside its machine evidence window", () => {
  const ownerGuide = scriptSource.slice(
    scriptSource.indexOf("run_owner_guided_canary() {"),
    scriptSource.indexOf("\nrecord_owner_only_observation() {", scriptSource.indexOf("run_owner_guided_canary() {"))
  );
  assert.doesNotMatch(ownerGuide, /read -r -p/);
  assert.match(ownerGuide, /capture_and_verify_phase fresh-scan/);
  assert.match(ownerGuide, /capture_and_verify_phase exact-reuse/);
  assert.match(ownerGuide, /capture_and_verify_phase scan-as-new/);

  const captureFunction = scriptSource.slice(
    scriptSource.indexOf("capture_and_verify_phase() {"),
    scriptSource.indexOf("\nrestore_original_app_absence() {", scriptSource.indexOf("capture_and_verify_phase() {"))
  );
  assert.ok(captureFunction.indexOf("start_utc=") < captureFunction.indexOf("read -r -p"));
  assert.ok(captureFunction.indexOf("read -r -p") < captureFunction.indexOf("end_utc="));
});

test("fresh seed and uncached Scan as New run in separate rollback-bounded live windows", () => {
  assert.match(scriptSource, /CANARY_PHASE="\$\{CANARY_PHASE:-seed\}"/);
  const ownerGuide = scriptSource.slice(
    scriptSource.indexOf("run_owner_guided_canary() {"),
    scriptSource.indexOf("\nrecord_owner_only_observation() {", scriptSource.indexOf("run_owner_guided_canary() {"))
  );
  assert.match(ownerGuide, /case "\$CANARY_PHASE" in/);
  assert.match(ownerGuide, /seed\)[\s\S]*capture_and_verify_phase fresh-scan[\s\S]*capture_and_verify_phase exact-reuse/);
  assert.match(ownerGuide, /rescan\)[\s\S]*capture_and_verify_phase scan-as-new/);
  const seedBody = ownerGuide.slice(ownerGuide.indexOf("seed)"), ownerGuide.indexOf("rescan)"));
  assert.doesNotMatch(seedBody, /capture_and_verify_phase scan-as-new/);
  const rescanBody = ownerGuide.slice(ownerGuide.indexOf("rescan)"));
  assert.doesNotMatch(rescanBody, /capture_and_verify_phase fresh-scan/);
  assert.match(scriptSource, /rollback between the seed and rescan windows/i);

  const invalidPhase = runScript({ CANARY_PHASE: "both-at-once" });
  assert.notEqual(invalidPhase.status, 0);
  assert.match(invalidPhase.stderr, /CANARY_PHASE must be seed or rescan/);
});

test("setup and readiness docs stage dry-run and approval-gated live commands without closing release gates", () => {
  for (const [label, source] of [
    ["production setup", productionSetupSource],
    ["App Store readiness", appStoreReadinessSource],
  ]) {
    assert.match(source, /run-positive-general-kenobi-canary\.sh/, `${label} omits the new harness`);
    assert.match(source, /DRY_RUN=true/, `${label} omits the dry-run command`);
    assert.match(
      source,
      /I_APPROVE_GENERAL_KENOBI_POSITIVE_CANARY_WITH_TEMPORARY_PUBLIC_CLOUD_RUN/,
      `${label} omits the approval gate`
    );
    assert.match(source, /positive sandbox-JWS real-device TestFlight gate/i);
    assert.match(source, /80-image\/120-call/i);
    assert.match(source, /distribution profile/i);
    assert.match(source, /remains open|still open|does not close/i);
  }
});

test("seed receipt enforces the buffered 24-hour rescan boundary", () => {
  withJsonFixture(
    { schemaVersion: 1, lifecycle: "seed_rolled_back", rescanNotBeforeEpoch: 1_000 },
    (fixturePath) => {
      const early = callSourcedFunction(`receipt_rescan_is_due "${fixturePath}" 999`);
      assert.notEqual(early.status, 0);
      const due = callSourcedFunction(`receipt_rescan_is_due "${fixturePath}" 1000`);
      assert.equal(due.status, 0, due.stderr);
    }
  );
  assert.match(scriptSource, /CANARY_RECEIPT_PATH/);
  assert.match(scriptSource, /RESCAN_INGESTION_SKEW_BUFFER_SECONDS="600"/);
  assert.match(scriptSource, /chmod 0700/);
  assert.match(scriptSource, /chmod 0600/);
});

test("rescan receipt revalidates the protected original-app backup before device or cloud actions", () => {
  const directory = mkdtempSync(path.join(tmpdir(), "cyclebalance-backup-continuity-"));
  const home = path.join(directory, "home");
  const backupRoot = path.join(home, "Library/Application Support/CycleBalance/DeviceBackups");
  const validBackup = path.join(backupRoot, "seed-backup");
  const emptyBackup = path.join(backupRoot, "empty-backup");
  const symlinkBackup = path.join(backupRoot, "linked-backup");
  mkdirSync(validBackup, { recursive: true, mode: 0o700 });
  mkdirSync(emptyBackup, { mode: 0o700 });
  chmodSync(backupRoot, 0o700);
  chmodSync(validBackup, 0o700);
  writeFileSync(path.join(validBackup, "container.db"), "protected", { mode: 0o600 });
  symlinkSync(validBackup, symlinkBackup);
  const run = (installed, state, backupPath) => callSourcedFunction(
    "APP_WAS_INSTALLED=" + installed + "; " +
    "ORIGINAL_APP_DATA_BACKUP_STATE='" + state + "'; " +
    "ORIGINAL_APP_DATA_BACKUP_PATH='" + backupPath + "'; " +
    "verify_receipt_backup_continuity",
    { HOME: home }
  );
  try {
    assert.equal(run("false", "not_present", "").status, 0);
    assert.equal(run("true", "app_data_container_copied", validBackup).status, 0);
    for (const [installed, state, backupPath] of [
      ["false", "app_data_container_copied", validBackup],
      ["false", "not_present", validBackup],
      ["true", "not_present", ""],
      ["true", "app_data_container_copied", path.join(backupRoot, "missing")],
      ["true", "app_data_container_copied", emptyBackup],
      ["true", "app_data_container_copied", symlinkBackup],
    ]) {
      assert.notEqual(run(installed, state, backupPath).status, 0);
    }
    chmodSync(path.join(validBackup, "container.db"), 0o644);
    assert.notEqual(run("true", "app_data_container_copied", validBackup).status, 0);
  } finally {
    rmSync(directory, { recursive: true, force: true });
  }

  const mainFunction = scriptSource.slice(scriptSource.indexOf("main() {"));
  assert.ok(
    mainFunction.indexOf("load_seed_receipt") < mainFunction.indexOf("verify_initial_cloud_state"),
    "receipt and backup continuity must be checked before cloud staging"
  );
});

test("Cloud Run policy checks reject both public principals and a disabled invoker IAM check", () => {
  for (const member of ["allUsers", "allAuthenticatedUsers"]) {
    withJsonFixture(
      { bindings: [{ role: "roles/run.invoker", members: [member] }] },
      (fixturePath) => {
        const result = callSourcedFunction(`iam_policy_is_private "${fixturePath}"`);
        assert.notEqual(result.status, 0, `${member} was accepted`);
      }
    );
  }
  withJsonFixture(
    { bindings: [{ role: "roles/run.invoker", members: ["serviceAccount:proxy@example.test"] }] },
    (fixturePath) => {
      const result = callSourcedFunction(`iam_policy_is_private "${fixturePath}"`);
      assert.equal(result.status, 0, result.stderr);
    }
  );

  for (const [annotation, accepted] of [["true", false], ["false", true], [undefined, true]]) {
    withJsonFixture(
      annotation === undefined ? { metadata: { annotations: {} } } : {
        metadata: { annotations: { "run.googleapis.com/invoker-iam-disabled": annotation } },
      },
      (fixturePath) => {
        const result = callSourcedFunction(`invoker_iam_check_is_enabled "${fixturePath}"`);
        assert.equal(result.status === 0, accepted, `${annotation}: ${result.stderr}`);
      }
    );
  }
});

test("live source, signing, device, deploy, and evidence gates are pinned and fail closed", () => {
  assert.match(scriptSource, /APPROVED_SOURCE_COMMIT/);
  assert.match(scriptSource, /git status --porcelain --untracked-files=all/);
  assert.match(scriptSource, /codesign --verify --deep --strict --verbose=4/);
  assert.match(scriptSource, /ProvisionedDevices/);
  assert.match(scriptSource, /TeamIdentifier/);
  assert.match(scriptSource, /application-identifier/);
  assert.match(scriptSource, /XCODE_DEVICE_UDID/);
  assert.match(scriptSource, /CoreDevice.*Xcode|Xcode.*CoreDevice/i);
  assert.match(scriptSource, /DEPLOY_MODE=canary/);
  assert.match(scriptSource, /MEAL_SCAN_CANARY_CORRELATION_SHA256/);
  assert.match(scriptSource, /positive-canary-evidence\.mjs/);
  assert.doesNotMatch(scriptSource, /rolling_quota_digest\(\)/);
});

test("Apple IAP preflight requires sole enabled v1, completed ownership, and exact proxy-only IAM", () => {
  const directory = mkdtempSync(path.join(tmpdir(), "cyclebalance-apple-iap-preflight-"));
  const metadataPath = path.join(directory, "metadata.json");
  const versionsPath = path.join(directory, "versions.json");
  const iamPath = path.join(directory, "iam.json");
  const validMetadata = {
    name: "projects/947929010052/secrets/cyclebalance-app-store-iap-private-key",
    labels: {
      cyclebalance_iap_provision_state: "complete",
      cyclebalance_iap_provision_owner: "a".repeat(32),
    },
  };
  const validVersions = [{
    name: "projects/947929010052/secrets/cyclebalance-app-store-iap-private-key/versions/1",
    state: "ENABLED",
  }];
  const validIam = {
    bindings: [{
      role: "roles/secretmanager.secretAccessor",
      members: [
        "serviceAccount:cyclebalance-meal-scan-proxy@cyclebalance-prod-20260710.iam.gserviceaccount.com",
      ],
    }],
  };
  const run = (metadata, versions, iam) => {
    writeFileSync(metadataPath, JSON.stringify(metadata));
    writeFileSync(versionsPath, JSON.stringify(versions));
    writeFileSync(iamPath, JSON.stringify(iam));
    return callSourcedFunction(
      "verify_apple_iap_provisioning_files " +
      "'" + metadataPath + "' '" + versionsPath + "' '" + iamPath + "'"
    );
  };
  try {
    assert.equal(run(validMetadata, validVersions, validIam).status, 0);
    for (const [metadata, versions, iam] of [
      [{ ...validMetadata, labels: { ...validMetadata.labels, cyclebalance_iap_provision_state: "locked" } }, validVersions, validIam],
      [{ ...validMetadata, labels: { ...validMetadata.labels, cyclebalance_iap_provision_owner: "foreign-owner" } }, validVersions, validIam],
      [validMetadata, [...validVersions, { ...validVersions[0], name: validVersions[0].name.replace("/1", "/2") }], validIam],
      [validMetadata, [{ ...validVersions[0], state: "DISABLED" }], validIam],
      [validMetadata, validVersions, { bindings: [{ role: "roles/secretmanager.secretAccessor", members: ["allUsers"] }] }],
      [validMetadata, validVersions, { bindings: [...validIam.bindings, { role: "roles/secretmanager.viewer", members: ["user:other@example.com"] }] }],
    ]) {
      assert.notEqual(run(metadata, versions, iam).status, 0);
    }
  } finally {
    rmSync(directory, { recursive: true, force: true });
  }
});

test("runner passes and reads back every pinned deploy principal and secret reference", () => {
  const service = {
    spec: {
      template: {
        spec: {
          serviceAccountName: "cyclebalance-meal-scan-proxy@cyclebalance-prod-20260710.iam.gserviceaccount.com",
          containers: [{
            env: [
              { name: "GEMINI_API_KEY", valueFrom: { secretKeyRef: { name: "cyclebalance-gemini-api-key", key: "7" } } },
              { name: "MEAL_SCAN_PRINCIPAL_HMAC_SECRET", valueFrom: { secretKeyRef: { name: "cyclebalance-meal-scan-principal-hmac", key: "1" } } },
              { name: "APPLE_IAP_PRIVATE_KEY", valueFrom: { secretKeyRef: { name: "cyclebalance-app-store-iap-private-key", key: "1" } } },
              { name: "REVENUECAT_SECRET_API_KEY", valueFrom: { secretKeyRef: { name: "cyclebalance-revenuecat-secret-api-key", key: "9" } } },
            ],
          }],
        },
      },
    },
  };

  withJsonFixture(service, (fixturePath) => {
    const result = callSourcedFunction(
      `GEMINI_SECRET_VERSION=7; REVENUECAT_SECRET_VERSION=9; verify_deployed_runtime_and_secret_refs "${fixturePath}"`
    );
    assert.equal(result.status, 0, result.stderr);
  });

  for (const mutate of [
    (fixture) => { fixture.spec.template.spec.serviceAccountName = "other@example.test"; },
    (fixture) => { fixture.spec.template.spec.containers[0].env[0].valueFrom.secretKeyRef.name = "other-gemini"; },
    (fixture) => { fixture.spec.template.spec.containers[0].env[3].valueFrom.secretKeyRef.key = "latest"; },
  ]) {
    const drifted = structuredClone(service);
    mutate(drifted);
    withJsonFixture(drifted, (fixturePath) => {
      const result = callSourcedFunction(
        `GEMINI_SECRET_VERSION=7; REVENUECAT_SECRET_VERSION=9; verify_deployed_runtime_and_secret_refs "${fixturePath}"`
      );
      assert.notEqual(result.status, 0, `deploy readback drift passed: ${JSON.stringify(drifted)}`);
    });
  }

  const deployFunction = scriptSource.slice(
    scriptSource.indexOf("deploy_environment() {"),
    scriptSource.indexOf("\ndeploy_temporarily_enabled_public() {", scriptSource.indexOf("deploy_environment() {"))
  );
  for (const variable of [
    "SERVICE_ACCOUNT_NAME",
    "BUILD_SERVICE_ACCOUNT_NAME",
    "GEMINI_SECRET_NAME",
    "PRINCIPAL_HMAC_SECRET_NAME",
    "APPLE_IAP_PRIVATE_KEY_SECRET_NAME",
    "REVENUECAT_SECRET_NAME",
    "APPROVED_SOURCE_COMMIT",
    "CANARY_SOURCE_ARCHIVE",
    "CANARY_SOURCE_ARCHIVE_SHA256",
  ]) {
    assert.match(deployFunction, new RegExp(`${variable}=`), `${variable} is not passed to the canary deploy`);
  }
});

test("runtime readback accepts only the exact enabled and disabled Cloud Run contract", () => {
  const regularEnvironment = Object.freeze({
    NODE_ENV: "production",
    APP_CHECK_REQUIRED: "true",
    FIREBASE_APP_ID: "1:947929010052:ios:6e68c8645a6a6b5e3057d1",
    APPLE_BUNDLE_ID: "alex.PCOS",
    APPLE_APP_ID: "6760353511",
    APPLE_ALLOWED_PRODUCT_IDS: "cyclebalance.premium.monthly,cyclebalance.premium.annual",
    APPLE_IAP_KEY_ID: "ABCD1234",
    APPLE_IAP_ISSUER_ID: "12345678-1234-1234-1234-123456789abc",
    REVENUECAT_PROJECT_ID: "proj8da4e000",
    REVENUECAT_ENTITLEMENT_ID: "CycleBalance Unlimited",
    REVENUECAT_TIMEOUT_MS: "3000",
    MEAL_SCAN_QUOTA_STORE: "firestore",
    MEAL_SCAN_QUOTA_COLLECTION: "mealScanRollingQuota",
    MEAL_SCAN_RESULT_CACHE: "firestore",
    MEAL_SCAN_RESULT_CACHE_COLLECTION: "mealScanEstimateCache",
    MEAL_SCAN_IDEMPOTENCY_STORE: "firestore",
    MEAL_SCAN_IDEMPOTENCY_COLLECTION: "mealScanIdempotency",
    MEAL_SCAN_IDEMPOTENCY_PENDING_TTL_MS: "30000",
    MEAL_SCAN_REQUEST_GATE: "firestore",
    MEAL_SCAN_REQUEST_GATE_COLLECTION: "mealScanRequestGate",
    MEAL_SCAN_REQUESTS_PER_MINUTE_LIMIT: "30",
    MEAL_SCAN_REQUESTS_PER_DAY_LIMIT: "200",
    MEAL_SCAN_GLOBAL_REQUESTS_PER_MINUTE_LIMIT: "300",
    MEAL_SCAN_GLOBAL_REQUESTS_PER_DAY_LIMIT: "3000",
    MEAL_SCAN_PRINCIPAL_ATTEMPT_STORE: "firestore",
    MEAL_SCAN_PRINCIPAL_ATTEMPT_COLLECTION: "mealScanPrincipalAttempts",
    MEAL_SCAN_PRINCIPAL_ATTEMPTS_PER_MINUTE_LIMIT: "3",
    MEAL_SCAN_PRINCIPAL_ATTEMPTS_PER_24_HOURS_LIMIT: "30",
    MEAL_SCAN_GLOBAL_PROVIDER_DISPATCHES_PER_MINUTE_LIMIT: "60",
    MEAL_SCAN_GLOBAL_PROVIDER_DISPATCHES_PER_24_HOURS_LIMIT: "1000",
    MEAL_SCAN_BUDGET_STORE: "firestore",
    MEAL_SCAN_CONTROL_COLLECTION: "mealScanControls",
    MEAL_SCAN_CONTROL_DOCUMENT: "global",
    MEAL_SCAN_BUDGET_STATE_MAX_AGE_SECONDS: "86400",
    MEAL_SCAN_RESULT_CACHE_TTL_SECONDS: "86400",
    MEAL_SCAN_RESULT_LEASE_TTL_MS: "30000",
    MEAL_SCAN_CONTROL_CACHE_TTL_MS: "30000",
    MEAL_SCAN_DAILY_LIMIT: "10",
    MEAL_SCAN_TRIAL_DAILY_LIMIT: "5",
    MEAL_SCAN_TRIAL_TOTAL_LIMIT: "25",
    MEAL_SCAN_MONTHLY_BUDGET_ALERT_USD: "15",
    MEAL_SCAN_MONTHLY_BUDGET_DEGRADE_USD: "20",
    MEAL_SCAN_MONTHLY_BUDGET_DISABLE_USD: "25",
    MAX_BODY_BYTES: "2200000",
    MAX_IMAGE_BYTES: "1500000",
    MAX_IMAGE_PIXELS: "12000000",
    MAX_CANONICAL_IMAGE_BYTES: "750000",
    APP_CHECK_TIMEOUT_MS: "5000",
    APPLE_STATUS_TIMEOUT_MS: "5000",
    GEMINI_TIMEOUT_MS: "12000",
  });
  const secretNames = [
    "GEMINI_API_KEY",
    "MEAL_SCAN_PRINCIPAL_HMAC_SECRET",
    "APPLE_IAP_PRIVATE_KEY",
    "REVENUECAT_SECRET_API_KEY",
  ];
  const service = (enabled) => ({
    metadata: { annotations: {
      "run.googleapis.com/ingress": "all",
      "run.googleapis.com/invoker-iam-disabled": enabled ? "true" : "false",
    } },
    spec: { template: {
      metadata: { annotations: {
        "autoscaling.knative.dev/minScale": "0",
        "autoscaling.knative.dev/maxScale": "2",
        "run.googleapis.com/execution-environment": "gen2",
      } },
      spec: {
        containerConcurrency: 20,
        timeoutSeconds: 30,
        containers: [{
          resources: { limits: { cpu: "1000m", memory: "512Mi" } },
          env: [
            ...Object.entries({
              ...regularEnvironment,
              MEAL_SCAN_ENABLED: enabled ? "true" : "false",
              ...(enabled ? { MEAL_SCAN_CANARY_CORRELATION_SHA256: genericHexValue } : {}),
            }).map(([name, value]) => ({ name, value })),
            ...secretNames.map((name) => ({
              name, valueFrom: { secretKeyRef: { name: "fixture-secret", key: "1" } },
            })),
          ],
        }],
      },
    } },
  });
  const command = (fixturePath, enabled) => [
    "APPLE_IAP_KEY_ID_VALUE=ABCD1234",
    "APPLE_IAP_ISSUER_ID_VALUE=12345678-1234-1234-1234-123456789abc",
    `CANARY_CORRELATION_ID=${genericHexValue}`,
    `verify_deployed_runtime_configuration "${fixturePath}" ${enabled}`,
  ].join("; ");

  for (const enabled of [false, true]) {
    withJsonFixture(service(enabled), (fixturePath) => {
      const result = callSourcedFunction(command(fixturePath, enabled));
      assert.equal(result.status, 0, `${enabled}: ${result.stderr}`);
    });
  }

  const drifts = [
    ["changed regular env", (value) => { value.spec.template.spec.containers[0].env.find((entry) => entry.name === "MEAL_SCAN_DAILY_LIMIT").value = "11"; }],
    ["missing env", (value) => { value.spec.template.spec.containers[0].env.pop(); }],
    ["extra env", (value) => { value.spec.template.spec.containers[0].env.push({ name: "UNAPPROVED", value: "true" }); }],
    ["renamed secret", (value) => { value.spec.template.spec.containers[0].env.find((entry) => entry.name === "GEMINI_API_KEY").name = "WRONG_GEMINI_KEY"; }],
    ["cpu", (value) => { value.spec.template.spec.containers[0].resources.limits.cpu = "2"; }],
    ["memory", (value) => { value.spec.template.spec.containers[0].resources.limits.memory = "1Gi"; }],
    ["concurrency", (value) => { value.spec.template.spec.containerConcurrency = 21; }],
    ["timeout", (value) => { value.spec.template.spec.timeoutSeconds = 31; }],
    ["min scale", (value) => { value.spec.template.metadata.annotations["autoscaling.knative.dev/minScale"] = "1"; }],
    ["max scale", (value) => { value.spec.template.metadata.annotations["autoscaling.knative.dev/maxScale"] = "3"; }],
    ["execution environment", (value) => { value.spec.template.metadata.annotations["run.googleapis.com/execution-environment"] = "gen1"; }],
    ["ingress", (value) => { value.metadata.annotations["run.googleapis.com/ingress"] = "internal"; }],
    ["service base image", (value) => { value.metadata.annotations["run.googleapis.com/base-images"] = "unexpected"; }],
    ["template base image", (value) => { value.spec.template.metadata.annotations["run.googleapis.com/base-images"] = "unexpected"; }],
    ["enabled invoker IAM", (value) => { value.metadata.annotations["run.googleapis.com/invoker-iam-disabled"] = "false"; }],
  ];
  for (const [label, mutate] of drifts) {
    const drifted = service(true);
    mutate(drifted);
    withJsonFixture(drifted, (fixturePath) => {
      const result = callSourcedFunction(command(fixturePath, true));
      assert.notEqual(result.status, 0, `${label} drift passed`);
    });
  }
  const publiclyDisabled = service(false);
  publiclyDisabled.metadata.annotations["run.googleapis.com/invoker-iam-disabled"] = "true";
  withJsonFixture(publiclyDisabled, (fixturePath) => {
    const result = callSourcedFunction(command(fixturePath, false));
    assert.notEqual(result.status, 0, "disabled/private readback accepted public invoker bypass");
  });
});

test("runner proves Cloud Build identity immutable source and produced revision image", () => {
  const buildId = "3b68eb76-3ce2-4c71-b75f-f08dc70a9e13";
  const revision = "cyclebalance-meal-scan-proxy-00099-canary";
  const imageName = "us-central1-docker.pkg.dev/cyclebalance-prod-20260710/cloud-run-source-deploy/cyclebalance-meal-scan-proxy";
  const imageDigest = `sha256:${"d".repeat(64)}`;
  const buildName = `projects/cyclebalance-prod-20260710/locations/us-central1/builds/${buildId}`;
  const buildServiceAccount = "projects/cyclebalance-prod-20260710/serviceAccounts/cyclebalance-cloud-build@cyclebalance-prod-20260710.iam.gserviceaccount.com";
  const sourceLocation = "gs://run-sources-cyclebalance-prod-20260710-us-central1/services/cyclebalance-meal-scan-proxy/source.tgz#1731549123456789";
  const service = {
    metadata: {
      annotations: {
        "run.googleapis.com/build-id": buildId,
        "run.googleapis.com/build-name": buildName,
        "run.googleapis.com/build-service-account": buildServiceAccount,
        "run.googleapis.com/build-source-location": sourceLocation,
      },
    },
    spec: {
      template: {
        metadata: { name: revision },
        spec: { containers: [{ image: `${imageName}@${imageDigest}` }] },
      },
    },
    status: {
      latestCreatedRevisionName: revision,
      latestReadyRevisionName: revision,
    },
  };
  const build = {
    id: buildId,
    name: buildName,
    status: "SUCCESS",
    serviceAccount: buildServiceAccount,
    source: {
      storageSource: {
        bucket: "run-sources-cyclebalance-prod-20260710-us-central1",
        object: "services/cyclebalance-meal-scan-proxy/source.tgz",
        generation: "1731549123456789",
      },
    },
    results: { images: [{ name: imageName, digest: imageDigest }] },
  };

  const verify = (serviceFixture, buildFixture) => withJsonFixture(serviceFixture, (servicePath) =>
    withJsonFixture(buildFixture, (buildPath) => callSourcedFunction(
      `verify_deployed_build_provenance "${servicePath}" "${buildPath}"`
    ))
  );
  const valid = verify(service, build);
  assert.equal(valid.status, 0, valid.stderr);

  const mutations = [
    [structuredClone(service), { ...structuredClone(build), serviceAccount: "projects/cyclebalance-prod-20260710/serviceAccounts/other@cyclebalance-prod-20260710.iam.gserviceaccount.com" }],
    [structuredClone(service), { ...structuredClone(build), source: { storageSource: { ...build.source.storageSource, generation: "99" } } }],
    [structuredClone(service), { ...structuredClone(build), results: { images: [{ name: imageName, digest: `sha256:${"e".repeat(64)}` }] } }],
    [{ ...structuredClone(service), status: { ...service.status, latestReadyRevisionName: "other-revision" } }, structuredClone(build)],
  ];
  for (const [serviceFixture, buildFixture] of mutations) {
    const result = verify(serviceFixture, buildFixture);
    assert.notEqual(result.status, 0, "unsafe build provenance fixture passed");
  }

  const captureFunction = scriptSource.slice(
    scriptSource.indexOf("capture_and_verify_build_provenance() {"),
    scriptSource.indexOf("\nservice_env_value() {", scriptSource.indexOf("capture_and_verify_build_provenance() {"))
  );
  assert.match(captureFunction, /gcloud builds describe/);
  assert.match(captureFunction, /--region "\$REGION"/);
  assert.match(captureFunction, /verify_deployed_build_provenance/);
});

test("one sealed approved source archive is prepared before enablement and reused for rollback", () => {
  assert.match(scriptSource, /prepare_approved_source_archive/);
  const mainFunction = scriptSource.slice(scriptSource.indexOf("main() {"));
  assert.ok(
    mainFunction.indexOf("prepare_approved_source_archive") < mainFunction.indexOf("ROLLBACK_ARMED=true"),
    "approved source must be sealed before rollback is armed and public enablement begins"
  );
  const deployFunction = scriptSource.slice(
    scriptSource.indexOf("deploy_environment() {"),
    scriptSource.indexOf("\ndeploy_temporarily_enabled_public() {", scriptSource.indexOf("deploy_environment() {"))
  );
  assert.match(deployFunction, /CANARY_SOURCE_ARCHIVE="\$CANARY_SOURCE_ARCHIVE"/);
  assert.match(deployFunction, /CANARY_SOURCE_ARCHIVE_SHA256="\$CANARY_SOURCE_ARCHIVE_SHA256"/);
});

test("two-window lifecycle keeps the canary installed after seed and restores only after rescan", () => {
  const mainFunction = scriptSource.slice(scriptSource.indexOf("main() {"));
  assert.match(mainFunction, /case "\$CANARY_PHASE"/);
  assert.match(mainFunction, /load_seed_receipt/);
  assert.match(scriptSource, /verify_dormant_window_continuity/);
  assert.match(scriptSource, /manual restore required/i);
  assert.match(scriptSource, /initially absent/i);

  const rollbackFunction = scriptSource.slice(
    scriptSource.indexOf("rollback() {"),
    scriptSource.indexOf("\nmain() {", scriptSource.indexOf("rollback() {"))
  );
  assert.match(rollbackFunction, /finalize_device_lifecycle/);
  assert.doesNotMatch(rollbackFunction, /restore_original_app_absence/);
});

test("command-shim state machine restores cloud and IAM on failures, signals, and rollback errors", () => {
  const directory = mkdtempSync(path.join(tmpdir(), "cyclebalance-rollback-state-machine-"));
  const commandLog = path.join(directory, "commands.log");
  const harness = `
source "$1"
TEMP_ROOT="$2/temp"
mkdir -p "$TEMP_ROOT"
COMMAND_LOG="$3"
EVIDENCE_DIR=""
EVIDENCE_SUMMARY=""
ROLLBACK_ARMED=true
ROLLBACK_COMPLETE=false
CANARY_PHASE=seed
CANARY_APP_INSTALL_STARTED=false
DEPLOY_RESULT=0
FIRST_RESTORE_RESULT=0
SECOND_RESTORE_RESULT=0
RESTORE_CALLS=0
VERIFY_MODE=success
SIGNAL_DURING_ROLLBACK=false
deploy_disabled_private() {
  printf 'deploy-disabled\n' >> "$COMMAND_LOG"
  [[ "$SIGNAL_DURING_ROLLBACK" == false ]] || kill -TERM $$
  return "$DEPLOY_RESULT"
}
restore_initial_iam_policy() {
  RESTORE_CALLS=$((RESTORE_CALLS + 1))
  printf 'restore-iam:%s\n' "$RESTORE_CALLS" >> "$COMMAND_LOG"
  if [[ "$RESTORE_CALLS" == 1 ]]; then return "$FIRST_RESTORE_RESULT"; fi
  return "$SECOND_RESTORE_RESULT"
}
verify_final_disabled_private() {
  printf 'verify-final\n' >> "$COMMAND_LOG"
  case "$VERIFY_MODE" in
    success) printf 'meal-scan-proxy-test-revision\n' >"$TEMP_ROOT/final-disabled-revision.txt"; return 0 ;;
    failure) return 1 ;;
    die) die "synthetic verifier exit" ;;
  esac
}
finalize_device_lifecycle() { printf 'finalize-device:%s\n' "$1" >> "$COMMAND_LOG"; return 0; }
cleanup_temp() { :; }
case "$4" in
  failure) rollback 1 ;;
  signal)
    trap 'handle_canary_signal TERM' TERM
    trap handle_canary_exit EXIT
    kill -TERM $$
    ;;
  first-restore-error) FIRST_RESTORE_RESULT=1; rollback 0 ;;
  second-restore-error) SECOND_RESTORE_RESULT=1; rollback 0 ;;
  deploy-error) DEPLOY_RESULT=1; rollback 0 ;;
  verify-error) VERIFY_MODE=failure; rollback 0 ;;
  verify-die) VERIFY_MODE=die; rollback 0 ;;
  repeated-signal) SIGNAL_DURING_ROLLBACK=true; rollback 1 ;;
esac
`;
  try {
    for (const [scenario, expectedStatus] of [
      ["failure", 1],
      ["signal", 143],
      ["first-restore-error", 1],
      ["second-restore-error", 1],
      ["deploy-error", 1],
      ["verify-error", 1],
      ["verify-die", 1],
      ["repeated-signal", 1],
    ]) {
      writeFileSync(commandLog, "");
      const result = spawnSync(
        "bash",
        ["-c", harness, "rollback-test", scriptPath, directory, commandLog, scenario],
        { cwd: repositoryRoot, encoding: "utf8" }
      );
      assert.equal(result.status, expectedStatus, `${scenario}: ${result.stderr}`);
      const calls = readFileSync(commandLog, "utf8");
      assert.equal((calls.match(/deploy-disabled/g) ?? []).length, 1, `${scenario}: rollback deploy repeated`);
      assert.equal((calls.match(/restore-iam/g) ?? []).length, 2, `${scenario}: rollback must make two bounded IAM restores`);
      assert.equal((calls.match(/verify-final/g) ?? []).length, 1, `${scenario}: final verification repeated or skipped`);
      assert.equal((calls.match(/finalize-device/g) ?? []).length, 1, `${scenario}: device finalization repeated`);
    }
  } finally {
    rmSync(directory, { recursive: true, force: true });
  }
});

test("simulated post-enable checkout dirt cannot replace or block the sealed rollback source", () => {
  const directory = mkdtempSync(path.join(tmpdir(), "cyclebalance-dirty-after-enable-"));
  const commandLog = path.join(directory, "commands.log");
  const archive = path.join(directory, "approved-source.tar");
  writeFileSync(archive, "sealed approved source", { mode: 0o400 });
  const archiveDigest = "a".repeat(64);
  const harness = `
source "$1"
TEMP_ROOT="$2/temp"
mkdir -p "$TEMP_ROOT"
COMMAND_LOG="$3"
CANARY_SOURCE_ARCHIVE="$4"
CANARY_SOURCE_ARCHIVE_SHA256="$5"
ORIGINAL_ARCHIVE="$CANARY_SOURCE_ARCHIVE"
ORIGINAL_DIGEST="$CANARY_SOURCE_ARCHIVE_SHA256"
CHECKOUT_DIRTY=false
EVIDENCE_DIR=""
EVIDENCE_SUMMARY=""
ROLLBACK_ARMED=false
ROLLBACK_COMPLETE=false
ROLLBACK_IN_PROGRESS=false
CANARY_PHASE=seed
CANARY_APP_INSTALL_STARTED=false
deploy_environment() {
  if [[ "$1" == "true" ]]; then
    printf 'enabled:%s:%s\n' "$CANARY_SOURCE_ARCHIVE" "$CANARY_SOURCE_ARCHIVE_SHA256" >>"$COMMAND_LOG"
    CHECKOUT_DIRTY=true
    return 0
  fi
  [[ "$CHECKOUT_DIRTY" == true ]]
  [[ "$CANARY_SOURCE_ARCHIVE" == "$ORIGINAL_ARCHIVE" ]]
  [[ "$CANARY_SOURCE_ARCHIVE_SHA256" == "$ORIGINAL_DIGEST" ]]
  printf 'rollback-dirty:%s:%s\n' "$CANARY_SOURCE_ARCHIVE" "$CANARY_SOURCE_ARCHIVE_SHA256" >>"$COMMAND_LOG"
}
restore_initial_iam_policy() { printf 'restore-iam\n' >>"$COMMAND_LOG"; }
verify_final_disabled_private() {
  printf 'verify-final\n' >>"$COMMAND_LOG"
  printf 'meal-scan-proxy-test-revision\n' >"$TEMP_ROOT/final-disabled-revision.txt"
}
finalize_device_lifecycle() { return 0; }
cleanup_temp() { :; }
deploy_environment true true
ROLLBACK_ARMED=true
rollback 1
`;
  try {
    const result = spawnSync(
      "bash",
      ["-c", harness, "dirty-after-enable-test", scriptPath, directory, commandLog, archive, archiveDigest],
      { cwd: repositoryRoot, encoding: "utf8" }
    );
    assert.equal(result.status, 1, result.stderr);
    const calls = readFileSync(commandLog, "utf8");
    assert.match(calls, /enabled:/);
    assert.match(calls, /rollback-dirty:/);
    assert.match(calls, /restore-iam/);
    assert.match(calls, /verify-final/);
    assert.equal((calls.match(new RegExp(archiveDigest, "g")) ?? []).length, 2);
  } finally {
    rmSync(directory, { recursive: true, force: true });
  }
});

test("final rescan lifecycle covers both initially absent and initially present app states", () => {
  for (const [initialState, expectedStatus, expectedLifecycle] of [
    ["absent", 0, "removed"],
    ["present", 1, "manual_restore_required"],
  ]) {
    const directory = mkdtempSync(path.join(tmpdir(), `cyclebalance-final-${initialState}-`));
    const home = path.join(directory, "home");
    mkdirSync(home);
    const harness = `
source "$1"
mkdir -p "$CANARY_RECEIPT_ROOT"
chmod 0700 "$CANARY_RECEIPT_ROOT"
printf '{"lifecycle":"seed_rolled_back"}\n' > "$CANARY_RECEIPT_PATH"
chmod 0600 "$CANARY_RECEIPT_PATH"
CANARY_PHASE=rescan
CANARY_RUN_COMPLETED=true
ROLLBACK_COMPLETE=true
ORIGINAL_APP_VERSION=1.0.4
ORIGINAL_APP_BUILD=17
ORIGINAL_APP_SIGNING_STATE=distribution_or_store
ORIGINAL_APP_DATA_BACKUP_PATH="$HOME/backup"
EVIDENCE_SUMMARY=""
if [[ "$2" == "absent" ]]; then APP_WAS_INSTALLED=false; else APP_WAS_INSTALLED=true; fi
uninstall_and_verify_initial_absence() { printf 'uninstalled-and-verified\n'; return 0; }
set +e
finalize_device_lifecycle 0
exit $?
`;
    try {
      const result = spawnSync(
        "bash",
        ["-c", harness, "lifecycle-test", scriptPath, initialState],
        { cwd: repositoryRoot, encoding: "utf8", env: { ...process.env, HOME: home } }
      );
      assert.equal(result.status, expectedStatus, `${initialState}: ${result.stderr}`);
      const receiptPath = path.join(home, "Library/Application Support/CycleBalance/PositiveCanary/seed-receipt.json");
      if (expectedLifecycle === "removed") {
        assert.match(result.stdout, /uninstalled-and-verified/);
        assert.equal(existsSync(receiptPath), false);
      } else {
        assert.equal(JSON.parse(readFileSync(receiptPath, "utf8")).lifecycle, expectedLifecycle);
        assert.match(result.stderr, /MANUAL RESTORE REQUIRED/);
      }
    } finally {
      rmSync(directory, { recursive: true, force: true });
    }
  }
});

test("failed seed receipt persistence never leaves an untracked installed canary", () => {
  for (const initialState of ["absent", "present"]) {
    const directory = mkdtempSync(path.join(tmpdir(), "cyclebalance-seed-receipt-failure-"));
    const commandLog = path.join(directory, "commands.log");
    const harness = [
      'source "$1"',
      'COMMAND_LOG="$2"',
      "CANARY_PHASE=seed",
      "CANARY_RUN_COMPLETED=true",
      "ROLLBACK_COMPLETE=true",
      "CANARY_APP_INSTALL_STARTED=true",
      "SEED_RECEIPT_PENDING=true",
      "ORIGINAL_APP_VERSION=1.0.4",
      "ORIGINAL_APP_BUILD=17",
      "ORIGINAL_APP_SIGNING_STATE=distribution_or_store",
      'ORIGINAL_APP_DATA_BACKUP_PATH="$HOME/protected-backup"',
      'if [[ "$3" == "absent" ]]; then APP_WAS_INSTALLED=false; else APP_WAS_INSTALLED=true; fi',
      "write_seed_receipt() { printf 'receipt-failed\\n' >>\"$COMMAND_LOG\"; return 1; }",
      "uninstall_and_verify_initial_absence() { printf 'uninstalled-and-verified\\n' >>\"$COMMAND_LOG\"; return 0; }",
      "set +e",
      "finalize_device_lifecycle 0",
      "exit $?",
    ].join("\n");
    try {
      const result = spawnSync(
        "bash",
        ["-c", harness, "seed-receipt-test", scriptPath, commandLog, initialState],
        { cwd: repositoryRoot, encoding: "utf8" }
      );
      assert.equal(result.status, 1, initialState);
      const calls = readFileSync(commandLog, "utf8");
      assert.match(calls, /receipt-failed/);
      if (initialState === "absent") {
        assert.match(calls, /uninstalled-and-verified/);
      } else {
        assert.doesNotMatch(calls, /uninstalled-and-verified/);
        assert.match(result.stderr, /MANUAL RESTORE REQUIRED/);
      }
    } finally {
      rmSync(directory, { recursive: true, force: true });
    }
  }
});

test("scanner canary Xcode configuration is isolated from canonical Release", () => {
  assert.equal(existsSync(scannerCanaryConfigPath), true);
  assert.match(projectSource, /configs:\n  Debug: debug\n  Release: release\n  ScannerCanary: release/);
  assert.match(projectSource, /ScannerCanary: Config\/ScannerCanary\.xcconfig/);

  const schemeStart = projectSource.indexOf("  PCOS General Kenobi Scanner Canary:");
  assert.notEqual(schemeStart, -1);
  const schemeSource = projectSource.slice(schemeStart);
  assert.match(schemeSource, /run:\n      config: ScannerCanary/);
  assert.match(schemeSource, /profile:\n      config: ScannerCanary/);
  assert.match(schemeSource, /analyze:\n      config: ScannerCanary/);
  assert.match(schemeSource, /archive:\n      config: Release/);
  assert.doesNotMatch(schemeSource, /storeKitConfiguration:/);
  assert.match(schemeSource, /"-billing\.backendMode": true/);
  assert.match(schemeSource, /"revenuecat": true/);

  const expectedCanaryFlags = new Map([
    ["MEAL_SCAN_RELEASE_UI_ENABLED", "YES"],
    ["MEAL_SCAN_RELEASE_GEMINI_ENABLED", "YES"],
    ["MEAL_SCAN_RELEASE_MOCK_DATA_ENABLED", "NO"],
    ["MEAL_SCAN_RELEASE_DEBUG_DIRECT_ENABLED", "NO"],
    ["MEAL_SCAN_RELEASE_FALLBACK_MODEL_ENABLED", "NO"],
    ["MEAL_SCAN_RELEASE_SIMILARITY_ENABLED", "NO"],
  ]);
  for (const [key, expected] of expectedCanaryFlags) {
    const canaryAssignments = [
      ...scannerCanaryConfigSource.matchAll(new RegExp(`^[ \\t]*${key}[ \\t]*=[ \\t]*(.*)[ \\t]*$`, "gm")),
    ];
    assert.equal(canaryAssignments.length, 1, `${key} must have exactly one canary assignment`);
    assert.equal(canaryAssignments[0][1].trim(), expected, `${key} canary assignment is unsafe`);

    const canonicalDeclarations = [
      ...projectSource.matchAll(new RegExp(`^[ \\t]+${key}:[ \\t]*(.*)[ \\t]*$`, "gm")),
    ];
    assert.equal(canonicalDeclarations.length, 1, `${key} must have exactly one canonical declaration`);
    assert.match(
      canonicalDeclarations[0][1].trim(),
      /^["']?NO["']?$/,
      `${key} canonical declaration must remain NO`,
    );
  }
});
