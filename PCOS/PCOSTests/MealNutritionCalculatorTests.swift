import Testing
import Foundation
@testable import PCOS

@Suite("Meal Nutrition Calculator")
struct MealNutritionCalculatorTests {
    @Test("per-100g nutrients scale deterministically by grams")
    func per100gFormulaScalesByGrams() {
        let food = FoodNutritionRecord(
            id: "rice-white-cooked",
            source: .appFixture,
            displayName: "White rice, cooked",
            canonicalName: "rice, white, cooked",
            servingDescription: "1 cup cooked",
            servingGrams: 158,
            caloriesPer100g: 130,
            proteinPer100g: 2.7,
            carbsPer100g: 28.2,
            fatPer100g: 0.3,
            fiberPer100g: 0.4,
            sugarPer100g: 0.1,
            sodiumMgPer100g: 1
        )

        let snapshot = MealNutritionCalculator().calculateItemNutrition(food: food, grams: 150)

        #expect(snapshot.caloriesKcal == 195)
        #expect(abs(snapshot.proteinGrams - 4.05) < 0.0001)
        #expect(snapshot.carbsGrams == 42.3)
        #expect(abs(snapshot.fatGrams - 0.45) < 0.0001)
        #expect(abs(snapshot.fiberGrams - 0.6) < 0.0001)
        #expect(abs(snapshot.sugarGrams - 0.15) < 0.0001)
        #expect(snapshot.sodiumMg == 1.5)
        #expect(abs(snapshot.netCarbsGrams - 41.7) < 0.0001)
    }

    @Test("missing nutrient values calculate as zero and net carbs never goes below zero")
    func missingValuesAndNetCarbFloor() {
        let food = FoodNutritionRecord(
            id: "fiber-only",
            source: .appFixture,
            displayName: "Fiber test",
            canonicalName: "fiber test",
            caloriesPer100g: nil,
            proteinPer100g: nil,
            carbsPer100g: 3,
            fatPer100g: nil,
            fiberPer100g: 8,
            sugarPer100g: nil,
            sodiumMgPer100g: nil
        )

        let snapshot = MealNutritionCalculator().calculateItemNutrition(food: food, grams: 100)

        #expect(snapshot.caloriesKcal == 0)
        #expect(snapshot.proteinGrams == 0)
        #expect(snapshot.fatGrams == 0)
        #expect(snapshot.sugarGrams == 0)
        #expect(snapshot.sodiumMg == 0)
        #expect(snapshot.netCarbsGrams == 0)
    }

    @Test("aggregation sums all nutrients and includes hidden oil items")
    func aggregationSumsMultipleItems() {
        let chicken = MealFoodItemDraft(
            displayName: "Chicken breast",
            canonicalFoodId: "chicken-breast-cooked",
            estimatedGrams: 120,
            nutrition: NutritionSnapshot(caloriesKcal: 198, proteinGrams: 37.2, carbsGrams: 0, fatGrams: 4.3)
        )
        let rice = MealFoodItemDraft(
            displayName: "White rice",
            canonicalFoodId: "rice-white-cooked",
            estimatedGrams: 150,
            nutrition: NutritionSnapshot(caloriesKcal: 195, proteinGrams: 4.1, carbsGrams: 42.3, fatGrams: 0.5, fiberGrams: 0.6, sugarGrams: 0.2, sodiumMg: 2)
        )
        let oil = MealFoodItemDraft(
            displayName: "Olive oil",
            canonicalFoodId: "olive-oil",
            estimatedGrams: 14,
            nutrition: NutritionSnapshot(caloriesKcal: 119, fatGrams: 13.5),
            warning: "Added for hidden oil estimate"
        )

        let total = MealNutritionCalculator().aggregateMealNutrition(items: [chicken, rice, oil])

        #expect(total.caloriesKcal == 512)
        #expect(abs(total.proteinGrams - 41.3) < 0.0001)
        #expect(total.carbsGrams == 42.3)
        #expect(total.fatGrams == 18.3)
        #expect(total.fiberGrams == 0.6)
        #expect(total.sugarGrams == 0.2)
        #expect(total.sodiumMg == 2)
        #expect(abs(total.netCarbsGrams - 41.7) < 0.0001)
    }

    @Test("display rounding follows meal scan formatting rules")
    func displayRounding() {
        let snapshot = NutritionSnapshot(
            caloriesKcal: 194.6,
            proteinGrams: 4.04,
            carbsGrams: 42.34,
            fatGrams: 0.44,
            fiberGrams: 0.55,
            sugarGrams: 0.15,
            sodiumMg: 1.5
        )

        #expect(MealNutritionCalculator.displayCalories(snapshot.caloriesKcal) == "195")
        #expect(MealNutritionCalculator.displayMacro(snapshot.carbsGrams) == "42.3")
        #expect(MealNutritionCalculator.displaySodium(snapshot.sodiumMg) == "2")
    }
}
