#!/usr/bin/env node
import crypto from "node:crypto";
import { isDeepStrictEqual } from "node:util";
import { readFileSync } from "node:fs";
import { pathToFileURL } from "node:url";

const EVENT_NAME = "meal_scan_scanner_event";
const EVENT_SCHEMA = "cyclebalance.meal_scan.operation.v1";
const PINNED_PROJECT_ID = "cyclebalance-prod-20260710";
const PINNED_SERVICE_NAME = "cyclebalance-meal-scan-proxy";
const PINNED_LOCATION = "us-central1";
const MAX_CANARY_DISPATCH_COUNT = 15;
const MAX_TRIAL_LIFETIME_COUNT = 25;
const HEX_64 = /^[a-f0-9]{64}$/;
const UUID = /^[0-9a-f]{8}-[0-9a-f]{4}-[1-8][0-9a-f]{3}-[89ab][0-9a-f]{3}-[0-9a-f]{12}$/;
const UUID_CASE_INSENSITIVE = new RegExp(UUID.source, "i");
const FIRESTORE_UPDATE_TIME = /^(\d{4})-(\d{2})-(\d{2})T(\d{2}):(\d{2}):(\d{2})(?:\.(\d{3}|\d{6}|\d{9}))?Z$/;
const DASHED_HEX_IDENTIFIER = /[0-9a-f]{8}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{12}/gi;
const CONTIGUOUS_HEX_IDENTIFIER = /[0-9a-f]{32,}/gi;
const LONG_DECIMAL_IDENTIFIER = /\p{Nd}{15,}/gu;
const SAFE_DIMENSION = /^[a-z0-9][a-z0-9_.-]{0,63}$/;
const EXPECTED_AUTHORIZATION_CONTROLS = Object.freeze([
  "app_check",
  "storekit_jws",
  "apple_current_status",
  "revenuecat_subscription",
]);
const STRING_FIELDS = new Set([
  "event",
  "severity",
  "schemaVersion",
  "eventType",
  "outcome",
  "control",
  "cacheDisposition",
  "localCacheDisposition",
  "providerId",
  "modelId",
  "tier",
  "budgetMode",
  "statusClass",
  "reason",
  "canaryCorrelationId",
  "canaryOperationTag",
  "canaryQuotaTag",
]);
const NUMBER_FIELDS = new Set([
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
  "quotaDelta",
]);
const NUMERIC_FIELD_LIMITS = Object.freeze({
  statusCode: { minimum: 100, maximum: 599, integer: true },
  latencyMs: { minimum: 0, maximum: 600_000, integer: true },
  inputTokens: { minimum: 0, maximum: 1_000_000, integer: true },
  outputTokens: { minimum: 0, maximum: 1_000_000, integer: true },
  totalTokens: { minimum: 0, maximum: 2_000_000, integer: true },
  estimatedCostUSD: { minimum: 0, maximum: 25, integer: false },
  quotaUsed: { minimum: 0, maximum: 25, integer: true },
  quotaLimit: { minimum: 0, maximum: 25, integer: true },
  quotaRemaining: { minimum: 0, maximum: 25, integer: true },
  stateAgeSeconds: { minimum: 0, maximum: 604_800, integer: false },
  quotaDelta: { minimum: 1, maximum: 1, integer: true },
});
const ALLOWED_EVENT_FIELDS = new Set([...STRING_FIELDS, ...NUMBER_FIELDS]);
const ALLOWED_NUMERIC_TOKEN_FIELDS = new Set([
  "inputTokens",
  "outputTokens",
  "totalTokens",
]);
const CANONICAL_HASH_FIELDS = new Set([
  "canaryCorrelationId",
  "canaryOperationTag",
  "canaryQuotaTag",
]);
const EXACT_SENSITIVE_CONTENT_FIELDS = new Set([
  "meal",
  "meals",
  "food",
  "foods",
  "mealdescription",
  "fooddescription",
]);
const EVENT_OUTCOMES = Object.freeze({
  authorization_acceptance: new Set(["accepted"]),
  authorization_rejection: new Set(["rejected", "unavailable"]),
  request_gate_decision: new Set(["allowed", "rejected", "unavailable"]),
  budget_state: new Set(["observed", "stale", "transitioned", "unavailable"]),
  global_dispatch_decision: new Set(["allowed", "rejected"]),
  quota_decision: new Set(["allowed", "rejected", "unavailable"]),
  cache_decision: new Set(["observed", "unavailable"]),
  provider_call: new Set(["started", "completed", "failed"]),
  request_result: new Set(["completed", "rejected", "failed"]),
});
const AUTHORIZATION_CONTROLS = new Set([
  "app_check", "storekit_jws", "apple_current_status", "revenuecat_subscription",
]);
const REQUEST_GATE_CONTROLS = new Set(["pre_verification", "principal_attempt"]);
const CACHE_DISPOSITIONS = new Set([
  "idempotency_replay",
  "server_unavailable",
  "server_hit",
  "server_miss",
  "server_hit_after_lease",
  "server_hit_after_wait",
  "server_miss_in_progress",
  "fresh_dispatch",
]);
const SAFE_SCANNER_REASONS = (() => {
  const source = readFileSync(new URL("../src/server.js", import.meta.url), "utf8");
  const match = source.match(/const SAFE_SCANNER_REASONS = new Set\(\[([\s\S]*?)\]\);/u);
  if (!match) throw new Error("approved scanner reason vocabulary is unavailable");
  const reasons = [...match[1].matchAll(/"([a-z0-9_]+)"/g)].map((entry) => entry[1]);
  if (reasons.length < 50 || reasons.length !== new Set(reasons).size) {
    throw new Error("approved scanner reason vocabulary is invalid");
  }
  return new Set(reasons);
})();
const SENSITIVE_TEXT_PATTERNS = [
  /authorization\s*:\s*bearer/i,
  /\b(?:x-firebase-appcheck|app[_-]?check[_-]?token|appCheckToken|signed[_-]?transaction[_-]?jws|signedTransactionJWS|store[_-]?kit[_-]?jws|storeKitJWS)\b/i,
  /-----BEGIN [A-Z ]+-----/i,
  /\bya29\.[A-Za-z0-9_-]+/i,
  /\b(?:sk|rc)_[A-Za-z0-9_-]{16,}\b/i,
  /(?:^|[^A-Za-z0-9_-])[A-Za-z0-9_-]{8,}\.[A-Za-z0-9_-]{8,}\.[A-Za-z0-9_-]{8,}(?![A-Za-z0-9_.-])/,
  /\/9j\/[A-Za-z0-9+/=]{16,}/i,
  /iVBORw0KGgo[A-Za-z0-9+/=]{16,}/i,
  /data:image/i,
  /\bAIza[A-Za-z0-9_-]+/i,
];
const CONFUSABLE_COLON_CHARACTERS = "︓﹕ःઃ：։܃܄᛬︰᠃᠉⁚׃˸꞉∶ːꓽ𑷙⩴⧴";
const CONFUSABLE_EQUALS_CHARACTERS = "﹦＝᐀⹀゠꓿≚≙≗≐≑⮖⩮⩵⩶≞";
const UUID_DASH_CONFUSABLES = new Set([...("‐‑‒–—﹘۔⁃˗−➖ⲻⲺ⨩⸚﬩∸ⲳⲲ⨪꓾")]);
// Generated from Unicode UTS #39 confusables.txt 17.0.0. Targets are limited
// to ASCII punctuation used by privacy-sensitive signatures. Combining marks
// attached to an ASCII target are intentionally stripped in this projection.
const ASCII_PUNCTUATION_CONFUSABLE_GROUPS = Object.freeze([
  ["ߺ﹍﹎﹏", "_"],
  ["ःઃ：։܃܄᛬︰᠃᠉⁚׃˸꞉∶ːꓽ𑷙", ":"],
  ["⩴", "::="],
  ["𝅭․܁܂꘎𐩐٠۰ꓸ", "."],
  ["‥ꓺ", ".."],
  ["…", "..."],
  ["᜵⁁∕⁄╱⟋⧸𝈺㇓〳ⳇⳆノ丿⼃⧶", "/"],
  ["⫽", "//"],
  ["⫻", "///"],
  ["᛭➕𐊛𞛩⨣⨢⨤∔⨥⨦", "+"],
  ["᐀⹀゠꓿≚≙≗≐≑⮖⩮≞", "="],
  ["⩵", "=="],
  ["⩶", "==="],
]);
const ASCII_PUNCTUATION_CONFUSABLE_MAP = new Map();
for (const [characters, replacement] of ASCII_PUNCTUATION_CONFUSABLE_GROUPS) {
  for (const character of characters) {
    ASCII_PUNCTUATION_CONFUSABLE_MAP.set(character, replacement);
  }
}
const CONFUSABLE_ASSIGNMENT_DELIMITERS = new Map();
for (const character of CONFUSABLE_COLON_CHARACTERS) {
  CONFUSABLE_ASSIGNMENT_DELIMITERS.set(character, ":");
}
for (const character of CONFUSABLE_EQUALS_CHARACTERS) {
  CONFUSABLE_ASSIGNMENT_DELIMITERS.set(character, "=");
}
const EXACT_FIELD_TRAILER = /^[\s"'`’”]*$/u;
const HIGH_ENTROPY_CANDIDATE = /[A-Za-z0-9+/_-]{40,}={0,2}/g;

// Generated from the single-code-point mappings in Unicode UTS #39
// confusables.txt 17.0.0 (2025-07-22). Only mappings whose normalized
// skeleton is ASCII alphanumeric are retained. Keeping exact skeletons avoids
// treating arbitrary localized characters as wildcards.
// https://www.unicode.org/Public/security/latest/confusables.txt
const ASCII_CONFUSABLE_GROUPS = Object.freeze([
  ["⏨", "10"],
  ["ꝚƧϨꙄᒿꛯƻ", "2"],
  ["𝈆३૩ꞫȜƷꝪⲜⳄⳌЗӠ𖼻𑣊Ҙ", "3"],
  ["Ꮞ𑢯", "4"],
  ["Ƽ𑢻", "5"],
  ["ⳓⳒϬⳜбᏮ𑣕", "6"],
  ["𝈒𐓒𑣆", "7"],
  ["৪੪𞣋ȣȢ𐌚", "8"],
  ["੧୨৭൭ꝮⳋⳊ𑣌𑢬𑣖", "9"],
  ["⍺ɑαаΑАᎪᗅꓮ𖽀𐊠⍶", "a"],
  ["ꜳꜲ", "aa"],
  ["æӕÆӔ", "ae"],
  ["ꜵꜴ", "ao"],
  ["🜇", "ar"],
  ["ꜷꜶ", "au"],
  ["ꜹꜻꜸꜺ", "av"],
  ["ꜽꜼ", "ay"],
  ["ƄЬᏏᑲᖯ𖺶ꞴΒⲂВᏴᗷꓐ𐊂𐊡𐌁ɓᑳƃƂБƀҍҌѣѢ", "b"],
  ["Ы", "bl"],
  ["ᴄςⲥсငၚꮯ𐐽🝌𑣩𑣲ΣⲤСᏟꓚ𐊢𐌂𐐕𐔜¢ȼ₡🅮ҫҪ", "c"],
  ["ԁᏧᑯꓒᎠᗞᗪꓓɗɖƌđĐÐƉ₫", "d"],
  ["ʣ", "dz"],
  ["℮ꬲеҽ⋿ΕЕⴹᎬꓰ𑢦𑢮𐊆ɇɆҿ", "e"],
  ["ꬵꞙƒẝք𝈓ꞘϜᖴꓝ𑣂𑢢𐊇𐊥𐔥Ƒᵮ", "f"],
  ["ʩ", "fn"],
  ["ɡᶃƍցԌᏀᏳꓖɠǥǤ", "g"],
  ["һհᏂΗⲎНᎻᕼꓧ𐋏нɦꚕᏲⱧҢħћĦӉӇ", "h"],
  ["⍳ıɪɩιⲓіꙇւꭵᎥ𑣃⍸ɨᵻᵼ", "i"],
  ["ϳјꞲͿЈᎫᒍꓙɉɈ", "j"],
  ["ΚⲔКᏦᛕꓗ𐔘ƙⱩҚ₭ꝀҞ", "k"],
  ["׀∣⏽│١۱𐌠𞣇ƖǀΙⲒІӏӀוןاߊⵏᛁꓲ𖼨𐊊𐌉𑷚𑷡𖺪𝈪ⳐᏞᒪꓡ𖼖𑢣𑢲𐐛𐔦łŁɭƗƚɫٳ", "l"],
  ["‖∥ǁװ𐆙", "ll"],
  ["𐆘", "lls"],
  ["Ю", "lo"],
  ["ʪ", "ls"],
  ["₶", "lt"],
  ["ʫ", "lz"],
  ["ΜϺⲘМᎷᗰᛖꓟ𐊰𐌑Ӎ", "m"],
  ["🝫", "mb"],
  ["ոռΝⲚꓠ𐔓𐆎ɳƞŋηղƝᵰ", "n"],
  ["०০੦૦୦௦౦൦๐໐၀០𑓐٥۵ᴏᴑꬽοσⲟϭоჿօסهھہەഠဝ𐓪𑣈𑣗𐐬߀೦〇𑣠ΟⲞОՕⵔዐଠ𐓂ꓳ𑢵𐊒𐊫𐐄𐔖𑷠ۿøꬾØⵁɵꝋⲑөѳꮎꮻ⊖⊝⍬𝈚🜔ƟꝊθΘⲐӨѲⴱᎾᏫꭴთတ", "o"],
  ["œŒ", "oe"],
  ["∞ꝏꚙꝎꚘ", "oo"],
  ["⍴þƿρϸⲣⳏрΡⲢⳎРᏢᑭꓑ𐊕ƥᵽ", "p"],
  ["ԛգզⵕʠ", "q"],
  ["🜀", "qe"],
  ["ꭇꭈᴦⲅгꮁ𝈖ƦᎡᏒ𐒴ᖇꓣ𖼵ɽɼɍғᵲ", "r"],
  ["𑣣𑜀₥ɱᵯ", "rn"],
  ["ꜱƽѕടꮪ𑣁𐑈ЅՏᏕᏚꓢ𖼺𐊖𐐠ʂᵴ", "s"],
  ["🝜", "sss"],
  ["⊤⟙🝨ΤⲦТᎢꓔ𖼊𑢼𐊗𐊱𐌕ƭ⍡ȾƮҬ₮ŧŦᵵ", "t"],
  ["Ꜩ", "t3"],
  ["ꝷ", "tf"],
  ["ʦ", "ts"],
  ["ꞟᴜꭎꭒʋυս𐓶𑣘∪⋃Սሀ𐓎ᑌꓴ𖽂𑢸џᵾꮜɄᏌ", "u"],
  ["ᵫ", "ue"],
  ["ꭣ", "uo"],
  ["∨⋁ᴠνѵט𑜆ꮩ𑣀𝈍٧۷ѴⴸᏙᐯꛟꓦ𖼈𑢠𐔝𐆗🜈", "v"],
  ["🝬", "vb"],
  ["ɯᴡⲽѡшԝա𑜊𑜎𑜏ꮃ𑣦𑣯ԜᎳᏔꓪѽ𑓅₩ꝡ", "w"],
  ["᙮×⤫⤬⨯хᕁᕽ᙭╳𐌢𑣬ꞳΧⲬХⵝᚷꓫ𐊐𐊴𐌗𐔧⨰Ҳ𐆖", "x"],
  ["ɣᶌʏỿꭚγⲩуүყ𑣜ΥⲨУҮᎩᎽꓬ𖽃𑢤𐊲ƴɏұ¥ɎҰ", "y"],
  ["ᴢꮓ𑣄𑣥𐋵ΖᏃꓜ𑢩ʐƶƵȥȤᵶ", "z"],
]);
// Preserve the original single-code-point sources as well as the normalized
// supplement above. This keeps compatibility-decomposable symbols and newer
// supplementary-plane characters detectable even when the host ICU does not
// classify or normalize them yet.
const ASCII_CONFUSABLE_RAW_GROUPS = Object.freeze([
  ["⏨", "10"],
  ["𜳲𝟐𝟚𝟤𝟮𝟸🯲ꝚƧϨꙄᒿꛯƻ", "2"],
  ["𝈆३૩𜳳𝟑𝟛𝟥𝟯𝟹🯳ꞫȜƷꝪⲜⳄⳌЗӠ𖼻𑣊Ҙ", "3"],
  ["𜳴𝟒𝟜𝟦𝟰𝟺🯴Ꮞ𑢯", "4"],
  ["𜳵𝟓𝟝𝟧𝟱𝟻🯵Ƽ𑢻", "5"],
  ["𜳶𝟔𝟞𝟨𝟲𝟼🯶ⳓⳒϬⳜбᏮ𑣕", "6"],
  ["𝈒𜳷𝟕𝟟𝟩𝟳𝟽🯷𐓒𑣆", "7"],
  ["ଃ৪੪𞣋𜳸𝟖𝟠𝟪𝟴𝟾🯸ȣȢ𐌚", "8"],
  ["੧୨৭൭𜳹𝟗𝟡𝟫𝟵𝟿🯹ꝮⳋⳊ𑣌𑢬𑣖", "9"],
  ["⍺ａ𝐚𝑎𝒂𝒶𝓪𝔞𝕒𝖆𝖺𝗮𝘢𝙖𝚊ɑα𝛂𝛼𝜶𝝰𝞪аＡ𜳖𝐀𝐴𝑨𝒜𝓐𝔄𝔸𝕬𝖠𝗔𝘈𝘼𝙰Α𝚨𝛢𝜜𝝖𝞐АᎪᗅꓮ𖽀𐊠⍶ǎǍȧȦẚ", "a"],
  ["ꜳꜲ", "aa"],
  ["æӕÆӔ", "ae"],
  ["ꜵꜴ", "ao"],
  ["🜇", "ar"],
  ["ꜷꜶ", "au"],
  ["ꜹꜻꜸꜺ", "av"],
  ["ꜽꜼ", "ay"],
  ["𝐛𝑏𝒃𝒷𝓫𝔟𝕓𝖇𝖻𝗯𝘣𝙗𝚋ƄЬᏏᑲᖯ𖺶Ｂℬ𜳗𝐁𝐵𝑩𝓑𝔅𝔹𝕭𝖡𝗕𝘉𝘽𝙱ꞴΒ𝚩𝛣𝜝𝝗𝞑ⲂВᏴᗷꓐ𐊂𐊡𐌁ɓᑳƃƂБƀҍҌѣѢ", "b"],
  ["Ы", "bl"],
  ["ｃⅽ𝐜𝑐𝒄𝒸𝓬𝔠𝕔𝖈𝖼𝗰𝘤𝙘𝚌ᴄϲⲥсငၚꮯ𐐽🝌𑣩𑣲ＣⅭℂℭ𜳘𝐂𝐶𝑪𝒞𝓒𝕮𝖢𝗖𝘊𝘾𝙲ϹⲤСᏟꓚ𐊢𐌂𐐕𐔜¢ȼ₡🅮çҫÇҪ", "c"],
  ["ⅾⅆ𝐝𝑑𝒅𝒹𝓭𝔡𝕕𝖉𝖽𝗱𝘥𝙙𝚍ԁᏧᑯꓒⅮⅅ𜳙𝐃𝐷𝑫𝒟𝓓𝔇𝔻𝕯𝖣𝗗𝘋𝘿𝙳ᎠᗞᗪꓓɗɖƌđĐÐƉ₫", "d"],
  ["ǳʣǲǱǆǅǄ", "dz"],
  ["℮ｅℯⅇ𝐞𝑒𝒆𝓮𝔢𝕖𝖊𝖾𝗲𝘦𝙚𝚎ꬲеҽ⋿Ｅℰ𜳚𝐄𝐸𝑬𝓔𝔈𝔼𝕰𝖤𝗘𝘌𝙀𝙴Ε𝚬𝛦𝜠𝝚𝞔ЕⴹᎬꓰ𑢦𑢮𐊆ěĚɇɆҿ", "e"],
  ["𝐟𝑓𝒇𝒻𝓯𝔣𝕗𝖋𝖿𝗳𝘧𝙛𝚏ꬵꞙƒſẝք𝈓ℱ𜳛𝐅𝐹𝑭𝓕𝔉𝔽𝕱𝖥𝗙𝘍𝙁𝙵ꞘϜ𝟊ᖴꓝ𑣂𑢢𐊇𐊥𐔥Ƒᵮ", "f"],
  ["℻", "fax"],
  ["ﬀ", "ff"],
  ["ﬃ", "ffi"],
  ["ﬄ", "ffl"],
  ["ﬁ", "fi"],
  ["ﬂ", "fl"],
  ["ʩ", "fn"],
  ["ｇℊ𝐠𝑔𝒈𝓰𝔤𝕘𝖌𝗀𝗴𝘨𝙜𝚐ɡᶃƍց𜳜𝐆𝐺𝑮𝒢𝓖𝔊𝔾𝕲𝖦𝗚𝘎𝙂𝙶ԌᏀᏳꓖᶢɠǧǦǵǥǤ", "g"],
  ["ｈℎ𝐡𝒉𝒽𝓱𝔥𝕙𝖍𝗁𝗵𝘩𝙝𝚑һհᏂＨℋℌℍ𜳝𝐇𝐻𝑯𝓗𝕳𝖧𝗛𝘏𝙃𝙷Η𝚮𝛨𝜢𝝜𝞖ⲎНᎻᕼꓧ𐋏ᵸɦꚕᏲⱧҢħℏћĦӉӇ", "h"],
  ["˛⍳ｉⅰℹⅈ𝐢𝑖𝒊𝒾𝓲𝔦𝕚𝖎𝗂𝗶𝘪𝙞𝚒ı𝚤ɪɩιιͺ𝛊𝜄𝜾𝝸𝞲ⲓіꙇւꭵᎥ𑣃ⓛ⍸ǐǏɨᵻᵼ", "i"],
  ["ⅱ", "ii"],
  ["ⅲ", "iii"],
  ["ĳ", "ij"],
  ["ⅳ", "iv"],
  ["ⅸ", "ix"],
  ["ｊⅉ𝐣𝑗𝒋𝒿𝓳𝔧𝕛𝖏𝗃𝗷𝘫𝙟𝚓ϳјＪ𜳟𝐉𝐽𝑱𝒥𝓙𝔍𝕁𝕵𝖩𝗝𝘑𝙅𝙹ꞲͿЈᎫᒍꓙɉɈ", "j"],
  ["𝐤𝑘𝒌𝓀𝓴𝔨𝕜𝖐𝗄𝗸𝘬𝙠𝚔KＫ𜳠𝐊𝐾𝑲𝒦𝓚𝔎𝕂𝕶𝖪𝗞𝘒𝙆𝙺Κ𝚱𝛫𝜥𝝟𝞙ⲔКᏦᛕꓗ𐔘ƙⱩҚ₭ꝀҞ", "k"],
  ["׀|∣⏽￨1١۱𐌠𞣇𜳱𝟏𝟙𝟣𝟭𝟷🯱IＩⅠℐℑ𜳞𝐈𝐼𝑰𝓘𝕀𝕴𝖨𝗜𝘐𝙄𝙸Ɩｌⅼℓ𝐥𝑙𝒍𝓁𝓵𝔩𝕝𝖑𝗅𝗹𝘭𝙡𝚕ǀΙ𝚰𝛪𝜤𝝞𝞘ⲒІӏӀוןا𞸀𞺀ﺎﺍߊⵏᛁꓲ𖼨𐊊𐌉𑷚𑷡𖺪𝈪Ⅼℒ𜳡𝐋𝐿𝑳𝓛𝔏𝕃𝕷𝖫𝗟𝘓𝙇𝙻ⳐᏞᒪꓡ𖼖𑢣𑢲𐐛𐔦ﴼﴽłŁɭƗƚɫإﺈﺇٳ", "l"],
  ["ǉĲǈǇ", "lj"],
  ["‖∥Ⅱǁװ𐆙", "ll"],
  ["Ⅲ", "lll"],
  ["𐆘", "lls"],
  ["Ю", "lo"],
  ["ʪ", "ls"],
  ["₶", "lt"],
  ["Ⅳ", "lv"],
  ["Ⅸ", "lx"],
  ["ʫ", "lz"],
  ["ＭⅯℳ𜳢𝐌𝑀𝑴𝓜𝔐𝕄𝕸𝖬𝗠𝘔𝙈𝙼Μ𝚳𝛭𝜧𝝡𝞛ϺⲘМᎷᗰᛖꓟ𐊰𐌑Ӎ", "m"],
  ["🝫", "mb"],
  ["𝐧𝑛𝒏𝓃𝓷𝔫𝕟𝖓𝗇𝗻𝘯𝙣𝚗ոռＮℕ𜳣𝐍𝑁𝑵𝒩𝓝𝔑𝕹𝖭𝗡𝘕𝙉𝙽Ν𝚴𝛮𝜨𝝢𝞜Ⲛꓠ𐔓𐆎ɳƞŋη𝛈𝜂𝜼𝝶𝞰ղƝᵰ", "n"],
  ["ǌǋǊ", "nj"],
  ["№", "no"],
  ["ంಂംං०০੦૦୦௦౦൦๐໐၀០𑓐٥۵ｏℴ𝐨𝑜𝒐𝓸𝔬𝕠𝖔𝗈𝗼𝘰𝙤𝚘ᴏᴑꬽο𝛐𝜊𝝄𝝾𝞸σ𝛔𝜎𝝈𝞂𝞼ⲟϭоჿօסه𞸤𞹤𞺄ﻫﻬﻪﻩھﮬﮭﮫﮪہﮨﮩﮧﮦەഠဝ𐓪𑣈𑣗𐐬0߀೦〇𑣠𜳰𝟎𝟘𝟢𝟬𝟶🯰Ｏ𜳤𝐎𝑂𝑶𝒪𝓞𝔒𝕆𝕺𝖮𝗢𝘖𝙊𝙾Ο𝚶𝛰𝜪𝝤𝞞ⲞОՕⵔዐଠ𐓂ꓳ𑢵𐊒𐊫𐐄𐔖𑷠⁰ᵒǒǑۿŐøꬾØⵁǾɵꝋⲑөѳꮎꮻ⊖⊝⍬𝈚🜔ƟꝊθϑ𝛉𝛝𝜃𝜗𝜽𝝑𝝷𝞋𝞱𝟅Θϴ𝚯𝚹𝛩𝛳𝜣𝜭𝝝𝝧𝞗𝞡ⲐӨѲⴱᎾᏫꭴﳙთတ", "o"],
  ["œŒ", "oe"],
  ["∞ꝏꚙꝎꚘ", "oo"],
  ["⍴ｐ𝐩𝑝𝒑𝓅𝓹𝔭𝕡𝖕𝗉𝗽𝘱𝙥𝚙þƿρϱ𝛒𝛠𝜌𝜚𝝆𝝔𝞀𝞎𝞺𝟈ϸⲣⳏрＰℙ𜳥𝐏𝑃𝑷𝒫𝓟𝔓𝕻𝖯𝗣𝘗𝙋𝙿Ρ𝚸𝛲𝜬𝝦𝞠ⲢⳎРᏢᑭꓑ𐊕ƥᵽ", "p"],
  ["𝐪𝑞𝒒𝓆𝓺𝔮𝕢𝖖𝗊𝗾𝘲𝙦𝚚ԛգզℚ𜳦𝐐𝑄𝑸𝒬𝓠𝔔𝕼𝖰𝗤𝘘𝙌𝚀ⵕʠ", "q"],
  ["🜀", "qe"],
  ["𝐫𝑟𝒓𝓇𝓻𝔯𝕣𝖗𝗋𝗿𝘳𝙧𝚛ꭇꭈᴦⲅгꮁ𝈖ℛℜℝ𜳧𝐑𝑅𝑹𝓡𝕽𝖱𝗥𝘙𝙍𝚁ƦᎡᏒ𐒴ᖇꓣ𖼵ɽɼɍғᵲ", "r"],
  ["𑣣mⅿ𝐦𝑚𝒎𝓂𝓶𝔪𝕞𝖒𝗆𝗺𝘮𝙢𝚖𑜀₥ɱᵯ", "rn"],
  ["₨", "rs"],
  ["ｓ𝐬𝑠𝒔𝓈𝓼𝔰𝕤𝖘𝗌𝘀𝘴𝙨𝚜ꜱƽѕടꮪ𑣁𐑈Ｓ𜳨𝐒𝑆𝑺𝒮𝓢𝔖𝕊𝕾𝖲𝗦𝘚𝙎𝚂ЅՏᏕᏚꓢ𖼺𐊖𐐠ʂᵴ", "s"],
  ["🝜", "sss"],
  ["ﬆ", "st"],
  ["𝐭𝑡𝒕𝓉𝓽𝔱𝕥𝖙𝗍𝘁𝘵𝙩𝚝⊤⟙🝨Ｔ𜳩𝐓𝑇𝑻𝒯𝓣𝔗𝕋𝕿𝖳𝗧𝘛𝙏𝚃Τ𝚻𝛵𝜯𝝩𝞣ⲦТᎢꓔ𖼊𑢼𐊗𐊱𐌕ƭ⍡ȾȚƮҬ₮ŧŦᵵ", "t"],
  ["Ꜩ", "t3"],
  ["℡", "tel"],
  ["ꝷ", "tf"],
  ["ʦ", "ts"],
  ["𝐮𝑢𝒖𝓊𝓾𝔲𝕦𝖚𝗎𝘂𝘶𝙪𝚞ꞟᴜꭎꭒʋυ𝛖𝜐𝝊𝞄𝞾ս𐓶𑣘∪⋃𜳪𝐔𝑈𝑼𝒰𝓤𝔘𝕌𝖀𝖴𝗨𝘜𝙐𝚄Սሀ𐓎ᑌꓴ𖽂𑢸ǔǓџᵾꮜɄᏌ", "u"],
  ["ᵫ", "ue"],
  ["ꭣ", "uo"],
  ["∨⋁ｖⅴ𝐯𝑣𝒗𝓋𝓿𝔳𝕧𝖛𝗏𝘃𝘷𝙫𝚟ᴠν𝛎𝜈𝝂𝝼𝞶ѵט𑜆ꮩ𑣀𝈍٧۷Ⅴ𜳫𝐕𝑉𝑽𝒱𝓥𝔙𝕍𝖁𝖵𝗩𝘝𝙑𝚅ѴⴸᏙᐯꛟꓦ𖼈𑢠𐔝𐆗🜈", "v"],
  ["🝬", "vb"],
  ["ⅵ", "vi"],
  ["ⅶ", "vii"],
  ["ⅷ", "viii"],
  ["Ⅵ", "vl"],
  ["Ⅶ", "vll"],
  ["Ⅷ", "vlll"],
  ["ɯ𝐰𝑤𝒘𝓌𝔀𝔴𝕨𝖜𝗐𝘄𝘸𝙬𝚠ᴡⲽѡшԝա𑜊𑜎𑜏ꮃ𑣦𑣯𜳬𝐖𝑊𝑾𝒲𝓦𝔚𝕎𝖂𝖶𝗪𝘞𝙒𝚆ԜᎳᏔꓪѽ𑓅₩ꝡ", "w"],
  ["᙮×⤫⤬⨯ｘⅹ𝐱𝑥𝒙𝓍𝔁𝔵𝕩𝖝𝗑𝘅𝘹𝙭𝚡хᕁᕽ᙭╳𐌢𑣬ＸⅩ𜳭𝐗𝑋𝑿𝒳𝓧𝔛𝕏𝖃𝖷𝗫𝘟𝙓𝚇ꞳΧ𝚾𝛸𝜲𝝬𝞦ⲬХⵝᚷꓫ𐊐𐊴𐌗𐔧⨰Ҳ𐆖", "x"],
  ["ⅺ", "xi"],
  ["ⅻ", "xii"],
  ["Ⅺ", "xl"],
  ["Ⅻ", "xll"],
  ["ɣᶌｙ𝐲𝑦𝒚𝓎𝔂𝔶𝕪𝖞𝗒𝘆𝘺𝙮𝚢ʏỿꭚγℽ𝛄𝛾𝜸𝝲𝞬ⲩуүყ𑣜Ｙ𜳮𝐘𝑌𝒀𝒴𝓨𝔜𝕐𝖄𝖸𝗬𝘠𝙔𝚈Υϒ𝚼𝛶𝜰𝝪𝞤ⲨУҮᎩᎽꓬ𖽃𑢤𐊲ƴɏұ¥ɎҰ", "y"],
  ["𝐳𝑧𝒛𝓏𝔃𝔷𝕫𝖟𝗓𝘇𝘻𝙯𝚣ᴢꮓ𑣄𑣥𐋵Ｚℤℨ𜳯𝐙𝑍𝒁𝒵𝓩𝖅𝖹𝗭𝘡𝙕𝚉Ζ𝚭𝛧𝜡𝝛𝞕Ꮓꓜ𑢩ʐƶƵȥȤᵶ", "z"],
]);
// Field normalization discards ASCII punctuation. Preserve the matching UTS
// prototypes that wrap an alphanumeric skeleton in apostrophes, parentheses,
// dots, slashes, or other ASCII punctuation so the token boundary cannot erase
// their meaningful letter or number.
const ASCII_CONFUSABLE_WRAPPED_GROUPS = Object.freeze([
  ["⑵⨧🄃⒉", "2"], ["⒇⒛", "2o"], ["⑶🄄⒊", "3"], ["⑷🄅⒋", "4"],
  ["⑸🄆⒌", "5"], ["⑹🄇⒍", "6"], ["⑺🄈⒎", "7"], ["⑻🄉⒏", "8"],
  ["⑼🄊⒐", "9"], ["⒜🄐", "a"], ["℀", "ac"], ["℁", "as"],
  ["Ɓ⒝🄑ᒈ", "b"], ["⒞🄒Ƈ", "c"], ["℅", "co"], ["℆", "cu"],
  ["Ɗ⒟🄓ᒇ", "d"], ["⒠🄔", "e"], ["⒡🄕", "f"], ["⒢🄖Ɠ", "g"],
  ["⒣🄗", "h"], ["⒤", "i"], ["⒥🄙", "j"], ["⒦🄚Ƙ", "k"],
  ["⑴🄘⒧🄛🄂⒈ױ", "l"], ["⑿⒓", "l2"], ["⒀⒔", "l3"],
  ["⒁⒕", "l4"], ["⒂⒖", "l5"], ["⒃⒗", "l6"], ["⒄⒘", "l7"],
  ["⒅⒙", "l8"], ["⒆⒚", "l9"], ["⑾⒒", "ll"], ["⑽⒑", "lo"],
  ["🄜", "m"], ["ŉ⒩🄝", "n"], ["⒪🄞🄁🄀ơƠᎤ", "o"],
  ["%٪⁒", "o0"], ["‰؉", "o00"], ["‱؊", "o000"],
  ["Ƥ⒫🄟ᒆ", "p"], ["⒬🄠", "q"], ["⒭🄡ґ", "r"], ["⒨", "rn"],
  ["⒮🄢🄪", "s"], ["Ƭ⒯🄣", "t"], ["⒰🄤ᑧ", "u"], ["⒱🄥", "v"],
  ["⒲🄦", "w"], ["⒳🄧", "x"], ["Ƴ⒴🄨", "y"], ["⒵🄩", "z"],
  ["ᔯᔰ", "4"], ["ᑾᒀᑿᒁ", "b"], ["℃", "c"], ["🅭", "cc"],
  ["ᑺᑻ", "d"], ["℉", "f"], ["ᒘᒙ", "j"], ["ᒶŀĿᒷ", "l"],
  ["ᑶᑷ", "p"], ["ᑗᑘ", "u"], ["ᐺᐻ", "v"],
]);
const ASCII_CONFUSABLE_MAP = new Map();
for (const groups of [
  ASCII_CONFUSABLE_GROUPS,
  ASCII_CONFUSABLE_RAW_GROUPS,
  ASCII_CONFUSABLE_WRAPPED_GROUPS,
]) {
  for (const [characters, replacement] of groups) {
    for (const character of characters) ASCII_CONFUSABLE_MAP.set(character, replacement);
  }
}
// UTS #39 maps lowercase Greek epsilon to an open-e skeleton rather than ASCII
// `e`. Preserve the earlier privacy policy's stricter `secrεt` rejection as a
// one-character extension without replacing any other official mapping.
ASCII_CONFUSABLE_MAP.set("ε", "e");
// Generated by enumerating every non-letter/number/mark Unicode scalar whose
// NFKD decomposition is entirely ASCII and still contains an alphanumeric
// character after field punctuation is erased. These compatibility symbols
// must remain visible to ambiguous plain-text field analysis even though they
// are outside the base Unicode token categories.
const NFKD_ASCII_COMPATIBILITY_TOKEN_CHARACTERS = (
  "₨℀℁℅℆№℠℡™℻⒜⒝⒞⒟⒠⒡⒢⒣⒤⒥⒦⒧⒨⒩⒪⒫⒬⒭⒮⒯⒰⒱⒲⒳⒴⒵" +
  "ⒶⒷⒸⒹⒺⒻⒼⒽⒾⒿⓀⓁⓂⓃⓄⓅⓆⓇⓈⓉⓊⓋⓌⓍⓎⓏⓐⓑⓒⓓⓔⓕⓖⓗⓘⓙⓚⓛⓜⓝⓞⓟⓠⓡⓢⓣⓤⓥⓦⓧⓨⓩ" +
  "㉐㋌㋍㋎㋏㍱㍲㍳㍴㍵㍶㍷㍸㍹㍺㎀㎁㎃㎄㎅㎆㎇㎈㎉㎊㎋㎎㎏㎐㎑㎒㎓㎔㎖㎗㎘㎙㎚㎜㎝㎞㎟" +
  "㎠㎡㎢㎣㎤㎥㎦㎩㎪㎫㎬㎭㎰㎱㎳㎴㎵㎷㎸㎹㎺㎻㎽㎾㎿㏂㏃㏄㏅㏇㏈㏉㏊㏋㏌㏍" +
  "㏎㏏㏐㏑㏒㏓㏔㏕㏖㏗㏘㏙㏚㏛㏜㏝㏿𜳖𜳗𜳘𜳙𜳚𜳛𜳜𜳝𜳞𜳟𜳠𜳡𜳢𜳣" +
  "𜳤𜳥𜳦𜳧𜳨𜳩𜳪𜳫𜳬𜳭𜳮𜳯🄐🄑🄒🄓🄔🄕🄖🄗🄘🄙🄚🄛🄜🄝🄞🄟🄠🄡🄢🄣🄤🄥🄦🄧🄨🄩" +
  "🄫🄬🄭🄮🄰🄱🄲🄳🄴🄵🄶🄷🄸🄹🄺🄻🄼🄽🄾🄿🅀🅁🅂🅃🅄🅅🅆🅇🅈🅉🅊🅋🅌🅍🅎🅏🅪🅫🅬🆐"
);
const CONFUSABLE_TOKEN_CHARACTERS = [
  ...ASCII_CONFUSABLE_MAP.keys(),
  ...CONFUSABLE_COLON_CHARACTERS,
  ...CONFUSABLE_EQUALS_CHARACTERS,
  ...NFKD_ASCII_COMPATIBILITY_TOKEN_CHARACTERS,
]
  .filter((character) => !/[\p{L}\p{N}]/u.test(character))
  .join("")
  .replace(/[\\\][\^-]/g, "\\$&");
const ASSIGNMENT_TOKEN_PATTERN = new RegExp(
  `[\\p{L}\\p{N}\\p{M}_.\\-${CONFUSABLE_TOKEN_CHARACTERS}]+`,
  "gu"
);

function fail(message) {
  throw new Error(message);
}

const MAX_JSON_EVIDENCE_DEPTH = 64;

function parseJsonWithoutDuplicateKeys(source) {
  // Let the platform parser establish complete JSON syntax first. The second,
  // linear pass retains raw object-key occurrences that JSON.parse would
  // otherwise silently overwrite, including escaped aliases such as
  // `"rea\\u0073on"` and `"reason"`.
  const parsed = JSON.parse(source);
  let index = 0;

  const skipWhitespace = () => {
    while (index < source.length && /\s/.test(source[index])) index += 1;
  };
  const scanString = () => {
    const start = index;
    index += 1;
    while (index < source.length) {
      if (source[index] === "\\") {
        index += 2;
        continue;
      }
      if (source[index] === '"') {
        index += 1;
        return JSON.parse(source.slice(start, index));
      }
      index += 1;
    }
    fail("invalid JSON string while checking duplicate keys");
  };
  const scanPrimitive = () => {
    const start = index;
    while (index < source.length && !/[\s,\]}]/.test(source[index])) index += 1;
    const token = source.slice(start, index);
    if (/^-?(?:0|[1-9][0-9]*)(?:\.[0-9]+)?(?:[eE][+-]?[0-9]+)?$/u.test(token)) {
      const decimalDigits = token.match(/[0-9]/g) ?? [];
      if (decimalDigits.length >= 15) {
        fail("unsafe generic decimal identifier detected before evidence projection");
      }
    }
  };
  const scanValue = (depth) => {
    if (depth > MAX_JSON_EVIDENCE_DEPTH) fail("JSON evidence nesting exceeds the safe bound");
    skipWhitespace();
    if (source[index] === "{") {
      index += 1;
      skipWhitespace();
      const keys = new Set();
      if (source[index] === "}") {
        index += 1;
        return;
      }
      while (index < source.length) {
        const key = scanString();
        if (keys.has(key)) fail("duplicate JSON object key");
        keys.add(key);
        skipWhitespace();
        index += 1; // JSON.parse already proved this is the key/value colon.
        scanValue(depth + 1);
        skipWhitespace();
        if (source[index] === "}") {
          index += 1;
          return;
        }
        index += 1; // JSON.parse already proved this is the member comma.
        skipWhitespace();
      }
      fail("invalid JSON object while checking duplicate keys");
    }
    if (source[index] === "[") {
      index += 1;
      skipWhitespace();
      if (source[index] === "]") {
        index += 1;
        return;
      }
      while (index < source.length) {
        scanValue(depth + 1);
        skipWhitespace();
        if (source[index] === "]") {
          index += 1;
          return;
        }
        index += 1; // JSON.parse already proved this is the element comma.
        skipWhitespace();
      }
      fail("invalid JSON array while checking duplicate keys");
    }
    if (source[index] === '"') {
      scanString();
      return;
    }
    scanPrimitive();
  };

  scanValue(0);
  skipWhitespace();
  if (index !== source.length) fail("invalid trailing JSON evidence content");
  return parsed;
}

function sha256(value) {
  return crypto.createHash("sha256").update(value).digest("hex");
}

function shannonEntropy(value) {
  const symbols = [...value];
  const counts = new Map();
  for (const character of symbols) counts.set(character, (counts.get(character) ?? 0) + 1);
  return [...counts.values()].reduce((entropy, count) => {
    const probability = count / symbols.length;
    return entropy - (probability * Math.log2(probability));
  }, 0);
}

function normalizeFieldName(field) {
  return field.normalize("NFKC").replace(/[^a-z0-9]/gi, "").toLowerCase();
}

function isSensitiveNormalizedFieldName(normalizedField, { includeExactContent = true } = {}) {
  if (!normalizedField) return false;
  if (includeExactContent && EXACT_SENSITIVE_CONTENT_FIELDS.has(normalizedField)) return true;
  if (
    normalizedField.includes("authorization") ||
    normalizedField.includes("appcheck") ||
    normalizedField.includes("token") ||
    normalizedField.includes("secret") ||
    normalizedField.includes("credential") ||
    normalizedField.includes("key") ||
    normalizedField.includes("jws") ||
    normalizedField.includes("jwt") ||
    normalizedField.includes("password") ||
    normalizedField.includes("passphrase") ||
    normalizedField.includes("displayname")
  ) {
    return true;
  }
  if (
    normalizedField.includes("transaction") &&
    (normalizedField.includes("id") || normalizedField.includes("payload"))
  ) {
    return true;
  }
  if (normalizedField.includes("storekit") && normalizedField.includes("payload")) return true;
  if (normalizedField.includes("image") || normalizedField.includes("photo")) return true;
  return (
    (normalizedField.includes("meal") || normalizedField.includes("food")) &&
    (normalizedField.includes("name") || normalizedField.includes("title"))
  );
}

function isSensitiveFieldName(field) {
  if (/[^\x00-\x7f]/u.test(field)) return true;
  return isSensitiveNormalizedFieldName(normalizeFieldName(field));
}

function fieldConfusableSkeleton(field) {
  const canonicalize = (value) => {
    let current = value.toLowerCase();
    for (let pass = 0; pass < 4; pass += 1) {
      const next = [...current]
        .map((character) => ASCII_CONFUSABLE_MAP.get(character) ?? character)
        .join("")
        .toLowerCase();
      if (next === current) return current;
      current = next;
    }
    fail("confusable skeleton did not converge");
  };

  return [...field].map((sourceCharacter) => {
    const direct = ASCII_CONFUSABLE_MAP.get(sourceCharacter);
    if (direct !== undefined) return canonicalize(direct);
    return [...sourceCharacter.normalize("NFKD").replace(/\p{M}/gu, "")]
      .map((character) => {
        const mapped = ASCII_CONFUSABLE_MAP.get(character);
        if (mapped !== undefined) return canonicalize(mapped);
        if (/[A-Za-z0-9]/.test(character)) return character.toLowerCase();
        return character;
      })
      .join("");
  }).join("");
}

function wholeTextConfusableSkeleton(value) {
  return [...value].map((sourceCharacter) => {
    if (UUID_DASH_CONFUSABLES.has(sourceCharacter)) return "-";
    if (/^[\x00-\x7f]$/.test(sourceCharacter)) return sourceCharacter;
    const punctuation = ASCII_PUNCTUATION_CONFUSABLE_MAP.get(sourceCharacter);
    if (punctuation !== undefined) return punctuation;
    const direct = ASCII_CONFUSABLE_MAP.get(sourceCharacter);
    if (direct !== undefined) return direct;
    return [...sourceCharacter.normalize("NFKD").replace(/\p{M}/gu, "")]
      .map((character) => {
        if (/^[\x00-\x7f]$/.test(character)) return character;
        return ASCII_CONFUSABLE_MAP.get(character) ?? character;
      })
      .join("");
  }).join("");
}

function isSensitiveConfusableNormalizedFieldName(normalizedField, { includeExactContent = true } = {}) {
  if (!normalizedField) return false;
  if (includeExactContent && EXACT_SENSITIVE_CONTENT_FIELDS.has(normalizedField)) return true;
  const has = (field) => normalizedField.includes(
    normalizeFieldName(fieldConfusableSkeleton(field))
  );
  if (
    has("authorization") ||
    has("appcheck") ||
    has("token") ||
    has("secret") ||
    has("credential") ||
    has("key") ||
    has("jws") ||
    has("jwt") ||
    has("password") ||
    has("passphrase") ||
    has("displayname")
  ) {
    return true;
  }
  if (has("transaction") && (has("id") || has("payload"))) return true;
  if (has("storekit") && has("payload")) return true;
  if (has("image") || has("photo")) return true;
  return (has("meal") || has("food")) && (has("name") || has("title"));
}

function isSensitiveFieldPath(path) {
  const rawField = path.at(-1);
  if (typeof rawField !== "string") return false;
  if (isSensitiveFieldName(rawField)) return true;
  const confusablePath = path
    .filter((part) => typeof part === "string")
    .map(fieldConfusableSkeleton)
    .join(" ");
  if (isSensitiveConfusableNormalizedFieldName(normalizeFieldName(confusablePath))) return true;
  const normalizedPath = path
    .filter((part) => typeof part === "string")
    .map(normalizeFieldName)
    .filter(Boolean);
  const leaf = normalizedPath.at(-1) ?? "";
  const ancestors = normalizedPath.slice(0, -1);
  const ancestorIncludes = (value) => ancestors.some((ancestor) => ancestor.includes(value));
  if (
    (leaf.includes("name") || leaf.includes("title")) &&
    (ancestorIncludes("meal") || ancestorIncludes("food"))
  ) {
    return true;
  }
  if (
    (leaf.includes("id") || leaf.includes("payload")) &&
    ancestorIncludes("transaction")
  ) {
    return true;
  }
  return leaf.includes("payload") && ancestorIncludes("storekit");
}

function isValidTimestamp(value) {
  return (
    typeof value === "string" &&
    /^\d{4}-\d{2}-\d{2}T\d{2}:\d{2}:\d{2}(?:\.\d{1,9})?Z$/.test(value) &&
    Number.isFinite(Date.parse(value))
  );
}

function envelopePathEquals(path, ...expected) {
  const metadataPath = typeof path[0] === "number" ? path.slice(1) : path;
  return metadataPath.length === expected.length &&
    metadataPath.every((part, index) => part === expected[index]);
}

function envelopeMetadataValidator(path) {
  const exact = (expected) => (value) => value === expected;
  const isPath = (...expected) => envelopePathEquals(path, ...expected);
  if (isPath("logName")) return (value) => new RegExp(
    `^projects/${PINNED_PROJECT_ID}/logs/run\\.googleapis\\.com%2F(?:stdout|stderr)$`
  ).test(value);
  if (isPath("trace")) return (value) => new RegExp(
    `^projects/${PINNED_PROJECT_ID}/traces/[a-f0-9]{32}$`
  ).test(value);
  if (isPath("insertId")) {
    return (value) => typeof value === "string" && /^[A-Za-z0-9_-]{1,64}$/.test(value);
  }
  if (isPath("severity")) return exact("INFO");
  if (isPath("timestamp") || isPath("receiveTimestamp")) return isValidTimestamp;
  if (isPath("resource", "type")) return exact("cloud_run_revision");
  if (isPath("resource", "labels", "project_id")) return exact(PINNED_PROJECT_ID);
  if (isPath("resource", "labels", "service_name") || isPath("resource", "labels", "configuration_name")) {
    return exact(PINNED_SERVICE_NAME);
  }
  if (isPath("resource", "labels", "revision_name")) {
    return (value) => new RegExp(`^${PINNED_SERVICE_NAME}-[0-9]{5}-[a-z0-9]{3}$`).test(value);
  }
  if (isPath("resource", "labels", "location")) return exact(PINNED_LOCATION);
  if (isPath("labels", "instanceId")) {
    return (value) => typeof value === "string" && HEX_64.test(value);
  }
  return null;
}

function rejectUnsafeInsertId(value) {
  if (typeof value !== "string") fail("invalid Cloud Logging insert ID");
  if (SENSITIVE_TEXT_PATTERNS.some((pattern) => pattern.test(value))) {
    fail("unsafe Cloud Logging insert ID");
  }
  if ([...value.matchAll(LONG_DECIMAL_IDENTIFIER)].length > 0) {
    fail("unsafe Cloud Logging insert ID");
  }
  if ([...value.matchAll(DASHED_HEX_IDENTIFIER)].length > 0) {
    fail("unsafe Cloud Logging insert ID");
  }
  if ([...value.matchAll(CONTIGUOUS_HEX_IDENTIFIER)].length > 0) {
    fail("unsafe Cloud Logging insert ID");
  }
  rejectHighEntropyText(value);
}

function isAllowedCanonicalRange(match, allowedCanonicalRanges) {
  const start = match.index;
  const end = start + match[0].length;
  return allowedCanonicalRanges.has(`${start}:${end}`);
}

function isContainedInAllowedCanonicalRange(match, allowedCanonicalRanges) {
  const start = match.index;
  const end = start + match[0].length;
  for (const range of allowedCanonicalRanges) {
    const [allowedStart, allowedEnd] = range.split(":").map(Number);
    if (start >= allowedStart && end <= allowedEnd) return true;
  }
  return false;
}

function maskAllowedCanonicalRanges(value, allowedCanonicalRanges) {
  if (allowedCanonicalRanges.size === 0) return value;
  const ranges = [...allowedCanonicalRanges].map((range) => {
    const [start, end] = range.split(":").map(Number);
    if (!Number.isSafeInteger(start) || !Number.isSafeInteger(end) || start < 0 || end < start) {
      fail("invalid canonical range");
    }
    return { start, end };
  }).sort((left, right) => left.start - right.start);
  const chunks = [];
  let cursor = 0;
  for (const range of ranges) {
    if (range.start < cursor || range.end > value.length) fail("invalid canonical range");
    chunks.push(value.slice(cursor, range.start), " ".repeat(range.end - range.start));
    cursor = range.end;
  }
  chunks.push(value.slice(cursor));
  return chunks.join("");
}

function rejectHighEntropyText(value, allowedCanonicalRanges = new Set()) {
  for (const match of value.matchAll(HIGH_ENTROPY_CANDIDATE)) {
    const candidate = match[0];
    if (HEX_64.test(candidate)) {
      if (isAllowedCanonicalRange(match, allowedCanonicalRanges)) continue;
      fail("unsafe generic 64-hex content detected before evidence projection");
    }
    if (shannonEntropy(candidate) >= 4.2) {
      fail("unsafe high-entropy content detected before evidence projection");
    }
  }
}

function rejectConfusableSourceEntropy(value) {
  let span = [];
  const flush = () => {
    if (span.length >= 40 && shannonEntropy(span.join("")) >= 4.2) {
      fail("unsafe high-entropy confusable source content detected before evidence projection");
    }
    span = [];
  };

  for (const sourceCharacter of value) {
    if (/\p{M}/u.test(sourceCharacter)) continue;
    const projected = wholeTextConfusableSkeleton(sourceCharacter.normalize("NFKC"));
    if (projected !== "" && /^[A-Za-z0-9+/_-]+$/.test(projected)) {
      span.push(sourceCharacter);
    } else {
      flush();
    }
  }
  flush();
}

function rejectGenericIdentifiers(value, allowedCanonicalRanges) {
  for (const match of value.matchAll(LONG_DECIMAL_IDENTIFIER)) {
    if (/^[0-9]+$/.test(match[0]) && isContainedInAllowedCanonicalRange(match, allowedCanonicalRanges)) {
      continue;
    }
    fail("unsafe generic decimal identifier detected before evidence projection");
  }
  if ([...value.matchAll(DASHED_HEX_IDENTIFIER)].length > 0) {
    fail("unsafe generic dashed identifier detected before evidence projection");
  }
  for (const match of value.matchAll(CONTIGUOUS_HEX_IDENTIFIER)) {
    if (match[0].length === 64 && isAllowedCanonicalRange(match, allowedCanonicalRanges)) continue;
    fail("unsafe generic contiguous hex identifier detected before evidence projection");
  }
}

function maskAnsiEscapeSequences(value) {
  const replacements = [];
  let insideOsc = false;

  for (let index = 0; index < value.length; index += 1) {
    if (insideOsc) {
      if (value.charCodeAt(index) === 0x07) {
        replacements.push({ start: index, end: index + 1 });
        insideOsc = false;
      } else if (value.charCodeAt(index) === 0x1b && value[index + 1] === "\\") {
        replacements.push({ start: index, end: index + 2 });
        insideOsc = false;
        index += 1;
      }
      continue;
    }

    if (value.charCodeAt(index) !== 0x1b || index + 1 >= value.length) continue;
    const kind = value[index + 1];
    let end = -1;

    if (kind === "[") {
      let cursor = index + 2;
      while (cursor < value.length && value.charCodeAt(cursor) >= 0x30 && value.charCodeAt(cursor) <= 0x3f) cursor += 1;
      while (cursor < value.length && value.charCodeAt(cursor) >= 0x20 && value.charCodeAt(cursor) <= 0x2f) cursor += 1;
      if (cursor < value.length && value.charCodeAt(cursor) >= 0x40 && value.charCodeAt(cursor) <= 0x7e) {
        end = cursor + 1;
      }
    } else if (kind === "]") {
      // OSC payloads are arbitrary terminal text and therefore remain inside
      // the privacy scan. Mask only the control introducer/terminator, never
      // the title or hyperlink payload between them.
      end = index + 2;
      insideOsc = true;
    }

    if (end > index) {
      replacements.push({ start: index, end });
      index = end - 1;
    }
  }

  if (replacements.length === 0) return value;
  const chunks = [];
  let cursor = 0;
  for (const replacement of replacements) {
    chunks.push(value.slice(cursor, replacement.start), " ".repeat(replacement.end - replacement.start));
    cursor = replacement.end;
  }
  chunks.push(value.slice(cursor));
  return chunks.join("");
}

function stripInvisibleControlCharactersPreservingText(value) {
  return [...value].filter((sourceCharacter) => (
    !/[\p{Cc}\p{Cf}\p{Zl}\p{Zp}\p{Default_Ignorable_Code_Point}]/u.test(sourceCharacter)
  )).join("");
}

function stripInvisibleSecuritySyntax(value) {
  // OSC payload text remains visible to privacy checks; only its terminal
  // introducer and terminator are removed in this first pass.
  const oscPayload = [];
  for (let index = 0; index < value.length;) {
    const sevenBitOsc = value.charCodeAt(index) === 0x1b && value[index + 1] === "]";
    const eightBitOsc = value.charCodeAt(index) === 0x9d;
    if (sevenBitOsc || eightBitOsc) {
      index += sevenBitOsc ? 2 : 1;
      while (index < value.length) {
        if (value.charCodeAt(index) === 0x07 || value.charCodeAt(index) === 0x9c) {
          index += 1;
          break;
        }
        if (value.charCodeAt(index) === 0x1b && value[index + 1] === "\\") {
          index += 2;
          break;
        }
        oscPayload.push(value[index]);
        index += 1;
      }
      continue;
    }
    oscPayload.push(value[index]);
    index += 1;
  }

  const source = oscPayload.join("");
  const output = [];
  for (let index = 0; index < source.length;) {
    const sevenBitCsi = source.charCodeAt(index) === 0x1b && source[index + 1] === "[";
    const eightBitCsi = source.charCodeAt(index) === 0x9b;
    if (sevenBitCsi || eightBitCsi) {
      let cursor = index + (sevenBitCsi ? 2 : 1);
      while (cursor < source.length && source.charCodeAt(cursor) >= 0x30 && source.charCodeAt(cursor) <= 0x3f) cursor += 1;
      while (cursor < source.length && source.charCodeAt(cursor) >= 0x20 && source.charCodeAt(cursor) <= 0x2f) cursor += 1;
      if (cursor < source.length && source.charCodeAt(cursor) >= 0x40 && source.charCodeAt(cursor) <= 0x7e) {
        index = cursor + 1;
      } else {
        index += sevenBitCsi ? 2 : 1;
      }
      continue;
    }
    if (source.charCodeAt(index) === 0x1b) {
      let cursor = index + 1;
      while (cursor < source.length && source.charCodeAt(cursor) >= 0x20 && source.charCodeAt(cursor) <= 0x2f) cursor += 1;
      if (cursor < source.length && source.charCodeAt(cursor) >= 0x30 && source.charCodeAt(cursor) <= 0x7e) {
        index = cursor + 1;
      } else {
        index += 1;
      }
      continue;
    }

    const sourceCharacter = String.fromCodePoint(source.codePointAt(index));
    index += sourceCharacter.length;
    if (/[\p{Cc}\p{Cf}\p{Zl}\p{Zp}\p{Default_Ignorable_Code_Point}]/u.test(sourceCharacter)) {
      continue;
    }
    output.push(sourceCharacter);
  }
  return output.join("");
}

function stripTerminalDisplaySequences(value) {
  const output = [];
  const eightBitStrings = new Map([
    [0x90, false], // DCS
    [0x98, false], // SOS
    [0x9d, true],  // OSC
    [0x9e, false], // PM
    [0x9f, false], // APC
  ]);
  const sevenBitStrings = new Map([
    ["]", true],  // OSC
    ["P", false], // DCS
    ["X", false], // SOS
    ["^", false], // PM
    ["_", false], // APC
  ]);

  for (let index = 0; index < value.length;) {
    const code = value.charCodeAt(index);
    const sevenBitKind = code === 0x1b ? value[index + 1] : null;
    const sevenBitString = sevenBitStrings.get(sevenBitKind);
    const hasSevenBitString = code === 0x1b && sevenBitStrings.has(sevenBitKind);
    const hasEightBitString = eightBitStrings.has(code);
    if (hasSevenBitString || hasEightBitString) {
      const isOsc = hasSevenBitString ? sevenBitString : eightBitStrings.get(code);
      let cursor = index + (hasSevenBitString ? 2 : 1);
      while (cursor < value.length) {
        if (isOsc && value.charCodeAt(cursor) === 0x07) {
          cursor += 1;
          break;
        }
        if (value.charCodeAt(cursor) === 0x9c) {
          cursor += 1;
          break;
        }
        if (value.charCodeAt(cursor) === 0x1b && value[cursor + 1] === "\\") {
          cursor += 2;
          break;
        }
        cursor += String.fromCodePoint(value.codePointAt(cursor)).length;
      }
      index = cursor;
      continue;
    }

    const sevenBitCsi = code === 0x1b && value[index + 1] === "[";
    const eightBitCsi = code === 0x9b;
    if (sevenBitCsi || eightBitCsi) {
      let cursor = index + (sevenBitCsi ? 2 : 1);
      while (cursor < value.length && value.charCodeAt(cursor) >= 0x30 && value.charCodeAt(cursor) <= 0x3f) cursor += 1;
      while (cursor < value.length && value.charCodeAt(cursor) >= 0x20 && value.charCodeAt(cursor) <= 0x2f) cursor += 1;
      if (cursor < value.length && value.charCodeAt(cursor) >= 0x40 && value.charCodeAt(cursor) <= 0x7e) cursor += 1;
      index = cursor;
      continue;
    }
    if (code === 0x1b) {
      let cursor = index + 1;
      while (cursor < value.length && value.charCodeAt(cursor) >= 0x20 && value.charCodeAt(cursor) <= 0x2f) cursor += 1;
      if (cursor < value.length && value.charCodeAt(cursor) >= 0x30 && value.charCodeAt(cursor) <= 0x7e) cursor += 1;
      index = cursor;
      continue;
    }

    const sourceCharacter = String.fromCodePoint(value.codePointAt(index));
    index += sourceCharacter.length;
    if (/[\p{Cc}\p{Cf}\p{Zl}\p{Zp}\p{Default_Ignorable_Code_Point}]/u.test(sourceCharacter)) continue;
    output.push(sourceCharacter);
  }
  return output.join("");
}

function assignmentTokens(segment) {
  return [...segment.matchAll(ASSIGNMENT_TOKEN_PATTERN)];
}

function hasExactFieldTrailer(segment, token) {
  return EXACT_FIELD_TRAILER.test(segment.slice(token.index + token[0].length));
}

function addCanonicalRange(ranges, sourceOffset, matchedValue, hash) {
  const localOffset = matchedValue.indexOf(hash);
  if (localOffset < 0) fail("invalid canonical canary hash field");
  const start = sourceOffset + localOffset;
  ranges.add(`${start}:${start + hash.length}`);
}

function rejectSensitiveCandidate(tokens) {
  if (tokens.length === 0) return;
  const candidate = tokens.map((token) => token[0]).join(" ");
  if (isSensitiveFieldName(candidate)) {
    fail("unsafe sensitive field detected before evidence projection");
  }
}

function rejectSensitiveConfusableCandidate(tokens) {
  if (tokens.length === 0) return;
  if (hasCompleteSensitiveConfusableField(tokens)) {
    fail("unsafe confusable sensitive field detected before evidence projection");
  }
}

function rejectExactSensitiveContentCandidate(tokens) {
  if (tokens.length === 0) return;
  const normalizedCandidates = new Set([
    normalizeFieldName(tokens.map((token) => token[0]).join(" ")),
    ...confusableSkeletonGroups(tokens),
    ...compatibilityNormalizedGroups(tokens),
  ]);
  if ([...normalizedCandidates].some((candidate) => EXACT_SENSITIVE_CONTENT_FIELDS.has(candidate))) {
    fail("unsafe exact meal or food content field detected before evidence projection");
  }
}

function fieldCompatibilityNormalizedSkeleton(field) {
  return [...field].map((sourceCharacter) => {
    if (CONFUSABLE_ASSIGNMENT_DELIMITERS.has(sourceCharacter)) return "";
    const decomposition = sourceCharacter.normalize("NFKD").replace(/\p{M}/gu, "");
    if (decomposition === "") return "";
    if (/^[\x00-\x7f]+$/u.test(decomposition)) return decomposition.toLowerCase();
    return fieldConfusableSkeleton(sourceCharacter);
  }).join("");
}

function confusableSkeletonGroups(tokens, skeletonizer = fieldConfusableSkeleton) {
  const groups = [[]];
  for (const token of tokens) {
    const skeleton = skeletonizer(token[0]);
    for (const character of skeleton) {
      if (/[a-z0-9]/i.test(character)) {
        groups[groups.length - 1].push(character.toLowerCase());
      } else if (character.codePointAt(0) > 0x7f && groups.at(-1).length > 0) {
        // A residual localized character is a hard boundary. This preserves
        // `to食ken` as localized value text while still retaining the complete
        // ASCII-confusable runs on either side for privacy checks.
        groups.push([]);
      }
    }
  }
  return groups.filter((group) => group.length > 0).map((group) => group.join(""));
}

function compatibilityNormalizedGroups(tokens) {
  return confusableSkeletonGroups(tokens, fieldCompatibilityNormalizedSkeleton);
}

function confusableGroupHas(groups, field) {
  const expected = normalizeFieldName(fieldConfusableSkeleton(field));
  return groups.some((group) => group.includes(expected));
}

function hasSensitiveConfusableGroups(groups) {
  if (groups.some((group) => isSensitiveConfusableNormalizedFieldName(
    group,
    { includeExactContent: false }
  ))) return true;
  return (
    ((confusableGroupHas(groups, "meal") || confusableGroupHas(groups, "food")) &&
      (confusableGroupHas(groups, "name") || confusableGroupHas(groups, "title"))) ||
    (confusableGroupHas(groups, "transaction") &&
      (confusableGroupHas(groups, "id") || confusableGroupHas(groups, "payload"))) ||
    (confusableGroupHas(groups, "store") && confusableGroupHas(groups, "kit") &&
      confusableGroupHas(groups, "payload")) ||
    (confusableGroupHas(groups, "display") && confusableGroupHas(groups, "name"))
  );
}

function compatibilityGroupHas(groups, field) {
  const expected = normalizeFieldName(field);
  return groups.some((group) => group.includes(expected));
}

function hasSensitiveCompatibilityGroups(groups) {
  if (groups.some((group) => isSensitiveNormalizedFieldName(
    group,
    { includeExactContent: false }
  ))) return true;
  return (
    ((compatibilityGroupHas(groups, "meal") || compatibilityGroupHas(groups, "food")) &&
      (compatibilityGroupHas(groups, "name") || compatibilityGroupHas(groups, "title"))) ||
    (compatibilityGroupHas(groups, "transaction") &&
      (compatibilityGroupHas(groups, "id") || compatibilityGroupHas(groups, "payload"))) ||
    (compatibilityGroupHas(groups, "store") && compatibilityGroupHas(groups, "kit") &&
      compatibilityGroupHas(groups, "payload")) ||
    (compatibilityGroupHas(groups, "display") && compatibilityGroupHas(groups, "name"))
  );
}

function hasCompleteSensitiveConfusableField(tokens) {
  if (tokens.length === 0) return false;
  return (
    hasSensitiveConfusableGroups(confusableSkeletonGroups(tokens)) ||
    hasSensitiveCompatibilityGroups(compatibilityNormalizedGroups(tokens))
  );
}

const COMPATIBILITY_FIELD_CARRY_LIMIT = 128;

function hasSensitiveCompatibilityFieldComponent(groups) {
  if (hasSensitiveCompatibilityGroups(groups)) return true;
  return [
    "meal", "food", "name", "title", "transaction", "id", "identifier",
    "payload", "store", "kit", "display",
  ].some((field) => compatibilityGroupHas(groups, field));
}

function compatibilityCarrySuffix(tokens) {
  let suffix = "";
  let canJoinPrior = true;
  for (const token of tokens) {
    const skeleton = fieldCompatibilityNormalizedSkeleton(token[0]);
    for (const character of skeleton) {
      if (/[a-z0-9]/i.test(character)) {
        suffix = `${suffix}${character.toLowerCase()}`.slice(-COMPATIBILITY_FIELD_CARRY_LIMIT);
      } else if (character.codePointAt(0) > 0x7f) {
        suffix = "";
        canJoinPrior = false;
      }
    }
  }
  return { suffix, canJoinPrior };
}

function createFieldRelationshipContext() {
  return {
    meal: false,
    food: false,
    name: false,
    title: false,
    transaction: false,
    id: false,
    payload: false,
    store: false,
    kit: false,
    display: false,
  };
}

function rejectSensitiveFieldRelationshipContext(context) {
  if (
    ((context.meal || context.food) && (context.name || context.title)) ||
    (context.transaction && (context.id || context.payload)) ||
    (context.store && context.kit && context.payload) ||
    (context.display && context.name)
  ) {
    fail("unsafe sensitive field relationship detected before evidence projection");
  }
}

function updateFieldRelationshipContext(context, tokens) {
  if (tokens.length === 0) return;
  const normalized = normalizeFieldName(tokens.map((token) => token[0]).join(" "));
  if (!normalized) return;

  context.meal ||= normalized.includes("meal");
  context.food ||= normalized.includes("food");
  context.name ||= normalized.includes("name");
  context.title ||= normalized.includes("title");
  context.transaction ||= normalized.includes("transaction");
  context.id ||= normalized.includes("id") || normalized.includes("identifier");
  context.payload ||= normalized.includes("payload");
  context.store ||= normalized.includes("store");
  context.kit ||= normalized.includes("kit");
  context.display ||= normalized.includes("display");

  rejectSensitiveFieldRelationshipContext(context);
}

function updateConfusableFieldRelationshipContext(context, tokens) {
  const groups = confusableSkeletonGroups(tokens);
  const compatibilityGroups = compatibilityNormalizedGroups(tokens);
  if (groups.length === 0 && compatibilityGroups.length === 0) return;
  context.meal ||= confusableGroupHas(groups, "meal");
  context.meal ||= compatibilityGroupHas(compatibilityGroups, "meal");
  context.food ||= confusableGroupHas(groups, "food");
  context.food ||= compatibilityGroupHas(compatibilityGroups, "food");
  context.name ||= confusableGroupHas(groups, "name");
  context.name ||= compatibilityGroupHas(compatibilityGroups, "name");
  context.title ||= confusableGroupHas(groups, "title");
  context.title ||= compatibilityGroupHas(compatibilityGroups, "title");
  context.transaction ||= confusableGroupHas(groups, "transaction");
  context.transaction ||= compatibilityGroupHas(compatibilityGroups, "transaction");
  context.id ||= confusableGroupHas(groups, "id") || confusableGroupHas(groups, "identifier");
  context.id ||= compatibilityGroupHas(compatibilityGroups, "id") || compatibilityGroupHas(compatibilityGroups, "identifier");
  context.payload ||= confusableGroupHas(groups, "payload");
  context.payload ||= compatibilityGroupHas(compatibilityGroups, "payload");
  context.store ||= confusableGroupHas(groups, "store");
  context.store ||= compatibilityGroupHas(compatibilityGroups, "store");
  context.kit ||= confusableGroupHas(groups, "kit");
  context.kit ||= compatibilityGroupHas(compatibilityGroups, "kit");
  context.display ||= confusableGroupHas(groups, "display");
  context.display ||= compatibilityGroupHas(compatibilityGroups, "display");
  rejectSensitiveFieldRelationshipContext(context);
}

function hasSensitiveConfusableFieldComponent(tokens) {
  const groups = confusableSkeletonGroups(tokens);
  const compatibilityGroups = compatibilityNormalizedGroups(tokens);
  if (groups.length === 0 && compatibilityGroups.length === 0) return false;
  if (
    hasSensitiveConfusableGroups(groups) ||
    hasSensitiveCompatibilityFieldComponent(compatibilityGroups)
  ) return true;
  const components = [
    "meal", "food", "name", "title", "transaction", "id", "identifier",
    "payload", "store", "kit", "display",
  ];
  return components.some((field) => (
    confusableGroupHas(groups, field) || compatibilityGroupHas(compatibilityGroups, field)
  ));
}

function explicitWrappedFieldTokens(segment, tokens, fieldToken) {
  const prefix = segment.slice(0, fieldToken.index);
  let wrapperIndex = -1;
  for (const wrapper of ["\"", "'", "`", "(", "[", "{", "<"]) {
    wrapperIndex = Math.max(wrapperIndex, prefix.lastIndexOf(wrapper));
  }
  return wrapperIndex < 0 ? [] : tokens.filter((token) => token.index > wrapperIndex);
}

const FIELD_VALUE_QUOTE_PAIRS = new Map([
  ["\"", "\""],
  ["'", "'"],
  ["`", "`"],
  ["“", "”"],
  ["‘", "’"],
  ["«", "»"],
  ["‹", "›"],
  ["「", "」"],
  ["『", "』"],
]);

function postAssignmentFieldStart(segment, tokens) {
  const firstToken = tokens[0];
  if (!firstToken) return segment.length;

  const firstNonWhitespace = segment.search(/\S/u);
  if (firstNonWhitespace >= 0 && FIELD_VALUE_QUOTE_PAIRS.has(segment[firstNonWhitespace])) {
    const openingQuote = segment[firstNonWhitespace];
    const closingQuote = FIELD_VALUE_QUOTE_PAIRS.get(openingQuote);
    let escaped = false;
    for (let index = firstNonWhitespace + 1; index < segment.length; index += 1) {
      const character = segment[index];
      if (character === closingQuote && !escaped) return index + 1;
      if (["\"", "'", "`"].includes(openingQuote) && character === "\\" && !escaped) escaped = true;
      else escaped = false;
    }
  }

  if (/[^\x00-\x7f]/u.test(firstToken[0])) {
    const firstTokenEnd = firstToken.index + firstToken[0].length;
    for (const token of tokens.slice(1)) {
      if (
        /^[\x00-\x7f]+$/u.test(token[0]) &&
        /\s/u.test(segment.slice(firstTokenEnd, token.index))
      ) {
        return token.index;
      }
    }
    return segment.length;
  }

  return firstToken.index + firstToken[0].length;
}

function leadingQuotedValueSyntaxIndexes(value) {
  const quotedSyntaxIndexes = new Set();
  let awaitingValue = false;
  let openingQuote = null;
  let closingQuote = null;
  let escaped = false;

  for (let index = 0; index < value.length; index += 1) {
    const character = String.fromCodePoint(value.codePointAt(index));
    const characterWidth = character.length;
    const isSyntax = (
      character === "," || character === ";" || character === "|" || character === "\0" ||
      character === ":" || character === "=" || CONFUSABLE_ASSIGNMENT_DELIMITERS.has(character)
    );

    if (openingQuote !== null) {
      if (isSyntax) quotedSyntaxIndexes.add(index);
      if (character === closingQuote && !escaped) {
        openingQuote = null;
        closingQuote = null;
      }
      if (openingQuote !== null && ["\"", "'", "`"].includes(openingQuote) && character === "\\" && !escaped) {
        escaped = true;
      } else {
        escaped = false;
      }
      index += characterWidth - 1;
      continue;
    }

    if (character === "," || character === ";" || character === "|" || character === "\0") {
      awaitingValue = false;
    } else if (character === ":" || character === "=" || CONFUSABLE_ASSIGNMENT_DELIMITERS.has(character)) {
      awaitingValue = true;
    } else if (awaitingValue && !/\s/u.test(character)) {
      const expectedClosingQuote = FIELD_VALUE_QUOTE_PAIRS.get(character);
      if (expectedClosingQuote) {
        openingQuote = character;
        closingQuote = expectedClosingQuote;
        escaped = false;
      }
      awaitingValue = false;
    }
    index += characterWidth - 1;
  }
  return quotedSyntaxIndexes;
}

function normalizeSensitiveConfusableDelimiters(value, quotedSyntaxIndexes) {
  const replacements = [];
  let segmentStart = 0;
  let segmentAfterAssignment = false;
  let compatibilityCarry = "";

  const compatibilityCandidate = (tokens) => {
    const carrySegment = compatibilityCarrySuffix(tokens);
    return `${carrySegment.canJoinPrior ? compatibilityCarry : ""}${carrySegment.suffix}`
      .slice(-COMPATIBILITY_FIELD_CARRY_LIMIT);
  };

  const carryCompletesSensitiveField = (tokens) => {
    if (compatibilityCarry === "") return false;
    const combined = compatibilityCandidate(tokens);
    return combined !== "" && hasSensitiveCompatibilityGroups([combined]);
  };

  for (let index = 0; index < value.length; index += 1) {
    const character = String.fromCodePoint(value.codePointAt(index));
    const characterWidth = character.length;
    if (quotedSyntaxIndexes.has(index) && [",", ";", "|"].includes(character)) {
      const segment = value.slice(segmentStart, index);
      const tokens = assignmentTokens(segment);
      if (hasCompleteSensitiveConfusableField(tokens) || carryCompletesSensitiveField(tokens)) {
        fail("unsafe quoted sensitive field detected before evidence projection");
      }
      compatibilityCarry = compatibilityCandidate(tokens);
      segmentStart = index + characterWidth;
      index += characterWidth - 1;
      continue;
    }
    if (character === "," || character === ";" || character === "|" || character === "\0") {
      segmentStart = index + characterWidth;
      segmentAfterAssignment = false;
      compatibilityCarry = "";
      index += characterWidth - 1;
      continue;
    }
    if (character === ":" || character === "=") {
      const segment = value.slice(segmentStart, index);
      const tokens = assignmentTokens(segment);
      if (quotedSyntaxIndexes.has(index)) {
        if (hasCompleteSensitiveConfusableField(tokens) || carryCompletesSensitiveField(tokens)) {
          fail("unsafe quoted sensitive field detected before evidence projection");
        }
        compatibilityCarry = compatibilityCandidate(tokens);
        segmentStart = index + characterWidth;
        index += characterWidth - 1;
        continue;
      }
      if (carryCompletesSensitiveField(tokens)) {
        fail("unsafe fragmented sensitive field detected before evidence projection");
      }
      segmentStart = index + characterWidth;
      segmentAfterAssignment = true;
      compatibilityCarry = "";
      index += characterWidth - 1;
      continue;
    }
    const replacement = CONFUSABLE_ASSIGNMENT_DELIMITERS.get(character);
    if (!replacement) {
      index += characterWidth - 1;
      continue;
    }

    const segment = value.slice(segmentStart, index);
    const tokens = assignmentTokens(segment);
    const fieldStart = segmentAfterAssignment ? postAssignmentFieldStart(segment, tokens) : 0;
    const fieldTokens = tokens.filter((token) => token.index >= fieldStart);
    const combinedCarry = compatibilityCandidate(tokens);
    const carryIsSensitive = carryCompletesSensitiveField(tokens);
    const completeSensitiveField = (
      hasCompleteSensitiveConfusableField(fieldTokens) ||
      hasCompleteSensitiveConfusableField(tokens)
    );
    if (
      !completeSensitiveField &&
      !carryIsSensitive
    ) {
      compatibilityCarry = combinedCarry;
      segmentStart = index + characterWidth;
      index += characterWidth - 1;
      continue;
    }

    if (quotedSyntaxIndexes.has(index)) {
      fail("unsafe quoted sensitive field detected before evidence projection");
    }

    const offsetPreservingReplacement = replacement.padEnd(characterWidth, " ");
    replacements.push({ index, characterWidth, value: offsetPreservingReplacement });
    segmentStart = index + characterWidth;
    segmentAfterAssignment = true;
    compatibilityCarry = "";
    index += characterWidth - 1;
  }

  if (compatibilityCarry !== "") {
    const terminalTokens = assignmentTokens(value.slice(segmentStart));
    if (carryCompletesSensitiveField(terminalTokens)) {
      fail("unsafe fragmented sensitive field detected before evidence projection");
    }
  }
  if (replacements.length === 0) return value;
  const chunks = [];
  let cursor = 0;
  for (const replacement of replacements) {
    chunks.push(value.slice(cursor, replacement.index), replacement.value);
    cursor = replacement.index + replacement.characterWidth;
  }
  chunks.push(value.slice(cursor));
  return chunks.join("");
}

function rejectSensitivePipeConfusables(value) {
  let componentStart = 0;
  let containsPipe = false;
  const rejectComponent = (componentEnd) => {
    if (!containsPipe) return;
    const component = value.slice(componentStart, componentEnd);
    if (hasSensitiveConfusableFieldComponent(assignmentTokens(component))) {
      fail("unsafe pipe-confusable sensitive field detected before evidence projection");
    }
  };

  for (let index = 0; index < value.length; index += 1) {
    const character = String.fromCodePoint(value.codePointAt(index));
    const characterWidth = character.length;
    if (character === "|") {
      containsPipe = true;
    } else if (/\s/u.test(character) || [",", ";", ":", "=", "\0"].includes(character)) {
      rejectComponent(index);
      componentStart = index + characterWidth;
      containsPipe = false;
    }
    index += characterWidth - 1;
  }
  rejectComponent(value.length);
}

function rejectSensitiveFieldExpression(segment, tokens, skippedToken, segmentAfterAssignment) {
  const fieldToken = tokens.at(-1);
  if (!fieldToken) return [];

  let adjacentStart = fieldToken.index;
  while (adjacentStart > 0 && !/\s/u.test(segment[adjacentStart - 1])) adjacentStart -= 1;
  const adjacentExpression = segment.slice(adjacentStart);
  if (/[^\x00-\x7f]/u.test(adjacentExpression)) {
    fail("unsafe non-ASCII evidence field detected before evidence projection");
  }

  if (fieldToken !== skippedToken) rejectSensitiveCandidate([fieldToken]);

  if (!segmentAfterAssignment) {
    if (/[^\x00-\x7f]/u.test(segment)) {
      fail("unsafe non-ASCII evidence field detected before evidence projection");
    }
    const candidateTokens = fieldToken === skippedToken ? tokens.slice(0, -1) : tokens;
    rejectSensitiveCandidate(candidateTokens);
    rejectSensitiveConfusableCandidate(candidateTokens);
    rejectExactSensitiveContentCandidate(candidateTokens);
    return candidateTokens;
  }

  const wrappedTokens = explicitWrappedFieldTokens(segment, tokens, fieldToken);
  const wrappedCandidate = fieldToken === skippedToken ? wrappedTokens.slice(0, -1) : wrappedTokens;
  if (wrappedTokens.length > 1) {
    rejectSensitiveCandidate(wrappedCandidate);
    rejectSensitiveConfusableCandidate(wrappedCandidate);
    rejectExactSensitiveContentCandidate(wrappedCandidate);
  }

  const fieldStart = postAssignmentFieldStart(segment, tokens);
  const fieldExpression = segment.slice(fieldStart);
  if (/[^\x00-\x7f]/u.test(fieldExpression)) {
    fail("unsafe non-ASCII evidence field detected before evidence projection");
  }
  const fieldTokens = tokens.filter((token) => token.index >= fieldStart);
  const candidateTokens = fieldToken === skippedToken ? fieldTokens.slice(0, -1) : fieldTokens;
  rejectSensitiveCandidate(candidateTokens);
  rejectExactSensitiveContentCandidate(candidateTokens);

  const completeEnd = fieldToken === skippedToken ? tokens.length - 1 : tokens.length;
  const completeTokens = tokens.slice(0, completeEnd);
  rejectSensitiveConfusableCandidate(completeTokens);

  if (wrappedCandidate.length > 0) return wrappedCandidate;
  if (candidateTokens.length > 0) return candidateTokens;
  return completeTokens;
}

function rejectSensitiveFieldAssignments(value, { allowConsoleOperationMarker = false } = {}) {
  const allowedCanonicalRanges = new Set();
  const ansiMaskedValue = maskAnsiEscapeSequences(value);
  const quotedSyntaxIndexes = leadingQuotedValueSyntaxIndexes(ansiMaskedValue);
  const maskedValue = normalizeSensitiveConfusableDelimiters(ansiMaskedValue, quotedSyntaxIndexes);
  rejectSensitivePipeConfusables(maskedValue);
  let segmentStart = 0;
  let segmentAfterAssignment = false;
  let fieldRelationshipContext = createFieldRelationshipContext();

  for (let index = 0; index < maskedValue.length; index += 1) {
    const character = maskedValue[index];
    if (quotedSyntaxIndexes.has(index) && character !== "\0") continue;
    if (character === "," || character === ";" || character === "|" || character === "\0") {
      segmentStart = index + 1;
      segmentAfterAssignment = false;
      if (character === "\0") fieldRelationshipContext = createFieldRelationshipContext();
      continue;
    }
    if (character !== ":" && character !== "=") continue;

    const segment = maskedValue.slice(segmentStart, index);
    const tokens = assignmentTokens(segment);
    const fieldToken = tokens.at(-1);
    let allowedNumericToken = null;

    if (fieldToken) {
      const field = fieldToken[0];
      const exactField = hasExactFieldTrailer(segment, fieldToken);

      if (CANONICAL_HASH_FIELDS.has(field)) {
        fail("unsafe canonical canary hash assignment in ordinary text");
      } else if (ALLOWED_NUMERIC_TOKEN_FIELDS.has(field)) {
        const assignedNumberPattern = /[\s]*(?:0|[1-9][0-9]*)(?:\.[0-9]+)?(?=$|[\s,}\]\)])/y;
        assignedNumberPattern.lastIndex = index + 1;
        if (!exactField || !assignedNumberPattern.test(value)) {
          fail("unsafe non-numeric token-count field detected before evidence projection");
        }
        allowedNumericToken = fieldToken;
      }
    }

    const fieldContextTokens = rejectSensitiveFieldExpression(
      segment,
      tokens,
      allowedNumericToken,
      segmentAfterAssignment
    );
    updateFieldRelationshipContext(fieldRelationshipContext, fieldContextTokens);
    const confusableContextEnd = allowedNumericToken ? tokens.length - 1 : tokens.length;
    updateConfusableFieldRelationshipContext(
      fieldRelationshipContext,
      tokens.slice(0, confusableContextEnd)
    );
    segmentStart = index + 1;
    segmentAfterAssignment = true;
  }

  if (allowConsoleOperationMarker) {
    for (const match of value.matchAll(
      /(?:^|[\r\n])[^\r\n]*?CYCLEBALANCE_CANARY_OPERATION tag=([a-f0-9]{64})[ \t]*(?=$|[\r\n])/g
    )) {
      addCanonicalRange(allowedCanonicalRanges, match.index, match[0], match[1]);
    }
  }
  return allowedCanonicalRanges;
}

function rejectLoneSurrogates(value) {
  for (let index = 0; index < value.length; index += 1) {
    const codeUnit = value.charCodeAt(index);
    if (codeUnit >= 0xd800 && codeUnit <= 0xdbff) {
      const lowSurrogate = value.charCodeAt(index + 1);
      if (!(lowSurrogate >= 0xdc00 && lowSurrogate <= 0xdfff)) {
        fail("unsafe lone Unicode surrogate detected before evidence projection");
      }
      index += 1;
    } else if (codeUnit >= 0xdc00 && codeUnit <= 0xdfff) {
      fail("unsafe lone Unicode surrogate detected before evidence projection");
    }
  }
}

function rejectTerminalControlSyntax(value) {
  for (const sourceCharacter of value) {
    const codePoint = sourceCharacter.codePointAt(0);
    if (codePoint === 0x1b || (codePoint >= 0x80 && codePoint <= 0x9f)) {
      fail("unsafe terminal control syntax detected before evidence projection");
    }
  }
}

function decodeJsonEscapeProjection(value) {
  const simpleEscapes = new Map([
    ['"', '"'], ["\\", "\\"], ["/", "/"],
    ["b", "\b"], ["f", "\f"], ["n", "\n"], ["r", "\r"], ["t", "\t"],
  ]);
  const hexadecimalCodeUnit = (offset) => {
    const digits = value.slice(offset, offset + 4);
    return digits.length === 4 && /^[0-9a-f]{4}$/i.test(digits)
      ? Number.parseInt(digits, 16)
      : null;
  };

  const chunks = [];
  for (let index = 0; index < value.length;) {
    if (value[index] !== "\\" || index + 1 >= value.length) {
      chunks.push(value[index]);
      index += 1;
      continue;
    }

    const escapeType = value[index + 1];
    if (simpleEscapes.has(escapeType)) {
      chunks.push(simpleEscapes.get(escapeType));
      index += 2;
      continue;
    }
    if (escapeType !== "u") {
      chunks.push("\\");
      index += 1;
      continue;
    }

    const codeUnit = hexadecimalCodeUnit(index + 2);
    if (codeUnit === null) {
      chunks.push("\\");
      index += 1;
      continue;
    }
    if (codeUnit >= 0xd800 && codeUnit <= 0xdbff) {
      const hasEscapedLowSurrogate = value[index + 6] === "\\" && value[index + 7] === "u";
      const lowSurrogate = hasEscapedLowSurrogate ? hexadecimalCodeUnit(index + 8) : null;
      if (!(lowSurrogate >= 0xdc00 && lowSurrogate <= 0xdfff)) {
        fail("unsafe lone escaped Unicode surrogate detected before evidence projection");
      }
      chunks.push(String.fromCodePoint(
        0x10000 + ((codeUnit - 0xd800) * 0x400) + (lowSurrogate - 0xdc00)
      ));
      index += 12;
      continue;
    }
    if (codeUnit >= 0xdc00 && codeUnit <= 0xdfff) {
      fail("unsafe lone escaped Unicode surrogate detected before evidence projection");
    }
    chunks.push(String.fromCharCode(codeUnit));
    index += 6;
  }
  return chunks.join("");
}

function decodeSlashRunInsensitiveUnicodeProjection(value) {
  const hexadecimalCodeUnit = (offset) => {
    const digits = value.slice(offset, offset + 4);
    return digits.length === 4 && /^[0-9a-f]{4}$/i.test(digits)
      ? Number.parseInt(digits, 16)
      : null;
  };

  const chunks = [];
  for (let index = 0; index < value.length;) {
    if (value[index] !== "\\") {
      chunks.push(value[index]);
      index += 1;
      continue;
    }

    let escapeMarker = index;
    while (value[escapeMarker] === "\\") escapeMarker += 1;
    const codeUnit = value[escapeMarker] === "u"
      ? hexadecimalCodeUnit(escapeMarker + 1)
      : null;
    if (codeUnit === null) {
      chunks.push(value.slice(index, escapeMarker));
      index = escapeMarker;
      continue;
    }

    const nextIndex = escapeMarker + 5;
    if (codeUnit >= 0xd800 && codeUnit <= 0xdbff) {
      let lowEscapeMarker = nextIndex;
      while (value[lowEscapeMarker] === "\\") lowEscapeMarker += 1;
      const lowSurrogate = lowEscapeMarker > nextIndex && value[lowEscapeMarker] === "u"
        ? hexadecimalCodeUnit(lowEscapeMarker + 1)
        : null;
      if (!(lowSurrogate >= 0xdc00 && lowSurrogate <= 0xdfff)) {
        fail("unsafe lone escaped Unicode surrogate detected before evidence projection");
      }
      chunks.push(String.fromCodePoint(
        0x10000 + ((codeUnit - 0xd800) * 0x400) + (lowSurrogate - 0xdc00)
      ));
      index = lowEscapeMarker + 5;
      continue;
    }
    if (codeUnit >= 0xdc00 && codeUnit <= 0xdfff) {
      fail("unsafe lone escaped Unicode surrogate detected before evidence projection");
    }
    chunks.push(String.fromCharCode(codeUnit));
    index = nextIndex;
  }
  return chunks.join("");
}

function decodeBareUnicodeNotationProjection(value) {
  const hexadecimalCodeUnit = (offset) => {
    const digits = value.slice(offset, offset + 4);
    return digits.length === 4 && /^[0-9a-f]{4}$/i.test(digits)
      ? Number.parseInt(digits, 16)
      : null;
  };

  const chunks = [];
  for (let index = 0; index < value.length;) {
    const isUnicodeMarker = value[index] === "u" || value[index] === "U";
    const codeUnit = isUnicodeMarker ? hexadecimalCodeUnit(index + 1) : null;
    if (codeUnit === null) {
      chunks.push(value[index]);
      index += 1;
      continue;
    }
    const nextIndex = index + 5;
    if (codeUnit >= 0xd800 && codeUnit <= 0xdbff) {
      let lowMarkerIndex = nextIndex;
      while (value[lowMarkerIndex] === "\\") lowMarkerIndex += 1;
      const hasLowMarker = value[lowMarkerIndex] === "u" || value[lowMarkerIndex] === "U";
      const lowSurrogate = hasLowMarker ? hexadecimalCodeUnit(lowMarkerIndex + 1) : null;
      if (!(lowSurrogate >= 0xdc00 && lowSurrogate <= 0xdfff)) {
        fail("unsafe lone escaped Unicode surrogate detected before evidence projection");
      }
      chunks.push(String.fromCodePoint(
        0x10000 + ((codeUnit - 0xd800) * 0x400) + (lowSurrogate - 0xdc00)
      ));
      index = lowMarkerIndex + 5;
      continue;
    }
    if (codeUnit >= 0xdc00 && codeUnit <= 0xdfff) {
      fail("unsafe lone escaped Unicode surrogate detected before evidence projection");
    }
    chunks.push(String.fromCharCode(codeUnit));
    index = nextIndex;
  }
  return chunks.join("");
}

function stripInnermostTerminalSecuritySyntax(value) {
  return value
    .replace(/\x1b\[[0-?]*[ -/]*[@-~]/g, "")
    .replace(/\x9b[0-?]*[ -/]*[@-~]/g, "")
    .replace(/\x1b\]([^\x1b\x07\x9c]*)(?:\x07|\x9c|\x1b\\)/g, "$1")
    .replace(/\x9d([^\x1b\x07\x9c]*)(?:\x07|\x9c|\x1b\\)/g, "$1")
    .replace(/\x1b[P\^_X]([^\x1b\x9c]*)(?:\x9c|\x1b\\)/g, "$1")
    .replace(/[\x90\x98\x9e\x9f]([^\x1b\x9c]*)(?:\x9c|\x1b\\)/g, "$1");
}

function rejectSecurityProjectionClosure(value) {
  const maximumDecodeDepth = 32;
  const maximumProjectionStates = 4_096;
  const maximumProjectedCodeUnits = 32_000_000;
  const transformations = [
    { project: decodeJsonEscapeProjection, scanAssignments: true },
    { project: decodeSlashRunInsensitiveUnicodeProjection, scanAssignments: true },
    { project: decodeBareUnicodeNotationProjection, scanAssignments: true },
    { project: stripInnermostTerminalSecuritySyntax, scanAssignments: true },
    { project: stripInvisibleControlCharactersPreservingText, scanAssignments: true },
    { project: stripInvisibleSecuritySyntax, scanAssignments: true },
    { project: stripTerminalDisplaySequences, scanAssignments: true },
    { project: (projection) => projection.replaceAll("\\", ""), scanAssignments: true },
    { project: (projection) => projection.replace(/u005c/gi, ""), scanAssignments: true },
    { project: (projection) => projection.normalize("NFKC"), scanAssignments: false },
    { project: wholeTextConfusableSkeleton, scanAssignments: false },
  ];
  const seen = new Map([[value, true]]);
  const queue = [{ projection: value, depth: 0 }];
  let projectedCodeUnits = value.length;

  for (let cursor = 0; cursor < queue.length; cursor += 1) {
    const { projection, depth } = queue[cursor];
    for (const transformation of transformations) {
      const projected = transformation.project(projection);
      if (projected === projection) continue;
      if (seen.has(projected)) {
        if (transformation.scanAssignments && !seen.get(projected)) {
          rejectSensitiveFieldAssignments(projected);
          seen.set(projected, true);
        }
        continue;
      }
      if (depth >= maximumDecodeDepth) {
        fail("unsafe excessive composed security projection nesting detected before evidence projection");
      }
      if (seen.size >= maximumProjectionStates) {
        fail("unsafe excessive security projection branching detected before evidence projection");
      }
      projectedCodeUnits += projected.length;
      if (projectedCodeUnits > maximumProjectedCodeUnits) {
        fail("unsafe excessive security projection work detected before evidence projection");
      }
      rejectLoneSurrogates(projected);
      rejectTerminalControlSyntax(projected);
      if (transformation.scanAssignments) rejectSensitiveFieldAssignments(projected);
      rejectGenericIdentifiers(projected, new Set());
      if (SENSITIVE_TEXT_PATTERNS.some((pattern) => pattern.test(projected))) {
        fail("unsafe projected sensitive content detected before evidence projection");
      }
      rejectHighEntropyText(projected);
      rejectConfusableSourceEntropy(projected);
      seen.set(projected, transformation.scanAssignments);
      queue.push({ projection: projected, depth: depth + 1 });
    }
  }
}

function rejectSensitiveText(
  value,
  { allowConsoleOperationMarker = false } = {}
) {
  if (typeof value !== "string") return;
  rejectLoneSurrogates(value);
  rejectTerminalControlSyntax(value);
  const allowedCanonicalRanges = rejectSensitiveFieldAssignments(value, { allowConsoleOperationMarker });
  rejectGenericIdentifiers(value, allowedCanonicalRanges);
  if (SENSITIVE_TEXT_PATTERNS.some((pattern) => pattern.test(value))) {
    fail("unsafe sensitive content detected before evidence projection");
  }
  rejectHighEntropyText(value, allowedCanonicalRanges);

  const compatibilitySource = maskAllowedCanonicalRanges(value, allowedCanonicalRanges);
  rejectSecurityProjectionClosure(compatibilitySource);
  const securitySource = stripInvisibleSecuritySyntax(compatibilitySource);
  rejectConfusableSourceEntropy(securitySource);
}

function isExactStoreKitAuthorizationControl(container, field, value) {
  return (
    field === "control" &&
    value === "storekit_jws" &&
    container?.event === EVENT_NAME &&
    container?.severity === "INFO" &&
    container?.schemaVersion === EVENT_SCHEMA &&
    container?.eventType === "authorization_acceptance" &&
    container?.outcome === "accepted"
  );
}

function isExactScannerCanonicalHashLocation(container, path) {
  if (
    container?.event !== EVENT_NAME ||
    container?.severity !== "INFO" ||
    container?.schemaVersion !== EVENT_SCHEMA ||
    !Object.hasOwn(EVENT_OUTCOMES, container?.eventType) ||
    !EVENT_OUTCOMES[container.eventType].has(container?.outcome)
  ) {
    return false;
  }
  const objectPath = typeof path[0] === "number" ? path.slice(1) : path;
  return (
    objectPath.length === 0 ||
    (objectPath.length === 1 && ["jsonPayload", "textPayload"].includes(objectPath[0]))
  );
}

function isExactFreshPhaseSummary(container, path) {
  const objectPath = typeof path[0] === "number" ? path.slice(1) : path;
  if (objectPath.length !== 0) return false;
  const phaseSummaryKeys = [
    "authorizationControls", "cacheFreshDispatch", "canaryQuotaTag", "eventCount",
    "modelId", "phase", "providerCompleted", "providerId", "providerStarted",
    "quotaDelta", "requestCompleted", "requestStatusCode",
  ].sort();
  return (
    isDeepStrictEqual(Object.keys(container).sort(), phaseSummaryKeys) &&
    ["fresh-scan", "scan-as-new"].includes(container.phase) &&
    container.eventCount === 13 &&
    container.requestCompleted === 1 &&
    container.requestStatusCode === 200 &&
    container.quotaDelta === 1 &&
    container.cacheFreshDispatch === 1 &&
    container.providerStarted === 1 &&
    container.providerCompleted === 1 &&
    container.providerId === "google-gemini" &&
    container.modelId === "gemini-3.1-flash-lite" &&
    HEX_64.test(container.canaryQuotaTag ?? "") &&
    isDeepStrictEqual(container.authorizationControls, EXPECTED_AUTHORIZATION_CONTROLS)
  );
}

function isExactFinalDisabledPosture(container, path) {
  const objectPath = typeof path[0] === "number" ? path.slice(1) : path;
  if (objectPath.length !== 0) return false;
  const expectedFields = [
    "authenticatedProbe", "iamPolicyDigest", "mealScanEnabled", "projectId",
    "revision", "serviceName", "transport",
  ].sort();
  return (
    isDeepStrictEqual(Object.keys(container).sort(), expectedFields) &&
    container.projectId === PINNED_PROJECT_ID &&
    container.serviceName === PINNED_SERVICE_NAME &&
    new RegExp(`^${PINNED_SERVICE_NAME}-[0-9]{5}-[a-z0-9]{3}$`).test(container.revision) &&
    HEX_64.test(container.iamPolicyDigest ?? "") &&
    container.mealScanEnabled === false &&
    container.transport === "private" &&
    container.authenticatedProbe === "503_feature_disabled"
  );
}

function isExactContentFreeQuotaTagLocation(container, path, field) {
  if (field !== "canaryQuotaTag") return false;
  const objectPath = typeof path[0] === "number" ? path.slice(1) : path;
  if (objectPath.length !== 0) return false;
  const keys = Object.keys(container).sort();
  const quotaSnapshotKeys = [
    "canaryQuotaTag", "dispatchCount", "exists", "lifetimeUsed", "updateTime",
  ].sort();
  if (
    isDeepStrictEqual(keys, quotaSnapshotKeys) &&
    typeof container.exists === "boolean" &&
    Number.isSafeInteger(container.dispatchCount) && container.dispatchCount >= 0 &&
    container.dispatchCount <= MAX_CANARY_DISPATCH_COUNT &&
    Number.isSafeInteger(container.lifetimeUsed) && container.lifetimeUsed >= 0 &&
    container.lifetimeUsed <= MAX_TRIAL_LIFETIME_COUNT &&
    (container.updateTime === null || isValidFirestoreUpdateTime(container.updateTime))
  ) {
    return true;
  }
  return isExactFreshPhaseSummary(container, path);
}

function rejectSensitivePayload(value, path = []) {
  if (typeof value === "string") {
    rejectSensitiveText(value);
    return;
  }
  if (typeof value === "number") {
    if (!Number.isFinite(value) || Math.abs(value) >= 100_000_000_000_000) {
      fail("unsafe generic decimal identifier detected before evidence projection");
    }
    return;
  }
  if (Array.isArray(value)) {
    for (const [index, item] of value.entries()) rejectSensitivePayload(item, [...path, index]);
    return;
  }
  if (!value || typeof value !== "object") return;
  for (const [field, nestedValue] of Object.entries(value)) {
    const fieldPath = [...path, field];
    if (field.includes("\\")) {
      fail("unsafe escaped structured field detected before evidence projection");
    }
    if (
      field.includes(".") &&
      (path.length === 0 || (path.length === 1 && typeof path[0] === "number"))
    ) {
      fail("unsafe flattened metadata alias detected before evidence projection");
    }
    const normalizedField = normalizeFieldName(field);
    if (normalizedField === "textpayload" && typeof nestedValue === "string") {
      try {
        rejectSensitivePayload(parseJsonWithoutDuplicateKeys(nestedValue), fieldPath);
      } catch (error) {
        if (error instanceof SyntaxError) rejectSensitiveText(nestedValue);
        else throw error;
      }
      continue;
    }
    const metadataValidator = envelopeMetadataValidator(fieldPath);
    if (metadataValidator) {
      if (!metadataValidator(nestedValue)) fail(`invalid Cloud Logging envelope metadata: ${fieldPath.join(".")}`);
      if (envelopePathEquals(fieldPath, "insertId")) rejectUnsafeInsertId(nestedValue);
      continue;
    }
    if (CANONICAL_HASH_FIELDS.has(field)) {
      if (typeof nestedValue !== "string" || !HEX_64.test(nestedValue)) {
        fail(`invalid canonical canary hash field: ${field}`);
      }
      if (
        !isExactScannerCanonicalHashLocation(value, path) &&
        !isExactContentFreeQuotaTagLocation(value, path, field)
      ) {
        rejectSensitivePayload(nestedValue, fieldPath);
        continue;
      }
      continue;
    }
    if (field === "iamPolicyDigest") {
      if (!isExactFinalDisabledPosture(value, path)) {
        fail("unsafe IAM policy digest outside the exact final posture evidence shape");
      }
      continue;
    }
    if (field === "authorizationControls" && isExactFreshPhaseSummary(value, path)) continue;
    if (ALLOWED_NUMERIC_TOKEN_FIELDS.has(field)) {
      if (typeof nestedValue !== "number" || !Number.isFinite(nestedValue) || nestedValue < 0) {
        fail("unsafe non-numeric token-count field detected before evidence projection");
      }
    } else if (isSensitiveFieldPath(fieldPath)) {
      fail("unsafe sensitive field detected before evidence projection");
    }
    rejectSensitiveText(field);
    if (isExactStoreKitAuthorizationControl(value, field, nestedValue)) continue;
    rejectSensitivePayload(nestedValue, fieldPath);
  }
}

function scannerPayload(entry) {
  if (!entry || typeof entry !== "object" || Array.isArray(entry)) {
    fail("invalid Cloud Logging entry");
  }
  if (entry.jsonPayload && typeof entry.jsonPayload === "object" && !Array.isArray(entry.jsonPayload)) {
    return entry.jsonPayload;
  }
  if (typeof entry.textPayload === "string") {
    try {
      const parsed = parseJsonWithoutDuplicateKeys(entry.textPayload);
      return parsed && typeof parsed === "object" && !Array.isArray(parsed) ? parsed : null;
    } catch (error) {
      if (error instanceof SyntaxError) {
        rejectSensitiveText(entry.textPayload);
        return null;
      }
      throw error;
    }
  }
  return null;
}

function normalizeLiftedScannerSeverity(entry) {
  if (!entry || typeof entry !== "object" || Array.isArray(entry)) {
    fail("invalid Cloud Logging entry");
  }
  const payload = entry.jsonPayload;
  if (!payload || typeof payload !== "object" || Array.isArray(payload) || payload.event !== EVENT_NAME) {
    return entry;
  }
  const payloadHasSeverity = Object.hasOwn(payload, "severity");
  const rootHasSeverity = Object.hasOwn(entry, "severity");
  if (payloadHasSeverity) {
    if (payload.severity !== "INFO" || (rootHasSeverity && entry.severity !== "INFO")) {
      fail("invalid or mismatched scanner severity");
    }
    return entry;
  }
  if (!rootHasSeverity || entry.severity !== "INFO") {
    fail("scanner event is missing exact lifted INFO severity");
  }
  return { ...entry, jsonPayload: { ...payload, severity: "INFO" } };
}

function validateEventValue(field, value, payload) {
  if (CANONICAL_HASH_FIELDS.has(field)) {
    if (typeof value !== "string" || !HEX_64.test(value)) fail(`invalid ${field} digest`);
    return;
  }
  if (STRING_FIELDS.has(field)) {
    if (typeof value !== "string") fail(`invalid ${field} field`);
    if (
      (field !== "schemaVersion" || value !== EVENT_SCHEMA) &&
      !isExactStoreKitAuthorizationControl(payload, field, value)
    ) {
      rejectSensitiveText(value);
    }
    if (
      !["canaryCorrelationId", "canaryOperationTag", "canaryQuotaTag", "schemaVersion"].includes(field) &&
      value.length >= 40 &&
      shannonEntropy(value) >= 4.2
    ) {
      fail(`unsafe high-entropy ${field} field`);
    }
  }
  if (NUMBER_FIELDS.has(field)) {
    const limits = NUMERIC_FIELD_LIMITS[field];
    if (
      !limits ||
      !Number.isFinite(value) ||
      value < limits.minimum ||
      value > limits.maximum ||
      (limits.integer && !Number.isInteger(value))
    ) {
      fail(`invalid ${field} field`);
    }
  }
  if (field === "quotaDelta") {
    if (value !== 1) fail("invalid quotaDelta field");
    return;
  }
  if (field === "event" && value !== EVENT_NAME) fail("invalid event name");
  if (field === "severity" && value !== "INFO") fail("invalid scanner severity");
  if (field === "schemaVersion" && value !== EVENT_SCHEMA) fail("invalid scanner schema");
  if (field === "statusClass" && !/^[1-5]xx$/.test(value)) fail("invalid statusClass field");
  if (
    STRING_FIELDS.has(field) &&
    !["event", "severity", "schemaVersion", "statusClass", "canaryCorrelationId", "canaryOperationTag", "canaryQuotaTag"].includes(field) &&
    !SAFE_DIMENSION.test(value)
  ) {
    fail(`invalid ${field} dimension`);
  }
}

function validateScannerEventVocabulary(payload) {
  for (const field of [
    "event", "severity", "schemaVersion", "eventType", "outcome",
    "canaryCorrelationId", "canaryOperationTag",
  ]) {
    if (!Object.hasOwn(payload, field)) fail("scanner event is missing a required field");
  }
  const outcomes = EVENT_OUTCOMES[payload.eventType];
  if (!outcomes || !outcomes.has(payload.outcome)) fail("invalid scanner event type or outcome");

  if (payload.eventType.startsWith("authorization_")) {
    if (!AUTHORIZATION_CONTROLS.has(payload.control)) fail("invalid authorization control");
  } else if (payload.eventType === "request_gate_decision") {
    if (!REQUEST_GATE_CONTROLS.has(payload.control)) fail("invalid request-gate control");
  } else if (payload.control !== undefined) {
    fail("unexpected scanner control");
  }
  if (payload.cacheDisposition !== undefined && !CACHE_DISPOSITIONS.has(payload.cacheDisposition)) {
    fail("invalid cache disposition");
  }
  if (payload.localCacheDisposition !== undefined && payload.localCacheDisposition !== "not_observed") {
    fail("invalid local cache disposition");
  }
  if (payload.providerId !== undefined && payload.providerId !== "google-gemini") {
    fail("invalid provider identifier");
  }
  if (payload.modelId !== undefined && payload.modelId !== "gemini-3.1-flash-lite") {
    fail("invalid model identifier");
  }
  if (payload.eventType === "provider_call" && (
    payload.providerId !== "google-gemini" || payload.modelId !== "gemini-3.1-flash-lite"
  )) {
    fail("provider event is missing its pinned provider or model");
  }
  if (payload.tier !== undefined && !new Set(["trial", "paid"]).has(payload.tier)) {
    fail("invalid quota tier");
  }
  if (payload.budgetMode !== undefined && !new Set(["normal", "alert", "degraded", "disabled"]).has(payload.budgetMode)) {
    fail("invalid budget mode");
  }
  if (payload.reason !== undefined && !SAFE_SCANNER_REASONS.has(payload.reason)) {
    fail("invalid scanner reason");
  }
  if (
    payload.reason !== undefined &&
    new Set(["accepted", "allowed", "observed", "stale", "transitioned", "started", "completed"]).has(payload.outcome)
  ) {
    fail("successful scanner event must not contain a reason");
  }
  if (
    payload.statusCode !== undefined &&
    payload.statusClass !== undefined &&
    payload.statusClass !== `${Math.floor(payload.statusCode / 100)}xx`
  ) {
    fail("scanner status class does not match its status code");
  }
}

export function projectCorrelatedScannerEvents(entries, { correlationId, operationTag }) {
  if (!Array.isArray(entries)) fail("Cloud Logging input must be an array");
  if (!HEX_64.test(correlationId ?? "") || !HEX_64.test(operationTag ?? "")) {
    fail("invalid canary correlation arguments");
  }
  if (entries.length > 200) fail("canary log window exceeds the 200-entry bound");

  const events = [];
  for (const rawEntry of entries) {
    const entry = normalizeLiftedScannerSeverity(rawEntry);
    rejectSensitivePayload(entry);
    const payload = scannerPayload(entry);
    if (!payload) continue;
    if (payload.event !== EVENT_NAME) {
      rejectSensitivePayload(payload);
      continue;
    }
    const unexpected = Object.keys(payload).filter((field) => !ALLOWED_EVENT_FIELDS.has(field));
    if (unexpected.length > 0) fail("unexpected scanner event field");
    for (const [field, value] of Object.entries(payload)) validateEventValue(field, value, payload);
    validateScannerEventVocabulary(payload);
    if (
      payload.canaryCorrelationId !== correlationId ||
      payload.canaryOperationTag !== operationTag
    ) {
      fail("invalid or uncorrelated scanner event in canary window");
    }
    events.push(Object.fromEntries(
      Object.entries(payload).filter(([field]) => ALLOWED_EVENT_FIELDS.has(field))
    ));
  }
  return events;
}

function isValidFirestoreUpdateTime(value) {
  if (typeof value !== "string") return false;
  const match = FIRESTORE_UPDATE_TIME.exec(value);
  if (!match) return false;
  const [, yearText, monthText, dayText, hourText, minuteText, secondText] = match;
  const year = Number(yearText);
  const month = Number(monthText);
  const day = Number(dayText);
  const hour = Number(hourText);
  const minute = Number(minuteText);
  const second = Number(secondText);
  if (year < 1 || month < 1 || month > 12 || day < 1 || hour > 23 || minute > 59 || second > 59) {
    return false;
  }
  const date = new Date(0);
  date.setUTCFullYear(year, month - 1, day);
  date.setUTCHours(hour, minute, second, 0);
  return (
    date.getUTCFullYear() === year &&
    date.getUTCMonth() === month - 1 &&
    date.getUTCDate() === day &&
    date.getUTCHours() === hour &&
    date.getUTCMinutes() === minute &&
    date.getUTCSeconds() === second
  );
}

function firestoreInteger(field, label, maximum) {
  if (
    !field || typeof field !== "object" || Array.isArray(field) ||
    !isDeepStrictEqual(Object.keys(field), ["integerValue"])
  ) {
    fail(`invalid Firestore ${label}`);
  }
  if (typeof field?.integerValue !== "string" || !/^(?:0|[1-9]\d*)$/.test(field.integerValue)) {
    fail(`invalid Firestore ${label}`);
  }
  const value = Number(field?.integerValue);
  if (!Number.isSafeInteger(value) || value < 0 || value > maximum) {
    fail(`invalid Firestore ${label}`);
  }
  return value;
}

function exactFirestoreValue(field, key, label) {
  if (
    !field || typeof field !== "object" || Array.isArray(field) ||
    !isDeepStrictEqual(Object.keys(field), [key])
  ) {
    fail(`invalid Firestore quota ${label}`);
  }
  return field[key];
}

function validateQuotaDocumentFields(fields) {
  const allowedFields = new Set([
    "tier", "dispatchTimestamps", "lifetimeUsed", "rollingLimit", "lifetimeLimit",
    "providerLeaseRequestId", "providerLeaseClaimId", "providerLeaseExpiresAt",
    "updatedAt", "expiresAt",
  ]);
  if (Object.keys(fields).some((field) => !allowedFields.has(field))) {
    fail("unexpected Firestore quota fields");
  }
  if (fields.tier !== undefined) {
    const tier = exactFirestoreValue(fields.tier, "stringValue", "tier");
    if (!["trial", "paid"].includes(tier)) fail("invalid Firestore quota tier");
  }
  if (fields.rollingLimit !== undefined) {
    firestoreInteger(fields.rollingLimit, "rollingLimit", MAX_CANARY_DISPATCH_COUNT);
  }
  if (fields.lifetimeLimit !== undefined) {
    if (Object.hasOwn(fields.lifetimeLimit ?? {}, "integerValue")) {
      firestoreInteger(fields.lifetimeLimit, "lifetimeLimit", MAX_TRIAL_LIFETIME_COUNT);
    } else {
      const nullValue = exactFirestoreValue(fields.lifetimeLimit, "nullValue", "lifetimeLimit");
      if (nullValue !== null && nullValue !== "NULL_VALUE") {
        fail("invalid Firestore quota lifetimeLimit");
      }
    }
  }
  for (const field of ["updatedAt", "expiresAt", "providerLeaseExpiresAt"]) {
    if (fields[field] === undefined) continue;
    if (Object.hasOwn(fields[field] ?? {}, "timestampValue")) {
      const timestamp = exactFirestoreValue(fields[field], "timestampValue", field);
      if (!isValidFirestoreUpdateTime(timestamp)) fail(`invalid Firestore quota ${field}`);
    } else {
      const nullValue = exactFirestoreValue(fields[field], "nullValue", field);
      if (nullValue !== null && nullValue !== "NULL_VALUE") {
        fail(`invalid Firestore quota ${field}`);
      }
    }
  }
  for (const field of ["providerLeaseRequestId", "providerLeaseClaimId"]) {
    if (fields[field] === undefined) continue;
    if (Object.hasOwn(fields[field] ?? {}, "stringValue")) {
      const identifier = exactFirestoreValue(fields[field], "stringValue", field);
      if (typeof identifier !== "string" || !UUID_CASE_INSENSITIVE.test(identifier)) {
        fail(`invalid Firestore quota ${field}`);
      }
    } else {
      const nullValue = exactFirestoreValue(fields[field], "nullValue", field);
      if (nullValue !== null && nullValue !== "NULL_VALUE") {
        fail(`invalid Firestore quota ${field}`);
      }
    }
  }
  const leaseFields = [
    "providerLeaseRequestId", "providerLeaseClaimId", "providerLeaseExpiresAt",
  ];
  const presentLeaseFields = leaseFields.filter((field) => fields[field] !== undefined);
  if (presentLeaseFields.length !== 0 && presentLeaseFields.length !== leaseFields.length) {
    fail("invalid Firestore quota lease state");
  }
  if (presentLeaseFields.length === leaseFields.length) {
    const released = leaseFields.every((field) => Object.hasOwn(fields[field], "nullValue"));
    const active = (
      Object.hasOwn(fields.providerLeaseRequestId, "stringValue") &&
      Object.hasOwn(fields.providerLeaseClaimId, "stringValue") &&
      Object.hasOwn(fields.providerLeaseExpiresAt, "timestampValue")
    );
    if (!released && !active) fail("invalid Firestore quota lease state");
  }
}

function dispatchCount(field, capturedAt) {
  if (
    !field || typeof field !== "object" || Array.isArray(field) ||
    !isDeepStrictEqual(Object.keys(field), ["arrayValue"]) ||
    !field.arrayValue || typeof field.arrayValue !== "object" || Array.isArray(field.arrayValue)
  ) {
    fail("invalid Firestore dispatchTimestamps");
  }
  const arrayKeys = Object.keys(field.arrayValue);
  if (!isDeepStrictEqual(arrayKeys, []) && !isDeepStrictEqual(arrayKeys, ["values"])) {
    fail("invalid Firestore dispatchTimestamps");
  }
  const values = field.arrayValue.values ?? [];
  if (!Array.isArray(values)) fail("invalid Firestore dispatchTimestamps");
  const activeThreshold = Number.isFinite(capturedAt)
    ? capturedAt - (24 * 60 * 60 * 1_000)
    : null;
  let count = 0;
  for (const value of values) {
    if (
      !value || typeof value !== "object" || Array.isArray(value) ||
      !isDeepStrictEqual(Object.keys(value), ["timestampValue"])
    ) {
      fail("invalid Firestore dispatch timestamp fields");
    }
    if (!isValidFirestoreUpdateTime(value?.timestampValue)) {
      fail("invalid Firestore dispatch timestamp");
    }
    const timestamp = Date.parse(value.timestampValue);
    if (!Number.isFinite(timestamp)) fail("invalid Firestore dispatch timestamp");
    if (activeThreshold === null || timestamp >= activeThreshold) count += 1;
  }
  if (count > MAX_CANARY_DISPATCH_COUNT) fail("invalid Firestore dispatch count");
  return count;
}

export function findCanaryQuotaSnapshot(input, { canaryId, quotaTag }) {
  if (!UUID.test(canaryId ?? "") || !HEX_64.test(quotaTag ?? "")) {
    fail("invalid quota correlation arguments");
  }
  if (!input || typeof input !== "object" || Array.isArray(input)) {
    fail("invalid Firestore quota response envelope");
  }
  if (!isValidFirestoreUpdateTime(input.capturedAt)) {
    fail("invalid Firestore quota captured timestamp");
  }
  const documents = input.documents ?? [];
  const capturedAt = Date.parse(input.capturedAt);
  if (!Array.isArray(documents)) fail("invalid Firestore quota response");
  const matches = [];
  const expectedPrefix = `projects/${PINNED_PROJECT_ID}/databases/(default)/documents/mealScanRollingQuota/`;
  for (const document of documents) {
    const name = document?.name;
    if (typeof name !== "string") fail("invalid Firestore quota document name");
    const principal = name.slice(name.lastIndexOf("/") + 1);
    if (!principal || sha256(`${canaryId}|${principal}`) !== quotaTag) continue;
    if (name !== `${expectedPrefix}${principal}`) {
      fail("invalid Firestore quota document path");
    }
    const fields = document.fields;
    if (!fields || typeof fields !== "object" || Array.isArray(fields)) {
      fail("invalid Firestore quota fields");
    }
    validateQuotaDocumentFields(fields);
    if (!isValidFirestoreUpdateTime(document.updateTime)) {
      fail("invalid Firestore quota update timestamp");
    }
    matches.push({
      canaryQuotaTag: quotaTag,
      exists: true,
      dispatchCount: dispatchCount(fields.dispatchTimestamps, capturedAt),
      lifetimeUsed: firestoreInteger(fields.lifetimeUsed, "lifetimeUsed", MAX_TRIAL_LIFETIME_COUNT),
      updateTime: document.updateTime,
    });
  }
  if (matches.length > 1) fail("multiple quota documents matched one canary quota tag");
  return matches[0] ?? {
    canaryQuotaTag: quotaTag,
    exists: false,
    dispatchCount: 0,
    lifetimeUsed: 0,
    updateTime: null,
  };
}

function matchingEvents(events, eventType, predicate = () => true) {
  return events.filter((event) => event.eventType === eventType && predicate(event));
}

function requireExactlyOne(events, eventType, predicate, description) {
  const matches = matchingEvents(events, eventType, predicate);
  if (matches.length !== 1) fail(`expected exactly one ${description}`);
  return matches[0];
}

function requireExactEventFields(event, fields, description) {
  const actual = Object.keys(event).sort();
  const expected = [...fields].sort();
  if (!isDeepStrictEqual(actual, expected)) fail(`${description} fields do not match the server contract`);
}

function validateQuotaSnapshot(snapshot, description) {
  if (!snapshot || typeof snapshot !== "object" || Array.isArray(snapshot)) {
    fail(`invalid ${description} quota snapshot`);
  }
  const expectedFields = [
    "canaryQuotaTag", "dispatchCount", "exists", "lifetimeUsed", "updateTime",
  ].sort();
  if (!isDeepStrictEqual(Object.keys(snapshot).sort(), expectedFields)) {
    fail(`invalid ${description} quota snapshot fields`);
  }
  if (
    !HEX_64.test(snapshot.canaryQuotaTag ?? "") ||
    typeof snapshot.exists !== "boolean" ||
    !Number.isSafeInteger(snapshot.dispatchCount) || snapshot.dispatchCount < 0 ||
    snapshot.dispatchCount > MAX_CANARY_DISPATCH_COUNT ||
    !Number.isSafeInteger(snapshot.lifetimeUsed) || snapshot.lifetimeUsed < 0 ||
    snapshot.lifetimeUsed > MAX_TRIAL_LIFETIME_COUNT
  ) {
    fail(`invalid ${description} quota snapshot values`);
  }
  if (snapshot.exists) {
    if (!isValidFirestoreUpdateTime(snapshot.updateTime)) {
      fail(`invalid ${description} quota snapshot update timestamp`);
    }
  } else if (
    snapshot.dispatchCount !== 0 || snapshot.lifetimeUsed !== 0 || snapshot.updateTime !== null
  ) {
    fail(`invalid absent ${description} quota snapshot`);
  }
}

function pinnedProviderCost(inputTokens, outputTokens) {
  return Number((
    (inputTokens / 1_000_000) * 0.25 +
    (outputTokens / 1_000_000) * 1.50
  ).toFixed(10));
}

export function verifyCorrelatedPhase({ phase, events, quotaBefore, quotaAfter }) {
  if (!Array.isArray(events)) fail("invalid projected event input");
  if (!["exact-reuse", "fresh-scan", "scan-as-new"].includes(phase)) fail("invalid canary phase");
  validateQuotaSnapshot(quotaBefore, "before");
  validateQuotaSnapshot(quotaAfter, "after");
  if (phase === "exact-reuse") {
    if (events.length !== 0) fail("exact reuse requires zero correlated events of every outcome");
    if (!isDeepStrictEqual(quotaBefore, quotaAfter)) {
      fail("exact reuse requires an unchanged exact quota snapshot");
    }
    return { phase, eventCount: 0, quotaUnchanged: true };
  }

  for (const event of events) {
    if (!event || typeof event !== "object" || Array.isArray(event)) fail("invalid projected scanner event");
    const unexpected = Object.keys(event).filter((field) => !ALLOWED_EVENT_FIELDS.has(field));
    if (unexpected.length > 0) fail("unexpected scanner event field");
    for (const [field, value] of Object.entries(event)) validateEventValue(field, value, event);
    validateScannerEventVocabulary(event);
  }
  if (
    new Set(events.map((event) => event.canaryCorrelationId)).size !== 1 ||
    new Set(events.map((event) => event.canaryOperationTag)).size !== 1
  ) {
    fail("fresh canary events do not share one correlation and operation tag");
  }
  if (events.length !== 13) fail("fresh canary requires the exact 13-event server sequence");

  const commonFields = [
    "event", "severity", "schemaVersion", "eventType", "outcome",
    "canaryCorrelationId", "canaryOperationTag",
  ];
  const withQuotaTag = [...commonFields, "canaryQuotaTag"];
  const authorizationEvents = events.filter((event) => /^authorization_/.test(event.eventType ?? ""));
  if (authorizationEvents.length !== EXPECTED_AUTHORIZATION_CONTROLS.length) {
    fail("fresh canary requires exactly four total authorization outcomes");
  }
  const authorizationControls = authorizationEvents
    .filter((event) => event.eventType === "authorization_acceptance" && event.outcome === "accepted")
    .map((event) => event.control);
  const canonicalAuthorizationControls = [...authorizationControls].sort();
  const expectedCanonicalAuthorizationControls = [...EXPECTED_AUTHORIZATION_CONTROLS].sort();
  if (!isDeepStrictEqual(canonicalAuthorizationControls, expectedCanonicalAuthorizationControls)) {
    fail("fresh canary requires exactly four affirmative authorization controls");
  }
  for (const control of EXPECTED_AUTHORIZATION_CONTROLS) {
    const event = requireExactlyOne(
      authorizationEvents,
      "authorization_acceptance",
      (candidate) => candidate.control === control && candidate.outcome === "accepted",
      `${control} authorization acceptance`
    );
    const early = control === "app_check" || control === "storekit_jws";
    requireExactEventFields(event, [...(early ? commonFields : withQuotaTag), "control"], `${control} authorization`);
  }

  const preVerificationGate = requireExactlyOne(
    events, "request_gate_decision",
    (event) => event.control === "pre_verification" && event.outcome === "allowed",
    "allowed pre-verification request gate"
  );
  requireExactEventFields(preVerificationGate, [...commonFields, "control"], "pre-verification request gate");
  const principalAttemptGate = requireExactlyOne(
    events, "request_gate_decision",
    (event) => event.control === "principal_attempt" && event.outcome === "allowed",
    "allowed principal-attempt request gate"
  );
  requireExactEventFields(principalAttemptGate, [...withQuotaTag, "control"], "principal-attempt request gate");

  const budget = requireExactlyOne(
    events, "budget_state",
    (event) => event.outcome === "observed" && event.budgetMode === "normal",
    "normal observed budget state"
  );
  requireExactEventFields(budget, [...commonFields, "budgetMode", "stateAgeSeconds"], "budget state");
  if (!Number.isFinite(budget.stateAgeSeconds) || budget.stateAgeSeconds < 0 || budget.stateAgeSeconds > 86_400) {
    fail("fresh canary budget state is stale");
  }

  const globalDispatch = requireExactlyOne(
    events, "global_dispatch_decision",
    (event) => event.outcome === "allowed",
    "allowed global provider dispatch"
  );
  requireExactEventFields(globalDispatch, withQuotaTag, "global provider dispatch");

  const requestEvents = matchingEvents(events, "request_result");
  if (requestEvents.length !== 1) fail("fresh canary requires exactly one total request result");
  const request = requestEvents[0];
  if (request.outcome !== "completed" || request.statusCode !== 200) {
    fail("fresh canary request result must be completed with status 200");
  }
  requireExactEventFields(request, [
    ...withQuotaTag, "statusCode", "statusClass", "latencyMs",
    "cacheDisposition", "localCacheDisposition",
  ], "request result");
  if (
    request.statusClass !== "2xx" ||
    request.cacheDisposition !== "fresh_dispatch" ||
    request.localCacheDisposition !== "not_observed"
  ) {
    fail("fresh canary request result did not retain the exact success cache/status contract");
  }
  const quotaEvents = matchingEvents(events, "quota_decision");
  if (quotaEvents.length !== 1) fail("fresh canary requires exactly one total quota decision");
  const quota = quotaEvents[0];
  if (quota.outcome !== "allowed" || quota.quotaDelta !== 1) {
    fail("fresh canary requires an allowed quota delta of one");
  }
  requireExactEventFields(quota, [
    ...withQuotaTag, "tier", "quotaUsed", "quotaLimit", "quotaRemaining", "quotaDelta",
  ], "quota decision");
  if (
    quota.tier !== "trial" || quota.quotaLimit !== 5 ||
    !Number.isSafeInteger(quota.quotaUsed) || quota.quotaUsed < 1 || quota.quotaUsed > 5 ||
    quota.quotaUsed !== quotaAfter?.dispatchCount ||
    quota.quotaRemaining !== Math.min(
      5 - quota.quotaUsed,
      25 - quotaAfter?.lifetimeUsed
    )
  ) {
    fail("General Kenobi sandbox quota did not match the pinned 5-scan trial contract");
  }
  const cacheEvents = matchingEvents(events, "cache_decision");
  if (cacheEvents.length !== 1) fail("fresh canary requires exactly one total cache decision");
  const cache = cacheEvents[0];
  if (cache.cacheDisposition !== "fresh_dispatch" || cache.outcome !== "observed") {
    fail("fresh canary requires one observed fresh cache dispatch");
  }
  requireExactEventFields(cache, [
    ...withQuotaTag, "cacheDisposition", "localCacheDisposition",
  ], "cache decision");
  if (cache.localCacheDisposition !== "not_observed") {
    fail("fresh canary cache decision reported an unexpected local cache state");
  }
  const providerEvents = matchingEvents(events, "provider_call");
  if (providerEvents.length !== 2) fail("fresh canary requires exactly two total provider events");
  const expectedProvider = "google-gemini";
  const expectedModel = "gemini-3.1-flash-lite";
  const providerStart = providerEvents.find((event) => event.outcome === "started");
  const providerCompletion = providerEvents.find((event) => event.outcome === "completed");
  if (!providerStart || !providerCompletion) {
    fail("fresh canary requires one provider start and one provider completion");
  }
  for (const providerEvent of [providerStart, providerCompletion]) {
    if (
      providerEvent.providerId !== expectedProvider ||
      providerEvent.modelId !== expectedModel
    ) {
      fail("fresh canary provider or model did not match the pinned Gemini configuration");
    }
  }
  requireExactEventFields(providerStart, [
    ...withQuotaTag, "providerId", "modelId",
  ], "provider start");
  requireExactEventFields(providerCompletion, [
    ...withQuotaTag, "providerId", "modelId", "latencyMs", "inputTokens",
    "outputTokens", "totalTokens", "estimatedCostUSD",
  ], "provider completion");
  if (
    providerCompletion.totalTokens < providerCompletion.inputTokens + providerCompletion.outputTokens ||
    providerCompletion.estimatedCostUSD !== pinnedProviderCost(
      providerCompletion.inputTokens,
      providerCompletion.outputTokens
    )
  ) {
    fail("fresh canary provider token totals or estimated cost do not match the pinned model contract");
  }

  if (!HEX_64.test(quota.canaryQuotaTag ?? "")) fail("fresh canary quota tag is missing");
  if (
    quotaBefore?.canaryQuotaTag !== quota.canaryQuotaTag ||
    quotaAfter?.canaryQuotaTag !== quota.canaryQuotaTag
  ) {
    fail("quota snapshots are not bound to the correlated principal");
  }
  for (const event of events.filter((candidate) => candidate.canaryQuotaTag !== undefined)) {
    if (event.canaryQuotaTag !== quota.canaryQuotaTag) {
      fail("correlated event quota tag does not match the accepted quota principal");
    }
  }
  if (
    !Number.isSafeInteger(quotaBefore?.dispatchCount) ||
    !Number.isSafeInteger(quotaAfter?.dispatchCount) ||
    quotaAfter.dispatchCount - quotaBefore.dispatchCount !== 1
  ) {
    fail("fresh canary exact quota delta is not one");
  }
  if (
    !Number.isSafeInteger(quotaBefore?.lifetimeUsed) ||
    !Number.isSafeInteger(quotaAfter?.lifetimeUsed) ||
    quotaAfter.lifetimeUsed - quotaBefore.lifetimeUsed !== 1
  ) {
    fail("fresh sandbox canary lifetime quota delta is not one");
  }
  return {
    phase,
    eventCount: events.length,
    requestCompleted: 1,
    requestStatusCode: request.statusCode,
    authorizationControls: [...EXPECTED_AUTHORIZATION_CONTROLS],
    quotaDelta: 1,
    cacheFreshDispatch: 1,
    providerStarted: 1,
    providerCompleted: 1,
    providerId: expectedProvider,
    modelId: expectedModel,
    canaryQuotaTag: quota.canaryQuotaTag,
  };
}

function parseArguments(argv) {
  const values = {};
  for (let index = 0; index < argv.length; index += 2) {
    const key = argv[index];
    const value = argv[index + 1];
    if (!key?.startsWith("--") || value === undefined) fail("invalid command arguments");
    values[key.slice(2)] = value;
  }
  return values;
}

function readStandardInputJSON() {
  const value = readFileSync(0, "utf8");
  try {
    return parseJsonWithoutDuplicateKeys(value || "null");
  } catch (error) {
    if (error instanceof SyntaxError) fail("invalid JSON input");
    throw error;
  }
}

export function assertSafeEvidenceContent(value) {
  if (typeof value !== "string") fail("evidence content must be text");
  try {
    rejectSensitivePayload(parseJsonWithoutDuplicateKeys(value));
  } catch (error) {
    if (error instanceof SyntaxError) rejectSensitiveText(value, { allowConsoleOperationMarker: true });
    else throw error;
  }
}

function main() {
  const [command, ...argv] = process.argv.slice(2);
  const args = parseArguments(argv);
  if (command === "assert-safe-content") {
    assertSafeEvidenceContent(readFileSync(0, "utf8"));
    return;
  }
  const input = readStandardInputJSON();
  let output;
  if (command === "project-events") {
    output = projectCorrelatedScannerEvents(input, {
      correlationId: args.correlation,
      operationTag: args.operation,
    });
  } else if (command === "quota-snapshot") {
    output = findCanaryQuotaSnapshot(input, {
      canaryId: args["canary-id"],
      quotaTag: args["quota-tag"],
    });
  } else if (command === "verify-phase") {
    output = verifyCorrelatedPhase(input);
  } else {
    fail("unknown evidence command");
  }
  process.stdout.write(`${JSON.stringify(output)}\n`);
}

if (process.argv[1] && import.meta.url === pathToFileURL(process.argv[1]).href) {
  try {
    main();
  } catch (error) {
    process.stderr.write(`ERROR: ${error.message}\n`);
    process.exitCode = 1;
  }
}
