import assert from "node:assert/strict";
import crypto from "node:crypto";
import { spawnSync } from "node:child_process";
import { readFileSync } from "node:fs";
import test from "node:test";
import { fileURLToPath } from "node:url";
import {
  assertSafeEvidenceContent,
  findCanaryQuotaSnapshot,
  projectCorrelatedScannerEvents,
  verifyCorrelatedPhase,
} from "../scripts/positive-canary-evidence.mjs";

const canaryId = "90b2ac63-e61f-49e1-a8b0-a5e85f154d4c";
const genericUuidValue = canaryId;
const correlationId = crypto.createHash("sha256").update(canaryId).digest("hex");
const operationTag = "b".repeat(64);
const quotaPrincipal = "principal-document-id-that-must-never-be-retained";
const quotaTag = crypto
  .createHash("sha256")
  .update(`${canaryId}|${quotaPrincipal}`)
  .digest("hex");
const helperPath = fileURLToPath(new URL("../scripts/positive-canary-evidence.mjs", import.meta.url));
const highEntropyGenericValue = "ABCDEFGHIJKLMNOPQRSTUVWXYZabcdefghijklmnopqr";
const genericHexValue = "0123456789abcdef".repeat(4);
const identifierBypasses = Object.freeze([
  "00000000-0000-0000-0000-000000000000",
  "90b2ac63-e61f-99e1-a8b0-a5e85f154d4c",
  "90b2ac63-e61f-49e1-78b0-a5e85f154d4c",
  "90b2ac63e61f49e1a8b0a5e85f154d4c",
  `a${genericUuidValue}`, `${genericUuidValue}f`, `a${genericHexValue}`, `${genericHexValue}f`,
]);
const numericTokenAliases = Object.freeze(["input_tokens", "InputTokens", "input.tokens", "input-tokens"]);
const quotedValuePairs = Object.freeze([
  ["\"", "\""], ["'", "'"], ["`", "`"], ["“", "”"], ["‘", "’"],
  ["«", "»"], ["‹", "›"], ["「", "」"], ["『", "』"],
]);
const lookalikeAssignmentDelimiters = Object.freeze([
  ..."︓﹕ःઃ：։܃܄᛬︰᠃᠉⁚׃˸꞉∶ːꓽ𑷙⩴⧴",
  ..."﹦＝᐀⹀゠꓿≚≙≗≐≑⮖⩮⩵⩶≞",
]);
const nfkdAsciiCompatibilitySymbols = Object.freeze([...(
  "₨℀℁℅℆№℠℡™℻⒜⒝⒞⒟⒠⒡⒢⒣⒤⒥⒦⒧⒨⒩⒪⒫⒬⒭⒮⒯⒰⒱⒲⒳⒴⒵" +
  "ⒶⒷⒸⒹⒺⒻⒼⒽⒾⒿⓀⓁⓂⓃⓄⓅⓆⓇⓈⓉⓊⓋⓌⓍⓎⓏⓐⓑⓒⓓⓔⓕⓖⓗⓘⓙⓚⓛⓜⓝⓞⓟⓠⓡⓢⓣⓤⓥⓦⓧⓨⓩ" +
  "㉐㋌㋍㋎㋏" +
  "㍱㍲㍳㍴㍵㍶㍷㍸㍹㍺㎀㎁㎃㎄㎅㎆㎇㎈㎉㎊㎋㎎㎏㎐㎑㎒㎓㎔㎖㎗㎘㎙㎚㎜㎝㎞㎟" +
  "㎠㎡㎢㎣㎤㎥㎦㎩㎪㎫㎬㎭㎰㎱㎳㎴㎵㎷㎸㎹㎺㎻㎽㎾㎿㏂㏃㏄㏅㏇㏈㏉㏊㏋㏌㏍" +
  "㏎㏏㏐㏑㏒㏓㏔㏕㏖㏗㏘㏙㏚㏛㏜㏝㏿𜳖𜳗𜳘𜳙𜳚𜳛𜳜𜳝𜳞𜳟𜳠𜳡𜳢𜳣" +
  "𜳤𜳥𜳦𜳧𜳨𜳩𜳪𜳫𜳬𜳭𜳮𜳯🄐🄑🄒🄓🄔🄕🄖🄗🄘🄙🄚🄛🄜🄝🄞🄟🄠🄡🄢🄣🄤🄥🄦🄧🄨🄩" +
  "🄫🄬🄭🄮🄰🄱🄲🄳🄴🄵🄶🄷🄸🄹🄺🄻" +
  "🄼🄽🄾🄿🅀🅁🅂🅃🅄🅅🅆🅇🅈🅉🅊🅋🅌🅍🅎🅏🅪🅫🅬🆐"
)]);
const nestedPrivacyBypasses = Object.freeze([
  ["meal.name", { meal: { name: "private breakfast" } }],
  ["foods[].name", { foods: [{ name: "private breakfast" }] }],
  ["transaction.id", { transaction: { id: "123456789" } }],
  ["storeKit.payload", { storeKit: { payload: "private-storekit-payload" } }],
]);
const exactPrivacyFieldBypasses = Object.freeze([
  ["authToken", "private-auth-value"],
  ["session_token", "private-session-value"],
  ["credential", "private-credential-value"],
  ["image", "private-image-value"],
  ["imageBytes", "private-image-bytes"],
  ["foodNames", ["private breakfast"]],
  ["mealTitle", "private breakfast title"],
  ["storeKitPayload", "private-storekit-payload"],
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
  `${fieldEndingAtLength(65, "canaryCorrelationId")}=${correlationId}`,
  `${fieldEndingAtLength(80, "canaryOperationTag")}=${operationTag}`,
  `${fieldEndingAtLength(128, "canaryQuotaTag")}=${quotaTag}`,
  `${"x".repeat(4096)}authToken=abc`,
  `${"._-".repeat(2048)}1credential=abc`,
]);

const exactWrappedAssignmentControls = Object.freeze([
  "(inputTokens=120)",
  "[outputTokens=30]",
  "{totalTokens=150}",
  `CYCLEBALANCE_CANARY_OPERATION tag=${operationTag}`,
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
  `message=bar auth token canaryCorrelationId=${correlationId}`,
  `message=bar meal name canaryOperationTag=${operationTag}`,
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
  `outer=meal name canaryOperationTag=${operationTag}`,
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
  `[canaryOperationTag]=${operationTag}`,
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

function scannerEvent(overrides = {}) {
  return {
    event: "meal_scan_scanner_event",
    severity: "INFO",
    schemaVersion: "cyclebalance.meal_scan.operation.v1",
    eventType: "request_result",
    outcome: "completed",
    canaryCorrelationId: correlationId,
    canaryOperationTag: operationTag,
    canaryQuotaTag: quotaTag,
    ...overrides,
  };
}

function scannerEventBeforePrincipal(overrides = {}) {
  const event = scannerEvent(overrides);
  delete event.canaryQuotaTag;
  return event;
}

function canonicalFreshEvents() {
  return [
    scannerEventBeforePrincipal({
      eventType: "authorization_acceptance", outcome: "accepted", control: "app_check",
    }),
    scannerEventBeforePrincipal({
      eventType: "request_gate_decision", outcome: "allowed", control: "pre_verification",
    }),
    scannerEventBeforePrincipal({
      eventType: "budget_state", outcome: "observed", budgetMode: "normal", stateAgeSeconds: 12.345,
    }),
    scannerEventBeforePrincipal({
      eventType: "authorization_acceptance", outcome: "accepted", control: "storekit_jws",
    }),
    scannerEvent({
      eventType: "request_gate_decision", outcome: "allowed", control: "principal_attempt",
    }),
    scannerEvent({
      eventType: "authorization_acceptance", outcome: "accepted", control: "apple_current_status",
    }),
    scannerEvent({
      eventType: "authorization_acceptance", outcome: "accepted", control: "revenuecat_subscription",
    }),
    scannerEvent({ eventType: "global_dispatch_decision", outcome: "allowed" }),
    scannerEvent({
      eventType: "quota_decision", outcome: "allowed", tier: "trial",
      quotaUsed: 2, quotaLimit: 5, quotaRemaining: 3, quotaDelta: 1,
    }),
    scannerEvent({
      eventType: "cache_decision", outcome: "observed",
      cacheDisposition: "fresh_dispatch", localCacheDisposition: "not_observed",
    }),
    scannerEvent({
      eventType: "provider_call", outcome: "started",
      providerId: "google-gemini", modelId: "gemini-3.1-flash-lite",
    }),
    scannerEvent({
      eventType: "provider_call", outcome: "completed",
      providerId: "google-gemini", modelId: "gemini-3.1-flash-lite",
      latencyMs: 321, inputTokens: 100, outputTokens: 50, totalTokens: 150,
      estimatedCostUSD: 0.0001,
    }),
    scannerEvent({
      eventType: "request_result", outcome: "completed", statusCode: 200,
      statusClass: "2xx", latencyMs: 654, cacheDisposition: "fresh_dispatch",
      localCacheDisposition: "not_observed",
    }),
  ];
}

function realisticLogEntry(payload = scannerEvent({ statusCode: 200, statusClass: "2xx" })) {
  return {
    insertId: "67f04de10001a2b3c4d5e6f7",
    jsonPayload: payload,
    resource: {
      type: "cloud_run_revision",
      labels: {
        project_id: "cyclebalance-prod-20260710",
        service_name: "cyclebalance-meal-scan-proxy",
        revision_name: "cyclebalance-meal-scan-proxy-00023-abc",
        configuration_name: "cyclebalance-meal-scan-proxy",
        location: "us-central1",
      },
    },
    timestamp: "2026-07-15T03:04:05.123456Z",
    severity: "INFO",
    labels: { instanceId: "c".repeat(64) },
    logName: "projects/cyclebalance-prod-20260710/logs/run.googleapis.com%2Fstdout",
    trace: `projects/cyclebalance-prod-20260710/traces/${"d".repeat(32)}`,
    receiveTimestamp: "2026-07-15T03:04:05.234567Z",
  };
}

test("strict projection retains only allowlisted content-free correlated fields", () => {
  const entries = [{
    timestamp: "2026-07-15T01:00:00Z",
    textPayload: JSON.stringify(scannerEvent({ statusCode: 200, statusClass: "2xx" })),
  }];

  const projected = projectCorrelatedScannerEvents(entries, { correlationId, operationTag });

  assert.deepEqual(projected, [scannerEvent({ statusCode: 200, statusClass: "2xx" })]);
  assert.equal(JSON.stringify(projected).includes(canaryId), false);
  assert.equal(JSON.stringify(projected).includes(quotaPrincipal), false);
});

test("Cloud Run lifted severity is normalized only from an exact INFO LogEntry field", () => {
  const payload = scannerEvent({ statusCode: 200, statusClass: "2xx" });
  delete payload.severity;
  const entry = realisticLogEntry(payload);
  const expected = { ...payload, severity: "INFO" };

  assert.deepEqual(
    projectCorrelatedScannerEvents([entry], { correlationId, operationTag }),
    [expected]
  );
  const cli = spawnSync(process.execPath, [
    helperPath, "project-events", "--correlation", correlationId, "--operation", operationTag,
  ], { input: JSON.stringify([entry]), encoding: "utf8" });
  assert.equal(cli.status, 0, cli.stderr);
  assert.deepEqual(JSON.parse(cli.stdout), [expected]);

  for (const unsafeEntry of [
    { ...entry, severity: "WARNING" },
    Object.fromEntries(Object.entries(entry).filter(([field]) => field !== "severity")),
    { ...entry, severity: "ERROR", jsonPayload: { ...payload, severity: "INFO" } },
    { ...entry, jsonPayload: { ...payload, severity: "WARNING" } },
  ]) {
    assert.throws(
      () => projectCorrelatedScannerEvents([unsafeEntry], { correlationId, operationTag }),
      /severity|unsafe|invalid|scanner/i
    );
    const rejected = spawnSync(process.execPath, [
      helperPath, "project-events", "--correlation", correlationId, "--operation", operationTag,
    ], { input: JSON.stringify([unsafeEntry]), encoding: "utf8" });
    assert.notEqual(rejected.status, 0);
    assert.equal(rejected.stdout, "");
  }
});

test("strict projection permits only the exact server-shaped StoreKit authorization control", () => {
  const event = scannerEvent({
    eventType: "authorization_acceptance",
    outcome: "accepted",
    control: "storekit_jws",
  });
  assert.deepEqual(
    projectCorrelatedScannerEvents([{ jsonPayload: event }], { correlationId, operationTag }),
    [event]
  );
  assert.throws(
    () => projectCorrelatedScannerEvents([{
      jsonPayload: scannerEvent({ diagnosticValue: "storekit_jws" }),
    }], { correlationId, operationTag }),
    /unsafe|sensitive|unexpected/i
  );
});

test("valid textPayload JSON with duplicate keys cannot hide raw sensitive content", () => {
  const safeEvent = scannerEvent({ reason: "other" });
  const shallowDuplicate = JSON.stringify(safeEvent).replace(
    '"reason":"other"',
    '"reason":"aaaaaaaa.bbbbbbbb.cccccccc","reason":"other"'
  );
  const nestedDuplicate = JSON.stringify({
    event: "other_event",
    nested: { value: "safe" },
  }).replace(
    '"value":"safe"',
    '"value":"aaaaaaaa.bbbbbbbb.cccccccc","value":"safe"'
  );

  for (const textPayload of [shallowDuplicate, nestedDuplicate]) {
    const entries = [{ textPayload }];
    assert.throws(
      () => projectCorrelatedScannerEvents(entries, { correlationId, operationTag }),
      /duplicate|unsafe|sensitive/i
    );
    const result = spawnSync(
      process.execPath,
      [helperPath, "project-events", "--correlation", correlationId, "--operation", operationTag],
      { input: JSON.stringify(entries), encoding: "utf8" }
    );
    assert.notEqual(result.status, 0, textPayload);
    assert.equal(result.stdout, "", textPayload);
  }
});

test("iterative JSON escapes cannot hide secrets in console or structured string layers", () => {
  const unicodeEscape = (value) => [...value]
    .map((character) => `\\u${character.charCodeAt(0).toString(16).padStart(4, "0")}`)
    .join("");
  const escapedFragment = `{"${unicodeEscape("token")}":"${unicodeEscape("sk_FAKE_SECRET_VALUE")}"}`;
  const doubleEscapedFragment = escapedFragment.replaceAll("\\", "\\\\");
  const unsafeContent = [
    `2026-07-15T03:04:05Z process[42] ${escapedFragment}`,
    `prefix\n${escapedFragment}\nsuffix`,
    `${escapedFragment}\n${escapedFragment}`,
    doubleEscapedFragment,
    JSON.stringify({ diagnosticValue: escapedFragment }),
    JSON.stringify({ values: [doubleEscapedFragment] }),
  ];
  for (const value of unsafeContent) {
    assert.throws(
      () => assertSafeEvidenceContent(value),
      /unsafe|sensitive|secret|token|entropy|escape/i,
      value
    );
    const direct = spawnSync(process.execPath, [helperPath, "assert-safe-content"], {
      input: value, encoding: "utf8",
    });
    assert.notEqual(direct.status, 0, value);
    assert.equal(direct.stdout, "", value);
  }

  const nestedTextPayload = [{
    textPayload: JSON.stringify({ event: "other_event", diagnosticValue: doubleEscapedFragment }),
  }];
  assert.throws(
    () => projectCorrelatedScannerEvents(nestedTextPayload, { correlationId, operationTag }),
    /unsafe|sensitive|secret|token|entropy|escape/i
  );
  const projected = spawnSync(process.execPath, [
    helperPath, "project-events", "--correlation", correlationId, "--operation", operationTag,
  ], { input: JSON.stringify(nestedTextPayload), encoding: "utf8" });
  assert.notEqual(projected.status, 0);
  assert.equal(projected.stdout, "");

  const surrogateSafe = String.raw`message=\uD83D\uDE00 status=completed`;
  assert.doesNotThrow(() => assertSafeEvidenceContent(surrogateSafe));
});

test("JSON escape projection rejects low-entropy, nested, confusable, and identifier bypasses", () => {
  const unicodeEscape = (value) => Array.from(
    { length: value.length },
    (_, index) => `\\u${value.charCodeAt(index).toString(16).padStart(4, "0")}`
  ).join("");
  const upperHexEscape = (value) => unicodeEscape(value).replace(/[a-f]/g, (character) => character.toUpperCase());
  const addEscapeLayer = (value) => value.replaceAll("\\", String.raw`\u005c`);
  const lowEntropySecret = `${unicodeEscape("sk_")}${"A".repeat(20)}`;
  const fragment = `{"${unicodeEscape("token")}":"${lowEntropySecret}"}`;
  const mixedSlashFragment = (keySlashCount, valueSlashCount) => {
    let escapeIndex = 0;
    return fragment.replaceAll("\\", () => {
      const slashCount = escapeIndex < 5 ? keySlashCount : valueSlashCount;
      escapeIndex += 1;
      return "\\".repeat(slashCount);
    });
  };
  const alternateSlashEncodings = (value) => {
    let escapeIndex = 0;
    return value.replaceAll("\\", () => {
      const replacement = escapeIndex % 2 === 0
        ? "\\".repeat(6)
        : String.raw`\\u005c`.repeat(3);
      escapeIndex += 1;
      return replacement;
    });
  };
  const fullEncode = (value) => unicodeEscape(value);
  const repeatRawSlashes = (value, count) => value.replaceAll("\\", "\\".repeat(count));
  const repeatEncodedSlashes = (value, count) => value.replaceAll(
    "\\", String.raw`\\u005c`.repeat(count)
  );
  const encodedSecretPrefix = unicodeEscape("sk_");
  const encodedSensitiveLine = `${unicodeEscape("token:sk_")}${"A".repeat(20)}`;
  const normalizationHiddenSecrets = [
    encodedSecretPrefix.replaceAll("\\", "\\\u200b"),
    encodedSecretPrefix.replaceAll("\\", "\\\u2060"),
    encodedSecretPrefix.replaceAll("\\", "\\\u001b"),
    encodedSecretPrefix.replaceAll("u", "ｕ"),
    encodedSecretPrefix.replaceAll("\\", "＼"),
    encodedSecretPrefix.replace(/[0-9]/g, (digit) => String.fromCharCode(0xff10 + Number(digit))),
    encodedSecretPrefix.replaceAll("u", "υ"),
    encodedSecretPrefix.replaceAll("u", "u\u0301"),
    encodedSecretPrefix.replaceAll("u", "u\u001b"),
  ].map((hiddenPrefix) => `diagnosticValue=${hiddenPrefix}${"A".repeat(20)}`);
  const composedEscapeBypasses = [
    alternateSlashEncodings(repeatRawSlashes(fullEncode(fragment), 3)),
    alternateSlashEncodings(repeatEncodedSlashes(fullEncode(fragment), 3)),
    alternateSlashEncodings(alternateSlashEncodings(fullEncode(fragment))),
    alternateSlashEncodings(fullEncode(fullEncode(fragment))),
  ];
  const ansiPrefix = (value) => value.replaceAll("\\u", `\\\u001b[31mu`);
  const ansiDigits = (value) => value.replace(/[0-9]/g, (digit) => `${digit}\u001b[0m`);
  const nestedAnsiBypasses = [
    ansiDigits(ansiDigits(repeatEncodedSlashes(fragment, 3))),
    ansiDigits(ansiDigits(alternateSlashEncodings(fragment))),
    ansiDigits(ansiPrefix(fullEncode(fragment))),
    ansiDigits(ansiDigits(fullEncode(fragment))),
    ansiDigits(ansiDigits(ansiPrefix(fragment))),
    ansiDigits(ansiDigits(ansiDigits(fragment))),
  ];
  const oscPieceBypass = fragment.replaceAll("\\u", `\\\u001b]x;u\u0007`);
  const escapedConfusableEntropy = unicodeEscape([
    "ɯᴡⲽѡшԝա𑜊𑜎𑜏ꮃ𑣦",
    "᙮×⤫⤬⨯хᕁᕽ᙭╳𐌢𑣬",
    "ɣᶌʏỿꭚγⲩуүყ𑣜Υ",
    "ᴢꮓ𑣄𑣥𐋵ΖᏃꓜ𑢩ʐƶƵ",
  ].join(""));
  const normalizationCompositionBypasses = [
    encodedSensitiveLine.replaceAll("u", "ᴜ"),
    encodedSensitiveLine.replaceAll("\\u", "\\\u200bu"),
    encodedSensitiveLine.replaceAll("\\u", "\\\u2060u"),
    encodedSensitiveLine.replace(/[0-9]/g, (digit) => `${digit}\u200b`),
    encodedSensitiveLine.replace(/[0-9]/g, (digit) => `${digit}\u0301`),
    encodedSensitiveLine.replaceAll("\\u", `\\\u0000u`),
    encodedSensitiveLine.replaceAll("\\u", `\\\u0007u`),
    encodedSensitiveLine.replaceAll("\\u", `\\\u001b[31mu`),
    encodedSensitiveLine.replace(/[0-9]/g, (digit) => `${digit}\u001b[0m`),
  ];
  let nestedFragment = fragment;
  for (let depth = 0; depth < 6; depth += 1) {
    nestedFragment = JSON.stringify({ diagnosticValue: nestedFragment });
  }

  const unsafeContent = [
    `prefix ${fragment}`,
    `prefix ${upperHexEscape("token")}:${upperHexEscape("sk_")}${"A".repeat(20)}`,
    `${unicodeEscape("token:")}${lowEntropySecret}`,
    addEscapeLayer(fragment),
    addEscapeLayer(addEscapeLayer(fragment)),
    `value=${unicodeEscape("123456789012345")}`,
    `value=${unicodeEscape("00000000-0000-4000-8000-000000000000")}`,
    unicodeEscape("-----BEGIN PRIVATE KEY-----"),
    `${unicodeEscape("to")}\\u200b${unicodeEscape("ken")}:${lowEntropySecret}`,
    `${unicodeEscape("tоken")}:${lowEntropySecret}`,
    `${unicodeEscape("𝚝𝚘𝚔𝚎𝚗")}:${lowEntropySecret}`,
    JSON.stringify({ diagnosticValue: fragment }),
    nestedFragment,
    `${unicodeEscape("to")}\\b${unicodeEscape("ken")}:${lowEntropySecret}`,
    `${unicodeEscape("to")}\\f${unicodeEscape("ken")}:${lowEntropySecret}`,
    `${unicodeEscape("to")}\\n${unicodeEscape("ken")}:${lowEntropySecret}`,
    `${unicodeEscape("to")}\\r${unicodeEscape("ken")}:${lowEntropySecret}`,
    `${unicodeEscape("to")}\\t${unicodeEscape("ken")}:${lowEntropySecret}`,
    `\\"${unicodeEscape("token")}\\"=${lowEntropySecret}`,
    `${unicodeEscape("token")}\\/${lowEntropySecret}`,
    unicodeEscape(`CYCLEBALANCE_CANARY_OPERATION tag=${operationTag}`),
    String.raw`message=\uD800 status=completed`,
    String.raw`message=\uDC00 status=completed`,
    String.raw`message=\uDC00\uD800 status=completed`,
    String.raw`message=\uD800\u0041 status=completed`,
    `message=${String.fromCharCode(0xd800)} status=completed`,
    ...Array.from(
      { length: 40 },
      (_, index) => fragment.replaceAll("\\", "\\".repeat(index + 1))
    ),
    ...Array.from(
      { length: 20 },
      (_, index) => fragment.replaceAll("\\", String.raw`\\u005c`.repeat(index + 1))
    ),
    mixedSlashFragment(2, 3),
    ...normalizationHiddenSecrets,
    ...composedEscapeBypasses,
    ...nestedAnsiBypasses,
    oscPieceBypass,
    ...normalizationCompositionBypasses,
    escapedConfusableEntropy,
  ];

  for (const [index, value] of unsafeContent.entries()) {
    assert.throws(
      () => assertSafeEvidenceContent(value),
      /unsafe|sensitive|secret|token|entropy|escape|surrogate/i,
      `unsafe escape fixture ${index}`
    );
  }
  for (let keySlashCount = 1; keySlashCount <= 20; keySlashCount += 1) {
    for (let valueSlashCount = 1; valueSlashCount <= 20; valueSlashCount += 1) {
      const value = mixedSlashFragment(keySlashCount, valueSlashCount);
      assert.throws(
        () => assertSafeEvidenceContent(value),
        /unsafe|sensitive|secret|token|entropy|escape|surrogate/i,
        `mixed slash grid ${keySlashCount}/${valueSlashCount}`
      );
    }
  }
  const mixedLayerCLI = spawnSync(process.execPath, [helperPath, "assert-safe-content"], {
    input: mixedSlashFragment(2, 3), encoding: "utf8",
  });
  assert.notEqual(mixedLayerCLI.status, 0);
  assert.equal(mixedLayerCLI.stdout, "");
  const composedCLI = spawnSync(process.execPath, [helperPath, "assert-safe-content"], {
    input: composedEscapeBypasses[0], encoding: "utf8",
  });
  assert.notEqual(composedCLI.status, 0);
  assert.equal(composedCLI.stdout, "");

  const benignContent = [
    String.raw`{"event":"status","message":"completed"}`,
    String.raw`message=\u65e5\u672c\u8a9e status=completed`,
    String.raw`message=\uD83D\uDE00 status=completed`,
    `CYCLEBALANCE_CANARY_OPERATION tag=${operationTag}\nmessage=😀 status=completed`,
  ];
  for (const value of benignContent) {
    assert.doesNotThrow(() => assertSafeEvidenceContent(value), value);
  }
});

test("duplicate-key rejection never echoes the raw key into CLI diagnostics", () => {
  const secretKey = "SENSITIVE_DUPLICATE_KEY_abcdefghijklmnopqrstuvwxyz0123456789";
  const content = JSON.stringify({ [secretKey]: "first" }).replace(
    '"first"',
    `"first","${secretKey}":"second"`
  );
  const result = spawnSync(process.execPath, [helperPath, "assert-safe-content"], {
    input: content,
    encoding: "utf8",
  });
  assert.notEqual(result.status, 0);
  assert.equal(result.stdout, "");
  assert.equal(result.stderr.includes(secretKey), false);
});

test("malformed JSON diagnostics never echo source snippets for any JSON command", () => {
  const marker = "sk_FAKEABCDEFGHIJKLMNOPQRSTUVWX";
  const malformed = `[{"jsonPayload": ${marker}}]`;
  for (const args of [
    ["project-events", "--correlation", correlationId, "--operation", operationTag],
    ["quota-snapshot", "--canary-id", canaryId, "--quota-tag", quotaTag],
    ["verify-phase"],
  ]) {
    const result = spawnSync(process.execPath, [helperPath, ...args], {
      input: malformed,
      encoding: "utf8",
    });
    assert.notEqual(result.status, 0, args[0]);
    assert.equal(result.stdout, "", args[0]);
    assert.equal(result.stderr.includes(marker), false, args[0]);
    assert.equal(result.stderr.includes("jsonPayload"), false, args[0]);
  }
});

test("evidence helper CLI executes projection and emits nothing on fail-closed input", () => {
  const entry = { jsonPayload: scannerEvent({ statusCode: 200 }) };
  const valid = spawnSync(
    process.execPath,
    [helperPath, "project-events", "--correlation", correlationId, "--operation", operationTag],
    { input: JSON.stringify([entry]), encoding: "utf8" }
  );
  assert.equal(valid.status, 0, valid.stderr);
  assert.deepEqual(JSON.parse(valid.stdout), [entry.jsonPayload]);

  const invalid = spawnSync(
    process.execPath,
    [helperPath, "project-events", "--correlation", correlationId, "--operation", operationTag],
    { input: JSON.stringify([{ jsonPayload: scannerEvent({ unexpected: "secret" }) }]), encoding: "utf8" }
  );
  assert.notEqual(invalid.status, 0);
  assert.equal(invalid.stdout, "", "fail-closed CLI must not persist a partial projection");
});

test("real Cloud Logging envelope and direct CLI paths accept only safe emitted metadata", () => {
  const entry = realisticLogEntry();
  assert.deepEqual(
    projectCorrelatedScannerEvents([entry], { correlationId, operationTag }),
    [entry.jsonPayload]
  );

  const projection = spawnSync(
    process.execPath,
    [helperPath, "project-events", "--correlation", correlationId, "--operation", operationTag],
    { input: JSON.stringify([entry]), encoding: "utf8" }
  );
  assert.equal(projection.status, 0, projection.stderr);
  assert.deepEqual(JSON.parse(projection.stdout), [entry.jsonPayload]);

  const contentCheck = spawnSync(
    process.execPath,
    [helperPath, "assert-safe-content"],
    { input: JSON.stringify([entry]), encoding: "utf8" }
  );
  assert.equal(contentCheck.status, 0, contentCheck.stderr);
  assert.equal(contentCheck.stdout, "");
});

test("flattened or array-nested metadata aliases never receive envelope exemptions", () => {
  const aliases = [
    "resource.type",
    "resource.labels.project_id",
    "resource.labels.service_name",
    "resource.labels.configuration_name",
    "resource.labels.revision_name",
    "resource.labels.location",
    "labels.instanceId",
  ];
  for (const alias of aliases) {
    const entry = {
      [alias]: genericHexValue,
      jsonPayload: { event: "other_event", outcome: "safe_control_message" },
    };
    assert.throws(
      () => projectCorrelatedScannerEvents([entry], { correlationId, operationTag }),
      /unsafe|alias|identifier|hex/i,
      alias
    );
    const result = spawnSync(
      process.execPath,
      [helperPath, "project-events", "--correlation", correlationId, "--operation", operationTag],
      { input: JSON.stringify([entry]), encoding: "utf8" }
    );
    assert.notEqual(result.status, 0, alias);
    assert.equal(result.stdout, "", alias);
  }

  const arrayAlias = {
    labels: [{ instanceId: genericHexValue }],
    jsonPayload: { event: "other_event", outcome: "safe_control_message" },
  };
  assert.throws(
    () => projectCorrelatedScannerEvents([arrayAlias], { correlationId, operationTag }),
    /unsafe|identifier|hex/i
  );
  const result = spawnSync(
    process.execPath,
    [helperPath, "project-events", "--correlation", correlationId, "--operation", operationTag],
    { input: JSON.stringify([arrayAlias]), encoding: "utf8" }
  );
  assert.notEqual(result.status, 0);
  assert.equal(result.stdout, "");
});

test("Cloud Logging insertId cannot carry secret prefixes identifiers or high-entropy content", () => {
  const unsafeInsertIds = [
    "sk_FAKEABCDEFGHIJKLMNOPQRSTUVWX",
    "AIzaFAKEABCDEFGHIJKLMNOPQRSTUVWX",
    "123456789012345",
    genericUuidValue,
    highEntropyGenericValue,
  ];
  for (const insertId of unsafeInsertIds) {
    const entry = realisticLogEntry();
    entry.insertId = insertId;
    assert.throws(
      () => projectCorrelatedScannerEvents([entry], { correlationId, operationTag }),
      /unsafe|invalid|identifier|insert|entropy/i,
      insertId
    );
    const result = spawnSync(
      process.execPath,
      [helperPath, "project-events", "--correlation", correlationId, "--operation", operationTag],
      { input: JSON.stringify([entry]), encoding: "utf8" }
    );
    assert.notEqual(result.status, 0, insertId);
    assert.equal(result.stdout, "", insertId);
    assert.equal(result.stderr.includes(insertId), false, insertId);
  }
});

test("unexpected scanner fields cannot echo meal labels or terminal controls", () => {
  for (const field of ["chickenRiceBowl", "myBreakfast", "\u001b[31mglucoseSnack\u001b[0m"]) {
    const event = scannerEvent({ [field]: "safe" });
    const result = spawnSync(
      process.execPath,
      [helperPath, "project-events", "--correlation", correlationId, "--operation", operationTag],
      { input: JSON.stringify([{ jsonPayload: event }]), encoding: "utf8" }
    );
    assert.notEqual(result.status, 0, field);
    assert.equal(result.stdout, "", field);
    assert.equal(result.stderr.includes(field), false, field);
    assert.equal(result.stderr.includes("\u001b"), false, field);
  }
});

test("path-validated LogEntry insertId still rejects a UUID-shaped identifier", () => {
  const entry = realisticLogEntry();
  entry.insertId = genericUuidValue;
  assert.throws(
    () => projectCorrelatedScannerEvents([entry], { correlationId, operationTag }),
    /unsafe|identifier|insert/i
  );
  const result = spawnSync(
    process.execPath,
    [helperPath, "assert-safe-content"],
    { input: JSON.stringify([entry]), encoding: "utf8" }
  );
  assert.notEqual(result.status, 0);
  assert.equal(result.stdout, "");
});

test("strict projection rejects unexpected fields and sensitive encodings before output", () => {
  const unsafe = [
    scannerEvent({ unexpected: "value" }),
    scannerEvent({ appCheckToken: "token" }),
    scannerEvent({ app_check_token: "token" }),
    scannerEvent({ signedTransactionJWS: "header.payload.signature" }),
    scannerEvent({ signed_transaction_jws: "header.payload.signature" }),
    scannerEvent({ storeKitJWS: "header.payload.signature" }),
    scannerEvent({ store_kit_jws: "header.payload.signature" }),
    scannerEvent({ reason: "Authorization: Bearer secret" }),
    scannerEvent({ reason: "-----BEGIN PRIVATE KEY-----" }),
    scannerEvent({ reason: "ya29.oauth-secret" }),
    scannerEvent({ reason: "sk_revenuecat_secret_1234567890" }),
    scannerEvent({ reason: "headerpayload.signaturepayload.signaturesuffix" }),
    scannerEvent({ reason: `/9j/${"A".repeat(120)}` }),
    scannerEvent({ reason: `iVBORw0KGgo${"A".repeat(120)}` }),
    scannerEvent({ reason: "A".repeat(160) }),
    scannerEvent({ reason: "abcdefghijklmnopqrstuvwxyz0123456789abcdefghijkl" }),
  ];

  for (const event of unsafe) {
    assert.throws(
      () => projectCorrelatedScannerEvents([{ jsonPayload: event }], { correlationId, operationTag }),
      /unsafe|unexpected|invalid/i
    );
  }
});

test("correlated non-scanner payloads are scanned for sensitive content before being ignored", () => {
  const unsafePayloads = [
    { event: "other_event", canaryCorrelationId: correlationId, appCheckToken: "must-not-pass" },
    { event: "other_event", canaryCorrelationId: correlationId, signedTransactionJWS: "header.payload.signature" },
    { event: "other_event", canaryCorrelationId: correlationId, image: `/9j/${"A".repeat(120)}` },
    { event: "other_event", canaryCorrelationId: correlationId, token: "plain-secret-value" },
    { event: "other_event", canaryCorrelationId: correlationId, secret: "plain-secret-value" },
    { event: "other_event", canaryCorrelationId: correlationId, photo: "breakfast-photo" },
    { event: "other_event", canaryCorrelationId: correlationId, foodName: "private breakfast" },
  ];
  for (const payload of unsafePayloads) {
    assert.throws(
      () => projectCorrelatedScannerEvents([{ jsonPayload: payload }], { correlationId, operationTag }),
      /unsafe|sensitive/i
    );
    assert.throws(
      () => projectCorrelatedScannerEvents([{ textPayload: JSON.stringify(payload) }], { correlationId, operationTag }),
      /unsafe|sensitive/i
    );
  }
  assert.throws(
    () => projectCorrelatedScannerEvents([{
      textPayload: `${correlationId} appCheckToken=must-not-pass`,
    }], { correlationId, operationTag }),
    /unsafe|sensitive/i
  );

  assert.deepEqual(
    projectCorrelatedScannerEvents([{
      jsonPayload: { event: "other_event", outcome: "safe_control_message" },
    }], { correlationId, operationTag }),
    []
  );
});

test("strict projection scans the complete Cloud Logging entry before selecting its payload", () => {
  const safePayload = {
    event: "other_event",
    canaryCorrelationId: correlationId,
    outcome: "safe_control_message",
  };
  for (const outsidePayload of [
    { labels: { token: "plain-secret-value" } },
    { httpRequest: { secret: "plain-secret-value" } },
    { resource: { labels: { photo: "private-breakfast" } } },
    { operation: { foodName: "private breakfast" } },
  ]) {
    assert.throws(
      () => projectCorrelatedScannerEvents([{
        jsonPayload: safePayload,
        ...outsidePayload,
      }], { correlationId, operationTag }),
      /unsafe|sensitive/i
    );
  }
});

for (const [field, value] of exactPrivacyFieldBypasses) {
  test(`privacy scan rejects ${field} in correlated payloads and complete log entries`, () => {
    const correlatedPayload = {
      event: "other_event",
      canaryCorrelationId: correlationId,
      [field]: value,
    };
    assert.throws(
      () => projectCorrelatedScannerEvents([{ jsonPayload: correlatedPayload }], { correlationId, operationTag }),
      /unsafe|sensitive/i
    );
    assert.throws(
      () => projectCorrelatedScannerEvents([{
        jsonPayload: {
          event: "other_event",
          canaryCorrelationId: correlationId,
          outcome: "safe_control_message",
        },
        labels: { [field]: value },
      }], { correlationId, operationTag }),
      /unsafe|sensitive/i
    );
  });
}

test("privacy scan rejects an arbitrary 44-character high-entropy value in payload and entry strings", () => {
  assert.equal(highEntropyGenericValue.length, 44);
  assert.throws(
    () => projectCorrelatedScannerEvents([{
      jsonPayload: {
        event: "other_event",
        canaryCorrelationId: correlationId,
        diagnosticValue: highEntropyGenericValue,
      },
    }], { correlationId, operationTag }),
    /unsafe|sensitive|entropy/i
  );
  assert.throws(
    () => projectCorrelatedScannerEvents([{
      jsonPayload: {
        event: "other_event",
        canaryCorrelationId: correlationId,
        outcome: "safe_control_message",
      },
      labels: { diagnosticValue: highEntropyGenericValue },
    }], { correlationId, operationTag }),
    /unsafe|sensitive|entropy/i
  );
});

test("privacy scan preserves the three allowlisted numeric token-count fields", () => {
  const tokenCounts = { inputTokens: 120, outputTokens: 30, totalTokens: 150 };
  assert.deepEqual(
    projectCorrelatedScannerEvents([{
      jsonPayload: scannerEvent(tokenCounts),
    }], { correlationId, operationTag }),
    [scannerEvent(tokenCounts)]
  );
  assert.deepEqual(
    projectCorrelatedScannerEvents([{
      jsonPayload: {
        event: "other_event",
        ...tokenCounts,
      },
    }], { correlationId, operationTag }),
    []
  );
});

for (const [label, nestedValue] of nestedPrivacyBypasses) {
  test(`privacy scan carries ancestor context through ${label}`, () => {
    const payload = {
      event: "other_event",
      canaryCorrelationId: correlationId,
      ...nestedValue,
    };
    assert.throws(
      () => projectCorrelatedScannerEvents([{ jsonPayload: payload }], { correlationId, operationTag }),
      /unsafe|sensitive/i
    );
    assert.throws(
      () => projectCorrelatedScannerEvents([{
        jsonPayload: { event: "other_event", canaryCorrelationId: correlationId },
        operation: nestedValue,
      }], { correlationId, operationTag }),
      /unsafe|sensitive/i
    );
  });
}

test("generic 64-hex content is rejected while exact canonical hash fields remain valid", () => {
  assert.equal(genericHexValue.length, 64);
  assert.throws(
    () => projectCorrelatedScannerEvents([{
      jsonPayload: {
        event: "other_event",
        canaryCorrelationId: correlationId,
        diagnosticValue: genericHexValue,
      },
    }], { correlationId, operationTag }),
    /unsafe|sensitive|hex|entropy/i
  );
  assert.throws(
    () => projectCorrelatedScannerEvents([{
      jsonPayload: { event: "other_event", canaryCorrelationId: "not-a-canonical-hash" },
    }], { correlationId, operationTag }),
    /unsafe|invalid|hash|digest/i
  );
  assert.throws(
    () => projectCorrelatedScannerEvents([{
      jsonPayload: { event: "other_event", canaryCorrelationId: correlationId },
    }], { correlationId, operationTag }),
    /unsafe|invalid|hash|digest|canonical/i
  );
  assert.throws(
    () => projectCorrelatedScannerEvents([{
      jsonPayload: { event: "other_event", diagnostic: { canaryQuotaTag: genericHexValue } },
    }], { correlationId, operationTag }),
    /unsafe|invalid|hash|digest|canonical/i
  );
});

test("canonical hash names cannot mask generic hashes in ordinary text", () => {
  const bypasses = [
    `canaryCorrelationId=${genericHexValue}`,
    `diagnostic canaryOperationTag=${genericHexValue}`,
    JSON.stringify({ diagnosticValue: `canaryQuotaTag=${genericHexValue}` }),
    `event=other_event canaryCorrelationId=${genericHexValue}`,
  ];
  for (const value of bypasses) {
    assert.throws(
      () => assertSafeEvidenceContent(value),
      /unsafe|identifier|hash|entropy/i,
      value
    );
    const direct = spawnSync(process.execPath, [helperPath, "assert-safe-content"], {
      input: value, encoding: "utf8",
    });
    assert.notEqual(direct.status, 0, value);
    assert.equal(direct.stdout, "", value);

    const project = spawnSync(process.execPath, [
      helperPath, "project-events", "--correlation", correlationId, "--operation", operationTag,
    ], {
      input: JSON.stringify([{ jsonPayload: { event: "other_event", diagnosticValue: value } }]),
      encoding: "utf8",
    });
    assert.notEqual(project.status, 0, value);
    assert.equal(project.stdout, "", value);
  }

  const consoleMarker = `CYCLEBALANCE_CANARY_OPERATION tag=${genericHexValue}`;
  assert.doesNotThrow(() => assertSafeEvidenceContent(consoleMarker));
  assert.throws(
    () => assertSafeEvidenceContent(JSON.stringify({ diagnosticValue: consoleMarker })),
    /unsafe|identifier|hash|entropy/i
  );
  const structuredMarker = spawnSync(process.execPath, [
    helperPath, "project-events", "--correlation", correlationId, "--operation", operationTag,
  ], {
    input: JSON.stringify([{ jsonPayload: { event: "other_event", diagnosticValue: consoleMarker } }]),
    encoding: "utf8",
  });
  assert.notEqual(structuredMarker.status, 0);
  assert.equal(structuredMarker.stdout, "");
});

test("IAM policy digests are allowed only in the exact final-posture evidence shape", () => {
  for (const value of [
    { iamPolicyDigest: genericHexValue },
    { event: "other_event", iamPolicyDigest: genericHexValue },
  ]) {
    assert.throws(
      () => assertSafeEvidenceContent(JSON.stringify(value)),
      /unsafe|identifier|digest|posture/i
    );
    assert.throws(
      () => projectCorrelatedScannerEvents([value], { correlationId, operationTag }),
      /unsafe|identifier|digest|posture/i
    );
  }

  const finalPosture = {
    projectId: "cyclebalance-prod-20260710",
    serviceName: "cyclebalance-meal-scan-proxy",
    revision: "cyclebalance-meal-scan-proxy-00001-abc",
    iamPolicyDigest: genericHexValue,
    mealScanEnabled: false,
    transport: "private",
    authenticatedProbe: "503_feature_disabled",
  };
  assert.doesNotThrow(() => assertSafeEvidenceContent(JSON.stringify(finalPosture)));
  assert.throws(
    () => assertSafeEvidenceContent(JSON.stringify({ ...finalPosture, transport: "public" })),
    /unsafe|identifier|digest|posture/i
  );
});

test("generic UUID identifiers are rejected in structured payloads and complete entries", () => {
  for (const entry of [
    {
      jsonPayload: {
        event: "other_event",
        canaryCorrelationId: correlationId,
        diagnosticValue: genericUuidValue,
      },
    },
    {
      jsonPayload: { event: "other_event", canaryCorrelationId: correlationId },
      labels: { diagnosticValue: genericUuidValue },
    },
  ]) {
    assert.throws(
      () => projectCorrelatedScannerEvents([entry], { correlationId, operationTag }),
      /unsafe|sensitive|uuid|identifier/i
    );
  }
});

test("assert-safe-content CLI rejects UUID identifiers without partial output", () => {
  for (const input of [
    [{ jsonPayload: { diagnosticValue: genericUuidValue } }],
    [{ textPayload: `diagnosticValue=${genericUuidValue}` }],
    [{ textPayload: JSON.stringify({ diagnosticValue: genericUuidValue }) }],
    [{ textPayload: `canaryId=${genericUuidValue}` }],
  ]) {
    const result = spawnSync(
      process.execPath,
      [helperPath, "assert-safe-content"],
      { input: JSON.stringify(input), encoding: "utf8" }
    );
    assert.notEqual(result.status, 0);
    assert.equal(result.stdout, "", "fail-closed UUID CLI must not emit partial evidence");
  }
});

test("identifier matcher rejects all dashed UUID shapes and contiguous hex runs", () => {
  for (const value of identifierBypasses) {
    for (const entry of [
      { jsonPayload: { event: "other_event", canaryCorrelationId: correlationId, diagnosticValue: value } },
      { jsonPayload: { event: "other_event", canaryCorrelationId: correlationId }, labels: { diagnosticValue: value } },
    ]) assert.throws(() => projectCorrelatedScannerEvents([entry], { correlationId, operationTag }), /unsafe|identifier|uuid|hex/i);
  }
});

test("identifier bypasses fail assert-safe-content CLI atomically", () => {
  for (const value of identifierBypasses) {
    const result = spawnSync(process.execPath, [helperPath, "assert-safe-content"], {
      input: JSON.stringify([{ textPayload: `diagnosticValue=${value}` }]), encoding: "utf8",
    });
    assert.notEqual(result.status, 0, value);
    assert.equal(result.stdout, "");
  }
});

test("punctuation-wrapped sensitive assignments fail direct content CLI", () => {
  for (const value of ["(authToken=abc)", "[session_token=abc]", ";credential=abc", "|foodName=breakfast", "(image=abc)", "[mealTitle=breakfast]", ";storeKitPayload=abc", "|token=abc", "prefix;(authToken=abc)", "\n(authToken=abc)", "outer=(authToken=abc)", "outer=authToken=abc", "outer=token=abc"]) {
    assert.throws(() => assertSafeEvidenceContent(value), /unsafe|sensitive/i, value);
    const result = spawnSync(process.execPath, [helperPath, "assert-safe-content"], { input: value, encoding: "utf8" });
    assert.notEqual(result.status, 0, value); assert.equal(result.stdout, "");
  }
  for (const value of [`(inputTokens=120)`, `CYCLEBALANCE_CANARY_OPERATION tag=${operationTag}`]) {
    assert.doesNotThrow(() => assertSafeEvidenceContent(value), value);
    assert.equal(spawnSync(process.execPath, [helperPath, "assert-safe-content"], { input: value, encoding: "utf8" }).status, 0, value);
  }
});

test("digit-prefixed sensitive assignments fail direct content and CLI atomically", () => {
  const unsafeAssignments = [
    "1authToken=abc",
    "outer=1authToken=abc",
    "1foodName=breakfast",
    "outer=(1credential=abc)",
    "1token=abc",
    "1inputTokens=120",
    "1outputTokens=30",
    "1totalTokens=150",
    `1canaryCorrelationId=${correlationId}`,
    `1canaryOperationTag=${operationTag}`,
    `1canaryQuotaTag=${quotaTag}`,
    "._-1authToken=abc",
    `${".".repeat(128)}1credential=abc`,
    `1${"x".repeat(54)}authToken=abc`,
  ];
  for (const value of unsafeAssignments) {
    assert.throws(() => assertSafeEvidenceContent(value), /unsafe|sensitive/i, value);
    const result = spawnSync(process.execPath, [helperPath, "assert-safe-content"], {
      input: value,
      encoding: "utf8",
    });
    assert.notEqual(result.status, 0, value);
    assert.equal(result.stdout, "", value);
  }
  for (const value of [
    "(inputTokens=120)",
    "[outputTokens=30]",
    "{totalTokens=150}",
    `CYCLEBALANCE_CANARY_OPERATION tag=${operationTag}`,
  ]) {
    assert.doesNotThrow(() => assertSafeEvidenceContent(value), value);
    const result = spawnSync(process.execPath, [helperPath, "assert-safe-content"], {
      input: value,
      encoding: "utf8",
    });
    assert.equal(result.status, 0, value);
    assert.equal(result.stdout, "", value);
  }
});

test("overlength sensitive assignments fail the direct content check", () => {
  for (const value of exactWrappedAssignmentControls) {
    assert.doesNotThrow(() => assertSafeEvidenceContent(value), value);
  }
  for (const value of overlengthAssignmentBypasses) {
    assert.throws(() => assertSafeEvidenceContent(value), /unsafe|sensitive/i, value);
  }
});

test("overlength sensitive assignments fail assert-safe-content CLI atomically", () => {
  for (const value of exactWrappedAssignmentControls) {
    const result = spawnSync(process.execPath, [helperPath, "assert-safe-content"], {
      input: value,
      encoding: "utf8",
    });
    assert.equal(result.status, 0, value);
    assert.equal(result.stdout, "", value);
  }
  for (const value of overlengthAssignmentBypasses) {
    const result = spawnSync(process.execPath, [helperPath, "assert-safe-content"], {
      input: value,
      encoding: "utf8",
    });
    assert.deepEqual({ failed: result.status !== 0, stdout: result.stdout }, {
      failed: true,
      stdout: "",
    }, value);
  }
});

test("wrapper unicode whitespace and compound sensitive assignments fail direct content", () => {
  for (const value of wrapperAndUnicodeAssignmentBypasses) {
    assert.throws(() => assertSafeEvidenceContent(value), /unsafe|sensitive|identifier|hash/i, value);
  }
});

test("wrapper unicode whitespace and compound assignments fail CLI atomically", () => {
  for (const value of wrapperAndUnicodeAssignmentBypasses) {
    const result = spawnSync(process.execPath, [helperPath, "assert-safe-content"], {
      input: value,
      encoding: "utf8",
    });
    assert.notEqual(result.status, 0, value);
    assert.equal(result.stdout, "", value);
  }
});

test("ANSI OSC payloads remain inside the privacy scan", () => {
  const unsafePayloads = [
    `\u001b]0; authorization=${"z".repeat(64)}\u0007`,
    `\u001b]0; mealName=${"z".repeat(64)}\u0007`,
    `\u001b]0; transactionId=${"z".repeat(64)}\u001b\\`,
    `\u001b]8;;https://example.invalid displayName=${"z".repeat(64)}\u001b\\`,
  ];
  for (const value of unsafePayloads) {
    assert.throws(() => assertSafeEvidenceContent(value), /unsafe|sensitive/i, value);
    const result = spawnSync(process.execPath, [helperPath, "assert-safe-content"], {
      input: value,
      encoding: "utf8",
    });
    assert.notEqual(result.status, 0, value);
    assert.equal(result.stdout, "", value);
  }
});

test("terminal display strings cannot hide a fragmented identifier", () => {
  const terminalStrings = [
    "\u001b]0;harmless-title\u0007",
    "\u001b]8;;https://example.invalid\u001b\\",
    "\u009d0;harmless-title\u009c",
    "\u001bPharmless-dcs\u001b\\",
    "\u0090harmless-dcs\u009c",
    "\u001bXharmless-sos\u001b\\",
    "\u0098harmless-sos\u009c",
    "\u001b^harmless-pm\u001b\\",
    "\u009eharmless-pm\u009c",
    "\u001b_harmless-apc\u001b\\",
    "\u009fharmless-apc\u009c",
  ];
  for (const sequence of terminalStrings) {
    for (const value of [
      `auth${sequence}Token=abc`,
      `12345${sequence}67890${sequence}12345`,
    ]) {
      assert.throws(() => assertSafeEvidenceContent(value), /unsafe|sensitive|identifier/i, value);
      const result = spawnSync(process.execPath, [helperPath, "assert-safe-content"], {
        input: value,
        encoding: "utf8",
      });
      assert.notEqual(result.status, 0, value);
      assert.equal(result.stdout, "", value);
    }
  }
});

test("localized value punctuation is not reinterpreted as an evidence assignment", () => {
  const values = [
    "message=ジャン゠ジャック status=completed",
    "message=ジャン゠ジャック、準備完了 status=completed",
  ];
  for (const value of values) {
    assert.doesNotThrow(() => assertSafeEvidenceContent(value), value);
    const result = spawnSync(process.execPath, [helperPath, "assert-safe-content"], {
      input: value,
      encoding: "utf8",
    });
    assert.equal(result.status, 0, `${value}: ${result.stderr}`);
    assert.equal(result.stdout, "", value);
  }
});

test("exact meal and food content fields are rejected while aggregate fields remain safe", () => {
  const sensitive = [
    "meal=breakfast",
    "meals=breakfast",
    "food=avocado",
    "foods=avocado",
    "mealDescription=private-breakfast",
    "foodDescription=private-avocado",
    JSON.stringify({ meal: "breakfast" }),
    JSON.stringify({ foods: ["avocado"] }),
    JSON.stringify({ mealDescription: "private breakfast" }),
  ];
  for (const value of sensitive) {
    assert.throws(() => assertSafeEvidenceContent(value), /unsafe|sensitive/i, value);
    const result = spawnSync(process.execPath, [helperPath, "assert-safe-content"], {
      input: value,
      encoding: "utf8",
    });
    assert.notEqual(result.status, 0, value);
    assert.equal(result.stdout, "", value);
  }
  for (const value of [
    "mealCount=2 foodCount=3 mealHash=redacted foodHash=redacted",
    JSON.stringify({ mealCount: 2, foodCount: 3, mealHash: "redacted", foodHash: "redacted" }),
  ]) {
    assert.doesNotThrow(() => assertSafeEvidenceContent(value), value);
  }
});

test("invisible format and ANSI controls cannot split prohibited identifiers", () => {
  const formatControls = ["\u200b", "\u200c", "\u200d", "\u2060", "\ufeff", "\u00ad"];
  const highEntropy = highEntropyGenericValue.slice(0, 22) + "\u001b[31m" +
    highEntropyGenericValue.slice(22) + "\u001b[0m";
  const unsafeValues = [
    ...formatControls.map((control) => "12345" + control + "67890" + control + "12345"),
    "12345\u001b[31m67890\u001b[0m12345",
    "12345\u001b67890\u001b12345",
    "12345\n67890\r12345",
    "12345\u202867890\u202812345",
    "12345\u202967890\u202912345",
    "12345\u007f67890\u008512345",
    "12345\u009b31m67890\u009b0m12345",
    "12345\u009d\u009c67890\u009d\u009c12345",
    "12345\u001b767890\u001b(B12345",
    "90b2ac63-\u001b[31me61f-49e1-a8b0-a5e85f154d4c\u001b[0m",
    highEntropy,
    "12345\u001b]\u000767890\u001b]\u000712345",
    "12345\u001b]\u001b\\67890\u001b]\u001b\\12345",
    "transaction\0Id=abc",
    "meal\0Name=abc",
    "food\0Title=abc",
    "storeKit\0Payload=abc",
    "display\0Name=abc",
  ];
  for (const value of unsafeValues) {
    assert.throws(() => assertSafeEvidenceContent(value), /unsafe|sensitive|identifier|entropy/i, value);
    const result = spawnSync(process.execPath, [helperPath, "assert-safe-content"], {
      input: value,
      encoding: "utf8",
    });
    assert.notEqual(result.status, 0, value);
    assert.equal(result.stdout, "", value);
  }
  for (const value of [
    "message=👩‍⚕️ 食事の準備 status=completed",
    "message=می‌خواهم غذا را ثبت کنم status=completed",
  ]) {
    assert.doesNotThrow(() => assertSafeEvidenceContent(value), value);
  }
});

test("plain Apple-style decimal transaction identifiers fail atomically", () => {
  for (const value of [
    "123456789012345",
    "transaction completed: 123456789012345",
    "original transaction 123456789012345",
  ]) {
    assert.throws(() => assertSafeEvidenceContent(value), /unsafe|identifier|transaction/i, value);
    const result = spawnSync(process.execPath, [helperPath, "assert-safe-content"], {
      input: value,
      encoding: "utf8",
    });
    assert.notEqual(result.status, 0, value);
    assert.equal(result.stdout, "", value);
  }
});

test("JSON numeric lexemes cannot hide a 15-digit identifier through decimals or exponents", () => {
  for (const numericLexeme of [
    "123456789012345e-10",
    "123456789012345E-30",
    "0.123456789012345",
    "-123456789012345.1",
  ]) {
    const value = `{"diagnosticValue":${numericLexeme}}`;
    assert.throws(() => assertSafeEvidenceContent(value), /unsafe|identifier|decimal/i, value);
    const direct = spawnSync(process.execPath, [helperPath, "assert-safe-content"], {
      input: value,
      encoding: "utf8",
    });
    assert.notEqual(direct.status, 0, value);
    assert.equal(direct.stdout, "", value);

    const project = spawnSync(process.execPath, [
      helperPath, "project-events", "--correlation", correlationId, "--operation", operationTag,
    ], { input: `[${value}]`, encoding: "utf8" });
    assert.notEqual(project.status, 0, value);
    assert.equal(project.stdout, "", value);
  }
});

test("decimal runs remain allowed only inside the exact console operation marker", () => {
  const hashWithDecimalRun = `${"a".repeat(20)}123456789012345${"b".repeat(29)}`;
  assert.equal(hashWithDecimalRun.length, 64);
  for (const value of [
    `canaryOperationTag=${hashWithDecimalRun}`,
    `canaryCorrelationId=${"1".repeat(64)}`,
  ]) {
    assert.throws(() => assertSafeEvidenceContent(value), /unsafe|identifier|hash|decimal/i, value);
    const result = spawnSync(process.execPath, [helperPath, "assert-safe-content"], {
      input: value,
      encoding: "utf8",
    });
    assert.notEqual(result.status, 0, value);
    assert.equal(result.stdout, "", value);
  }
  const marker = `CYCLEBALANCE_CANARY_OPERATION tag=${hashWithDecimalRun}`;
  assert.doesNotThrow(() => assertSafeEvidenceContent(marker));
  assert.equal(spawnSync(process.execPath, [helperPath, "assert-safe-content"], {
    input: marker, encoding: "utf8",
  }).status, 0);
});

test("Unicode decimal transaction identifier lookalikes fail atomically", () => {
  for (const value of [
    "diagnosticValue=１２３４５６７８９０１２３４５",
    "diagnosticValue=١٢٣٤٥٦٧٨٩٠١٢٣٤٥",
    "diagnosticValue=۱۲۳۴۵۶۷۸۹۰۱۲۳۴۵",
    "diagnosticValue=𝟙𝟚𝟛𝟜𝟝𝟞𝟟𝟠𝟡𝟘𝟙𝟚𝟛𝟜𝟝",
    "diagnosticValue=12345６７８９０12345",
    "diagnosticValue=¹²³⁴⁵⁶⁷⁸⁹⁰¹²³⁴⁵",
    "diagnosticValue=₁₂₃₄₅₆₇₈₉₀₁₂₃₄₅",
    "diagnosticValue=①②③④⑤⑥⑦⑧⑨⓪①②③④⑤",
    "diagnosticValue=¹٢３⁴۵６₇٨⑨０¹٢３⁴۵",
  ]) {
    assert.throws(() => assertSafeEvidenceContent(value), /unsafe|identifier|transaction/i, value);
    const result = spawnSync(process.execPath, [helperPath, "assert-safe-content"], {
      input: value,
      encoding: "utf8",
    });
    assert.notEqual(result.status, 0, value);
    assert.equal(result.stdout, "", value);
  }
});

test("NFKC-compatible UUID and hex identifier lookalikes fail atomically", () => {
  const toFullwidth = (value) => [...value].map((character) => {
    if (character === "-") return "－";
    if (/[0-9A-Za-z]/.test(character)) {
      return String.fromCodePoint(character.codePointAt(0) + 0xfee0);
    }
    return character;
  }).join("");
  const uuid = "90b2ac63-e61f-49e1-a8b0-a5e85f154d4c";
  const hex = "0123456789abcdef".repeat(4);
  const mixedUuid = `${uuid.slice(0, 8)}${toFullwidth(uuid.slice(8, 20))}${uuid.slice(20)}`;
  for (const value of [
    `diagnosticValue=${toFullwidth(uuid)}`,
    `diagnosticValue=${toFullwidth(hex)}`,
    `diagnosticValue=${mixedUuid}`,
  ]) {
    assert.throws(() => assertSafeEvidenceContent(value), /unsafe|identifier|hex/i, value);
    const result = spawnSync(process.execPath, [helperPath, "assert-safe-content"], {
      input: value,
      encoding: "utf8",
    });
    assert.notEqual(result.status, 0, value);
    assert.equal(result.stdout, "", value);
  }
});

test("NFKC-compatible high-entropy text fails without invalidating canonical hash ranges", () => {
  const toFullwidth = (value) => [...value].map((character) => (
    /[0-9A-Za-z]/.test(character)
      ? String.fromCodePoint(character.codePointAt(0) + 0xfee0)
      : character
  )).join("");
  const unsafe = `diagnosticValue=${toFullwidth(highEntropyGenericValue)}`;
  assert.throws(() => assertSafeEvidenceContent(unsafe), /unsafe|entropy/i);
  const result = spawnSync(process.execPath, [helperPath, "assert-safe-content"], {
    input: unsafe,
    encoding: "utf8",
  });
  assert.notEqual(result.status, 0);
  assert.equal(result.stdout, "");

  assert.doesNotThrow(() => assertSafeEvidenceContent(
    `note=Ａ\nCYCLEBALANCE_CANARY_OPERATION tag=${operationTag}`
  ));
});

test("UTS-skeleton UUID hex and high-entropy lookalikes fail without rejecting localized text", () => {
  const unsafeValues = [
    "diagnosticValue=90Ь2ас63-е61Ϝ-49е1-а8Ь0-а5е85Ϝ154ԁ4с",
    `diagnosticValue=${"аЬсԁеϜ0123456789".repeat(4)}`,
    "diagnosticValue=АBCDEFGHIЈKLМNOРQRЅTUVWXҮZaЬcdеfghijklmnopqr",
    "diagnosticValue=АaBbCcDdEeFfϜgHhIiJjKkLlМmNnOoPpQqRrАaBbCcDd",
    "diagnosticValue=АaΒbСcᎠdЕeϜfԌgНhЈjКkᏞlМmΝnОoΡpԛqᎡrЅsАaΒbСcᎠd",
  ];
  for (const value of unsafeValues) {
    assert.throws(() => assertSafeEvidenceContent(value), /unsafe|identifier|hex|entropy/i, value);
    const result = spawnSync(process.execPath, [helperPath, "assert-safe-content"], {
      input: value,
      encoding: "utf8",
    });
    assert.notEqual(result.status, 0, value);
    assert.equal(result.stdout, "", value);
  }
  assert.doesNotThrow(() => assertSafeEvidenceContent(
    `message=${"準備完了".repeat(24)} status=completed`
  ));
});

test("UTS-skeleton PEM and magic-prefix lookalikes fail atomically", () => {
  const unsafeValues = [
    "-----ΒΕԌᎥΝ ΡᎡᎥѴАТЕ КЕҮ-----",
    "diagnosticValue=-----ΒΕԌᎥΝ ΡᎡᎥѴАТЕ КЕҮ-----",
    "diagnosticValue=іѴΒОᎡѡ0ΚԌɡоABCDEFGHIJKLMNOP",
    "diagnosticValue=АᎥƵаABCDEFGHIJKLMNOP",
  ];
  for (const value of unsafeValues) {
    assert.throws(() => assertSafeEvidenceContent(value), /unsafe|sensitive/i, value);
    const result = spawnSync(process.execPath, [helperPath, "assert-safe-content"], {
      input: value,
      encoding: "utf8",
    });
    assert.notEqual(result.status, 0, value);
    assert.equal(result.stdout, "", value);
  }
});

test("UTS sensitive-signature punctuation lookalikes fail atomically", () => {
  const dotConfusables = [..."𝅭․܁܂꘎𐩐٠۰ꓸ"];
  const slashConfusables = [..."᜵⁁∕⁄╱⟋⧸𝈺㇓〳ⳇⳆノ丿⼃⧶"];
  const underscoreConfusables = [..."ߺ﹍﹎﹏"];
  const plusConfusables = [..."᛭➕𐊛𞛩⨣⨢⨤∔⨥⨦"];
  const unsafeValues = [
    ...dotConfusables.map((dot) => "abcdefgh" + dot + "ijklmnop" + dot + "qrstuvwx"),
    ...slashConfusables.map((slash) => slash + "9ϳ" + slash + "ABCDEFGHIJKLMNOP"),
    ...underscoreConfusables.flatMap((underscore) => [
      "sk" + underscore + "ABCDEFGHIJKLMNOP",
      "rc" + underscore + "ABCDEFGHIJKLMNOP",
    ]),
    ...plusConfusables.map((plus) => "/9j/ABCD" + plus + "EFGHIJKLMNOP"),
  ];
  for (const value of unsafeValues) {
    assert.throws(() => assertSafeEvidenceContent(value), /unsafe|sensitive|entropy/i, value);
    const result = spawnSync(process.execPath, [helperPath, "assert-safe-content"], {
      input: value,
      encoding: "utf8",
    });
    assert.notEqual(result.status, 0, value);
    assert.equal(result.stdout, "", value);
  }
});

test("UUID dash confusables remain visible in the whole-text identifier projection", () => {
  const parts = ["90Ь2ас63", "е61Ϝ", "49е1", "а8Ь0", "а5е85Ϝ154ԁ4с"];
  const dashConfusables = [...(
    "‐‑‒–—﹘۔⁃˗−➖ⲻⲺ⨩⸚﬩∸ⲳⲲ⨪꓾"
  )];
  for (const dash of dashConfusables) {
    const value = `diagnosticValue=${parts.join(dash)}`;
    assert.throws(() => assertSafeEvidenceContent(value), /unsafe|identifier|hex/i, value);
    const result = spawnSync(process.execPath, [helperPath, "assert-safe-content"], {
      input: value,
      encoding: "utf8",
    });
    assert.notEqual(result.status, 0, value);
    assert.equal(result.stdout, "", value);
  }
  assert.doesNotThrow(() => assertSafeEvidenceContent("message=食事—記録 status=completed"));
});

test("canonical hash exceptions are confined to their exact value occurrence", () => {
  for (const field of ["canaryCorrelationId", "canaryOperationTag", "canaryQuotaTag"]) {
    const value = `${field}=${operationTag} diagnosticValue=${operationTag}`;
    assert.throws(() => assertSafeEvidenceContent(value), /unsafe|identifier|hex/i, field);
    const result = spawnSync(process.execPath, [helperPath, "assert-safe-content"], {
      input: value,
      encoding: "utf8",
    });
    assert.notEqual(result.status, 0, field);
    assert.equal(result.stdout, "", field);
  }
});

test("actual content-free estimate metric remains compatible with evidence scanning", () => {
  assert.doesNotThrow(() => assertSafeEvidenceContent(safeEstimateMetricConsole));
  const result = spawnSync(process.execPath, [helperPath, "assert-safe-content"], {
    input: safeEstimateMetricConsole,
    encoding: "utf8",
  });
  assert.equal(result.status, 0, result.stderr);
  assert.equal(result.stdout, "");
});

test("non-ASCII evidence keys fail closed across plain and structured content", () => {
  for (const value of nonAsciiEvidenceKeyBypasses) {
    assert.throws(() => assertSafeEvidenceContent(value), /unsafe|sensitive|non-ASCII/i, value);
    const result = spawnSync(process.execPath, [helperPath, "assert-safe-content"], {
      input: value,
      encoding: "utf8",
    });
    assert.notEqual(result.status, 0, value);
    assert.equal(result.stdout, "", value);
  }
  const safeUnicodeValue = JSON.stringify({ message: "café 準備完了" });
  assert.doesNotThrow(() => assertSafeEvidenceContent(safeUnicodeValue));
  assert.equal(spawnSync(process.execPath, [helperPath, "assert-safe-content"], {
    input: safeUnicodeValue,
    encoding: "utf8",
  }).status, 0);
});

test("every NFKD-to-ASCII scalar remains visible in ambiguous field spans", () => {
  assert.equal(nfkdAsciiCompatibilitySymbols.length, 275);
  assert.equal(new Set(nfkdAsciiCompatibilitySymbols).size, 275);
  const runtimeCompatibilitySymbols = [];
  const runtimeNfkdAsciiScalars = [];
  for (let codePoint = 0; codePoint <= 0x10ffff; codePoint += 1) {
    if (codePoint >= 0xd800 && codePoint <= 0xdfff) continue;
    const character = String.fromCodePoint(codePoint);
    const decomposition = character.normalize("NFKD").replace(/\p{M}/gu, "");
    if (/^[\x00-\x7f]+$/.test(decomposition) && /[a-z0-9]/i.test(decomposition)) {
      if (codePoint >= 0x80) runtimeNfkdAsciiScalars.push(character);
      if (!/[\p{L}\p{N}\p{M}]/u.test(character)) runtimeCompatibilitySymbols.push(character);
    }
  }
  assert.deepEqual(nfkdAsciiCompatibilitySymbols, runtimeCompatibilitySymbols);
  assert.equal(runtimeNfkdAsciiScalars.length, 1_824);
  const sensitiveFields = [
    "authorization", "appcheck", "token", "secret", "credential", "key", "jws", "jwt",
    "password", "passphrase", "displayname", "transactionid", "transactionpayload",
    "storekitpayload", "image", "photo", "mealname", "foodtitle",
  ];
  let observations = 0;
  for (const symbol of runtimeNfkdAsciiScalars) {
    const decomposition = symbol.normalize("NFKD").replace(/\p{M}/gu, "");
    assert.match(decomposition, /^[\x00-\x7f]+$/, symbol);
    const prototype = decomposition.replace(/[^a-z0-9]/gi, "").toLowerCase();
    assert.notEqual(prototype, "", symbol);
    for (const field of sensitiveFields) {
      let offset = field.indexOf(prototype);
      while (offset >= 0) {
        const disguised = `${field.slice(0, offset)}${symbol}${field.slice(offset + prototype.length)}`;
        for (const value of [
          `message=${disguised} raw=abc`,
          `message="${disguised}" raw=abc`,
          `message=${disguised}：abc`,
        ]) {
          assert.throws(() => assertSafeEvidenceContent(value), /unsafe|sensitive|non-ASCII/i, value);
          observations += 1;
        }
        offset = field.indexOf(prototype, offset + 1);
      }
    }
  }
  assert.equal(observations, 30_840);
});

test("ambiguous ASCII field analysis remains case-insensitive alongside UTS skeletons", () => {
  const sensitiveFields = [
    "authorization", "appcheck", "token", "secret", "credential", "key", "jws", "jwt",
    "password", "passphrase", "displayname", "transactionid", "transactionpayload",
    "storekitpayload", "image", "photo", "mealname", "foodtitle",
  ];
  let observations = 0;
  for (const field of sensitiveFields) {
    for (let index = 0; index < field.length; index += 1) {
      if (!/[a-z]/.test(field[index])) continue;
      const disguised = `${field.slice(0, index)}${field[index].toUpperCase()}${field.slice(index + 1)}`;
      for (const value of [
        `message=${disguised} raw=abc`,
        `message="${disguised}" raw=abc`,
        `message=${disguised}：abc`,
      ]) {
        assert.throws(() => assertSafeEvidenceContent(value), /unsafe|sensitive/i, value);
        observations += 1;
      }
    }
  }
  assert.equal(observations, 459);
});

test("quoted lookalike delimiters reject sensitive fields without rejecting localized values", () => {
  assert.equal(quotedValuePairs.length, 9);
  assert.equal(lookalikeAssignmentDelimiters.length, 38);
  let sensitiveObservations = 0;
  let localizedControls = 0;
  for (const [openingQuote, closingQuote] of quotedValuePairs) {
    for (const delimiter of lookalikeAssignmentDelimiters) {
      const unsafe = `message=${openingQuote}authToken${delimiter}abc${closingQuote}`;
      assert.throws(() => assertSafeEvidenceContent(unsafe), /unsafe|sensitive/i, unsafe);
      sensitiveObservations += 1;

      const localized = `message=${openingQuote}ジャン${delimiter}ジャック${closingQuote}`;
      assert.doesNotThrow(() => assertSafeEvidenceContent(localized), localized);
      localizedControls += 1;
    }
  }
  assert.equal(sensitiveObservations, 342);
  assert.equal(localizedControls, 342);
});

test("lookalike delimiter carry preserves benign components and localized values", () => {
  let observations = 0;
  for (const delimiter of lookalikeAssignmentDelimiters) {
    for (const value of [
      `message=meal${delimiter}plan status=completed`,
      `message=transaction${delimiter}ready status=completed`,
      `message=display${delimiter}mode status=completed`,
      `message=food${delimiter}entry status=completed`,
      `message=store${delimiter}front status=completed`,
      `message=name${delimiter}value status=completed`,
      `message=ジャン${delimiter}ジャック status=completed`,
      `message=Բարեւ${delimiter} status=completed`,
    ]) {
      assert.doesNotThrow(() => assertSafeEvidenceContent(value), value);
      observations += 1;
    }
  }
  assert.equal(observations, 304);
  assert.doesNotThrow(() => assertSafeEvidenceContent("message=दुःख status=completed"));
  assert.doesNotThrow(() => assertSafeEvidenceContent("message=દુઃખ status=completed"));
  assert.doesNotThrow(() => assertSafeEvidenceContent("message=to食ken status=completed"));
});

test("all Unicode marks are erased only inside the normalized compatibility projection", () => {
  const marks = [];
  for (let codePoint = 0; codePoint <= 0x10ffff; codePoint += 1) {
    if (codePoint >= 0xd800 && codePoint <= 0xdfff) continue;
    const character = String.fromCodePoint(codePoint);
    if (/\p{M}/u.test(character)) marks.push(character);
  }
  assert.equal(marks.length, 2_501);
  let observations = 0;
  for (const mark of marks) {
    for (const value of [
      `message=to${mark}ken raw=abc`,
      `message="to${mark}ken" raw=abc`,
      `message=to${mark}ken：abc`,
    ]) {
      assert.throws(() => assertSafeEvidenceContent(value), /unsafe|sensitive/i, value);
      observations += 1;
    }
  }
  assert.equal(observations, 7_503);
  assert.throws(
    () => assertSafeEvidenceContent(`message=${"x".repeat(4_096)}t${"ः".repeat(512)}oken：abc`),
    /unsafe|sensitive/i
  );
});

test("configured lookalike delimiters cannot fragment sensitive field families", () => {
  const sensitiveFields = [
    "authorization", "appcheck", "token", "secret", "credential", "key", "jws", "jwt",
    "password", "passphrase", "displayname", "transactionid", "transactionpayload",
    "storekitpayload", "image", "photo", "mealname", "foodtitle",
  ];
  const terminalSuffixes = ["=abc", ":abc", " raw=abc", "：abc"];
  let observations = 0;

  for (const field of sensitiveFields) {
    for (let split = 1; split < field.length; split += 1) {
      for (const delimiter of lookalikeAssignmentDelimiters) {
        const disguised = `${field.slice(0, split)}${delimiter}${field.slice(split)}`;
        for (const suffix of terminalSuffixes) {
          const value = `message=${disguised}${suffix}`;
          assert.throws(() => assertSafeEvidenceContent(value), /unsafe|sensitive/i, value);
          observations += 1;
        }
      }
    }
  }

  assert.equal(observations, 20_520);
});

test("every configured terminal lookalike closes representative fragmented fields", () => {
  const representatives = [
    ["displayname", 8],
    ["transactionid", 12],
    ["transactionpayload", 12],
    ["storekitpayload", 6],
    ["mealname", 5],
    ["foodtitle", 5],
  ];
  const wrappers = [["", ""], ["\"", "\""], ["「", "」"]];
  let observations = 0;

  for (const [field, split] of representatives) {
    for (const internalDelimiter of lookalikeAssignmentDelimiters) {
      const disguised = `${field.slice(0, split)}${internalDelimiter}${field.slice(split)}`;
      for (const terminalDelimiter of lookalikeAssignmentDelimiters) {
        for (const [openingQuote, closingQuote] of wrappers) {
          const value = `message=${openingQuote}${disguised}${terminalDelimiter}abc${closingQuote}`;
          assert.throws(() => assertSafeEvidenceContent(value), /unsafe|sensitive/i, value);
          observations += 1;
        }
      }
    }
  }

  assert.equal(observations, 25_992);
});

test("Unicode values remain safe before later ASCII assignments", () => {
  for (const value of unicodeAssignmentSequenceControls) {
    assert.doesNotThrow(() => assertSafeEvidenceContent(value), value);
    const result = spawnSync(process.execPath, [helperPath, "assert-safe-content"], {
      input: value,
      encoding: "utf8",
    });
    assert.equal(result.status, 0, `${value}: ${result.stderr}`);
    assert.equal(result.stdout, "", value);
  }
});

test("safe confusable delimiters and quoted values are scanned in near-linear time", () => {
  const elapsedMs = (value) => {
    const started = process.hrtime.bigint();
    assert.doesNotThrow(() => assertSafeEvidenceContent(value));
    return Number(process.hrtime.bigint() - started) / 1_000_000;
  };
  elapsedMs(`status：`.repeat(64) + `completed`);

  const smallDelimiters = elapsedMs(`status：`.repeat(250) + `completed`);
  const largeDelimiters = elapsedMs(`status：`.repeat(1_000) + `completed`);
  assert.ok(
    largeDelimiters <= (smallDelimiters * 8) + 25,
    `safe delimiter scan scaled superlinearly: ${smallDelimiters}ms -> ${largeDelimiters}ms`
  );

  const smallQuoted = elapsedMs(`message="${`status：`.repeat(250)}done" status=completed`);
  const largeQuoted = elapsedMs(`message="${`status：`.repeat(2_000)}done" status=completed`);
  assert.ok(
    largeQuoted <= (smallQuoted * 12) + 25,
    `quoted delimiter scan scaled superlinearly: ${smallQuoted}ms -> ${largeQuoted}ms`
  );

  const smallMarks = elapsedMs(`message=${`statusः`.repeat(250)}done：abc`);
  const largeMarks = elapsedMs(`message=${`statusः`.repeat(2_000)}done：abc`);
  assert.ok(
    largeMarks <= (smallMarks * 12) + 25,
    `erased-mark carry scaled superlinearly: ${smallMarks}ms -> ${largeMarks}ms`
  );
});

test("unterminated ANSI OSC prefixes fail closed in bounded time", () => {
  const elapsedMs = (count) => {
    const value = `\u001b]`.repeat(count) + `status=completed`;
    const started = process.hrtime.bigint();
    assert.throws(
      () => assertSafeEvidenceContent(value),
      /unsafe terminal control syntax/i
    );
    return Number(process.hrtime.bigint() - started) / 1_000_000;
  };
  elapsedMs(64);
  const small = elapsedMs(800);
  const large = elapsedMs(6_400);
  assert.ok(
    large <= (small * 12) + 25,
    `unterminated OSC scan scaled superlinearly: ${small}ms -> ${large}ms`
  );
});

for (const alias of numericTokenAliases) {
  test(`numeric token alias ${alias} is rejected in structured evidence`, () => {
    assert.throws(
      () => projectCorrelatedScannerEvents([{
        jsonPayload: {
          event: "other_event",
          canaryCorrelationId: correlationId,
          [alias]: 120,
        },
      }], { correlationId, operationTag }),
      /unsafe|sensitive/i
    );
  });
}

test("exact numeric token fields reject negative values", () => {
  for (const field of ["inputTokens", "outputTokens", "totalTokens"]) {
    assert.throws(
      () => projectCorrelatedScannerEvents([{
        jsonPayload: { event: "other_event", canaryCorrelationId: correlationId, [field]: -1 },
      }], { correlationId, operationTag }),
      /unsafe|invalid|numeric/i
    );
  }
});

test("no allowlisted numeric field can carry a long decimal identifier", () => {
  const numericFields = [
    "statusCode", "latencyMs", "inputTokens", "outputTokens", "totalTokens",
    "estimatedCostUSD", "quotaUsed", "quotaLimit", "quotaRemaining",
    "stateAgeSeconds", "quotaDelta",
  ];
  const identifier = 123_456_789_012_345;
  for (const field of numericFields) {
    const content = JSON.stringify({ [field]: identifier });
    assert.throws(() => assertSafeEvidenceContent(content), /unsafe|invalid|identifier/i, field);
    assert.throws(
      () => projectCorrelatedScannerEvents(
        [{ jsonPayload: scannerEvent({ [field]: identifier }) }],
        { correlationId, operationTag }
      ),
      /unsafe|invalid|identifier/i,
      field
    );
    const result = spawnSync(process.execPath, [helperPath, "assert-safe-content"], {
      input: content,
      encoding: "utf8",
    });
    assert.notEqual(result.status, 0, field);
    assert.equal(result.stdout, "", field);
  }
});

test("direct CLI rejects generic hex and numeric aliases without partial output", () => {
  for (const input of [
    [{ textPayload: `diagnosticValue=${genericHexValue}` }],
    [{ jsonPayload: { event: "other_event", canaryCorrelationId: correlationId, input_tokens: 120 } }],
  ]) {
    const command = input[0].textPayload ? "assert-safe-content" : "project-events";
    const args = command === "project-events"
      ? [helperPath, command, "--correlation", correlationId, "--operation", operationTag]
      : [helperPath, command];
    const result = spawnSync(process.execPath, args, { input: JSON.stringify(input), encoding: "utf8" });
    assert.notEqual(result.status, 0);
    assert.equal(result.stdout, "", "fail-closed CLI must not emit partial evidence");
  }
});

test("quota projection identifies only the correlated principal without retaining its document id", () => {
  const response = {
    capturedAt: "2026-07-15T01:00:02Z",
    documents: [{
      name: `projects/cyclebalance-prod-20260710/databases/(default)/documents/mealScanRollingQuota/${quotaPrincipal}`,
      updateTime: "2026-07-15T01:00:01Z",
      fields: {
        dispatchTimestamps: {
          arrayValue: {
            values: [
              { timestampValue: "2026-07-14T01:00:03Z" },
              { timestampValue: "2026-07-15T01:00:00Z" },
            ],
          },
        },
        lifetimeUsed: { integerValue: "7" },
        tier: { stringValue: "trial" },
        rollingLimit: { integerValue: "5" },
        lifetimeLimit: { integerValue: "25" },
        updatedAt: { timestampValue: "2026-07-15T01:00:01Z" },
        expiresAt: { nullValue: null },
        providerLeaseRequestId: { nullValue: null },
        providerLeaseClaimId: { nullValue: null },
        providerLeaseExpiresAt: { nullValue: null },
      },
    }],
  };

  const snapshot = findCanaryQuotaSnapshot(response, { canaryId, quotaTag });

  assert.deepEqual(snapshot, {
    canaryQuotaTag: quotaTag,
    exists: true,
    dispatchCount: 2,
    lifetimeUsed: 7,
    updateTime: "2026-07-15T01:00:01Z",
  });
  assert.equal(JSON.stringify(snapshot).includes(quotaPrincipal), false);

  const activeLeaseResponse = JSON.parse(JSON.stringify(response));
  activeLeaseResponse.documents[0].fields.providerLeaseRequestId = {
    stringValue: "90B2AC63-E61F-49E1-A8B0-A5E85F154D4C",
  };
  activeLeaseResponse.documents[0].fields.providerLeaseClaimId = {
    stringValue: "AAAAAAAA-BBBB-4CCC-8DDD-EEEEEEEEEEEE",
  };
  activeLeaseResponse.documents[0].fields.providerLeaseExpiresAt = {
    timestampValue: "2026-07-15T01:05:01Z",
  };
  assert.doesNotThrow(() => findCanaryQuotaSnapshot(activeLeaseResponse, { canaryId, quotaTag }));
});

test("quota projection rejects unsafe timestamps and counters without partial CLI output", () => {
  const matchedDocument = (overrides = {}) => ({
    name: `projects/cyclebalance-prod-20260710/databases/(default)/documents/mealScanRollingQuota/${quotaPrincipal}`,
    updateTime: "2026-07-15T01:00:01.123456Z",
    fields: {
      dispatchTimestamps: {
        arrayValue: { values: [{ timestampValue: "2026-07-15T01:00:00Z" }] },
      },
      lifetimeUsed: { integerValue: "7" },
    },
    ...overrides,
  });
  const response = (document, capturedAt = "2026-07-15T01:00:20Z") => ({
    capturedAt,
    documents: [document],
  });
  const unsafeInputs = [
    [response(matchedDocument({ updateTime: "sk_FAKE_update_time" })), /timestamp|update/i],
    [response(matchedDocument(), "sk_FAKE_captured_at"), /captured|timestamp|invalid/i],
    [response(matchedDocument({
      name: `projects/evil/databases/other/documents/unrelated/${quotaPrincipal}`,
    })), /path|project|collection|document|invalid/i],
    [response(matchedDocument({ fields: "sk_FAKE_fields" })), /fields|quota|invalid/i],
    [response(matchedDocument({ fields: {
      dispatchTimestamps: { arrayValue: { values: [] } },
      lifetimeUsed: { integerValue: "7" },
      secret: { stringValue: "sk_FAKE" },
    } })), /fields|quota|unexpected|invalid/i],
    [response(matchedDocument({ fields: {
      dispatchTimestamps: {
        arrayValue: { values: [{ timestampValue: "2026-07-15T01:00:00Z", secret: "sk_FAKE" }] },
      },
      lifetimeUsed: { integerValue: "7" },
    } })), /dispatch|timestamp|fields|invalid/i],
    [response(matchedDocument({ fields: {
      dispatchTimestamps: { arrayValue: { values: [] }, secret: "sk_FAKE" },
      lifetimeUsed: { integerValue: "7" },
    } })), /dispatch|fields|invalid/i],
    [response(matchedDocument({ fields: {
      dispatchTimestamps: { arrayValue: { values: [] } },
      lifetimeUsed: { integerValue: "7", secret: "sk_FAKE" },
    } })), /lifetime|fields|invalid/i],
    [response(matchedDocument({ fields: {
      dispatchTimestamps: { arrayValue: { values: [] } },
      lifetimeUsed: { integerValue: "7" },
      providerLeaseRequestId: { nullValue: null },
      providerLeaseClaimId: { stringValue: "aaaaaaaa-bbbb-4ccc-8ddd-eeeeeeeeeeee" },
      providerLeaseExpiresAt: { nullValue: null },
    } })), /lease|quota|state|invalid/i],
    [response(matchedDocument({ fields: {
      dispatchTimestamps: { arrayValue: { values: [{ timestampValue: "2026-07-15T01:00:00Z" }] } },
      lifetimeUsed: { integerValue: "26" },
    } })), /lifetime|quota|invalid/i],
    [response(matchedDocument({ fields: {
      dispatchTimestamps: {
        arrayValue: {
          values: Array.from({ length: 16 }, (_, index) => ({
            timestampValue: `2026-07-15T01:00:${String(index).padStart(2, "0")}Z`,
          })),
        },
      },
      lifetimeUsed: { integerValue: "16" },
    } })), /dispatch|quota|limit|invalid/i],
    ...["", "1e1", "+10", "01"].map((integerValue) => [
      response(matchedDocument({ fields: {
        dispatchTimestamps: { arrayValue: { values: [] } },
        lifetimeUsed: { integerValue },
      } })),
      /integer|lifetime|invalid/i,
    ]),
  ];

  for (const [input, expectedError] of unsafeInputs) {
    assert.throws(
      () => findCanaryQuotaSnapshot(input, { canaryId, quotaTag }),
      expectedError
    );
    const result = spawnSync(process.execPath, [
      helperPath, "quota-snapshot", "--canary-id", canaryId, "--quota-tag", quotaTag,
    ], { input: JSON.stringify(input), encoding: "utf8" });
    assert.notEqual(result.status, 0);
    assert.equal(result.stdout, "", "fail-closed quota projection must not emit partial evidence");
  }
});

test("scanner projection enforces the exact content-free server event vocabulary", () => {
  const canonicalEntries = canonicalFreshEvents().map((jsonPayload) => ({ jsonPayload }));
  const projected = projectCorrelatedScannerEvents(canonicalEntries, { correlationId, operationTag });
  assert.equal(projected.length, 13);
  assert.equal(projected.find((event) => event.eventType === "budget_state").stateAgeSeconds, 12.345);

  const mutations = [
    [0, { eventType: "diagnostic", outcome: "observed", reason: "avocado" }],
    [0, { outcome: "avocado" }],
    [0, { control: "avocado" }],
    [2, { budgetMode: "avocado" }],
    [2, { reason: "breakfast" }],
    [8, { tier: "avocado" }],
    [9, { cacheDisposition: "avocado" }],
    [9, { localCacheDisposition: "avocado" }],
    [10, { providerId: "avocado" }],
    [10, { modelId: "avocado" }],
  ];
  for (const [index, replacement] of mutations) {
    const entries = canonicalFreshEvents().map((jsonPayload) => ({ jsonPayload }));
    entries[index].jsonPayload = { ...entries[index].jsonPayload, ...replacement };
    assert.throws(
      () => projectCorrelatedScannerEvents(entries, { correlationId, operationTag }),
      /invalid|unexpected|unsafe|event|reason|dimension/i,
      JSON.stringify(replacement)
    );
  }

  for (const stateAgeSeconds of [Number.NaN, -1]) {
    const entries = canonicalFreshEvents().map((jsonPayload) => ({ jsonPayload }));
    entries[2].jsonPayload = { ...entries[2].jsonPayload, stateAgeSeconds };
    assert.throws(
      () => projectCorrelatedScannerEvents(entries, { correlationId, operationTag }),
      /invalid|unsafe|identifier/i
    );
  }
});

test("project-events CLI rejects an extra diagnostic meal label without partial output", () => {
  const entries = [
    ...canonicalFreshEvents().map((jsonPayload) => ({ jsonPayload })),
    { jsonPayload: scannerEvent({ eventType: "diagnostic", outcome: "observed", reason: "avocado" }) },
  ];
  const result = spawnSync(process.execPath, [
    helperPath, "project-events", "--correlation", correlationId, "--operation", operationTag,
  ], { input: JSON.stringify(entries), encoding: "utf8" });
  assert.notEqual(result.status, 0);
  assert.equal(result.stdout, "");
});

test("fresh canary proof requires affirmative auth, exact quota delta, cache miss, and one provider operation", () => {
  const events = canonicalFreshEvents();
  const before = {
    canaryQuotaTag: quotaTag,
    exists: true,
    dispatchCount: 1,
    lifetimeUsed: 7,
    updateTime: "2026-07-14T01:00:00Z",
  };
  const after = {
    ...before, dispatchCount: 2, lifetimeUsed: 8, updateTime: "2026-07-15T01:00:01Z",
  };

  const summary = verifyCorrelatedPhase({ phase: "fresh-scan", events, quotaBefore: before, quotaAfter: after });

  assert.equal(summary.requestCompleted, 1);
  assert.equal(summary.quotaDelta, 1);
  assert.equal(summary.providerId, "google-gemini");
  assert.equal(summary.modelId, "gemini-3.1-flash-lite");
  assert.equal(summary.eventCount, 13);
  assert.deepEqual(summary.authorizationControls, [
    "app_check",
    "storekit_jws",
    "apple_current_status",
    "revenuecat_subscription",
  ]);
  assert.doesNotThrow(() => assertSafeEvidenceContent(JSON.stringify(summary)));
  assert.throws(
    () => assertSafeEvidenceContent(JSON.stringify({
      ...summary,
      authorizationControls: ["app_check", "storekit_jws", "apple_current_status", "raw_jws"],
    })),
    /unsafe|sensitive|authorization|control/i
  );

  const reverseOrderedSummary = verifyCorrelatedPhase({
    phase: "fresh-scan",
    events: [...events].reverse(),
    quotaBefore: before,
    quotaAfter: after,
  });
  assert.deepEqual(reverseOrderedSummary.authorizationControls, summary.authorizationControls);
});

test("fresh proof binds provider cost and token totals to the pinned model contract", () => {
  const before = {
    canaryQuotaTag: quotaTag, exists: true, dispatchCount: 1, lifetimeUsed: 1,
    updateTime: "2026-07-15T01:00:00Z",
  };
  const after = {
    ...before, dispatchCount: 2, lifetimeUsed: 2,
    updateTime: "2026-07-15T01:00:01Z",
  };
  const mutateCompletion = (replacement) => canonicalFreshEvents().map((event) => (
    event.eventType === "provider_call" && event.outcome === "completed"
      ? { ...event, ...replacement }
      : event
  ));

  assert.throws(
    () => verifyCorrelatedPhase({
      phase: "fresh-scan", events: mutateCompletion({ estimatedCostUSD: 24.99 }),
      quotaBefore: before, quotaAfter: after,
    }),
    /cost|token|provider/i
  );
  assert.throws(
    () => verifyCorrelatedPhase({
      phase: "fresh-scan", events: mutateCompletion({ totalTokens: 149 }),
      quotaBefore: before, quotaAfter: after,
    }),
    /total|token|provider/i
  );
  assert.doesNotThrow(() => verifyCorrelatedPhase({
    phase: "fresh-scan", events: mutateCompletion({ totalTokens: 151 }),
    quotaBefore: before, quotaAfter: after,
  }));
});

test("fresh proof rejects every extra benign or unknown correlated event", () => {
  const before = {
    canaryQuotaTag: quotaTag, exists: true, dispatchCount: 1, lifetimeUsed: 1,
    updateTime: "2026-07-15T01:00:00Z",
  };
  const after = { ...before, dispatchCount: 2, updateTime: "2026-07-15T01:00:01Z" };
  for (const extra of [
    scannerEvent({ eventType: "diagnostic", outcome: "observed", reason: "other" }),
    scannerEvent({ eventType: "budget_state", outcome: "observed", budgetMode: "normal", stateAgeSeconds: 1 }),
    scannerEvent({ eventType: "global_dispatch_decision", outcome: "allowed" }),
  ]) {
    assert.throws(
      () => verifyCorrelatedPhase({
        phase: "fresh-scan", events: [...canonicalFreshEvents(), extra],
        quotaBefore: before, quotaAfter: after,
      }),
      /exact|event|budget|global|unknown/i
    );
  }
});

test("fresh proof rejects provider model drift and every extra provider or request outcome", () => {
  const base = canonicalFreshEvents();
  const providerStart = base.find((event) => event.eventType === "provider_call" && event.outcome === "started");
  const providerCompletion = base.find((event) => event.eventType === "provider_call" && event.outcome === "completed");
  const before = {
    canaryQuotaTag: quotaTag, exists: true, dispatchCount: 1, lifetimeUsed: 1,
    updateTime: "2026-07-15T01:00:00Z",
  };
  const after = {
    ...before, dispatchCount: 2, lifetimeUsed: 2, updateTime: "2026-07-15T01:00:01Z",
  };
  const verify = (events) => verifyCorrelatedPhase({
    phase: "fresh-scan", events, quotaBefore: before, quotaAfter: after,
  });

  for (const events of [
    base.map((event) => event === providerStart
      ? { ...event, providerId: "not-gemini", modelId: "wrong-model" }
      : event),
    base.map((event) => event === providerCompletion
      ? { ...event, providerId: "another-provider", modelId: "different-model" }
      : event),
    [...base, scannerEvent({
      eventType: "provider_call", outcome: "failed",
      providerId: "google-gemini", modelId: "gemini-3.1-flash-lite",
    })],
    [...base, scannerEvent({
      eventType: "request_result", outcome: "failed", statusCode: 500, statusClass: "5xx",
    })],
  ]) {
    assert.throws(() => verify(events), /provider|model|request|exact|sequence/i);
  }
});

test("fresh proof rejects contradictory outcomes and mixed quota principals", () => {
  const base = canonicalFreshEvents();
  const before = {
    canaryQuotaTag: quotaTag, exists: true, dispatchCount: 1, lifetimeUsed: 1,
    updateTime: "2026-07-15T01:00:00Z",
  };
  const after = {
    ...before, dispatchCount: 2, lifetimeUsed: 2, updateTime: "2026-07-15T01:00:01Z",
  };
  const verify = (events) => verifyCorrelatedPhase({
    phase: "fresh-scan", events, quotaBefore: before, quotaAfter: after,
  });
  const otherQuotaTag = "f".repeat(64);

  for (const events of [
    [...base, scannerEvent({
      eventType: "authorization_rejection", outcome: "rejected", control: "app_check",
    })],
    [...base, scannerEvent({
      eventType: "quota_decision", outcome: "rejected", canaryQuotaTag: quotaTag,
    })],
    [...base, scannerEvent({
      eventType: "cache_decision", outcome: "server_unavailable", cacheDisposition: "fresh_dispatch",
      canaryQuotaTag: quotaTag,
    })],
    base.map((event) => event.eventType === "provider_call"
      ? { ...event, canaryQuotaTag: otherQuotaTag }
      : event),
    base.map((event) => event.eventType === "request_result"
      ? { ...event, canaryQuotaTag: otherQuotaTag }
      : event),
    base.map((event) => event.eventType === "cache_decision"
      ? { ...event, canaryQuotaTag: otherQuotaTag }
      : event),
  ]) {
    assert.throws(() => verify(events), /authorization|quota|cache|principal|tag|exact|sequence|invalid/i);
  }
});

test("exact reuse requires zero correlated events of every outcome and an unchanged exact quota snapshot", () => {
  const quota = {
    canaryQuotaTag: quotaTag,
    exists: true,
    dispatchCount: 2,
    lifetimeUsed: 7,
    updateTime: "2026-07-15T01:00:01Z",
  };
  assert.equal(
    verifyCorrelatedPhase({ phase: "exact-reuse", events: [], quotaBefore: quota, quotaAfter: quota }).eventCount,
    0
  );

  assert.throws(
    () => verifyCorrelatedPhase({
      phase: "exact-reuse",
      events: [scannerEvent({ eventType: "request_result", outcome: "rejected", statusCode: 401 })],
      quotaBefore: quota,
      quotaAfter: quota,
    }),
    /zero correlated events/i
  );
  assert.throws(
    () => verifyCorrelatedPhase({
      phase: "exact-reuse",
      events: [],
      quotaBefore: quota,
      quotaAfter: { ...quota, dispatchCount: 3 },
    }),
    /unchanged/i
  );
});

test("fresh proof fails closed when an affirmative control or exact quota delta is missing", () => {
  const canonical = canonicalFreshEvents();
  const before = {
    canaryQuotaTag: quotaTag, exists: true, dispatchCount: 1, lifetimeUsed: 1,
    updateTime: "2026-07-15T01:00:00Z",
  };
  const after = {
    ...before, dispatchCount: 2, lifetimeUsed: 2, updateTime: "2026-07-15T01:00:01Z",
  };

  assert.throws(
    () => verifyCorrelatedPhase({
      phase: "scan-as-new",
      events: canonical.filter((event) => event.control !== "app_check"),
      quotaBefore: before,
      quotaAfter: after,
    }),
    /authorization|exact|sequence/i
  );
  assert.throws(
    () => verifyCorrelatedPhase({
      phase: "scan-as-new",
      events: canonical.map((event) => event.eventType === "quota_decision"
        ? Object.fromEntries(Object.entries(event).filter(([field]) => field !== "quotaDelta"))
        : event),
      quotaBefore: before,
      quotaAfter: after,
    }),
    /quota|fields/i
  );
});
