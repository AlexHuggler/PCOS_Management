import Foundation

struct SuggestionProvider {
    private let defaultsStore: UserEntryDefaultsStore

    init(defaultsStore: UserEntryDefaultsStore = .shared) {
        self.defaultsStore = defaultsStore
    }

    func bloodSugarMealContexts(limit: Int = 4) -> [String] {
        bloodSugarMealContextSuggestions(query: "", limit: limit)
    }

    func mealDescriptions(limit: Int = 4) -> [String] {
        mealDescriptionSuggestions(query: "", mealType: .lunch, limit: limit)
    }

    func supplementNames(limit: Int = 6) -> [String] {
        defaultsStore.recentSupplementNames(limit: limit)
    }

    func supplementBrands(limit: Int = 4) -> [String] {
        defaultsStore.recentSupplementBrands(limit: limit)
    }

    func recordBloodSugarMealContext(_ value: String) {
        defaultsStore.recordRecentBloodSugarMealContext(value)
    }

    func recordBloodSugarNote(_ value: String) {
        defaultsStore.recordRecentBloodSugarNote(value)
    }

    func recordMealDescription(_ value: String) {
        defaultsStore.recordRecentMealDescription(value)
    }

    func recordMealNote(_ value: String) {
        defaultsStore.recordRecentMealNote(value)
    }

    func recordPeriodNote(_ value: String, flowIntensity: FlowIntensity) {
        defaultsStore.recordRecentPeriodNote(value, flowIntensity: flowIntensity)
    }

    func recordSupplementName(_ value: String) {
        defaultsStore.recordRecentSupplementName(value)
    }

    func recordSupplementBrand(_ value: String) {
        defaultsStore.recordRecentSupplementBrand(value)
    }

    func mealDescriptionSuggestions(
        query: String,
        mealType: MealType,
        limit: Int = 6
    ) -> [String] {
        let curated = curatedMealDescriptions(for: mealType)
        let learned = defaultsStore.recentMealDescriptions(limit: max(limit * 2, 10))
        return rankedSuggestions(query: query, curated: curated, learned: learned, limit: limit)
    }

    func mealNoteSuggestions(query: String, limit: Int = 6) -> [String] {
        let curated = curatedMealNotes
        let learned = defaultsStore.recentMealNotes(limit: max(limit * 2, 10))
        return rankedSuggestions(query: query, curated: curated, learned: learned, limit: limit)
    }

    func periodNoteSuggestions(
        flowIntensity: FlowIntensity,
        query: String,
        limit: Int = 6
    ) -> [String] {
        let curated = curatedPeriodNotes(for: flowIntensity)
        let learned = defaultsStore.recentPeriodNotes(
            flowIntensity: flowIntensity,
            limit: max(limit * 2, 12)
        )
        return rankedSuggestions(query: query, curated: curated, learned: learned, limit: limit)
    }

    func bloodSugarMealContextSuggestions(query: String, limit: Int = 8) -> [String] {
        let curated = curatedBloodSugarContexts
        let learned = defaultsStore.recentBloodSugarMealContexts(limit: max(limit * 2, 12))
        return rankedSuggestions(query: query, curated: curated, learned: learned, limit: limit)
    }

    func bloodSugarNoteSuggestions(query: String, limit: Int = 8) -> [String] {
        let curated = curatedBloodSugarNotes
        let learned = defaultsStore.recentBloodSugarNotes(limit: max(limit * 2, 12))
        return rankedSuggestions(query: query, curated: curated, learned: learned, limit: limit)
    }

    private func rankedSuggestions(
        query: String,
        curated: [String],
        learned: [String],
        limit: Int
    ) -> [String] {
        let normalizedQuery = normalized(query)

        var candidates: [SuggestionCandidate] = []
        candidates.append(contentsOf: learned.enumerated().compactMap { index, value in
            let trimmed = value.trimmingCharacters(in: .whitespacesAndNewlines)
            guard !trimmed.isEmpty else { return nil }
            return SuggestionCandidate(text: trimmed, source: .learned(index))
        })
        candidates.append(contentsOf: curated.enumerated().compactMap { index, value in
            let trimmed = value.trimmingCharacters(in: .whitespacesAndNewlines)
            guard !trimmed.isEmpty else { return nil }
            return SuggestionCandidate(text: trimmed, source: .curated(index))
        })

        let filtered = candidates.filter { candidate in
            normalizedQuery.isEmpty || candidate.normalized.contains(normalizedQuery)
        }

        let sorted = filtered.sorted { lhs, rhs in
            let lhsMatchRank = matchRank(for: lhs, query: normalizedQuery)
            let rhsMatchRank = matchRank(for: rhs, query: normalizedQuery)
            if lhsMatchRank != rhsMatchRank {
                return lhsMatchRank < rhsMatchRank
            }

            if lhs.sourceRank != rhs.sourceRank {
                return lhs.sourceRank < rhs.sourceRank
            }

            if lhs.sourceOrder != rhs.sourceOrder {
                return lhs.sourceOrder < rhs.sourceOrder
            }

            return lhs.normalized < rhs.normalized
        }

        var seen = Set<String>()
        var output: [String] = []
        for candidate in sorted {
            let key = candidate.normalized
            guard seen.insert(key).inserted else { continue }
            output.append(candidate.text)
            if output.count >= limit { break }
        }
        return output
    }

    private func matchRank(for candidate: SuggestionCandidate, query: String) -> Int {
        guard !query.isEmpty else { return 0 }
        if candidate.normalized.hasPrefix(query) { return 0 }
        if candidate.normalized.contains(query) { return 1 }
        return 2
    }

    private func normalized(_ value: String) -> String {
        value.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
    }

    private func curatedMealDescriptions(for mealType: MealType) -> [String] {
        switch mealType {
        case .breakfast:
            [
                "Greek yogurt + berries",
                "Eggs + avocado toast",
                "Protein smoothie",
                "Oatmeal + nuts",
                "Chia pudding + fruit",
                "Veggie omelet",
                "Cottage cheese + pineapple",
                "Overnight oats + flax",
                "Whole grain toast + almond butter",
                "Scrambled eggs + spinach",
                "Breakfast burrito bowl",
                "Smoked salmon + cucumber toast",
                "Tofu scramble + peppers",
                "Quinoa porridge + cinnamon",
                "Apple cinnamon oats",
                "Skyr + walnuts",
                "Hard-boiled eggs + fruit",
                "Peanut butter banana smoothie",
                "Egg muffins + greens",
                "Buckwheat pancakes + berries",
                "Savory oats + egg",
                "Breakfast quinoa + berries",
                "Turkey sausage + eggs",
                "Avocado + cottage cheese bowl",
                "Muesli + yogurt",
            ]
        case .lunch:
            [
                "Grilled chicken salad",
                "Quinoa bowl",
                "Turkey lettuce wrap",
                "Lentil soup",
                "Tuna salad + crackers",
                "Chicken and veggie wrap",
                "Chickpea salad bowl",
                "Brown rice + tofu bowl",
                "Turkey chili",
                "Shrimp salad",
                "Salmon grain bowl",
                "Hummus + veggie pita",
                "Chicken quinoa soup",
                "Egg salad lettuce cups",
                "Steak + arugula salad",
                "Black bean bowl",
                "Greek salad + chicken",
                "Sardines + toast",
                "Cottage cheese + tomato plate",
                "Tofu miso soup + rice",
                "Edamame quinoa salad",
                "Chicken caesar wrap",
                "Farro + roasted veggie bowl",
                "Turkey burger bowl",
                "Caprese chicken salad",
            ]
        case .dinner:
            [
                "Salmon + roasted vegetables",
                "Chicken stir-fry",
                "Tofu + vegetables",
                "Lean protein + greens",
                "Turkey meatballs + zucchini noodles",
                "Baked cod + asparagus",
                "Steak + sweet potato + broccoli",
                "Shrimp + cauliflower rice",
                "Lentil curry + spinach",
                "Grilled chicken + quinoa",
                "Beef and veggie skillet",
                "Tofu stir-fry + brown rice",
                "Chicken fajita bowl",
                "Turkey chili + salad",
                "Miso salmon + bok choy",
                "Pesto chicken + green beans",
                "Stuffed bell peppers",
                "Soba noodles + tofu",
                "Baked chicken + Brussels sprouts",
                "Ground turkey lettuce wraps",
                "Cod tacos + slaw",
                "Chickpea pasta + vegetables",
                "Shakshuka + side salad",
                "Roasted tofu + carrots",
                "Grilled shrimp + quinoa salad",
            ]
        case .snack:
            [
                "Apple + peanut butter",
                "Cottage cheese + fruit",
                "Nuts + seeds",
                "Hummus + veggies",
                "Greek yogurt cup",
                "Protein shake",
                "Cheese + whole grain crackers",
                "Hard-boiled eggs",
                "Trail mix",
                "Edamame",
                "Banana + almond butter",
                "Turkey roll-ups",
                "Chia pudding cup",
                "Carrots + guacamole",
                "Roasted chickpeas",
                "Berry smoothie",
                "Pumpkin seeds + fruit",
                "Rice cake + cottage cheese",
                "Celery + peanut butter",
                "Protein bar",
                "Apple slices + cheese",
                "Tuna cucumber boats",
                "Boiled egg + almonds",
                "Yogurt + granola",
                "Pear + walnuts",
            ]
        }
    }

    private var curatedMealNotes: [String] {
        [
            "High stress",
            "Poor sleep",
            "Late meal",
            "Post-workout",
            "Ate out",
        ]
    }

    private var curatedBloodSugarContexts: [String] {
        [
            "Fasting (morning)",
            "Before breakfast",
            "1h after breakfast",
            "2h after breakfast",
            "Before lunch",
            "2h after lunch",
            "Before dinner",
            "2h after dinner",
            "Bedtime",
            "Post-workout",
        ]
    }

    private var curatedBloodSugarNotes: [String] {
        [
            "Dizzy",
            "Shaky",
            "Sweaty",
            "Headache",
            "Low energy",
            "Missed meal",
            "High stress",
            "Poor sleep",
            "After exercise",
        ]
    }

    private func curatedPeriodNotes(for flowIntensity: FlowIntensity) -> [String] {
        switch flowIntensity {
        case .none:
            []
        case .spotting:
            [
                "Spotting duration",
                "Brown spotting",
                "Pink spotting",
                "Mild cramps",
                "Mood changes",
                "After exercise",
            ]
        case .light:
            [
                "Small clots",
                "Mild cramps",
                "Mood changes",
                "Low energy",
                "Spotting duration",
                "Headache",
            ]
        case .medium:
            [
                "Clotting",
                "Moderate cramps",
                "Back pain",
                "Mood changes",
                "Fatigue",
                "Bloating",
            ]
        case .heavy:
            [
                "Heavy clotting",
                "Severe cramps",
                "Frequent product change",
                "Mood changes",
                "Low energy",
                "Dizziness",
            ]
        }
    }
}

private enum SuggestionSource {
    case learned(Int)
    case curated(Int)

    var rank: Int {
        switch self {
        case .learned:
            0
        case .curated:
            1
        }
    }

    var order: Int {
        switch self {
        case .learned(let index), .curated(let index):
            index
        }
    }
}

private struct SuggestionCandidate {
    let text: String
    let normalized: String
    let source: SuggestionSource

    init(text: String, source: SuggestionSource) {
        self.text = text
        self.normalized = text.lowercased()
        self.source = source
    }

    var sourceRank: Int { source.rank }
    var sourceOrder: Int { source.order }
}
