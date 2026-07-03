import Testing
@testable import PCOS

@Suite("Meal Metabolic Profile")
struct MealMetabolicProfileTests {
    @Test("high-carb low-fiber meals are marked high impact without medical claims")
    func highCarbLowFiberMeal() {
        let profile = MealMetabolicProfileService().profile(
            for: NutritionSnapshot(
                caloriesKcal: 720,
                proteinGrams: 12,
                carbsGrams: 96,
                fatGrams: 18,
                fiberGrams: 2,
                sugarGrams: 24
            ),
            confidence: .medium,
            hiddenIngredientEstimate: .notSure,
            visibleWarnings: ["Restaurant meals can include hidden oil or sauce."]
        )

        #expect(profile.carbLoadCategory == .veryHigh)
        #expect(profile.fiberAdequacy == .low)
        #expect(profile.estimatedGlycemicImpact == .high)
        #expect(profile.mealBalanceScore < 50)
        #expect(profile.explanation.localizedCaseInsensitiveContains("may have"))
        #expect(!profile.explanation.localizedCaseInsensitiveContains("will spike"))
        #expect(profile.caution?.localizedCaseInsensitiveContains("estimate") == true)
    }

    @Test("protein and fiber lower impact and improve balance score")
    func balancedProteinFiberMeal() {
        let profile = MealMetabolicProfileService().profile(
            for: NutritionSnapshot(
                caloriesKcal: 520,
                proteinGrams: 38,
                carbsGrams: 42,
                fatGrams: 18,
                fiberGrams: 11,
                sugarGrams: 7
            ),
            confidence: .high,
            hiddenIngredientEstimate: .no,
            visibleWarnings: []
        )

        #expect(profile.proteinAdequacy == .strong)
        #expect(profile.fiberAdequacy == .strong)
        #expect(profile.estimatedGlycemicImpact == .low || profile.estimatedGlycemicImpact == .moderate)
        #expect(profile.mealBalanceScore >= 70)
        #expect(profile.explanation.localizedCaseInsensitiveContains("may help balance"))
    }

    @Test("mixed meals and hidden sauces reduce confidence")
    func hiddenSauceReducesConfidence() {
        let adjusted = MealScanConfidenceScorer.adjustedConfidence(
            base: .high,
            hiddenIngredientEstimate: .aLot,
            isMixedDish: true,
            wasUserEdited: false
        )

        #expect(adjusted == .low)
    }
}
