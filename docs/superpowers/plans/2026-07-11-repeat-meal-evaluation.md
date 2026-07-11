# CycleBalance Repeat Meal Evaluation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Build a private, reproducible 100-image evaluation workflow that can enable similar-photo repeat suggestions only after measured precision and safety gates pass.

**Architecture:** A local Swift/Vision extractor reads image paths from a private manifest, computes revision-2 feature prints in memory, and writes only IDs, labels, pairwise distances, and timings. A zero-dependency Node calibrator performs leave-one-out nearest-neighbor evaluation and emits a signed-off policy-shaped JSON only when all release gates pass. Raw images and generated reports remain ignored local artifacts.

**Tech Stack:** Swift 6, Vision, Foundation, Node.js built-in test runner, JSON.

## Global Constraints

- The real dataset must contain exactly 100 images: 20 meal identities with four views each, plus 20 visually similar negatives.
- Do not commit photos, EXIF metadata, local paths, generated reports, or generated policies.
- The extractor must never copy or upload image bytes.
- Output may contain only opaque IDs, labels, distances, timings, and aggregate metrics.
- Do not claim the similarity gate passes until all 100 real images have been reviewed.
- A valid policy requires precision at least `0.95` and zero reviewed high-risk false matches.

### Task 1: Drive The Calibrator With Failing Tests

**Files:**
- Create: `tools/meal-repeat-evaluation/test/calibrate-policy.test.mjs`
- Create: `tools/meal-repeat-evaluation/manifest.example.json`

- [ ] **Step 1: Add synthetic reports for a safe threshold, sub-95% precision, a high-risk cross-meal match, and an incomplete dataset**

- [ ] **Step 2: Assert the safe dataset selects the highest-recall valid distance/margin pair**

The resulting policy must contain exactly these release metadata fields in addition to the thresholds:

```json
{
  "version": 1,
  "enabled": true,
  "maximumDistance": 0.0,
  "minimumNeighborMargin": 0.0,
  "evaluatedImageCount": 100,
  "precision": 0.95,
  "highRiskFalseMatches": 0
}
```

- [ ] **Step 3: Assert every unsafe or incomplete case exits nonzero and writes no policy**

- [ ] **Step 4: Run `node --test tools/meal-repeat-evaluation/test/*.test.mjs` and verify RED because the calibrator does not exist**

### Task 2: Implement The Calibrator

**Files:**
- Create: `tools/meal-repeat-evaluation/calibrate-policy.mjs`

- [ ] **Step 1: Implement manifest/report validation and leave-one-out nearest-neighbor scoring**

- [ ] **Step 2: Search candidate distance and nearest-neighbor-margin pairs**

Choose the highest-recall pair subject to precision `>= 0.95`, `highRiskFalseMatches == 0`, and `evaluatedImageCount == 100`. Use deterministic tie-breaking: higher precision, then smaller maximum distance, then larger minimum margin.

- [ ] **Step 3: Write policy atomically only after all gates pass**

- [ ] **Step 4: Run the focused Node suite and verify GREEN**

### Task 3: Implement The Private Vision Extractor

**Files:**
- Create: `tools/meal-repeat-evaluation/extract-feature-distances.swift`
- Create: `tools/meal-repeat-evaluation/.gitignore`

- [ ] **Step 1: Validate exactly 100 manifest entries with unique opaque IDs and existing local files**

- [ ] **Step 2: Use `VNGenerateImageFeaturePrintRequestRevision2` and keep feature prints in memory only**

- [ ] **Step 3: Emit IDs, labels, pairwise distances, nearest-neighbor margins, and timings without copying photos or writing paths**

- [ ] **Step 4: Ignore `dataset/`, `output/`, image extensions, private manifests, generated reports, and generated policy JSON**

- [ ] **Step 5: Compile the extractor and run a private five-image smoke fixture only to validate mechanics**

The smoke fixture does not satisfy or weaken the 100-image release gate.

### Task 4: Write The Capture And Review Runbook

**Files:**
- Create: `tools/meal-repeat-evaluation/README.md`
- Modify: `docs/meal_scan_flash_lite_production_setup.md`

- [ ] **Step 1: Define 20 meal identities, four views per identity, and 20 visually similar negatives**

For each identity, capture whole-plate overhead and 30-45 degree views across two lighting conditions without changing the portion. Record weighed or label-backed macro truth separately from the image manifest.

- [ ] **Step 2: Require EXIF stripping and exclude faces, documents, medication labels, and location-revealing backgrounds**

- [ ] **Step 3: Document manual review of every false match and explicit high-risk labeling**

- [ ] **Step 4: Document policy installation only after the real gate passes**

### Task 5: Verify And Commit The Toolkit

- [ ] **Step 1: Run `node --test tools/meal-repeat-evaluation/test/*.test.mjs`**

- [ ] **Step 2: Compile the Swift extractor with the current Xcode toolchain**

- [ ] **Step 3: Run `git diff --check` and confirm no image or private dataset path is staged**

- [ ] **Step 4: Commit only the toolkit, tests, and runbook changes**
