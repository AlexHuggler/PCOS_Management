import Foundation

struct MealTemplate: Identifiable, Hashable {
    let id: String
    let title: String
    let mealType: MealType
    let description: String
    let glycemicImpact: GlycemicImpact
}

protocol MealPlanningProviding {
    func templates(for mealType: MealType) -> [MealTemplate]
    func swapSuggestions(for description: String, glycemicImpact: GlycemicImpact) -> [String]
}

struct MealPlanningService: MealPlanningProviding {
    func templates(for mealType: MealType) -> [MealTemplate] {
        switch mealType {
        case .breakfast:
            return [
                MealTemplate(
                    id: "breakfast.greek-yogurt-berries",
                    title: "Greek Yogurt Bowl",
                    mealType: .breakfast,
                    description: "Greek yogurt, berries, chia seeds",
                    glycemicImpact: .low
                ),
                MealTemplate(
                    id: "breakfast.veggie-omelet",
                    title: "Veggie Omelet",
                    mealType: .breakfast,
                    description: "Eggs, spinach, mushrooms, avocado",
                    glycemicImpact: .low
                ),
                MealTemplate(
                    id: "breakfast.protein-oats",
                    title: "Protein Oats",
                    mealType: .breakfast,
                    description: "Steel-cut oats, walnuts, protein powder",
                    glycemicImpact: .medium
                ),
            ]
        case .lunch:
            return [
                MealTemplate(
                    id: "lunch.chicken-quinoa-bowl",
                    title: "Chicken Quinoa Bowl",
                    mealType: .lunch,
                    description: "Grilled chicken, quinoa, roasted vegetables",
                    glycemicImpact: .low
                ),
                MealTemplate(
                    id: "lunch.salmon-salad",
                    title: "Salmon Salad",
                    mealType: .lunch,
                    description: "Salmon, mixed greens, olive oil vinaigrette",
                    glycemicImpact: .low
                ),
                MealTemplate(
                    id: "lunch.lentil-bowl",
                    title: "Lentil Power Bowl",
                    mealType: .lunch,
                    description: "Lentils, greens, tahini, cucumber",
                    glycemicImpact: .low
                ),
            ]
        case .dinner:
            return [
                MealTemplate(
                    id: "dinner.salmon-veggies",
                    title: "Salmon + Veggies",
                    mealType: .dinner,
                    description: "Baked salmon, broccoli, cauliflower mash",
                    glycemicImpact: .low
                ),
                MealTemplate(
                    id: "dinner.turkey-chili",
                    title: "Turkey Chili",
                    mealType: .dinner,
                    description: "Ground turkey, beans, tomatoes, peppers",
                    glycemicImpact: .medium
                ),
                MealTemplate(
                    id: "dinner.tofu-stirfry",
                    title: "Tofu Stir-Fry",
                    mealType: .dinner,
                    description: "Tofu, mixed vegetables, brown rice",
                    glycemicImpact: .medium
                ),
            ]
        case .snack:
            return [
                MealTemplate(
                    id: "snack.apple-nut-butter",
                    title: "Apple + Nut Butter",
                    mealType: .snack,
                    description: "Apple slices with almond butter",
                    glycemicImpact: .low
                ),
                MealTemplate(
                    id: "snack.greek-yogurt",
                    title: "Greek Yogurt Cup",
                    mealType: .snack,
                    description: "Greek yogurt with cinnamon",
                    glycemicImpact: .low
                ),
                MealTemplate(
                    id: "snack.nuts-seeds",
                    title: "Nuts + Seeds",
                    mealType: .snack,
                    description: "Mixed nuts, pumpkin seeds",
                    glycemicImpact: .low
                ),
            ]
        }
    }

    func swapSuggestions(for description: String, glycemicImpact: GlycemicImpact) -> [String] {
        guard glycemicImpact == .high else { return [] }

        let lowercased = description.lowercased()
        var swaps: [String] = []

        if lowercased.contains("white rice") || lowercased.contains("rice") {
            swaps.append("Try cauliflower rice or quinoa instead of white rice.")
        }
        if lowercased.contains("white bread") || lowercased.contains("bread") {
            swaps.append("Try whole-grain or seed bread instead of white bread.")
        }
        if lowercased.contains("pasta") {
            swaps.append("Try chickpea or lentil pasta instead of refined pasta.")
        }
        if lowercased.contains("potato") {
            swaps.append("Try sweet potato or roasted cauliflower instead of white potato.")
        }
        if lowercased.contains("soda") || lowercased.contains("juice") || lowercased.contains("sweet") {
            swaps.append("Try sparkling water or unsweetened tea instead of sugary drinks.")
        }

        if swaps.isEmpty {
            swaps.append("Try pairing carbs with protein and fiber to reduce glucose spikes.")
            swaps.append("Try swapping one refined carb with a legume-based option this week.")
        }

        return Array(swaps.prefix(3))
    }
}
