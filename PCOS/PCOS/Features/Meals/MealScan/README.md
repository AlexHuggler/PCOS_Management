# Meal Scan V2

Meal Scan V2 is a local-first AI meal estimate flow for CycleBalance. Pass 1 ships with deterministic mock vision, editable fixture foods, nutrient math, SwiftData persistence, and manual fallback. Pass 2 adds Core ML adapter hooks, depth/portion strategies, local USDA SQLite support, optional barcode/package interfaces, and insight query helpers.

## Privacy Defaults

- Mock scan data and fixture nutrition run fully on device and require no backend.
- When the user chooses a cloud photo estimate, the app sends one normalized JPEG to the CycleBalance proxy for AI analysis. The proxy does not retain raw image bytes.
- Meal photos are stored locally only after save and only while `mealScan.enableMealPhotoRetention` remains enabled.
- Photo-based Meal Scan V2 remains behind `mealScan.enableMealScanV2` in release builds.
- User-initiated barcode lookup is available from Meal Log in release builds after first-use consent. Open Food Facts receives the entered or scanned UPC/EAN only, and results fill the meal draft only after review.

## Feature Flags

- `mealScan.enableMealScanV2`
- `mealScan.enableFoodSegmentation`
- `mealScan.enableDepthEstimation`
- `mealScan.enableBarcodeNutritionLookup`
- `mealScan.enableMealPhotoRetention`
- `mealScan.enableMockMealScanData`
- `mealScan.enableOpenFoodFactsLookup`
- `mealScan.enableGeminiMealScan`
- `mealScan.enableGeminiFallbackModel`
- `mealScan.enableMealScanResultCache`

Debug builds default Meal Scan V2 and mock data on. Release builds keep the photo path off until cloud security and review gates pass. Segmentation and depth are off unless explicitly enabled through launch arguments or `UserDefaults`. The older barcode/Open Food Facts flags document the experimental Meal Scan V2 package interface; the release Meal Log barcode sheet is intentionally available outside the photo-scan feature flag.

The production proxy defaults to `gemini-2.5-flash-lite` and allowlists `gemini-3.1-flash-lite` for migration evaluation. Do not use retired `gemini-2.0-flash-lite`.

## Model Assets

Place compiled Core ML models in the app bundle and set names through `MealScanModelRegistry`:

- Food classifier: `foodClassifierModelName`
- Food segmentation model: `foodSegmentationModelName`
- Depth model: `depthModelName`

If a model is missing or incompatible, the adapter falls back to the mock/heuristic service and the scan remains editable.

## Local Nutrition Database

Pass 1 uses `SampleNutritionFixtures.json` mirrored by `SampleNutritionFixtures` in Swift for deterministic tests. Pass 2 can bundle a compact SQLite database named `MealNutrition.sqlite` with this schema:

```sql
CREATE TABLE foods (
  id TEXT PRIMARY KEY,
  display_name TEXT NOT NULL,
  canonical_name TEXT NOT NULL,
  source TEXT NOT NULL,
  category TEXT,
  serving_description TEXT,
  serving_grams REAL,
  calories_per_100g REAL,
  protein_per_100g REAL,
  carbs_per_100g REAL,
  fat_per_100g REAL,
  fiber_per_100g REAL,
  sugar_per_100g REAL,
  sodium_mg_per_100g REAL,
  saturated_fat_per_100g REAL,
  cholesterol_mg_per_100g REAL,
  potassium_mg_per_100g REAL,
  calcium_mg_per_100g REAL,
  iron_mg_per_100g REAL,
  aliases TEXT
);
CREATE VIRTUAL TABLE food_search USING fts5(id UNINDEXED, display_name, canonical_name, aliases);
```

Use `scripts/import_usda_foods.py` to prepare the compact database from a USDA FoodData Central subset.

## Known Limits

Nutrition values are estimates and can vary by preparation, ingredient visibility, and portion size. CycleBalance is not a medical device, and Meal Scan copy should continue to say "AI meal estimate" rather than exact scanner language.
