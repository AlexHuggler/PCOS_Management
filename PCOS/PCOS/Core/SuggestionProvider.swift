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

    func recordMealDescription(_ value: String, mealType: MealType) {
        defaultsStore.recordRecentMealDescription(value, mealType: mealType)
    }

    func recordMealNote(_ value: String, mealType: MealType) {
        defaultsStore.recordRecentMealNote(value, mealType: mealType)
    }

    func recordPhotoNote(_ value: String, photoType: HairPhotoType) {
        defaultsStore.recordRecentPhotoNote(value, photoType: photoType)
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
        let learned = defaultsStore.recentMealDescriptions(
            mealType: mealType,
            limit: max(limit * 2, 10)
        )
        return rankedSuggestions(query: query, curated: curated, learned: learned, limit: limit)
    }

    func mealNoteSuggestions(query: String, mealType: MealType, limit: Int = 6) -> [String] {
        let curated = curatedMealNotes(for: mealType)
        let learned = defaultsStore.recentMealNotes(
            mealType: mealType,
            limit: max(limit * 2, 10)
        )
        return rankedSuggestions(query: query, curated: curated, learned: learned, limit: limit)
    }

    func photoNoteSuggestions(photoType: HairPhotoType, query: String, limit: Int = 8) -> [String] {
        let curated = curatedPhotoNotes(for: photoType)
        let learned = defaultsStore.recentPhotoNotes(photoType: photoType, limit: max(limit * 2, 12))
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
                "Breakfast sandwich",
                "Sweet potato hash + eggs",
                "Yogurt parfait",
                "Protein pancakes",
                "Breakfast tacos",
                "Egg white bites",
                "Tofu breakfast burrito",
                "Smoothie bowl",
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
                "Chicken burrito bowl",
                "Turkey sandwich + fruit",
                "Mediterranean bowl",
                "Soup + half sandwich",
                "Poke bowl",
                "Sushi bowl",
                "Chicken pasta salad",
                "Taco salad",
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
                "Sheet-pan chicken + veggies",
                "Chicken curry + rice",
                "Salmon rice bowl",
                "Turkey burger + salad",
                "Beef tacos + slaw",
                "Turkey stuffed sweet potato",
                "Veggie frittata + salad",
                "Chicken soup + salad",
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
                "String cheese + fruit",
                "Jerky + fruit",
                "Cottage cheese cup",
                "Dates + nuts",
                "Mini smoothie",
                "Veggie chips + hummus",
                "Rice cake + nut butter",
                "Protein bites",
            ]
        }
    }

    private func curatedMealNotes(for mealType: MealType) -> [String] {
        let common = [
            "Balanced meal",
            "Ate out",
            "Meal prep",
            "Large portion",
            "Craving-driven",
        ]

        let specific: [String] = switch mealType {
        case .breakfast:
            [
                "Skipped breakfast",
                "Coffee first",
                "Sweet breakfast",
                "High protein",
                "On the go",
            ]
        case .lunch:
            [
                "Desk lunch",
                "Packed lunch",
                "Light lunch",
                "High carb",
                "Restaurant lunch",
            ]
        case .dinner:
            [
                "Late dinner",
                "Heavy dinner",
                "Family meal",
                "Takeout",
                "High carb",
            ]
        case .snack:
            [
                "Pre-workout",
                "Post-workout",
                "Sweet snack",
                "Salty snack",
                "Late-night snack",
            ]
        }

        return common + specific
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
                L10n.string("Spotting duration", defaultValue: "Spotting duration"),
                L10n.string("Brown spotting", defaultValue: "Brown spotting"),
                L10n.string("Pink spotting", defaultValue: "Pink spotting"),
                L10n.string("Mild cramps", defaultValue: "Mild cramps"),
                L10n.string("Mood changes", defaultValue: "Mood changes"),
                L10n.string("After exercise", defaultValue: "After exercise"),
            ]
        case .light:
            [
                L10n.string("Small clots", defaultValue: "Small clots"),
                L10n.string("Mild cramps", defaultValue: "Mild cramps"),
                L10n.string("Mood changes", defaultValue: "Mood changes"),
                L10n.string("Low energy", defaultValue: "Low energy"),
                L10n.string("Spotting duration", defaultValue: "Spotting duration"),
                L10n.string("Headache", defaultValue: "Headache"),
            ]
        case .medium:
            [
                L10n.string("Clotting", defaultValue: "Clotting"),
                L10n.string("Moderate cramps", defaultValue: "Moderate cramps"),
                L10n.string("Back pain", defaultValue: "Back pain"),
                L10n.string("Mood changes", defaultValue: "Mood changes"),
                L10n.string("Fatigue", defaultValue: "Fatigue"),
                L10n.string("Bloating", defaultValue: "Bloating"),
            ]
        case .heavy:
            [
                L10n.string("Heavy clotting", defaultValue: "Heavy clotting"),
                L10n.string("Severe cramps", defaultValue: "Severe cramps"),
                L10n.string("Frequent product change", defaultValue: "Frequent product change"),
                L10n.string("Mood changes", defaultValue: "Mood changes"),
                L10n.string("Low energy", defaultValue: "Low energy"),
                L10n.string("Dizziness", defaultValue: "Dizziness"),
            ]
        }
    }

    private func curatedPhotoNotes(for photoType: HairPhotoType) -> [String] {
        switch photoType {
        case .scalpPart:
            [
                "Same part placement",
                "More shedding",
                "Less shedding",
                "New growth",
                "Dry scalp",
                "Oily scalp",
            ]
        case .hairline:
            [
                "Baby hairs",
                "Temple thinning",
                "Fill-in growth",
                "Breakage",
                "Redness",
                "Same angle",
            ]
        case .faceChin:
            [
                "New coarse hairs",
                "Less dense",
                "Post-removal",
                "Ingrown hairs",
                "Irritated skin",
                "Same lighting",
            ]
        case .faceUpperLip:
            [
                "Darker hairs",
                "Less visible",
                "Post-removal",
                "Shadowing",
                "Irritated skin",
                "Same lighting",
            ]
        case .body:
            [
                "Area tracked today",
                "Coarser hair",
                "Patchy growth",
                "Less growth",
                "Post-removal",
                "Same angle",
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
