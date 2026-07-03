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
                L10n.string("Greek yogurt + berries", defaultValue: "Greek yogurt + berries"),
                L10n.string("Eggs + avocado toast", defaultValue: "Eggs + avocado toast"),
                L10n.string("Protein smoothie", defaultValue: "Protein smoothie"),
                L10n.string("Oatmeal + nuts", defaultValue: "Oatmeal + nuts"),
                L10n.string("Chia pudding + fruit", defaultValue: "Chia pudding + fruit"),
                L10n.string("Veggie omelet", defaultValue: "Veggie omelet"),
                L10n.string("Cottage cheese + pineapple", defaultValue: "Cottage cheese + pineapple"),
                L10n.string("Overnight oats + flax", defaultValue: "Overnight oats + flax"),
                L10n.string("Whole grain toast + almond butter", defaultValue: "Whole grain toast + almond butter"),
                L10n.string("Scrambled eggs + spinach", defaultValue: "Scrambled eggs + spinach"),
                L10n.string("Breakfast burrito bowl", defaultValue: "Breakfast burrito bowl"),
                L10n.string("Smoked salmon + cucumber toast", defaultValue: "Smoked salmon + cucumber toast"),
                L10n.string("Tofu scramble + peppers", defaultValue: "Tofu scramble + peppers"),
                L10n.string("Quinoa porridge + cinnamon", defaultValue: "Quinoa porridge + cinnamon"),
                L10n.string("Apple cinnamon oats", defaultValue: "Apple cinnamon oats"),
                L10n.string("Skyr + walnuts", defaultValue: "Skyr + walnuts"),
                L10n.string("Hard-boiled eggs + fruit", defaultValue: "Hard-boiled eggs + fruit"),
                L10n.string("Peanut butter banana smoothie", defaultValue: "Peanut butter banana smoothie"),
                L10n.string("Egg muffins + greens", defaultValue: "Egg muffins + greens"),
                L10n.string("Buckwheat pancakes + berries", defaultValue: "Buckwheat pancakes + berries"),
                L10n.string("Savory oats + egg", defaultValue: "Savory oats + egg"),
                L10n.string("Breakfast quinoa + berries", defaultValue: "Breakfast quinoa + berries"),
                L10n.string("Turkey sausage + eggs", defaultValue: "Turkey sausage + eggs"),
                L10n.string("Avocado + cottage cheese bowl", defaultValue: "Avocado + cottage cheese bowl"),
                L10n.string("Muesli + yogurt", defaultValue: "Muesli + yogurt"),
                L10n.string("Breakfast sandwich", defaultValue: "Breakfast sandwich"),
                L10n.string("Sweet potato hash + eggs", defaultValue: "Sweet potato hash + eggs"),
                L10n.string("Yogurt parfait", defaultValue: "Yogurt parfait"),
                L10n.string("Protein pancakes", defaultValue: "Protein pancakes"),
                L10n.string("Breakfast tacos", defaultValue: "Breakfast tacos"),
                L10n.string("Egg white bites", defaultValue: "Egg white bites"),
                L10n.string("Tofu breakfast burrito", defaultValue: "Tofu breakfast burrito"),
                L10n.string("Smoothie bowl", defaultValue: "Smoothie bowl"),
            ]
        case .lunch:
            [
                L10n.string("Grilled chicken salad", defaultValue: "Grilled chicken salad"),
                L10n.string("Quinoa bowl", defaultValue: "Quinoa bowl"),
                L10n.string("Turkey lettuce wrap", defaultValue: "Turkey lettuce wrap"),
                L10n.string("Lentil soup", defaultValue: "Lentil soup"),
                L10n.string("Tuna salad + crackers", defaultValue: "Tuna salad + crackers"),
                L10n.string("Chicken and veggie wrap", defaultValue: "Chicken and veggie wrap"),
                L10n.string("Chickpea salad bowl", defaultValue: "Chickpea salad bowl"),
                L10n.string("Brown rice + tofu bowl", defaultValue: "Brown rice + tofu bowl"),
                L10n.string("Turkey chili", defaultValue: "Turkey chili"),
                L10n.string("Shrimp salad", defaultValue: "Shrimp salad"),
                L10n.string("Salmon grain bowl", defaultValue: "Salmon grain bowl"),
                L10n.string("Hummus + veggie pita", defaultValue: "Hummus + veggie pita"),
                L10n.string("Chicken quinoa soup", defaultValue: "Chicken quinoa soup"),
                L10n.string("Egg salad lettuce cups", defaultValue: "Egg salad lettuce cups"),
                L10n.string("Steak + arugula salad", defaultValue: "Steak + arugula salad"),
                L10n.string("Black bean bowl", defaultValue: "Black bean bowl"),
                L10n.string("Greek salad + chicken", defaultValue: "Greek salad + chicken"),
                L10n.string("Sardines + toast", defaultValue: "Sardines + toast"),
                L10n.string("Cottage cheese + tomato plate", defaultValue: "Cottage cheese + tomato plate"),
                L10n.string("Tofu miso soup + rice", defaultValue: "Tofu miso soup + rice"),
                L10n.string("Edamame quinoa salad", defaultValue: "Edamame quinoa salad"),
                L10n.string("Chicken caesar wrap", defaultValue: "Chicken caesar wrap"),
                L10n.string("Farro + roasted veggie bowl", defaultValue: "Farro + roasted veggie bowl"),
                L10n.string("Turkey burger bowl", defaultValue: "Turkey burger bowl"),
                L10n.string("Caprese chicken salad", defaultValue: "Caprese chicken salad"),
                L10n.string("Chicken burrito bowl", defaultValue: "Chicken burrito bowl"),
                L10n.string("Turkey sandwich + fruit", defaultValue: "Turkey sandwich + fruit"),
                L10n.string("Mediterranean bowl", defaultValue: "Mediterranean bowl"),
                L10n.string("Soup + half sandwich", defaultValue: "Soup + half sandwich"),
                L10n.string("Poke bowl", defaultValue: "Poke bowl"),
                L10n.string("Sushi bowl", defaultValue: "Sushi bowl"),
                L10n.string("Chicken pasta salad", defaultValue: "Chicken pasta salad"),
                L10n.string("Taco salad", defaultValue: "Taco salad"),
            ]
        case .dinner:
            [
                L10n.string("Salmon + roasted vegetables", defaultValue: "Salmon + roasted vegetables"),
                L10n.string("Chicken stir-fry", defaultValue: "Chicken stir-fry"),
                L10n.string("Tofu + vegetables", defaultValue: "Tofu + vegetables"),
                L10n.string("Lean protein + greens", defaultValue: "Lean protein + greens"),
                L10n.string("Turkey meatballs + zucchini noodles", defaultValue: "Turkey meatballs + zucchini noodles"),
                L10n.string("Baked cod + asparagus", defaultValue: "Baked cod + asparagus"),
                L10n.string("Steak + sweet potato + broccoli", defaultValue: "Steak + sweet potato + broccoli"),
                L10n.string("Shrimp + cauliflower rice", defaultValue: "Shrimp + cauliflower rice"),
                L10n.string("Lentil curry + spinach", defaultValue: "Lentil curry + spinach"),
                L10n.string("Grilled chicken + quinoa", defaultValue: "Grilled chicken + quinoa"),
                L10n.string("Beef and veggie skillet", defaultValue: "Beef and veggie skillet"),
                L10n.string("Tofu stir-fry + brown rice", defaultValue: "Tofu stir-fry + brown rice"),
                L10n.string("Chicken fajita bowl", defaultValue: "Chicken fajita bowl"),
                L10n.string("Turkey chili + salad", defaultValue: "Turkey chili + salad"),
                L10n.string("Miso salmon + bok choy", defaultValue: "Miso salmon + bok choy"),
                L10n.string("Pesto chicken + green beans", defaultValue: "Pesto chicken + green beans"),
                L10n.string("Stuffed bell peppers", defaultValue: "Stuffed bell peppers"),
                L10n.string("Soba noodles + tofu", defaultValue: "Soba noodles + tofu"),
                L10n.string("Baked chicken + Brussels sprouts", defaultValue: "Baked chicken + Brussels sprouts"),
                L10n.string("Ground turkey lettuce wraps", defaultValue: "Ground turkey lettuce wraps"),
                L10n.string("Cod tacos + slaw", defaultValue: "Cod tacos + slaw"),
                L10n.string("Chickpea pasta + vegetables", defaultValue: "Chickpea pasta + vegetables"),
                L10n.string("Shakshuka + side salad", defaultValue: "Shakshuka + side salad"),
                L10n.string("Roasted tofu + carrots", defaultValue: "Roasted tofu + carrots"),
                L10n.string("Grilled shrimp + quinoa salad", defaultValue: "Grilled shrimp + quinoa salad"),
                L10n.string("Sheet-pan chicken + veggies", defaultValue: "Sheet-pan chicken + veggies"),
                L10n.string("Chicken curry + rice", defaultValue: "Chicken curry + rice"),
                L10n.string("Salmon rice bowl", defaultValue: "Salmon rice bowl"),
                L10n.string("Turkey burger + salad", defaultValue: "Turkey burger + salad"),
                L10n.string("Beef tacos + slaw", defaultValue: "Beef tacos + slaw"),
                L10n.string("Turkey stuffed sweet potato", defaultValue: "Turkey stuffed sweet potato"),
                L10n.string("Veggie frittata + salad", defaultValue: "Veggie frittata + salad"),
                L10n.string("Chicken soup + salad", defaultValue: "Chicken soup + salad"),
            ]
        case .snack:
            [
                L10n.string("Apple + peanut butter", defaultValue: "Apple + peanut butter"),
                L10n.string("Cottage cheese + fruit", defaultValue: "Cottage cheese + fruit"),
                L10n.string("Nuts + seeds", defaultValue: "Nuts + seeds"),
                L10n.string("Hummus + veggies", defaultValue: "Hummus + veggies"),
                L10n.string("Greek yogurt cup", defaultValue: "Greek yogurt cup"),
                L10n.string("Protein shake", defaultValue: "Protein shake"),
                L10n.string("Cheese + whole grain crackers", defaultValue: "Cheese + whole grain crackers"),
                L10n.string("Hard-boiled eggs", defaultValue: "Hard-boiled eggs"),
                L10n.string("Trail mix", defaultValue: "Trail mix"),
                L10n.string("Edamame", defaultValue: "Edamame"),
                L10n.string("Banana + almond butter", defaultValue: "Banana + almond butter"),
                L10n.string("Turkey roll-ups", defaultValue: "Turkey roll-ups"),
                L10n.string("Chia pudding cup", defaultValue: "Chia pudding cup"),
                L10n.string("Carrots + guacamole", defaultValue: "Carrots + guacamole"),
                L10n.string("Roasted chickpeas", defaultValue: "Roasted chickpeas"),
                L10n.string("Berry smoothie", defaultValue: "Berry smoothie"),
                L10n.string("Pumpkin seeds + fruit", defaultValue: "Pumpkin seeds + fruit"),
                L10n.string("Rice cake + cottage cheese", defaultValue: "Rice cake + cottage cheese"),
                L10n.string("Celery + peanut butter", defaultValue: "Celery + peanut butter"),
                L10n.string("Protein bar", defaultValue: "Protein bar"),
                L10n.string("Apple slices + cheese", defaultValue: "Apple slices + cheese"),
                L10n.string("Tuna cucumber boats", defaultValue: "Tuna cucumber boats"),
                L10n.string("Boiled egg + almonds", defaultValue: "Boiled egg + almonds"),
                L10n.string("Yogurt + granola", defaultValue: "Yogurt + granola"),
                L10n.string("Pear + walnuts", defaultValue: "Pear + walnuts"),
                L10n.string("String cheese + fruit", defaultValue: "String cheese + fruit"),
                L10n.string("Jerky + fruit", defaultValue: "Jerky + fruit"),
                L10n.string("Cottage cheese cup", defaultValue: "Cottage cheese cup"),
                L10n.string("Dates + nuts", defaultValue: "Dates + nuts"),
                L10n.string("Mini smoothie", defaultValue: "Mini smoothie"),
                L10n.string("Veggie chips + hummus", defaultValue: "Veggie chips + hummus"),
                L10n.string("Rice cake + nut butter", defaultValue: "Rice cake + nut butter"),
                L10n.string("Protein bites", defaultValue: "Protein bites"),
            ]
        }
    }

    private func curatedMealNotes(for mealType: MealType) -> [String] {
        let common = [
            L10n.string("Balanced meal", defaultValue: "Balanced meal"),
            L10n.string("Ate out", defaultValue: "Ate out"),
            L10n.string("Meal prep", defaultValue: "Meal prep"),
            L10n.string("Large portion", defaultValue: "Large portion"),
            L10n.string("Craving-driven", defaultValue: "Craving-driven"),
        ]

        let specific: [String] = switch mealType {
        case .breakfast:
            [
                L10n.string("Skipped breakfast", defaultValue: "Skipped breakfast"),
                L10n.string("Coffee first", defaultValue: "Coffee first"),
                L10n.string("Sweet breakfast", defaultValue: "Sweet breakfast"),
                L10n.string("High protein", defaultValue: "High protein"),
                L10n.string("On the go", defaultValue: "On the go"),
            ]
        case .lunch:
            [
                L10n.string("Desk lunch", defaultValue: "Desk lunch"),
                L10n.string("Packed lunch", defaultValue: "Packed lunch"),
                L10n.string("Light lunch", defaultValue: "Light lunch"),
                L10n.string("High carb", defaultValue: "High carb"),
                L10n.string("Restaurant lunch", defaultValue: "Restaurant lunch"),
            ]
        case .dinner:
            [
                L10n.string("Late dinner", defaultValue: "Late dinner"),
                L10n.string("Heavy dinner", defaultValue: "Heavy dinner"),
                L10n.string("Family meal", defaultValue: "Family meal"),
                L10n.string("Takeout", defaultValue: "Takeout"),
                L10n.string("High carb", defaultValue: "High carb"),
            ]
        case .snack:
            [
                L10n.string("Pre-workout", defaultValue: "Pre-workout"),
                L10n.string("Post-workout", defaultValue: "Post-workout"),
                L10n.string("Sweet snack", defaultValue: "Sweet snack"),
                L10n.string("Salty snack", defaultValue: "Salty snack"),
                L10n.string("Late-night snack", defaultValue: "Late-night snack"),
            ]
        }

        return common + specific
    }

    private var curatedBloodSugarContexts: [String] {
        [
            L10n.string("Fasting (morning)", defaultValue: "Fasting (morning)"),
            L10n.string("Before breakfast", defaultValue: "Before breakfast"),
            L10n.string("1h after breakfast", defaultValue: "1h after breakfast"),
            L10n.string("2h after breakfast", defaultValue: "2h after breakfast"),
            L10n.string("Before lunch", defaultValue: "Before lunch"),
            L10n.string("2h after lunch", defaultValue: "2h after lunch"),
            L10n.string("Before dinner", defaultValue: "Before dinner"),
            L10n.string("2h after dinner", defaultValue: "2h after dinner"),
            L10n.string("Bedtime", defaultValue: "Bedtime"),
            L10n.string("Post-workout", defaultValue: "Post-workout"),
        ]
    }

    private var curatedBloodSugarNotes: [String] {
        [
            L10n.string("Dizzy", defaultValue: "Dizzy"),
            L10n.string("Shaky", defaultValue: "Shaky"),
            L10n.string("Sweaty", defaultValue: "Sweaty"),
            L10n.string("Headache", defaultValue: "Headache"),
            L10n.string("Low energy", defaultValue: "Low energy"),
            L10n.string("Missed meal", defaultValue: "Missed meal"),
            L10n.string("High stress", defaultValue: "High stress"),
            L10n.string("Poor sleep", defaultValue: "Poor sleep"),
            L10n.string("After exercise", defaultValue: "After exercise"),
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
