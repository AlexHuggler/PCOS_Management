# Meal-Scan Quality Evaluation

This bounded toolkit prepares, executes, and scores the CycleBalance public meal-scan evaluation. Bundle preparation opens only explicitly indexed public images, and paid Gemini calls are impossible unless the operator supplies the exact confirmation variable. Dataset acquisition is never implicit; the optional Nutrition5k, SNAPMe, and MFDS helpers are separate, explicit public-data commands.

The included `sample-manifest.json` is a schema fixture only. Its reserved `example.invalid` URLs, synthetic hashes, repeated nutrition values, and explicit placeholder metadata are not dataset evidence and must be replaced before a real evaluation.

## Requirements

- Node.js 20 or newer
- Exactly 80 manifest records: 40 `Nutrition5k`, 30 `SNAPMe`, and 10 `MFDS`
- Exactly 20 records marked as locked holdouts with `holdout: true`
- One primary result for every manifest ID
- Exactly two additional structured-success stability runs for every locked holdout, and no other IDs
- One qualitative decision for every record, with at least 72 acceptable dominant-food interpretations and zero severe or uneditable failures
- macOS/Xcode command-line tools for the production-equivalent image normalizer
- Authenticated `gcloud` access to `cyclebalance-prod-20260710` for the paid runner
- Python 3 and approximately 2.03 GB of network transfer for the optional one-pass SNAPMe acquirer
- A Food Safety Korea OpenAPI key for the optional ten-record MFDS acquirer

No package installation is required.

## Acquire The Public Nutrition5k Slice

The Nutrition5k helper pins the official depth-test split and both dish-metadata CSVs by SHA-256, deterministically ranks nutrition-complete test dishes, and downloads only 40 official overhead RGB PNGs from the public Google Cloud Storage bucket. It validates host, byte size, PNG type, and dimensions; stores a SHA-256 for every retained image; and falls through to the next ranked dish if an individual public image is unavailable. It does not download the 181.4 GB full archive or the side-angle videos.

Keep the output outside the repository:

```sh
python3 scripts/acquire_nutrition5k.py \
  --output-dir /absolute/private/public-datasets/nutrition5k
```

Nutrition5k is provided under CC BY 4.0. Preserve attribution if the images are shared, and merge the generated `source-index-fragment.json` with the SNAPMe and MFDS fragments before bundle preparation.

## Acquire The Public SNAPMe Slice

The official SNAPMe computer-science image folders are symbolic links to originals later in one 2,034,227,035-byte `tar.gz`. The checked-in acquirer streams that archive once and never stores the full tarball. It downloads the official linkage metadata, selects a deterministic meal-type-balanced slice of 30 non-packaged before-meal photos, follows only those archive links in memory, verifies the pinned official size and MD5, and writes only owner-readable regular JPEGs plus a source-index fragment. Participant identifiers are not copied into the output.

Keep the output outside the repository:

```sh
python3 scripts/acquire_snapme.py \
  --output-dir /absolute/private/public-datasets/snapme
```

The output is licensed under SNAPMe's CC BY-SA 4.0 terms and is for the documented evaluation slice, not model training. Merge `source-index-fragment.json` with the separately verified 40-record Nutrition5k and 10-record MFDS fragments before preparing the complete private bundle.

## Acquire The Public MFDS Slice

The MFDS helper reads the Food Safety Korea key from a hidden terminal prompt. It does not accept the key as a command-line argument, environment variable, or file, and it does not write the key or key-bearing request URL to output. It pages through the official `COOKRCP01` API with bounded responses, deterministically ranks complete recipe records, upgrades allowlisted official image URLs to HTTPS, validates image host, type, byte size, and dimensions, and keeps the first ten usable records. Output files are owner-only and partial output is removed on failure.

Keep the output outside the repository and do not paste the key into chat or shell history:

```sh
python3 scripts/acquire_mfds.py \
  --output-dir /absolute/private/public-datasets/mfds
```

The helper labels records with the official Korea Open Government License Type 1 attribution terms shown on the Food Safety Korea dataset page, which allow commercial and noncommercial use and derivative works with attribution. Keep the intended benchmark bundle private and preserve attribution if any acquired image is shared. Merge its `source-index-fragment.json` with the verified Nutrition5k and SNAPMe fragments before bundle preparation.

## Prepare A Private Bundle

Keep the source index and generated bundle outside the repository. The source index contains exactly 40 Nutrition5k, 30 SNAPMe, and 10 MFDS records. Each record uses this shape:

```json
{
  "id": "nutrition5k_001",
  "source": "Nutrition5k",
  "sourceUrl": "https://verified-public-source.example/record/001",
  "license": "Verified license or terms for this record",
  "sourceImagePath": "/absolute/private/source/image.png",
  "groundTruth": {
    "calories": 500,
    "protein": 25,
    "carbs": 50,
    "fat": 20
  },
  "referenceType": "dataset_annotation",
  "samplingReason": "Documented reason this item represents the evaluation slice",
  "mealType": "lunch",
  "locale": "en_US"
}
```

Create a new owner-only bundle directory:

```sh
npm run prepare -- \
  --source-index /absolute/private/source-index.json \
  --source-root /absolute/private/public-datasets \
  --output-dir /absolute/private/cyclebalance-public-benchmark
```

Preparation validates every source record before opening an image. Every indexed image must be a regular, non-symlink file whose resolved path remains inside `--source-root`; validation finishes before the native normalizer is compiled or the output directory is created. It compiles the checked-in ImageIO normalizer once, applies the app's 960-pixel long-edge, white-background, JPEG 0.78 pipeline without copying source metadata, and writes owner-only normalized JPEGs. It computes each normalized hash, produces a provenance-only `manifest.json`, and keeps local paths in a separate `image-map.json`. Holdouts are assigned before model execution by a deterministic hash policy with 10 Nutrition5k, 7 SNAPMe, and 3 MFDS records.

Bundle preparation also freezes the candidate before inference. It refuses to run while the production model/prompt/schema sources, evaluator runner, or image normalizer differ from the current Git commit. The manifest records the full source commit together with the pinned model, prompt, schema, and normalizer versions. Unrelated working-tree changes do not affect this check.

## Run The Paid Evaluation

The runner is pinned to project `cyclebalance-prod-20260710`, service `cyclebalance-meal-scan-proxy`, secret `cyclebalance-gemini-api-key`, region `us-central1`, and model `gemini-3.1-flash-lite`. It refuses to read the secret unless Cloud Run is still private, `MEAL_SCAN_ENABLED=false`, and the deployed key remains a numeric-pinned Secret Manager reference. It reads that exact deployed version, never `latest`.

It validates all 80 normalized JPEGs, hashes, and size limits before the first model call. The private bundle's `images` directory and every indexed JPEG must be regular, non-symlink filesystem entries confined to that bundle. A complete run makes exactly 120 sequential calls: 80 primary calls plus two additional calls for each locked holdout. Calls use the production prompt builder, response schema, model, and 12-second timeout. Output files are published with an atomic no-overwrite operation and mode `0600`.

```sh
CONFIRM_PAID_PUBLIC_BENCHMARK=YES npm run evaluate -- \
  --manifest /absolute/private/cyclebalance-public-benchmark/manifest.json \
  --image-map /absolute/private/cyclebalance-public-benchmark/image-map.json \
  --output /absolute/private/cyclebalance-public-benchmark/results.json \
  --stability-output /absolute/private/cyclebalance-public-benchmark/stability-results.json
```

The runner never sends benchmark traffic through the customer endpoint and never prints or writes the API key, raw model response, source path, or model error. Nutrition totals are the sum of each model item's structured `nutrition_fallback`, deliberately excluding the app's local food-database correction so the benchmark remains a conservative model-quality floor.

## Manifest

The manifest must be JSON with schema version 2:

```json
{
  "version": 2,
  "candidate": {
    "modelVersion": "gemini-3.1-flash-lite",
    "promptVersion": "meal-scan-prompt-v1",
    "schemaVersion": "meal-scan-gemini-v1",
    "normalizerVersion": "imageio-960-jpeg078-v1",
    "sourceCommit": "0123456789abcdef0123456789abcdef01234567"
  },
  "records": [
    {
      "id": "nutrition5k_001",
      "source": "Nutrition5k",
      "holdout": true,
      "sourceUrl": "https://verified-public-source.example/record/001",
      "license": "Verified license or terms for this record",
      "imageSha256": "0123456789abcdef0123456789abcdef0123456789abcdef0123456789abcdef",
      "groundTruth": {
        "calories": 500,
        "protein": 25,
        "carbs": 50,
        "fat": 20
      },
      "referenceType": "dataset_annotation",
      "samplingReason": "Documented reason this item represents the evaluation slice"
    }
  ]
}
```

All candidate and record fields are required. The source commit must be a full 40-character Git hash. IDs must be unique opaque strings, image hashes must be 64 hexadecimal characters, URLs must use HTTP or HTTPS, strings must be non-empty, and ground-truth values must be finite and non-negative. Unknown record fields are rejected, including image paths.

Treat the holdout selection as locked before producing model results. Changing holdout membership, source composition, truth, or sampling rationale after reviewing results invalidates the evaluation.

## Results

Results can be a JSON array or JSONL with one object per line. Each primary record must have exactly these fields:

```json
{
  "id": "nutrition5k_001",
  "structuredSuccess": true,
  "calories": 490,
  "protein": 24,
  "carbs": 49,
  "fat": 21,
  "modelVersion": "gemini-3.1-flash-lite",
  "promptVersion": "meal-scan-prompt-v1",
  "schemaVersion": "meal-scan-gemini-v1",
  "normalizerVersion": "imageio-960-jpeg078-v1",
  "sourceCommit": "0123456789abcdef0123456789abcdef01234567",
  "latencyMs": 842
}
```

For `structuredSuccess: true`, all four nutrition values must be finite and non-negative. For `structuredSuccess: false`, all four must be `null`. Every result must repeat the exact frozen candidate provenance; mixed model, prompt, schema, normalizer, or source-commit results are rejected. `latencyMs` must be finite and non-negative.

The qualitative-review file uses schema version 1 and contains exactly one decision for every manifest ID:

```json
{
  "version": 1,
  "records": [
    {
      "id": "nutrition5k_001",
      "acceptableDominantFoodInterpretation": true,
      "severeOrUneditableFailure": false
    }
  ]
}
```

Run the scorer from this directory:

```sh
node score.mjs \
  --manifest /absolute/private/cyclebalance-public-benchmark/manifest.json \
  --results /absolute/private/cyclebalance-public-benchmark/results.json \
  --stability /absolute/private/cyclebalance-public-benchmark/stability-results.json \
  --qualitative /absolute/private/cyclebalance-public-benchmark/qualitative-review.json \
  > /absolute/private/cyclebalance-public-benchmark/report.json
```

Stability and qualitative inputs are mandatory. The scorer writes the aggregate report and exits nonzero whenever any numerical, source, stability, provenance, or qualitative gate fails. The report never echoes source URLs, licenses, image hashes, ground truth, sampling reasons, reference types, or image paths.

## Metrics

Metrics are reported for `Nutrition5k`, `SNAPMe`, `MFDS`, and `combined`.

- JSON success is the percentage of records with `structuredSuccess: true`.
- MAE is mean absolute error among structured-success records.
- WAPE is total absolute error divided by total ground truth among structured-success records.
- Calorie median absolute percentage error uses records with ground truth above zero. Macro percentage error excludes records below 5g; absolute error and aggregate WAPE still include them.
- Signed bias is total signed error divided by total ground truth among structured-success records.
- Pass rates use every record in the group as the denominator; structured failures therefore fail every nutrient pass check.
- Latency reports count, mean, median, and nearest-rank p95 in milliseconds.

A calorie prediction passes when absolute error is at most `max(100 kcal, 20% of truth)`. Each macro passes independently when absolute error is at most `max(5g, 25% of truth)`. Threshold comparisons are inclusive. Percentages are emitted in percentage points, so `25` means 25%.

If a metric has no valid denominator, the report emits `null` and its gate fails.

## Release Gates

The combined report passes only when all applicable gates pass:

- JSON success is at least 98%.
- Calorie WAPE is at most 25%.
- Median calorie absolute percentage error is at most 20%.
- Signed calorie bias is between -10% and +10%, inclusive.
- Protein, carb, and fat WAPE are each at most 30%.
- Calorie pass rate is at least 70%.
- Protein, carb, and fat pass rates are each at least 65%.
- Nutrition5k, SNAPMe, and MFDS calorie WAPE are each at most 35%.
- The complete locked stability panel passes all stability gates.
- At least 72 of 80 qualitative reviews are acceptable dominant-food interpretations.
- There are zero severe or uneditable qualitative failures.

## Stability Panel

A mandatory stability file uses the same JSON or JSONL result schema. It must contain exactly 40 records: exactly two structured-success repeats for each of the 20 locked holdouts, with no non-holdout IDs.

```sh
node score.mjs \
  --manifest manifest.private.json \
  --results results.json \
  --stability stability-results.jsonl \
  --qualitative qualitative-review.json > report.json
```

For each ID, calorie spread is `max - min` divided by the median predicted calories. Macro spread is `max - min` in grams. The panel then takes the median across IDs and passes when median calorie spread is at most 10% and each median macro spread is at most 5g. Any structured-failure repeat invalidates the panel before scoring.

If any gate fails, keep the scanner hidden and the customer Cloud Run revision private and disabled. Adjust the candidate, freeze it again, and rerun the complete 120-call benchmark; partial reruns cannot qualify a release.

## Tests

```sh
npm test
```

The tests use temporary synthetic inputs and one generated one-pixel image for the native normalizer. Passing tests prove toolkit mechanics, safety ordering, and result privacy, not public-dataset quality and not a production model gate.
