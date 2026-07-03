import Foundation
import UIKit
import Vision
import CoreML
import SwiftData
import os

@MainActor
protocol FoodClassificationService {
    func classifyFood(in image: UIImage) async throws -> [FoodClassificationCandidate]
}

@MainActor
protocol FoodSegmentationService {
    func segmentFood(in image: UIImage) async throws -> [FoodSegmentationResult]
}

@MainActor
protocol PortionEstimationService {
    func estimatePortions(
        image: UIImage,
        detectedItems: [DetectedFoodItem],
        segmentationResults: [FoodSegmentationResult],
        depthData: MealDepthData?
    ) async throws -> [PortionEstimate]
}

protocol NutritionLookupService: Sendable {
    func searchFood(query: String) async throws -> [FoodNutritionRecord]
    func nutrition(forFoodId foodId: String) async throws -> FoodNutritionRecord?
}

protocol MealNutritionCalculating: Sendable {
    func calculateItemNutrition(food: FoodNutritionRecord, grams: Double) -> NutritionSnapshot
    func aggregateMealNutrition(items: [MealFoodItemDraft]) -> NutritionSnapshot
}

@MainActor
protocol MealLogRepository {
    func saveMealScan(_ confirmedMeal: ConfirmedMealScan) async throws
}

struct MealNutritionCalculator: MealNutritionCalculating {
    func calculateItemNutrition(food: FoodNutritionRecord, grams: Double) -> NutritionSnapshot {
        let multiplier = grams / 100
        return NutritionSnapshot(
            caloriesKcal: amount(food.caloriesPer100g, multiplier: multiplier),
            proteinGrams: amount(food.proteinPer100g, multiplier: multiplier),
            carbsGrams: amount(food.carbsPer100g, multiplier: multiplier),
            fatGrams: amount(food.fatPer100g, multiplier: multiplier),
            fiberGrams: amount(food.fiberPer100g, multiplier: multiplier),
            sugarGrams: amount(food.sugarPer100g, multiplier: multiplier),
            sodiumMg: amount(food.sodiumMgPer100g, multiplier: multiplier),
            saturatedFatGrams: amount(food.saturatedFatPer100g, multiplier: multiplier),
            cholesterolMg: amount(food.cholesterolMgPer100g, multiplier: multiplier),
            potassiumMg: amount(food.potassiumMgPer100g, multiplier: multiplier),
            calciumMg: amount(food.calciumMgPer100g, multiplier: multiplier),
            ironMg: amount(food.ironMgPer100g, multiplier: multiplier)
        )
    }

    func aggregateMealNutrition(items: [MealFoodItemDraft]) -> NutritionSnapshot {
        items.reduce(NutritionSnapshot()) { partial, item in
            partial.adding(item.nutrition)
        }
    }

    static func displayCalories(_ value: Double) -> String {
        "\(Int(value.rounded()))"
    }

    static func displayMacro(_ value: Double) -> String {
        let rounded = (value * 10).rounded() / 10
        if rounded.rounded() == rounded {
            return "\(Int(rounded))"
        }
        return String(format: "%.1f", rounded)
    }

    static func displaySodium(_ value: Double) -> String {
        "\(Int(value.rounded()))"
    }

    private func amount(_ value: Double?, multiplier: Double) -> Double {
        guard let value, value.isFinite else { return 0 }
        return value * multiplier
    }
}

struct MealMetabolicProfileService {
    func profile(
        for nutrition: NutritionSnapshot,
        confidence: NutritionConfidence,
        hiddenIngredientEstimate: HiddenIngredientEstimate,
        visibleWarnings: [String]
    ) -> MealMetabolicProfile {
        let carbLoad = carbLoadCategory(for: nutrition.carbsGrams)
        let protein = proteinAdequacy(for: nutrition.proteinGrams)
        let fiber = fiberAdequacy(for: nutrition.fiberGrams, carbs: nutrition.carbsGrams)
        let fat = fatLevel(for: nutrition.fatGrams)
        let impact = glycemicImpact(for: nutrition, protein: protein, fiber: fiber)
        let score = balanceScore(for: nutrition, impact: impact, protein: protein, fiber: fiber)

        let explanation: String
        switch impact {
        case .low:
            explanation = "This meal may have a low glucose impact. Protein and fiber may help balance the meal."
        case .moderate:
            explanation = "This meal may have a moderate glucose impact. Protein and fiber may help balance the meal."
        case .moderateHigh:
            explanation = "This meal may have a moderate-high glucose impact, mostly from visible carbs."
        case .high:
            explanation = "This meal may have a higher glucose impact, mostly from visible carbs and lower fiber."
        case .unknown:
            explanation = "This meal needs review before CycleBalance can estimate glucose impact."
        }

        let caution: String?
        if hiddenIngredientEstimate != .no || confidence.rank <= NutritionConfidence.medium.rank || !visibleWarnings.isEmpty {
            caution = "Nutrition values are estimates and can vary with preparation, ingredients, oil, dressing, sauces, and portion size. CycleBalance is not a medical device."
        } else {
            caution = nil
        }

        return MealMetabolicProfile(
            carbLoadCategory: carbLoad,
            proteinAdequacy: protein,
            fiberAdequacy: fiber,
            fatLevel: fat,
            estimatedGlycemicImpact: impact,
            mealBalanceScore: score,
            explanation: explanation,
            caution: caution
        )
    }

    private func carbLoadCategory(for carbs: Double) -> MealScanCarbLoadCategory {
        if carbs < 25 { return .low }
        if carbs < 55 { return .moderate }
        if carbs < 85 { return .high }
        return .veryHigh
    }

    private func proteinAdequacy(for protein: Double) -> MealScanAdequacy {
        if protein >= 25 { return .strong }
        if protein >= 12 { return .moderate }
        return .low
    }

    private func fiberAdequacy(for fiber: Double, carbs: Double) -> MealScanAdequacy {
        let ratio = carbs > 0 ? fiber / carbs : 0
        if fiber >= 8 || ratio >= 0.18 { return .strong }
        if fiber >= 4 || ratio >= 0.10 { return .moderate }
        return .low
    }

    private func fatLevel(for fat: Double) -> MealScanFatLevel {
        if fat < 12 { return .low }
        if fat <= 30 { return .moderate }
        return .high
    }

    private func glycemicImpact(
        for nutrition: NutritionSnapshot,
        protein: MealScanAdequacy,
        fiber: MealScanAdequacy
    ) -> GlycemicImpactLevel {
        var score = nutrition.carbsGrams / 25
        score += nutrition.sugarGrams / 30
        if fiber == .strong { score -= 0.9 }
        if fiber == .moderate { score -= 0.4 }
        if protein == .strong { score -= 0.55 }
        if protein == .moderate { score -= 0.25 }

        if score < 1.0 { return .low }
        if score < 2.5 { return .moderate }
        if score < 3.6 { return .moderateHigh }
        return .high
    }

    private func balanceScore(
        for nutrition: NutritionSnapshot,
        impact: GlycemicImpactLevel,
        protein: MealScanAdequacy,
        fiber: MealScanAdequacy
    ) -> Int {
        var score = 72
        switch impact {
        case .low: score += 12
        case .moderate: score += 2
        case .moderateHigh: score -= 18
        case .high: score -= 34
        case .unknown: score -= 25
        }
        if protein == .strong { score += 8 } else if protein == .low { score -= 10 }
        if fiber == .strong { score += 8 } else if fiber == .low { score -= 12 }
        if nutrition.sugarGrams > 20 { score -= 8 }
        return min(max(score, 0), 100)
    }
}

enum MealScanConfidenceScorer {
    static func adjustedConfidence(
        base: NutritionConfidence,
        hiddenIngredientEstimate: HiddenIngredientEstimate,
        isMixedDish: Bool,
        wasUserEdited: Bool
    ) -> NutritionConfidence {
        var penalty = 0
        if hiddenIngredientEstimate == .aLot || hiddenIngredientEstimate == .notSure {
            penalty += 1
        }
        if hiddenIngredientEstimate == .moderate {
            penalty += 1
        }
        if isMixedDish {
            penalty += 1
        }
        if wasUserEdited, penalty > 0 {
            penalty -= 1
        }
        return base.lowered(by: penalty)
    }

    static func aggregate(_ values: [NutritionConfidence]) -> NutritionConfidence {
        guard !values.isEmpty else { return .unknown }
        let average = values.map(\.score).reduce(0, +) / Double(values.count)
        if average >= 0.8 { return .high }
        if average >= 0.5 { return .medium }
        if average >= 0.25 { return .low }
        return .unknown
    }
}

struct LocalFoodNutritionRepository: NutritionLookupService {
    private let recordsByID: [String: FoodNutritionRecord]
    private let aliases: [String: String]

    init(records: [FoodNutritionRecord] = SampleNutritionFixtures.records, aliases: [FoodAlias] = SampleNutritionFixtures.aliases) {
        recordsByID = Dictionary(uniqueKeysWithValues: records.map { ($0.id, $0) })
        var aliasMap: [String: String] = [:]
        for record in records {
            aliasMap[Self.normalized(record.displayName)] = record.id
            aliasMap[Self.normalized(record.canonicalName)] = record.id
            for alias in record.aliases {
                aliasMap[Self.normalized(alias)] = record.id
            }
        }
        for alias in aliases {
            if let defaultFoodId = alias.defaultFoodId {
                aliasMap[Self.normalized(alias.inputName)] = defaultFoodId
            }
        }
        self.aliases = aliasMap
    }

    func searchFood(query: String) async throws -> [FoodNutritionRecord] {
        let normalizedQuery = Self.normalized(query)
        if let id = aliases[normalizedQuery], let record = recordsByID[id] {
            return [record]
        }
        return recordsByID.values
            .filter { record in
                Self.normalized(record.displayName).contains(normalizedQuery)
                    || Self.normalized(record.canonicalName).contains(normalizedQuery)
                    || record.aliases.contains(where: { Self.normalized($0).contains(normalizedQuery) })
            }
            .sorted { $0.displayName < $1.displayName }
    }

    func nutrition(forFoodId foodId: String) async throws -> FoodNutritionRecord? {
        recordsByID[foodId]
    }

    private static func normalized(_ value: String) -> String {
        value.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
    }
}

struct MockFoodVisionService: FoodClassificationService {
    func classifyFood(in image: UIImage) async throws -> [FoodClassificationCandidate] {
        [
            FoodClassificationCandidate(label: "Chicken breast", canonicalFoodId: "chicken-breast-cooked", confidence: 0.82),
            FoodClassificationCandidate(label: "White rice", canonicalFoodId: "rice-white-cooked", confidence: 0.78),
            FoodClassificationCandidate(label: "Broccoli", canonicalFoodId: "broccoli", confidence: 0.72),
        ]
    }
}

struct MockFoodSegmentationService: FoodSegmentationService {
    func segmentFood(in image: UIImage) async throws -> [FoodSegmentationResult] {
        [
            FoodSegmentationResult(label: "Chicken breast", boundingBox: MealScanRect(CGRect(x: 0.1, y: 0.2, width: 0.3, height: 0.3)), confidence: 0.7, maskIdentifier: "mock-chicken"),
            FoodSegmentationResult(label: "White rice", boundingBox: MealScanRect(CGRect(x: 0.42, y: 0.24, width: 0.32, height: 0.34)), confidence: 0.68, maskIdentifier: "mock-rice"),
        ]
    }
}

struct MockPortionEstimationService: PortionEstimationService {
    func estimatePortions(
        image: UIImage,
        detectedItems: [DetectedFoodItem],
        segmentationResults: [FoodSegmentationResult],
        depthData: MealDepthData?
    ) async throws -> [PortionEstimate] {
        detectedItems.map { item in
            PortionEstimate(
                foodItemId: item.id,
                estimatedGrams: item.estimatedGrams,
                estimatedVolumeMl: item.estimatedVolumeMl,
                servingDescription: item.servingDescription,
                method: .mockFixture,
                confidence: item.confidence,
                warning: item.warning
            )
        }
    }
}

struct MealScanPipeline {
    static let pipelineVersion = "meal-scan-v2-local-1"

    let classificationService: any FoodClassificationService
    let segmentationService: any FoodSegmentationService
    let portionEstimationService: any PortionEstimationService
    let nutritionLookupService: any NutritionLookupService
    var calculator: any MealNutritionCalculating = MealNutritionCalculator()
    var metabolicProfileService = MealMetabolicProfileService()
    var modelVersion = "mock-food-fixtures"

    @MainActor
    static func mock() -> MealScanPipeline {
        MealScanPipeline(
            classificationService: MockFoodVisionService(),
            segmentationService: MockFoodSegmentationService(),
            portionEstimationService: MockPortionEstimationService(),
            nutritionLookupService: LocalFoodNutritionRepository(records: SampleNutritionFixtures.records)
        )
    }

    @MainActor
    static func production(registry: MealScanModelRegistry) -> MealScanPipeline {
        MealScanPipeline(
            classificationService: CoreMLFoodClassificationService(registry: registry, fallback: MockFoodVisionService()),
            segmentationService: CoreMLFoodSegmentationService(registry: registry, fallback: MockFoodSegmentationService()),
            portionEstimationService: DepthAwarePortionEstimationService(fallback: MockPortionEstimationService()),
            nutritionLookupService: LocalUSDANutritionRepository(fallback: LocalFoodNutritionRepository(records: SampleNutritionFixtures.records)),
            modelVersion: registry.hasAnyModel ? registry.modelVersion : "mock-food-fixtures"
        )
    }

    @MainActor
    func scan(image: UIImage, mealType: MealType) async throws -> MealScanResult {
        _ = try await classificationService.classifyFood(in: image)
        _ = try await segmentationService.segmentFood(in: image)

        let template = MockMealScanTemplate.template(for: image)
        let drafts = try await template.makeDrafts(repository: nutritionLookupService, calculator: calculator)
        let total = calculator.aggregateMealNutrition(items: drafts)
        let warnings = template.warnings
        let confidence = MealScanConfidenceScorer.aggregate(drafts.map(\.confidence))
        let profile = metabolicProfileService.profile(
            for: total,
            confidence: confidence,
            hiddenIngredientEstimate: .notSure,
            visibleWarnings: warnings
        )
        let originalJSON = MealScanJSON.encodeOriginal(
            mealName: template.mealName,
            items: drafts,
            nutrition: total,
            confidence: confidence,
            warnings: warnings
        )

        return MealScanResult(
            mealName: template.mealName,
            mealType: mealType,
            detectedItems: drafts,
            nutrition: total,
            metabolicProfile: profile,
            confidence: confidence,
            warnings: warnings,
            originalPredictionJSON: originalJSON,
            modelVersion: modelVersion,
            pipelineVersion: Self.pipelineVersion
        )
    }
}

private struct MockMealScanTemplate {
    var mealName: String
    var components: [(name: String, foodID: String, grams: Double, serving: String, warning: String?)]
    var warnings: [String]

    static let templates: [MockMealScanTemplate] = [
        chickenRiceBowl,
        eggsAndToast,
        oatmealWithBerries,
        saladWithChicken,
        pastaWithSauce,
        smoothie,
    ]

    static let chickenRiceBowl = MockMealScanTemplate(
        mealName: "Chicken rice bowl",
        components: [
            ("Chicken breast", "chicken-breast-cooked", 120, "about 1 palm-sized serving", nil),
            ("White rice", "rice-white-cooked", 150, "about 1 cup cooked", nil),
            ("Broccoli", "broccoli", 80, "about 1 cup", nil),
        ],
        warnings: ["Estimates may be lower if oil, dressing, or sauce was not visible."]
    )

    static let eggsAndToast = MockMealScanTemplate(
        mealName: "Eggs and toast",
        components: [
            ("Eggs", "egg", 100, "about 2 large eggs", nil),
            ("Whole wheat toast", "whole-wheat-bread", 38, "1 slice", nil),
            ("Butter", "butter", 7, "about 1/2 tbsp", "Butter may be hidden or spread unevenly."),
        ],
        warnings: ["Toast toppings and cooking fat can change the estimate."]
    )

    static let oatmealWithBerries = MockMealScanTemplate(
        mealName: "Oatmeal with berries",
        components: [
            ("Oatmeal", "oats-oatmeal", 234, "about 1 cup cooked", nil),
            ("Berries", "berries", 80, "about 1/2 cup", nil),
            ("Greek yogurt", "greek-yogurt", 85, "about 1/2 serving", nil),
        ],
        warnings: ["Sweeteners, nut butter, or milk may not be visible."]
    )

    static let saladWithChicken = MockMealScanTemplate(
        mealName: "Salad with chicken",
        components: [
            ("Salad greens", "salad-greens", 85, "about 2 cups", nil),
            ("Chicken breast", "chicken-breast-cooked", 100, "about 1 small palm-sized serving", nil),
            ("Vinaigrette", "vinaigrette", 20, "about 1.5 tbsp", "Dressing amounts are often hard to see."),
            ("Avocado", "avocado", 50, "about 1/3 avocado", nil),
        ],
        warnings: ["Dressing, croutons, cheese, and toppings can change the estimate."]
    )

    static let pastaWithSauce = MockMealScanTemplate(
        mealName: "Pasta with sauce",
        components: [
            ("Pasta", "pasta-cooked", 180, "about 1.25 cups cooked", nil),
            ("Tomato sauce", "tomato-sauce", 125, "about 1/2 cup", "Sauce recipes can vary widely."),
            ("Olive oil", "olive-oil", 7, "about 1/2 tbsp", "Added oil may be hidden in sauce."),
        ],
        warnings: ["Mixed dishes and restaurant portions need careful review."]
    )

    static let smoothie = MockMealScanTemplate(
        mealName: "Smoothie",
        components: [
            ("Smoothie", "smoothie-generic", 360, "about 1.5 cups", "Smoothies are low-confidence because ingredients are blended."),
            ("Banana", "banana", 60, "about 1/2 banana", nil),
            ("Berries", "berries", 70, "about 1/2 cup", nil),
        ],
        warnings: ["Blended meals can hide juice, sweeteners, protein powder, or nut butter."]
    )

    static func template(for image: UIImage) -> MockMealScanTemplate {
        guard image.size.width > 0 || image.size.height > 0 else {
            return chickenRiceBowl
        }
        let index = abs(Int(image.size.width + image.size.height)) % templates.count
        return templates[index]
    }

    @MainActor
    func makeDrafts(
        repository: any NutritionLookupService,
        calculator: any MealNutritionCalculating
    ) async throws -> [MealFoodItemDraft] {
        var drafts: [MealFoodItemDraft] = []
        for component in components {
            guard let food = try await repository.nutrition(forFoodId: component.foodID) else {
                throw FoodLookupError.productNotFound
            }
            let nutrition = calculator.calculateItemNutrition(food: food, grams: component.grams)
            drafts.append(MealFoodItemDraft(
                displayName: component.name,
                canonicalFoodId: component.foodID,
                nutritionSource: food.source,
                estimatedGrams: component.grams,
                servingDescription: component.serving,
                nutrition: nutrition,
                confidence: .medium,
                warning: component.warning
            ))
        }
        return drafts
    }
}

enum MealScanJSON {
    static func encodeOriginal(
        mealName: String,
        items: [MealFoodItemDraft],
        nutrition: NutritionSnapshot,
        confidence: NutritionConfidence,
        warnings: [String]
    ) -> String {
        let payload = MealScanJSONPayload(
            mealName: mealName,
            items: items,
            nutrition: nutrition,
            confidence: confidence,
            warnings: warnings
        )
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.sortedKeys]
        guard let data = try? encoder.encode(payload) else { return "{}" }
        return String(data: data, encoding: .utf8) ?? "{}"
    }
}

private struct MealScanJSONPayload: Codable {
    var mealName: String
    var items: [MealFoodItemDraft]
    var nutrition: NutritionSnapshot
    var confidence: NutritionConfidence
    var warnings: [String]
}

struct SampleNutritionFixtures {
    static let aliases: [FoodAlias] = [
        FoodAlias(inputName: "plain rice", canonicalFoodName: "rice, white, cooked", defaultFoodId: "rice-white-cooked", category: .cookedRice),
        FoodAlias(inputName: "chicken", canonicalFoodName: "chicken breast, cooked", defaultFoodId: "chicken-breast-cooked", category: .chicken),
        FoodAlias(inputName: "salad", canonicalFoodName: "salad greens", defaultFoodId: "salad-greens", category: .salad),
        FoodAlias(inputName: "smoothie", canonicalFoodName: "smoothie generic", defaultFoodId: "smoothie-generic", category: .mixedDish),
    ]

    static let records: [FoodNutritionRecord] = [
        record("rice-white-cooked", "White rice, cooked", "rice, white, cooked", .cookedRice, 130, 2.7, 28.2, 0.3, 0.4, 0.1, 1, "1 cup cooked", 158, ["white rice", "plain rice"]),
        record("rice-brown-cooked", "Brown rice, cooked", "rice, brown, cooked", .cookedRice, 123, 2.7, 25.6, 1.0, 1.8, 0.2, 4, "1 cup cooked", 195, ["brown rice"]),
        record("chicken-breast-cooked", "Chicken breast, cooked", "chicken breast, cooked", .chicken, 165, 31, 0, 3.6, 0, 0, 74, "3 oz cooked", 85, ["chicken breast", "chicken"]),
        record("chicken-thigh-cooked", "Chicken thigh, cooked", "chicken thigh, cooked", .chicken, 209, 26, 0, 10.9, 0, 0, 84, "3 oz cooked", 85, ["chicken thigh"]),
        record("salmon-cooked", "Salmon, cooked", "salmon, cooked", .fish, 206, 22, 0, 12, 0, 0, 61, "3 oz cooked", 85, ["salmon"]),
        record("ground-beef-cooked", "Ground beef, cooked", "ground beef, cooked", .beef, 250, 26, 0, 15, 0, 0, 72, "3 oz cooked", 85, ["beef"]),
        record("egg", "Egg", "egg, whole", .eggs, 143, 12.6, 0.7, 9.5, 0, 0.4, 142, "1 large egg", 50, ["eggs"]),
        record("greek-yogurt", "Greek yogurt", "greek yogurt, plain", .yogurt, 97, 9, 3.6, 5, 0, 3.2, 35, "3/4 cup", 170, ["plain greek yogurt"]),
        record("plain-yogurt", "Plain yogurt", "plain yogurt", .yogurt, 61, 3.5, 4.7, 3.3, 0, 4.7, 46, "3/4 cup", 170, ["yogurt"]),
        record("oats-oatmeal", "Oats/oatmeal", "oatmeal, cooked", .oatmeal, 71, 2.5, 12, 1.5, 1.7, 0.3, 4, "1 cup cooked", 234, ["oats", "oatmeal"]),
        record("whole-wheat-bread", "Whole wheat bread", "bread, whole wheat", .bread, 247, 13, 41, 4.2, 7, 6, 400, "1 slice", 38, ["whole grain bread"]),
        record("white-bread", "White bread", "bread, white", .bread, 265, 9, 49, 3.2, 2.7, 5, 491, "1 slice", 28, ["toast"]),
        record("avocado", "Avocado", "avocado", .fruit, 160, 2, 8.5, 14.7, 6.7, 0.7, 7, "1/2 avocado", 75, ["avocado"]),
        record("banana", "Banana", "banana", .fruit, 89, 1.1, 22.8, 0.3, 2.6, 12.2, 1, "1 medium", 118, ["banana"]),
        record("apple", "Apple", "apple", .fruit, 52, 0.3, 13.8, 0.2, 2.4, 10.4, 1, "1 medium", 182, ["apple"]),
        record("berries", "Berries", "berries, mixed", .fruit, 57, 0.7, 14.5, 0.3, 2.4, 10, 1, "1 cup", 140, ["blueberries", "strawberries", "mixed berries"]),
        record("broccoli", "Broccoli", "broccoli, cooked", .vegetables, 35, 2.4, 7.2, 0.4, 3.3, 1.4, 41, "1 cup", 156, ["broccoli"]),
        record("spinach", "Spinach", "spinach", .vegetables, 23, 2.9, 3.6, 0.4, 2.2, 0.4, 79, "2 cups raw", 60, ["spinach"]),
        record("salad-greens", "Salad greens", "salad greens", .salad, 17, 1.5, 3.3, 0.2, 2, 0.6, 28, "2 cups", 85, ["greens", "lettuce"]),
        record("black-beans", "Black beans", "black beans, cooked", .beans, 132, 8.9, 23.7, 0.5, 8.7, 0.3, 1, "1/2 cup", 86, ["black beans"]),
        record("pinto-beans", "Pinto beans", "pinto beans, cooked", .beans, 143, 9, 26, 0.7, 9, 0.3, 1, "1/2 cup", 86, ["pinto beans"]),
        record("pasta-cooked", "Pasta, cooked", "pasta, cooked", .pasta, 158, 5.8, 30.9, 0.9, 1.8, 0.6, 1, "1 cup", 140, ["pasta"]),
        record("olive-oil", "Olive oil", "olive oil", .oilDressing, 884, 0, 0, 100, 0, 0, 2, "1 tbsp", 14, ["oil"]),
        record("butter", "Butter", "butter", .oilDressing, 717, 0.9, 0.1, 81, 0, 0.1, 11, "1 tbsp", 14, ["butter"]),
        record("ranch-dressing", "Ranch dressing", "ranch dressing", .oilDressing, 430, 1, 6, 45, 0, 4, 780, "2 tbsp", 30, ["ranch"]),
        record("vinaigrette", "Vinaigrette", "vinaigrette", .oilDressing, 467, 0, 7, 50, 0, 6, 800, "2 tbsp", 30, ["dressing"]),
        record("tomato-sauce", "Tomato sauce", "tomato sauce", .sauce, 29, 1.3, 6.4, 0.2, 1.5, 4, 400, "1/2 cup", 125, ["red sauce"]),
        record("soup-generic", "Soup generic", "soup generic", .soup, 45, 2, 7, 1.5, 1, 2, 350, "1 cup", 245, ["soup"]),
        record("smoothie-generic", "Smoothie generic", "smoothie generic", .mixedDish, 80, 2, 16, 1.5, 2, 11, 20, "1 cup", 240, ["smoothie"]),
    ]

    private static func record(
        _ id: String,
        _ displayName: String,
        _ canonicalName: String,
        _ category: FoodCategory,
        _ calories: Double,
        _ protein: Double,
        _ carbs: Double,
        _ fat: Double,
        _ fiber: Double,
        _ sugar: Double,
        _ sodium: Double,
        _ serving: String,
        _ servingGrams: Double,
        _ aliases: [String]
    ) -> FoodNutritionRecord {
        FoodNutritionRecord(
            id: id,
            source: .appFixture,
            displayName: displayName,
            canonicalName: canonicalName,
            servingDescription: serving,
            servingGrams: servingGrams,
            caloriesPer100g: calories,
            proteinPer100g: protein,
            carbsPer100g: carbs,
            fatPer100g: fat,
            fiberPer100g: fiber,
            sugarPer100g: sugar,
            sodiumMgPer100g: sodium,
            category: category,
            aliases: aliases
        )
    }
}
