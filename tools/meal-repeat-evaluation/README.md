# CycleBalance Repeat-Meal Evaluation Toolkit

This toolkit calibrates the on-device repeat-meal similarity policy from a private, labeled image set. It is an evaluation aid, not a production matching service. Photos, private manifests, generated distance reports, and generated policy JSON must remain local and untracked.

## Release Dataset

The release evaluation set contains exactly 100 images:

- 20 meal identities with four views each, for 80 images.
- 20 visually similar negative meals, for 20 images.

For every repeated identity, capture the same portion as a whole plate twice overhead and twice at a 30-45 degree angle. Capture one view of each angle under each of two lighting conditions. Do not add, remove, or rearrange food between views.

The 20 negatives must be different meal identities that are visually easy to confuse with the repeated meals, such as similar bowls, salads, sauces, grains, proteins, or plating. Mark a negative `highRisk: true` when a false suggestion could plausibly cause someone to accept materially wrong meal content or macros. Use opaque IDs for image records; labels identify the meal identity and never contain a person, place, or file name.

Keep weighed ingredient measurements or label-backed macro truth in a separate private review sheet. The image manifest is only for opaque IDs, meal labels, the local file reference needed by the extractor, and an optional high-risk flag.

`manifest.example.json` is an intentionally incomplete shape reference. A production manifest must have exactly 100 entries and is not committed.

## Privacy Before Evaluation

Before adding a photo to the private dataset:

1. Exclude faces, people, documents, medication labels, mail, screens, and location-revealing backgrounds. Re-crop or retake any image that includes them.
2. Strip all EXIF and other metadata before the image enters the evaluation directory. For example, use a reviewed local metadata-removal workflow such as `exiftool -all= -overwrite_original <image>` and verify the result before continuing.
3. Store only opaque image IDs in manifests and reports. Do not place source paths, device names, coordinates, or copied photos in generated reports.
4. Keep the dataset, private manifests, output, image formats, and generated policy JSON ignored by Git. Confirm no image files or private data are staged before every commit.

## Run The Extractor

Compile with the current Xcode toolchain:

```sh
swiftc tools/meal-repeat-evaluation/extract-feature-distances.swift \
  -o /tmp/cyclebalance-extract-feature-distances
```

Run a production evaluation using a local 100-image manifest:

```sh
/tmp/cyclebalance-extract-feature-distances \
  --manifest manifest.private.json \
  --report output/feature-distances.json
```

The extractor rejects a normal run unless the manifest has exactly 100 unique opaque IDs and every referenced local file exists. It uses `VNGenerateImageFeaturePrintRequestRevision2`, retains feature prints in memory only, and emits only IDs, labels, high-risk flags, pair distances, nearest-neighbor margins, and timing data. It never copies photos or emits input paths.

For mechanics-only validation, `--smoke` accepts exactly five locally generated test images. The smoke output is explicitly non-production and cannot pass the calibrator's 100-image gate.

## Review And Calibration

Manually review every false match in the distance report before calibration. For each one, compare both meals and the separate macro truth, record why the feature print confused them, and label it high risk when accepting the suggestion could lead to a materially unsafe or misleading meal draft. A single high-risk false match blocks release.

Run the policy calibrator only after the complete review is recorded:

```sh
node tools/meal-repeat-evaluation/calibrate-policy.mjs \
  --manifest manifest.private.json \
  --report output/feature-distances.json \
  --policy output/policy.json
```

The calibrator recomputes leave-one-out nearest-neighbor matches and searches distance and margin thresholds. It refuses to write a policy unless all conditions are true:

- exactly 100 evaluated images;
- precision is at least `0.95`; and
- high-risk false matches equal `0`.

It chooses the highest-recall valid pair, breaking ties by higher precision, smaller maximum distance, then larger minimum margin. The policy write is atomic and happens only after every gate passes.

Do not install a generated policy into the app, ship it, or describe the real 100-image gate as passed until this complete private run and manual review have passed. Hand the policy and review evidence to the Swift repeat-cache owner for a separately reviewed installation.

## Verification

```sh
node --test tools/meal-repeat-evaluation/test/*.test.mjs
swiftc tools/meal-repeat-evaluation/extract-feature-distances.swift \
  -o /tmp/cyclebalance-extract-feature-distances
git diff --check
git diff --cached --name-only
```

The Node tests use synthetic temporary reports only. They prove that the toolkit selects a safe highest-recall policy and refuses sub-95-percent precision, high-risk false matches, and incomplete datasets. They are not evidence that the private 100-image release gate has passed.
