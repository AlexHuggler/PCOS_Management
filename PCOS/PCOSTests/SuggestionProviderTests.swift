import Testing
import Foundation
@testable import PCOS

@Suite("SuggestionProvider")
struct SuggestionProviderTests {
    @Test("Prefix matches rank ahead of contains matches")
    func prefixRanksAheadOfContains() {
        let provider = makeProvider(testName: #function)

        provider.recordMealNote("Post-workout", mealType: .snack)
        provider.recordMealNote("Workout fuel", mealType: .snack)

        let suggestions = provider.mealNoteSuggestions(query: "work", mealType: .snack, limit: 4)
        #expect(suggestions.prefix(2).elementsEqual(["Workout fuel", "Post-workout"]))
    }

    @Test("Learned suggestions are merged with curated defaults and de-duplicated")
    func learnedAndCuratedMergeWithoutDuplicates() {
        let provider = makeProvider(testName: #function)

        provider.recordMealDescription("Quinoa bowl", mealType: .lunch)
        provider.recordMealDescription("Turkey chili", mealType: .lunch)

        let suggestions = provider.mealDescriptionSuggestions(query: "", mealType: .lunch, limit: 4)
        #expect(suggestions == ["Turkey chili", "Quinoa bowl", "Grilled chicken salad", "Turkey lettuce wrap"])
    }

    @Test("Meal note suggestions are scoped by meal type")
    func mealNoteSuggestionsScopedByMealType() {
        let provider = makeProvider(testName: #function)

        let breakfast = provider.mealNoteSuggestions(query: "coffee", mealType: .breakfast, limit: 4)
        let dinner = provider.mealNoteSuggestions(query: "coffee", mealType: .dinner, limit: 4)

        #expect(breakfast == ["Coffee first"])
        #expect(dinner.isEmpty)
    }

    @Test("Legacy meal recents seed scoped suggestions as fallback")
    func legacyMealRecentsFallback() {
        let suiteName = "SuggestionProviderTests.\(#function).\(UUID().uuidString)"
        let defaults = UserDefaults(suiteName: suiteName)!
        defaults.removePersistentDomain(forName: suiteName)
        defaults.set(["Legacy oats"], forKey: "entryDefaults.recentMealDescriptions")
        defaults.set(["Legacy note"], forKey: "entryDefaults.recentMealNotes")
        let provider = SuggestionProvider(defaultsStore: UserEntryDefaultsStore(defaults: defaults))

        let descriptionSuggestions = provider.mealDescriptionSuggestions(
            query: "legacy",
            mealType: .breakfast,
            limit: 4
        )
        let noteSuggestions = provider.mealNoteSuggestions(
            query: "legacy",
            mealType: .breakfast,
            limit: 4
        )

        #expect(descriptionSuggestions == ["Legacy oats"])
        #expect(noteSuggestions == ["Legacy note"])
    }

    @Test("Recent blood sugar contexts keep deterministic recent-first order")
    func bloodSugarContextRecencyOrder() {
        let provider = makeProvider(testName: #function)

        provider.recordBloodSugarMealContext("Before breakfast")
        provider.recordBloodSugarMealContext("2h after dinner")
        provider.recordBloodSugarMealContext("Before breakfast")

        let suggestions = provider.bloodSugarMealContextSuggestions(query: "", limit: 5)
        #expect(suggestions.prefix(3).elementsEqual(["Before breakfast", "2h after dinner", "Fasting (morning)"]))
    }

    @Test("Period note suggestions return curated defaults for each flow")
    func periodCuratedSuggestionsByFlow() {
        L10n.withOverrides(appLanguage: .en, preferredLanguages: ["en_US"]) {
            let provider = makeProvider(testName: #function)

            let spotting = provider.periodNoteSuggestions(flowIntensity: .spotting, query: "", limit: 6)
            #expect(
                spotting == [
                    "Spotting duration",
                    "Brown spotting",
                    "Pink spotting",
                    "Mild cramps",
                    "Mood changes",
                    "After exercise",
                ]
            )
        }
    }

    @Test("Period note suggestions merge learned notes and de-duplicate curated defaults")
    func periodLearnedSuggestionsMergeAndDedup() {
        L10n.withOverrides(appLanguage: .en, preferredLanguages: ["en_US"]) {
            let provider = makeProvider(testName: #function)

            provider.recordPeriodNote("Fatigue", flowIntensity: .medium)
            provider.recordPeriodNote("Hydrated", flowIntensity: .medium)

            let suggestions = provider.periodNoteSuggestions(flowIntensity: .medium, query: "", limit: 6)
            #expect(
                suggestions == [
                    "Hydrated",
                    "Fatigue",
                    "Clotting",
                    "Moderate cramps",
                    "Back pain",
                    "Mood changes",
                ]
            )
        }
    }

    @Test("Period note suggestions are isolated by flow intensity")
    func periodSuggestionsIsolatedByFlow() {
        let provider = makeProvider(testName: #function)

        provider.recordPeriodNote("Passed tissue", flowIntensity: .heavy)

        let heavy = provider.periodNoteSuggestions(flowIntensity: .heavy, query: "passed", limit: 6)
        let spotting = provider.periodNoteSuggestions(flowIntensity: .spotting, query: "passed", limit: 6)

        #expect(heavy == ["Passed tissue"])
        #expect(spotting.isEmpty)
    }

    @Test("Photo note suggestions are isolated by photo type")
    func photoSuggestionsIsolatedByType() {
        let provider = makeProvider(testName: #function)

        provider.recordPhotoNote("Temple thinning", photoType: .hairline)

        let hairline = provider.photoNoteSuggestions(photoType: .hairline, query: "temple", limit: 6)
        let body = provider.photoNoteSuggestions(photoType: .body, query: "temple", limit: 6)

        #expect(hairline == ["Temple thinning"])
        #expect(body.isEmpty)
    }

    private func makeProvider(testName: String) -> SuggestionProvider {
        let suiteName = "SuggestionProviderTests.\(testName).\(UUID().uuidString)"
        let defaults = UserDefaults(suiteName: suiteName)!
        defaults.removePersistentDomain(forName: suiteName)
        let store = UserEntryDefaultsStore(defaults: defaults)
        return SuggestionProvider(defaultsStore: store)
    }
}
