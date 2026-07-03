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
                    title: L10n.string("Greek Yogurt Bowl", defaultValue: "Greek Yogurt Bowl"),
                    mealType: .breakfast,
                    description: L10n.string("Greek yogurt, berries, chia seeds", defaultValue: "Greek yogurt, berries, chia seeds"),
                    glycemicImpact: .low
                ),
                MealTemplate(
                    id: "breakfast.veggie-omelet",
                    title: L10n.string("Veggie Omelet", defaultValue: "Veggie Omelet"),
                    mealType: .breakfast,
                    description: L10n.string("Eggs, spinach, mushrooms, avocado", defaultValue: "Eggs, spinach, mushrooms, avocado"),
                    glycemicImpact: .low
                ),
                MealTemplate(
                    id: "breakfast.protein-oats",
                    title: L10n.string("Protein Oats", defaultValue: "Protein Oats"),
                    mealType: .breakfast,
                    description: L10n.string("Steel-cut oats, walnuts, protein powder", defaultValue: "Steel-cut oats, walnuts, protein powder"),
                    glycemicImpact: .medium
                ),
            ]
        case .lunch:
            return [
                MealTemplate(
                    id: "lunch.chicken-quinoa-bowl",
                    title: L10n.string("Chicken Quinoa Bowl", defaultValue: "Chicken Quinoa Bowl"),
                    mealType: .lunch,
                    description: L10n.string("Grilled chicken, quinoa, roasted vegetables", defaultValue: "Grilled chicken, quinoa, roasted vegetables"),
                    glycemicImpact: .low
                ),
                MealTemplate(
                    id: "lunch.salmon-salad",
                    title: L10n.string("Salmon Salad", defaultValue: "Salmon Salad"),
                    mealType: .lunch,
                    description: L10n.string("Salmon, mixed greens, olive oil vinaigrette", defaultValue: "Salmon, mixed greens, olive oil vinaigrette"),
                    glycemicImpact: .low
                ),
                MealTemplate(
                    id: "lunch.lentil-bowl",
                    title: L10n.string("Lentil Power Bowl", defaultValue: "Lentil Power Bowl"),
                    mealType: .lunch,
                    description: L10n.string("Lentils, greens, tahini, cucumber", defaultValue: "Lentils, greens, tahini, cucumber"),
                    glycemicImpact: .low
                ),
            ]
        case .dinner:
            return [
                MealTemplate(
                    id: "dinner.salmon-veggies",
                    title: L10n.string("Salmon + Veggies", defaultValue: "Salmon + Veggies"),
                    mealType: .dinner,
                    description: L10n.string("Baked salmon, broccoli, cauliflower mash", defaultValue: "Baked salmon, broccoli, cauliflower mash"),
                    glycemicImpact: .low
                ),
                MealTemplate(
                    id: "dinner.turkey-chili",
                    title: L10n.string("Turkey Chili", defaultValue: "Turkey Chili"),
                    mealType: .dinner,
                    description: L10n.string("Ground turkey, beans, tomatoes, peppers", defaultValue: "Ground turkey, beans, tomatoes, peppers"),
                    glycemicImpact: .medium
                ),
                MealTemplate(
                    id: "dinner.tofu-stirfry",
                    title: L10n.string("Tofu Stir-Fry", defaultValue: "Tofu Stir-Fry"),
                    mealType: .dinner,
                    description: L10n.string("Tofu, mixed vegetables, brown rice", defaultValue: "Tofu, mixed vegetables, brown rice"),
                    glycemicImpact: .medium
                ),
            ]
        case .snack:
            return [
                MealTemplate(
                    id: "snack.apple-nut-butter",
                    title: L10n.string("Apple + Nut Butter", defaultValue: "Apple + Nut Butter"),
                    mealType: .snack,
                    description: L10n.string("Apple slices with almond butter", defaultValue: "Apple slices with almond butter"),
                    glycemicImpact: .low
                ),
                MealTemplate(
                    id: "snack.greek-yogurt",
                    title: L10n.string("Greek Yogurt Cup", defaultValue: "Greek Yogurt Cup"),
                    mealType: .snack,
                    description: L10n.string("Greek yogurt with cinnamon", defaultValue: "Greek yogurt with cinnamon"),
                    glycemicImpact: .low
                ),
                MealTemplate(
                    id: "snack.nuts-seeds",
                    title: L10n.string("Nuts + Seeds", defaultValue: "Nuts + Seeds"),
                    mealType: .snack,
                    description: L10n.string("Mixed nuts, pumpkin seeds", defaultValue: "Mixed nuts, pumpkin seeds"),
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
            swaps.append(L10n.string(
                "Try cauliflower rice or quinoa instead of white rice.",
                defaultValue: "Try cauliflower rice or quinoa instead of white rice."
            ))
        }
        if lowercased.contains("white bread") || lowercased.contains("bread") {
            swaps.append(L10n.string(
                "Try whole-grain or seed bread instead of white bread.",
                defaultValue: "Try whole-grain or seed bread instead of white bread."
            ))
        }
        if lowercased.contains("pasta") {
            swaps.append(L10n.string(
                "Try chickpea or lentil pasta instead of refined pasta.",
                defaultValue: "Try chickpea or lentil pasta instead of refined pasta."
            ))
        }
        if lowercased.contains("potato") {
            swaps.append(L10n.string(
                "Try sweet potato or roasted cauliflower instead of white potato.",
                defaultValue: "Try sweet potato or roasted cauliflower instead of white potato."
            ))
        }
        if lowercased.contains("soda") || lowercased.contains("juice") || lowercased.contains("sweet") {
            swaps.append(L10n.string(
                "Try sparkling water or unsweetened tea instead of sugary drinks.",
                defaultValue: "Try sparkling water or unsweetened tea instead of sugary drinks."
            ))
        }

        if swaps.isEmpty {
            swaps.append(L10n.string(
                "Try pairing carbs with protein and fiber to reduce glucose spikes.",
                defaultValue: "Try pairing carbs with protein and fiber to reduce glucose spikes."
            ))
            swaps.append(L10n.string(
                "Try swapping one refined carb with a legume-based option this week.",
                defaultValue: "Try swapping one refined carb with a legume-based option this week."
            ))
        }

        return Array(swaps.prefix(3))
    }
}
