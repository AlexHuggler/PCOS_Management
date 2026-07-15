# Task 3 Positive General Kenobi Canary Report

Date: 2026-07-15 (America/Chicago)

Branch: `codex/cyclebalance-1.0.5-rc`

Prior implementation commits:

- `3e6cc191b59cc49661adef2fd6dd8027337e2fcf` (`feat: add approval-gated meal scan canary`)
- `c6949d1` (`docs: record positive canary implementation`)
- `13e44565f850e94256d454113498585acf276631` (`fix: harden positive meal scan canary`)

## Outcome

FROZEN LOCAL CANARY/EVIDENCE BOUNDARY ACCEPTED; LIVE CANARY NOT RUN. The final independent review found no critical, important, or minor findings within the documented JSON, Unicode, control, terminal, structured-recursion, canonical-mask, identifier, and CLI-atomicity scope. The accepted boundary intentionally excludes arbitrary reversible non-JSON encodings such as `\\xNN`, `%NN`, and HTML entities. The full local proxy suite reports 368 passed, 0 failed, 0 skipped; the dedicated frozen suites report 90/90 evidence-parser, 59/59 runner, 14/14 Apple-IAP provisioner, and 8/8 canary-deploy tests. This acceptance covers only the frozen local implementation and does not authorize the approval-gated General Kenobi or Cloud Run live canary.

No Cloud Run deploy or IAM mutation, Secret Manager write or rotation, RevenueCat configuration change, device build/install/launch, General Kenobi interaction, TestFlight distribution, App Store action, or publication occurred during this remediation. A real entitled scan is still an owner-approved external gate; this work does not claim it passed.

## Review Findings Addressed

1. **Correlated affirmative evidence:** a random canary UUID is accepted only by a development-signed runtime whose embedded profile has `get-task-allow=true`. The client sends the UUID plus `SHA-256(requestId)` in canary-only headers and prints only the operation hash immediately before dispatch. The proxy hash-validates both, preserves the public response schema, and correlates allowlisted App Check, StoreKit JWS, current Apple status, RevenueCat, quota, cache, provider, and request events. Ordinary scanner requests emit none of the canary fields or affirmative events.
2. **Owner-only seed receipt:** seed writes a mode-`0600` content-free receipt only after verified disabled/private rollback. It records lifecycle, approved source and service revisions, random canary ID/hash, exact quota tag, IAM digest, General Kenobi identities, and original/canary app state. Rescan is blocked until the 24-hour result TTL plus a 10-minute ingestion/skew buffer.
3. **Two-window device lifecycle:** a successful seed keeps the development canary installed and preserves local repeat state. Rescan does not rebuild or reinstall. Initially absent devices are uninstalled and verified absent only after final rescan; initially present devices stop with an explicit manual binary/data restore handoff because CoreDevice cannot export the original binary.
4. **Apple IAP key state machine:** `provision-apple-iap-key-v1.sh` defaults to non-mutating dry run, inspects resource/version/IAM metadata before key-file access, aborts on any enabled/disabled/destroyed version, permits only zero versions to exact enabled `v1`, prevents `v2`, and reads back exact proxy-service-account-only `secretAccessor` IAM without printing key material.
5. **Cloud Run IAM:** preflight rejects both `allUsers` and `allAuthenticatedUsers`, requires the invoker IAM check, snapshots a canonical restorable policy before mutation, and restores/compares the exact policy and digest on every armed rollback. Rescan also requires the seed's disabled revision/IAM digest and a bounded no-mutation audit readback; the runbook explicitly says this is continuity evidence, not absolute audit proof.
6. **Strict evidence projection:** Cloud Logging output is piped directly through `positive-canary-evidence.mjs`; raw logs are never written. The helper rejects unexpected fields, normalized sensitive field-name families, bearer/JWT/JWS, StoreKit/App Check identifiers, JPEG/PNG base64, PEM, OAuth/RevenueCat key patterns, oversized strings, and high-entropy arbitrary values before emitting a bounded allowlisted projection. Only the exact numeric `inputTokens`, `outputTokens`, and `totalTokens` fields are exempt from token-name rejection. Exact reuse requires zero correlated events of every outcome and an unchanged exact quota snapshot.
7. **Canary-specific deploy mode:** `DEPLOY_MODE=canary` pins the production project/region/service, requires the canary digest, skips global `gcloud config` mutation and Firestore Rules deployment, and limits mutations to the reviewed Cloud Run deployment/access path. General deploy behavior remains unchanged.
8. **Live RevenueCat configuration verification:** `verify-revenuecat-offering-v2.sh` is GET-only, accepts a v2 secret through hidden/stdin memory only, and fails closed unless the active current offering is `default`, exact monthly/annual packages map to the exact `P1M`/`P1Y` products, and active `CycleBalance Unlimited` contains both products. The live harness pipes only the pinned Secret Manager version into this verifier and never persists or exposes it.

Additional hardening verifies a clean tracked/untracked worktree at an owner-approved full commit, strict code signing, pinned team/application identifiers, General Kenobi in `ProvisionedDevices`, and CoreDevice/Xcode UDID continuity. Command-shim tests cover failures, signals, rollback errors, and both initially present/absent device outcomes.

## Second Independent Re-review Remediation Implemented (Accepted In Final Frozen Review)

1. **Rollback kill-switch precedence:** disabled server mode now returns `503 feature_disabled` before canary-correlation validation. Disabled canary deploys require an empty correlation value and omit the environment variable entirely; the final authenticated rollback probe therefore exercises the actual disabled posture.
2. **Log order:** Cloud Logging reads explicitly use `--order=asc`, while affirmative authorization verification compares an exact duplicate-free set independently of input order.
3. **Pinned deploy resources:** canary mode rejects drift in runtime/build service-account names and all four Secret Manager resource names. The runner explicitly passes each reviewed identity/name and reads back the deployed runtime identity plus every exact numeric secret reference from initial, enabled, and final revisions.
4. **Signals and cleanup:** `EXIT`, `INT`, and `TERM` have distinct handlers. Interruption returns `130`/`143`, successful status is impossible before `CANARY_RUN_COMPLETED=true`, traps are removed before cleanup, and rollback/device finalization runs once.
5. **Complete redaction path:** correlated non-scanner JSON/text is checked for sensitive fields and encodings before it can be ignored. Device-console segments and projected event files invoke the prohibited-content checker. The restricted evidence directory retains only redacted per-phase machine JSON plus exact final disabled revision/IAM digest.
6. **Approved source boundary:** canary deploy requires a full approved commit, rechecks exact `HEAD` plus a clean tracked/untracked worktree immediately before `gcloud run deploy --source`, and aborts before mutation on drift.
7. **Apple IAP inspection and key validation:** dry run now performs authenticated read-only resource/version/IAM inspection without Cloud writes or key-file access. Live mode repeats inspection, checks approval afterward, and uses Node cryptography to parse PKCS#8 and require EC P-256 before the first mutation. Fake PEM, RSA, and P-384 fixtures fail before Secret Manager mutation.
8. **Curl configuration isolation:** every canary HTTP probe starts with `curl --disable`, preventing a local `.curlrc` from enabling verbose/trace behavior around bearer-authenticated calls.
9. **Evidence retention:** sanitized phase arithmetic and exact final revision/IAM posture survive temporary-directory cleanup under mode-`0600` files in a mode-`0700` evidence directory; raw logs and console segments remain ephemeral.

## Prior Frozen Review Remediation Implemented (Re-reviewed; One Important Privacy Finding Remained)

1. **Enabled readiness ordering:** production App Check verification now precedes enabled-canary correlation validation. A headerless public readiness request returns exact `401 app_check_required`, while a valid correlated request still emits the exact four affirmative authorization controls.
2. **Rollback source independence:** the runner creates one mode-`0400` `git archive` of the approved commit's proxy subtree before cloud mutation and passes the same archive/digest to enable and rollback. Canary deploys compare it byte-for-byte with `git archive` from the approved commit, extract a private read-only snapshot, deploy only that snapshot, and recheck content plus archive digest after packaging. Enabled deploy still requires clean approved `HEAD`; disabled rollback deliberately remains available if the checkout becomes dirty afterward.
3. **Complete redaction lifetime:** the evidence helper recursively checks the complete Cloud Logging entry, including generic token, secret, photo, and food-name fields, before selecting or ignoring a payload. The device checker rejects generic assignments and scans startup, each phase, and the complete final console after termination; a sensitive-console failure is retained as a failed run without preventing cloud rollback.
4. **Real Secret Manager inventory identity:** the Apple IAP inventory query uses the short-name contains filter proven by read-only metadata, then accepts only the exact pinned numeric-project resource `projects/947929010052/secrets/cyclebalance-app-store-iap-private-key`.
5. **Cloud Build provenance readback:** enabled and disabled revisions read the service build ID/name/service-account/source-location annotations, describe that regional Cloud Build, and fail closed unless the pinned build service account, immutable GCS source generation, successful build, ready revision, deployed image digest, and `results.images` digest all tie together.
6. **Curl isolation:** the deploy-script readiness probe now starts with `curl --disable`, matching every bearer-authenticated and anonymous canary probe.

## Prior Privacy Fail-open Remediation Implemented (Re-reviewed; Third Remediation Required)

1. **Central normalized field-name policy:** the evidence helper now normalizes every field name and applies one fail-closed predicate across token, secret, credential, key, JWS/JWT, transaction ID/payload, image/photo data/bytes, and meal/food name/title families. Composite, separator, plural, and payload variants no longer depend on exact-set membership.
2. **Numeric token-count compatibility:** only exact finite nonnegative numeric `inputTokens`, `outputTokens`, and `totalTokens` fields bypass token-name rejection. The same exact names in textual console assignments are accepted only with a nonnegative numeric value.
3. **Arbitrary-string entropy:** strings in scanner, non-scanner, and outer Cloud Logging fields now undergo candidate-level high-entropy rejection before payload selection. A generic 44-character high-entropy value fails in both payload and complete-entry locations.
4. **Whole-console parity:** `assert_no_prohibited_content` delegates to the same content checker used by the evidence helper, so startup, phase segments, final console tail, and retained projected evidence use the same normalized field and entropy policy.
5. **Exact regressions:** separate tests cover `authToken`, `session_token`, `credential`, `image`, `imageBytes`, `foodNames`, `mealTitle`, `storeKitPayload`, and the 44-character entropy value in both the JavaScript correlated/full-entry paths and the shell whole-console path. Positive controls preserve the three allowed numeric token-count fields.

## Third Privacy Boundary Remediation Implemented (Re-reviewed; One Important UUID Finding Remained)

1. **Real Cloud Logging envelope:** only exact pinned Cloud Run `logName`, trace, insert ID, RFC3339 timestamps, resource type/labels, and instance ID paths receive tightly validated metadata exemptions. A realistic complete envelope passes direct projection and the content-check CLI; arbitrary strings elsewhere remain fully scanned.
2. **Ancestor-aware recursion:** arrays preserve their semantic ancestor path and objects append raw field names. Nested `meal.name`, `foods[].name`, `transaction.id`, and `storeKit.payload` now fail before payload selection, including when nested outside `jsonPayload`.
3. **Canonical hash confinement:** generic 64-character lowercase hex is rejected regardless of Shannon entropy. Only exact raw `canaryCorrelationId`, `canaryOperationTag`, and `canaryQuotaTag` fields may carry a validated 64-hex digest; invalid canonical fields fail closed.
4. **Exact numeric names:** only raw case-sensitive `inputTokens`, `outputTokens`, and `totalTokens` with finite nonnegative numeric values are allowed. Structured and plain/JSON console forms reject `input_tokens`, `InputTokens`, `input.tokens`, `input-tokens`, and negative exact counts.
5. **CLI atomicity:** the real envelope succeeds through both direct CLI paths, while generic hex and alias fixtures return nonzero with empty stdout so no partial evidence can be persisted.

## Fourth UUID Boundary Remediation Implemented (Re-reviewed; Two Important Findings Remained)

1. **Length-independent UUID rejection:** UUID-shaped identifiers are detected directly instead of relying on the 40-character entropy candidate, so the 36-character value cannot bypass scanning.
2. **No generic UUID exemption:** the blanket UUID exception is removed. Structured payloads, complete outer entries, and `assert-safe-content` reject generic UUID values before evidence projection.
3. **Console parity:** both `diagnosticValue=<UUID>` and `canaryId=<UUID>` fail in plain and JSON console forms through the shared content checker.
4. **Exact envelope compatibility:** a UUID-shaped value remains allowed only at the tightly validated root Cloud Logging `insertId` path; no broad UUID field or value exception was added.
5. **CLI atomicity:** UUID failures return nonzero with empty stdout, preventing partial evidence persistence.

## Fifth Final-posture And Identifier Remediation Implemented (Re-reviewed; One Important Assignment-boundary Finding Remained)

1. Exact root `iamPolicyDigest` is path-validated as 64 lowercase hex; JSON payload/label aliases remain rejected. Real final-disabled posture persistence now succeeds and retains mode `0600`.
2. Generic privacy matching rejects every 8-4-4-4-12 hex-dashed substring regardless of version, variant, or adjacent hex, plus every contiguous hex run of 32 or more characters.
3. Only validated root `insertId`, `trace`, `labels.instanceId`, root `iamPolicyDigest`, and exact canonical canary hash fields bypass generic identifier rejection.
4. Plain assignment parsing preserves leading `_`, `.`, and `-`; prefixed/suffixed canonical hash aliases are rejected rather than normalized into canonical fields.

## Sixth Assignment-boundary Remediation Implemented (Re-reviewed; One Important Digit-prefix Finding Remained)

1. Plain assignment parsing now uses a zero-width boundary that accepts any preceding character outside the field alphabet `[A-Za-z0-9_.-]`. Punctuation-wrapped fields are inspected without consuming the delimiter needed to inspect a nested second assignment.
2. Leading `_`, `.`, and `-` remain part of the captured field name, so `_canaryCorrelationId`, `.canaryOperationTag`, and `-canaryQuotaTag` remain noncanonical and fail closed.
3. Direct helper, `assert-safe-content` CLI, and whole-console fixtures reject parenthesis-, bracket-, semicolon-, pipe-, prefix-, newline-, and outer-assignment forms, including `outer=authToken=abc` and `outer=token=abc`.
4. Exact wrapped numeric `inputTokens` and canonical `canaryOperationTag` values remain accepted, as does the dedicated `CYCLEBALANCE_CANARY_OPERATION tag=<canonical hash>` line.

## Seventh Digit-prefix Remediation Implemented (Re-reviewed; One Important Length-boundary Finding Remained)

1. The assignment parser now permits a digit as the first non-punctuation field-token character, while retaining the zero-width field boundary and capturing the complete raw field name for the normalized sensitivity predicate.
2. Direct-helper, atomic `assert-safe-content` CLI, and whole-console fixtures reject `1authToken=abc`, `outer=1authToken=abc`, `1foodName=breakfast`, `outer=(1credential=abc)`, digit-prefixed generic token and exact-token aliases, and digit-prefixed canonical-hash aliases.
3. Leading-punctuation fixtures, a 128-character punctuation prefix, and the 64-character field-token boundary remain fail closed without broadening the parser's existing tail bound or introducing a new overlapping wildcard.
4. Wrapped exact `inputTokens`, `outputTokens`, and `totalTokens` plus all three exact canonical canary hash fields and the dedicated operation-tag line remain accepted.

## Eighth Length-boundary Remediation Implemented (Re-reviewed; One Important Wrapper-boundary Finding Remained)

1. The assignment parser no longer imposes an arbitrary field-name cap. One uncapped field-alphabet quantifier captures the complete raw `[A-Za-z0-9_.-]+` name behind the existing zero-width boundary before the normalized sensitivity predicate runs.
2. The parser shape remains linear: the field quantifier is followed by disjoint optional quote, horizontal whitespace, and assignment-delimiter classes, with no nested or overlapping wildcard quantifiers.
3. Direct-helper, atomic `assert-safe-content` CLI, and whole-console fixtures reject sensitive fields of lengths 63, 64, 65, 66, 80, and 128, overlength numeric/canonical aliases, a 4,096-character alphanumeric prefix, and a long punctuation prefix.
4. Wrapped exact numeric token fields, all three exact canonical canary hash fields, the dedicated operation-tag line, and a long benign field remain accepted.

## Ninth Wrapper, Unicode, And Canonical-span Remediation Implemented (Review Interrupted By One Log-compatibility Blocker)

1. Assignment inspection is now delimiter-centric and linear. It masks terminal ANSI escape sequences without changing string offsets, tracks hard assignment boundaries once, and evaluates Unicode letter/number field tokens plus one-, two-, and three-token compound names immediately before every `:` or `=` delimiter.
2. Closing quotes, brackets, parentheses, braces, Unicode punctuation/digits, CR/LF/vertical whitespace, nested wrappers, and compound fields such as `transaction id`, `storeKit payload`, `meal name`, and `food title` reach the normalized sensitive-field predicate in direct, CLI, and whole-console paths.
3. Exact numeric token counters remain allowed only with an exact raw terminal field and a nonnegative decimal textual value. A closing wrapper between the raw field and delimiter, digit/separator alias, negative/non-numeric value, or sensitive companion token fails closed.
4. Canonical 64-hex exemptions are no longer value-global. The helper records only exact source index ranges for a validated canonical assignment or dedicated operation line; reusing the same hash under `diagnosticValue` or any other location is rejected by both generic-identifier and entropy scans.
5. The parser retains linear behavior for 4,096-character alphanumeric/punctuation fixtures, does not bridge intervening ordinary field words, and preserves exact JSON/plain canonical and numeric controls.

## Tenth Successful-metric Log Compatibility Remediation Implemented (Re-reviewed; One Important Unicode/compound Finding Remained)

1. The existing content-free `meal_scan_estimate` metric now emits the allowlisted `inputTokens` field instead of the rejected `promptTokens` alias. `outputTokens`, cost, quota, tier, budget mode, and cache status remain unchanged; no identifier or meal content was added.
2. The proxy privacy contract test requires `promptTokens` to be absent and exact `inputTokens`/`outputTokens` values to be present on a successful metric.
3. Direct helper, atomic CLI, and sourced whole-console fixtures now pass the console-formatted metric produced by a successful provider call, proving complete-log scanning and server logging use the same field contract.

## Eleventh Fullwidth-delimiter And Unbounded-compound Remediation Implemented (Re-reviewed; One Important Non-ASCII-key Finding Remained)

1. Field normalization now applies Unicode NFKC before the ASCII sensitivity policy, so compatibility-width spellings of sensitive names cannot bypass the same normalized predicate.
2. The offset-preserving assignment view maps fullwidth/small/vertical colon and equals forms to their ASCII delimiters after ANSI masking; exact source indices for canonical hash exemptions remain unchanged.
3. One-, two-, and three-token windows are retained for local field detection, while a single linear complete-segment check covers sensitive relationships separated by four or more tokens without nested window expansion.
4. Direct, atomic CLI, and whole-console cases now reject fullwidth `authToken` delimiters/names and four- or five-token StoreKit-payload and meal/food-name/title compounds; the successful content-free metric and canonical occurrence controls remain green.

## Twelfth Fail-closed Non-ASCII Evidence-key Remediation Implemented (Re-reviewed; One Important Field-expression Finding Remained)

1. Any non-ASCII evidence field token or structured object key now fails closed before compatibility normalization. Legitimate emitted Cloud Logging, scanner-event, final-posture, and content-free metric keys are all ASCII.
2. Plain Greek-omicron and Cyrillic-o `authToken` substitutions plus the same keys in structured JSON are rejected by direct helper, atomic CLI, and whole-console paths.
3. Unicode values under safe ASCII keys remain accepted, keeping the policy scoped to evidence keys rather than user-language text.

## Thirteenth Exact Field-expression Suffix Remediation Implemented (Re-reviewed; One Important Unquoted-compound Finding Remained)

1. After a prior assignment delimiter, the parser now inspects only the actual terminal field expression rather than treating the previous value as another field. Unicode values such as `mañana`, `食事`, and `déjeuner équilibré` remain safe before a later ASCII `status` assignment.
2. Non-ASCII adjacency is checked across the complete punctuation-attached field suffix, so emoji or other symbols immediately before or after an ASCII field token fail closed.
3. At a true record boundary the complete field label is still inspected. After another assignment, quoted/bracketed compound labels remain complete, and unquoted `id`, `identifier`, `payload`, `name`, and `title` suffixes retain bounded ancestor inspection.
4. The parser remains single-pass over delimiters and performs only constant-count suffix checks; long-field, fullwidth, compound, canonical-range, metric, numeric, and ANSI controls remain green.

## Fourteenth Unquoted-compound Suffix Remediation Implemented (Re-reviewed; One Important Trailing-token Finding Remained)

1. After a prior assignment, special terminal leaves (`id`, `identifier`, `payload`, `name`, and `title`) now inspect one complete consecutive-ASCII token suffix instead of only the last three tokens. This closes unquoted four- and five-token StoreKit-payload and meal/food-name/title relationships without adding nested or combinatorial scans.
2. A preceding non-ASCII token remains a hard boundary for this suffix, so localized values such as `mañana`, `食事`, and `déjeuner équilibré` remain accepted before a later safe ASCII assignment.
3. Display-name detection now applies to the complete normalized ASCII suffix rather than exact equality, preventing a prior ASCII value from masking a later `display name` field expression.
4. Non-ASCII-key, adjacent-symbol, wrapped-compound, fullwidth-delimiter, canonical-range, numeric-token, successful-metric, and exact Unicode-value controls remain unchanged.

## Fifteenth Post-assignment Field-grammar Remediation Implemented (Re-reviewed; One Important First-segment Numeric-prefix Finding Remained)

1. The post-assignment parser no longer depends on a terminal-leaf allowlist. It treats exactly one leading unquoted token, or one complete leading ASCII-quoted string, as the prior assignment value; the remaining raw suffix is the next field expression.
2. Any non-ASCII character in that derived field expression fails closed. This catches confusable letters, emoji, and Unicode tokens inserted before a trailing ASCII leaf while preserving the reviewed unquoted single-token and quoted multi-token localized values.
3. Sensitive matching runs over both the derived field-expression tokens and a complete ASCII projection of the segment. The second view prevents a sensitive family that begins in the first ambiguous token (`store kit payload`, `meal name`, or `display name`) from hiding behind the value boundary.
4. Exact numeric-token fields may omit only their terminal allowlisted token from compound matching. Sensitive prefixes before `inputTokens`, `outputTokens`, or `totalTokens` still reject. Canonical hash occurrence confinement, exact numeric validation, wrapper checks, successful metric compatibility, and linear delimiter processing remain unchanged.

## Sixteenth First-segment Numeric-prefix Remediation Implemented (Re-reviewed; Two Important And One Minor Field-grammar Findings Remained)

1. At an initial or hard-delimiter-reset assignment segment, an exact numeric-token leaf now exempts only that terminal token. Every preceding token is still projected through the normalized sensitive-field predicate.
2. Bare and wrapped exact `inputTokens`, `outputTokens`, and `totalTokens` counters remain accepted, as do benign prefixes such as `status inputTokens=120`. Sensitive prefixes such as `auth token`, `store kit payload`, `meal name`, or `authorization header value` reject before evidence projection.
3. Post-assignment numeric handling, localized-value boundaries, canonical hash ranges, complete ASCII projection, non-ASCII field-expression rejection, and atomic CLI output remain unchanged.

## Seventeenth Record-ancestry, Confusable, And Quoted-value Remediation Implemented (Re-reviewed; One Important Confusable Finding Remained)

1. A bounded record context now carries only the semantic field-family flags needed for `meal`/`food` plus `name`/`title`, `transaction` plus `id`/`payload`, `store` plus `kit` plus `payload`, and `display` plus `name`. It updates after every assignment and resets only at the existing hard record delimiters, catching relationships split across adjacent plain assignments without retaining values.
2. The complete ambiguous segment is projected through NFKC plus a conservative Greek/Cyrillic homoglyph skeleton before sensitive matching. Fullwidth `authToken`, Greek/Cyrillic `o` substitutions, `secrεt`, and relationship components such as confusable `meal` or `store` can no longer disappear when the first token is treated as a prior value.
3. Leading value parsing now supports matched straight, curly, guillemet, and single-guillemet quote pairs. Localized quoted values are consumed before the raw ASCII field-expression check, while sensitive English or confusable content still reaches the complete-segment skeleton.
4. Context storage is fixed-size booleans and each segment is scanned a constant number of times, retaining linear behavior. Numeric-token and canonical-hash exemptions, wrapper checks, successful metric compatibility, and atomic CLI output remain unchanged.

## Eighteenth Mixed-script Wildcard Remediation Implemented (Re-reviewed; One Important Localization Finding And One Minor Quote Finding Remained)

1. Mixed ASCII/Unicode tokens now receive a second NFKC projection in which every remaining Unicode letter or number becomes a one-character wildcard. Sensitive keywords and relationship components are matched against that projection, so an omitted homoglyph mapping cannot silently delete a character from `meal`, `display`, `store`, `photo`, `image`, `credential`, or the direct secret families.
2. Wildcard matching is token-local. Wildcards cannot bridge into the next ordinary token to create short-key false positives; multi-token relationships are evaluated by their semantic components instead.
3. The bounded record context also consumes the wildcard projection. A confusable ancestor separated from `name`, `title`, `payload`, or another relationship component by benign assignments remains fail closed.
4. Pure non-ASCII localized tokens remain values rather than wildcard keys, while mixed localized controls such as `PCOS食事`, `clé`, `mañana`, and quoted Japanese/French/Spanish values remain accepted. The existing explicit Greek/Cyrillic skeleton remains defense in depth.

## Nineteenth Exact-confusable And Localization Remediation Implemented (Re-reviewed; One Important Official-mapping Finding Remained)

1. Arbitrary one-character wildcards are removed. The helper introduced a static Unicode UTS #39 17.0.0 confusable-to-ASCII skeleton plus conservative Greek/Cyrillic overrides. NFKD and combining-mark removal preserved accented-letter handling without allowing unrelated localized characters to impersonate `key`, `jws`, `jwt`, or relationship components; the frozen review later proved that several broad overrides replaced safer official mappings.
2. Any ambiguous token containing an unmapped non-ASCII character is excluded from the confusable projection as a whole, so CJK text cannot disappear and concatenate surrounding ASCII into a sensitive word. Exact confusable symbols are included in assignment tokenization; supplementary-plane and non-Greek/Cyrillic lookalikes still fail closed.
3. The fixed-size relationship context consumes the complete exact-confusable segment, preserving confusable ancestors across benign assignments, while an unrelated localized value cannot create `id`, `name`, `payload`, or another short component. Hard record delimiters and numeric/canonical handling are unchanged.
4. Matched Japanese `「」` and `『』` value quotes join the existing straight, curly, and guillemet pairs. Benign Japanese, CJK-mixed, French, Spanish, and accented controls remain accepted without weakening atomic rejection of sensitive direct, CLI, or whole-console content.

## Twentieth UTS #39 Canonicalization, Delimiter, Localization, And Linearity Remediation Implemented (Re-reviewed; Compatibility, Mixed-residue, And Complexity Findings Remained)

1. Broad mapping overrides are removed. The static table now preserves every reviewed UTS #39 17.0.0 single-code-point source with an ASCII-alphanumeric prototype, including compatibility-decomposable and supplementary-plane characters, plus the controlled punctuation-residue prototypes that field normalization itself discards. Only the pre-existing stricter lowercase-epsilon rejection extends the official table.
2. Skeleton mapping is direct-source-first and fixed-point canonical. ASCII `0`/`1`/`I`/`m`, Greek/Cyrillic/math `M`, fullwidth forms, wrapper symbols, and official multi-character prototypes converge before comparison against equally canonical sensitive terms. Plain assignments, structured keys and ancestor paths, CLI input, and whole-console content share that predicate. A generated 8,009-case single-substitution differential against the cited Unicode table reports zero accepted bypasses.
3. All 34 reviewed single-code-point colon/equal prototypes are handled by a code-point-aware, UTF-16-offset-preserving, field-sensitive delimiter pass. Only a sensitive direct family or relationship component is interpreted as an assignment; Japanese katakana double-hyphen, Devanagari visarga, Armenian punctuation, and other quoted or unquoted localized values remain unchanged. Japanese `「」`/`『』`, curly, straight, and guillemet value boundaries remain supported.
4. Comma, semicolon, and pipe remain intra-record separators and retain the fixed-size relationship context; only NUL resets the record. Pipe is also checked as the official `l` confusable inside a candidate component, closing `credentia|`, `mea|`, `pay|oad`, and `disp|ay` without treating benign unrelated pipe-separated fields as sensitive.
5. Delimiter replacements are collected and materialized once, canonical hash ranges use constant-time set membership, and numeric/hash values use sticky offset reads instead of repeated tail copies. Measured delimiter runs scale from 4,000/8,000/16,000 cases in about 188/352/713 ms and canonical-range runs from 1,000/2,000/4,000 cases in about 48/77/154 ms on the review machine.
6. Tokenization includes combining marks, exact confusable symbols, delimiter prototypes, and controlled wrapped prototypes while retaining the all-or-nothing boundary for unrelated localized letters. CJK insertion, Japanese/French/Spanish/Armenian/Devanagari controls, `PCOS食事`, `clé`, and `mañana` remain accepted.

## Twenty-first Compatibility-symbol, Mixed-residue, And Bounded-linearity Remediation Implemented (Accepted In Final Frozen Review)

1. The complete initial inferred field expression now rejects any non-ASCII evidence-key character, including compatibility symbols that NFKD into ASCII but do not belong to a Unicode letter/number/mark category. Circled `i`/`p`/`t`/`a`/`m`/`d`/`c` prefixes, quoted variants, direct helper input, atomic CLI input, and whole-console input are covered.
2. Confusable projection no longer drops a whole token when one localized code point remains. It retains contiguous ASCII-confusable groups on both sides of a hard localized boundary, checks direct sensitive groups independently, and carries the fixed relationship flags across groups. This rejects `authTοken食`, `credential`/`authorization` compatibility variants, and `meal`/`display`/`store kit`/`transaction` mixed-residue relationships while preserving `to食ken` and the existing Japanese/CJK/localized-value controls.
3. Confusable delimiter analysis now precomputes leading quoted-value syntax in one code-point-aware pass and advances its bounded segment after every outside-quote delimiter prototype, whether replaced or left as localized text. The pipe-confusable check is a one-pass component scanner rather than an unanchored suffix-rescanning regex. ANSI CSI/OSC masking is likewise one-pass, including repeated unterminated OSC prefixes, with offset-preserving replacements materialized once.
4. The new red/green regressions cover direct, CLI, whole-console, localization, safe skipped delimiters, quoted delimiter values, and unterminated ANSI prefixes. The final full proxy suite reports 368 passed, 0 failed, 0 skipped. Independent review accepted the frozen local boundary with no findings in scope; no live canary has run.

## TDD And Verification Evidence

- Proxy correlation RED: focused canary tests initially failed because correlated fields were missing and an operation/request mismatch returned `200`; GREEN: 3 focused tests passed.
- Swift correlation RED: the focused suite failed to compile because `MealScanCanaryCorrelation` and the injected client argument were absent; GREEN: `GeminiMealScanTests` passed 31/31 after the development-profile-gated implementation.
- Second-review rollback RED: an actual disabled server with correlation configured returned `400`; GREEN: the server-level probe returns exact `503 feature_disabled` without canary headers.
- Earlier evidence-helper RED: reversed valid authorization events failed and correlated non-scanner token/JWS/image payloads projected to an empty array; GREEN: the then-current 8/8 tests passed with order-independent exact controls and fail-closed payload inspection.
- Earlier canary-deploy RED: disabled rollback rejected an empty correlation, service-account/secret overrides were accepted, and source drift reached the deploy boundary; GREEN: the then-current 4/4 tests passed.
- Earlier Apple-IAP RED: dry run made no metadata calls and fake/RSA/wrong-curve material could reach mutation; GREEN: the then-current 8/8 command-shim and real-key fixture tests passed.
- Latest readiness RED: the actual enabled server with configured correlation returned `400` to the headerless readiness request; GREEN: the integration request returns exact `401 app_check_required`, and the correlated affirmative path remains green.
- Latest source/rollback RED: disabled rollback failed on a dirty checkout and `gcloud` received the mutable proxy directory; GREEN: 7/7 deploy tests prove dirty-worktree-independent rollback, an extracted private read-only source path, packaging-time mutation detection, clean enabled-source validation, and `curl --disable`.
- Prior redaction RED: generic `token`, `secret`, `photo`, and `foodName` payload/outer-entry fields plus startup/final console content escaped; GREEN: the then-current 9/9 evidence-helper tests and the runner's whole-console-lifetime tests passed.
- Latest Apple-IAP inventory RED: a real-format numeric-project secret resource was rejected while the query used an ineffective equality filter; GREEN: 9/9 provisioner tests pass with the short-name filter and exact numeric-resource validation.
- Latest provenance RED: no build-provenance verifier or regional Cloud Build readback existed; GREEN: fixture mutations now fail for service-account, source-generation, revision, or image-digest drift.
- Prior privacy RED: the evidence-helper suite reported 10 passed and 9 failed, with one failure for each of the eight named field variants plus the arbitrary 44-character high-entropy value; the shell runner reported 27 passed and the same 9 failures. Both numeric token-count controls already passed in RED.
- Prior privacy GREEN: the then-current evidence-helper suite passed 19/19 and the positive-canary runner passed 36/36.
- Third privacy RED: the evidence-helper suite reported 20 passed and 11 failed across the real LogEntry, four ancestor paths, generic/canonical hash boundary, four structured aliases, and direct CLI atomicity. The shell runner reported 38 passed and 4 failed, one for each numeric alias; former privacy cases, exact numeric positives, negative controls, and generic 64-hex console rejection remained green.
- Third privacy GREEN: the evidence-helper suite passes 31/31 and the positive-canary runner passes 42/42, including the real envelope/CLI fixture, all nested paths, exact canonical hashes, alias/plain/JSON checks, former privacy regressions, sealed enable/rollback source reuse, Cloud Build provenance, full-lifetime console scanning, strict retention/redaction, receipt/IAM gates, and both app lifecycle outcomes.
- Fourth UUID RED: the evidence-helper suite reported 32 passed and 2 failed for structured/full-entry UUID rejection and `assert-safe-content` atomicity; the shell runner reported 42 passed and 2 failed for `diagnosticValue` and `canaryId` in plain/JSON forms. The path-validated UUID-shaped root `insertId` control already passed.
- Fourth UUID GREEN: the evidence-helper suite passes 34/34 and the positive-canary runner passes 44/44, including every third-review regression, all exact UUID cases, and the root `insertId` compatibility control.
- Fifth RED: evidence reported 34/36 passed with identifier matcher and CLI failures; runner reported 43/46 passed with identifier-boundary, canonical-alias, and final-posture persistence failures.
- Fifth GREEN: evidence passes 36/36 and runner passes 46/46, including real mode-`0600` final-posture retention and every identifier/hash/alias bypass.
- Sixth RED: the two named punctuation-assignment regressions passed 0/2; the direct helper reported a missing expected exception for `outer=authToken=abc`, and the whole-console checker also accepted that nested assignment. The broader pre-fix run reported 82/84 passed, with the new evidence and runner regressions failing.
- Sixth GREEN: evidence passes 37/37 and runner passes 47/47. Direct helper, atomic CLI, and whole-console coverage reject all required punctuation and nested-assignment forms while exact numeric/canonical controls pass.
- Seventh RED: the two named digit-prefix regressions passed 0/2. The direct helper reported `Missing expected exception: 1authToken=abc`, and the whole-console checker also accepted that exact assignment.
- Seventh GREEN: evidence passes 38/38 and runner passes 48/48. Direct helper, atomic CLI, and whole-console coverage reject every required digit-prefixed form while exact wrapped numeric/canonical controls pass.
- Eighth RED: the three independent named length-boundary regressions passed 0/3; direct helper, atomic CLI, and whole-console each first accepted the 65-character field ending in `authToken`. The complete pre-fix evidence-plus-runner run reported 86/89 passed with exactly those three regressions failing.
- Eighth GREEN: evidence passes 40/40 and runner passes 49/49. Every required boundary, overlength-alias, long-input, atomic-output, and exact positive control passes.
- Ninth RED: the five named wrapper/span regressions passed 0/5. Direct helper and atomic CLI first accepted `["authToken"]=abc`; whole-console accepted the same wrapper, and both direct and whole-console paths accepted reuse of one allowlisted canonical hash under `diagnosticValue`.
- Ninth GREEN: evidence passes 43/43 and runner passes 51/51. The complete wrapper, Unicode, whitespace, compound-field, ANSI, exact-raw numeric/canonical, occurrence-confined hash, long-input, and atomic-output matrices pass.
- Tenth RED: the focused proxy privacy contract passed 0/1 because `meal_scan_estimate` contained `promptTokens` and no `inputTokens`; the actual console string separately returned status 1 from `assert-safe-content` with `unsafe sensitive field detected before evidence projection`.
- Tenth GREEN: the focused proxy contract and direct/CLI/whole-console metric compatibility checks pass 3/3.
- Eleventh RED: the three shared wrapper/compound regressions passed 0/3; direct helper, atomic CLI, and whole-console each first accepted `authToken＝abc`, while the frozen review independently recorded 12/12 fail-open observations across two fullwidth-delimiter and two four-token compound inputs.
- Eleventh GREEN: those direct, CLI, and whole-console matrices pass 3/3 with the new fullwidth, compatibility-width, and unbounded-compound cases included.
- Twelfth RED: the two named non-ASCII-key regressions passed 0/2; direct/CLI and whole-console first accepted the Greek-omicron assignment, while the frozen review independently recorded 12/12 fail-open observations across Greek/Cyrillic plain and structured cases.
- Twelfth GREEN: direct, CLI, structured, and whole-console non-ASCII-key cases pass while Unicode-value controls under ASCII keys remain accepted.
- Thirteenth RED: the four named key/value boundary regressions passed 0/4. Direct/CLI and whole-console accepted `status😀=abc`, while direct/CLI and whole-console rejected the safe `message=mañana status=completed` control; the frozen review recorded the same Unicode-value regression across nine observations.
- Thirteenth GREEN: non-ASCII plain/structured keys and adjacent symbols reject, while all three Unicode-before-assignment controls pass in direct, CLI, and whole-console paths.
- Fourteenth RED: the three shared wrapper/Unicode/compound regressions passed 0/3. Direct helper, atomic CLI, and whole-console each first accepted `message=mañana store kit private payload=abc`; the thirteenth frozen review independently recorded 12/12 fail-open observations across four unquoted multi-assignment compound inputs.
- Fourteenth GREEN: the same direct, CLI, and whole-console matrices pass 3/3. Complete consecutive-ASCII suffix inspection rejects all four new compounds while the Unicode-value controls continue to pass.
- Fifteenth RED: the fourteenth frozen review independently recorded 18/18 fail-open observations across six trailing-token inputs. The first local regression run passed 0/3 because direct, CLI, and whole-console paths accepted `message=bar auth token raw=abc`. Two additional preemptive RED cycles each passed 2/5: one first accepted `message=bar auth token mañana raw=abc`, and one first accepted `outer=store kit payload raw=abc`, while all localized-value controls stayed green.
- Fifteenth GREEN: the direct, atomic CLI, whole-console, and localized-value matrices pass 5/5 with trailing generic leaves, exact numeric/canonical leaves, non-ASCII insertion, confusable/emoji insertion, quoted and unquoted nesting, sensitive-first ambiguity, and benign ASCII/Unicode controls included.
- Sixteenth RED: the fifteenth frozen review independently recorded 15/15 fail-open observations across five first-segment sensitive prefixes ending in an exact numeric leaf. The local direct, atomic CLI, and whole-console regression run passed 0/3 and first accepted `auth token inputTokens=120`; localized and benign numeric-prefix controls stayed green.
- Sixteenth GREEN: the same five-path regression set rejects across all three content-check paths, while bare/wrapped numeric counters, the actual successful metric, and `status inputTokens=120` remain accepted.
- Seventeenth RED: the sixteenth frozen review independently recorded 33/33 cross-assignment fail-open observations, 12/12 confusable/fullwidth fail-open observations, and 3/3 false positives for a safe curly-quoted localized value. The local expanded direct/CLI/whole/localized matrix passed 0/5: `meal=foo name=breakfast` was accepted and `message=“mañana” status=completed` was rejected.
- Seventeenth GREEN: the same matrix passes 5/5 with eleven cross-assignment ancestry forms, six confusable/fullwidth forms, three curly/guillemet localized controls, every prior wrapper/Unicode/numeric/canonical regression, and atomic failure output.
- Eighteenth RED: the seventeenth frozen review independently recorded 6/6 fail-open observations for palochka-substituted `meal` and `display`. The local expanded matrix passed 2/5 and first accepted `message=mеaӏ name raw=breakfast`, while all localized controls stayed green.
- Eighteenth GREEN: the direct, atomic CLI, whole-console, and localized matrices pass 5/5 with palochka, unmapped accented/Cyrillic letters, mixed-script `photo`/`image`/`credential`, cross-assignment confusable ancestry, and mixed-script benign controls included.
- Nineteenth RED: the eighteenth frozen review independently recorded 15/15 false-positive observations for `k食y`, `j食s`, `j食t`, `A食事語`, and a transaction followed by `x食事`, plus 3/3 rejections for a benign Japanese corner-quoted value. The local five-test matrix initially passed 0/5, reproducing the localization failures while also first accepting a non-Greek/Cyrillic `⍴hoto` confusable.
- Nineteenth GREEN: the same direct, atomic CLI, whole-console, and localized matrices pass 5/5. Exact UTS #39 skeleton cases from Lisu, Carian, APL, Greek/Cyrillic, fullwidth, and supplementary-plane characters reject; CJK insertion, Japanese corner quotes, `PCOS食事`, `clé`, `mañana`, and cross-assignment localized controls remain accepted.
- Twentieth RED: the nineteenth frozen review recorded 12/12 accepted paths after official upsilon, iota, and eta mappings were overwritten. The second review then reproduced ASCII `0`/`1`/`I` and `rn` aliases, non-recursive `M`, raw supplementary/compatibility/wrapped sources, structured aliases, 34 visual delimiter sources, pipe-split components and relationships, localized delimiter false positives, UTF-16 supplementary delimiter failure, and quadratic delimiter/range behavior.
- Twentieth GREEN: direct helper, atomic CLI, whole-console, structured-path, localized-value, delimiter, relationship, and generated UTS-differential matrices are green. The 8,009-case generated substitution audit reports zero bypasses, Japanese/Devanagari/Armenian and CJK controls pass, and the measured large-input ratios are consistent with the bounded linear design.
- Twenty-first RED: direct/CLI paths accepted circled compatibility-symbol keys and mixed-residue sensitive groups, while a skipped-safe-delimiter benchmark scaled from about 96 ms at 250 fields to 1,186 ms at 1,000 and repeated unterminated OSC prefixes scaled from about 2.5 ms at 800 prefixes to 87 ms at 6,400.
- Twenty-first GREEN: the six-test direct/CLI/localization/performance matrix passes. The safe-delimiter and quoted-value regression completes in about 58 ms total, the unterminated-OSC regression in about 4 ms, and the whole-console mixed-residue/non-ASCII/localization matrix passes 3/3.
- Current focused remediation matrix: 122/122 passed (4 proxy canary, 7 deploy, 48 evidence, 9 Apple IAP, and 54 runner tests).
- Full proxy suite: `npm test` reported 368 passed, 0 failed, 0 skipped.
- `node --check scripts/positive-canary-evidence.mjs`: passed.
- `bash -n` passed for the positive canary, Cloud Run deploy, Apple IAP provisioner, and RevenueCat verifier scripts.
- `DRY_RUN=true cloud/meal-scan-proxy/scripts/run-positive-general-kenobi-canary.sh`: passed and remained non-mutating.
- `git diff --check`: passed.

## Files In This Remediation

Second-review follow-up scope:

- `cloud/meal-scan-proxy/src/server.js`
- `cloud/meal-scan-proxy/test/proxy.test.js`
- `cloud/meal-scan-proxy/scripts/deploy-cloud-run.sh`
- `cloud/meal-scan-proxy/test/canary-deploy-mode.test.js`
- `cloud/meal-scan-proxy/scripts/run-positive-general-kenobi-canary.sh`
- `cloud/meal-scan-proxy/test/positive-canary-script.test.js`
- `cloud/meal-scan-proxy/scripts/positive-canary-evidence.mjs`
- `cloud/meal-scan-proxy/test/positive-canary-evidence.test.js`
- `cloud/meal-scan-proxy/scripts/provision-apple-iap-key-v1.sh`
- `cloud/meal-scan-proxy/test/provision-apple-iap-key-v1.test.js`
- `docs/meal_scan_flash_lite_production_setup.md`
- `AppStoreReadinessChecklist.md`
- `.superpowers/sdd/task-3-report.md`

Complete two-pass canary scope:

- `PCOS/PCOS/Features/Meals/MealScan/Remote/GeminiMealScanRemote.swift`
- `PCOS/PCOSTests/GeminiMealScanTests.swift` (only the canary correlation assertions/tests)
- `cloud/meal-scan-proxy/src/server.js`
- `cloud/meal-scan-proxy/test/proxy.test.js`
- `cloud/meal-scan-proxy/scripts/run-positive-general-kenobi-canary.sh`
- `cloud/meal-scan-proxy/scripts/positive-canary-evidence.mjs`
- `cloud/meal-scan-proxy/scripts/deploy-cloud-run.sh`
- `cloud/meal-scan-proxy/scripts/provision-apple-iap-key-v1.sh`
- `cloud/meal-scan-proxy/scripts/verify-revenuecat-offering-v2.sh`
- `cloud/meal-scan-proxy/test/positive-canary-script.test.js`
- `cloud/meal-scan-proxy/test/positive-canary-evidence.test.js`
- `cloud/meal-scan-proxy/test/canary-deploy-mode.test.js`
- `cloud/meal-scan-proxy/test/provision-apple-iap-key-v1.test.js`
- `cloud/meal-scan-proxy/test/revenuecat-offering-verifier.test.js`
- `cloud/meal-scan-proxy/test/fixtures/revenuecat/*.json`
- `docs/meal_scan_flash_lite_production_setup.md`
- `AppStoreReadinessChecklist.md`
- `.superpowers/sdd/task-3-report.md`

## Remaining Owner And External Gates

- Run and review the Apple IAP provisioner's dry-run metadata plan. Only if there are zero existing versions may the owner separately approve the one-time `v1` write.
- Supply the matching App Store IAP key ID and issuer ID through the live harness's hidden prompts.
- Confirm the RevenueCat v2 key has the required least-privilege read scopes; a permission failure blocks the canary.
- Freeze and explicitly approve the full source commit, then run the separately approved `seed` and post-buffer `rescan` windows on unlocked General Kenobi.
- If CycleBalance is initially present, complete and verify the explicit manual original-binary/data restore handoff after rescan.
- A passing development-signed canary still does not close the positive sandbox-JWS real-device TestFlight gate.
- The 80-image/120-call benchmark, signed distribution archive/export, production distribution profile, App Privacy/policy review, localization, screenshots, reviewer access, TestFlight, and publication approval remain open.

## Safety Notes

- No third Release feature override was added; canonical scanner flags remain `NO`.
- No client model selection, direct Gemini route, mock path, or release bypass was introduced.
- No raw canary UUID, App Check token, JWS, transaction identifier, purchase principal, photo, meal content, API key, bearer header, or raw log is retained in evidence.
- The negative invalid-JWS physical probe remains separate and unchanged.
