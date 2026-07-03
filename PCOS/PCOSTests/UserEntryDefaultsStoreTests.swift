import Testing
import Foundation
@testable import PCOS

@Suite("UserEntryDefaultsStore")
struct UserEntryDefaultsStoreTests {
    @Test("Persists last-used values for core entry flows")
    func persistsLastUsedValues() {
        let suiteName = "UserEntryDefaultsStoreTests.\(UUID().uuidString)"
        let defaults = UserDefaults(suiteName: suiteName)!
        defer { defaults.removePersistentDomain(forName: suiteName) }
        let store = UserEntryDefaultsStore(defaults: defaults)

        store.lastBloodSugarReadingType = .fasting
        store.lastBloodSugarMealContext = "After dinner"
        store.lastMealType = .dinner
        store.lastMealGlycemicImpact = .high
        store.lastSupplementName = "Myo-Inositol"
        store.lastSupplementBrand = "Theralogix"
        store.lastPhotoType = .hairline

        #expect(store.lastBloodSugarReadingType == .fasting)
        #expect(store.lastBloodSugarMealContext == "After dinner")
        #expect(store.lastMealType == .dinner)
        #expect(store.lastMealGlycemicImpact == .high)
        #expect(store.lastSupplementName == "Myo-Inositol")
        #expect(store.lastSupplementBrand == "Theralogix")
        #expect(store.lastPhotoType == .hairline)
    }

    @Test("Recent values are deduplicated and recency ranked")
    func recentValuesRecencyAndDeduping() {
        let suiteName = "UserEntryDefaultsStoreTests.\(UUID().uuidString)"
        let defaults = UserDefaults(suiteName: suiteName)!
        defer { defaults.removePersistentDomain(forName: suiteName) }
        let store = UserEntryDefaultsStore(defaults: defaults)

        store.recordRecentSupplementName("Magnesium")
        store.recordRecentSupplementName("Omega 3")
        store.recordRecentSupplementName("magnesium")

        let recents = store.recentSupplementNames(limit: 5)
        #expect(recents.count == 2)
        #expect(recents.first == "magnesium")
        #expect(recents.last == "Omega 3")
    }

    @Test("Period note recents are deduplicated and isolated by flow intensity")
    func periodNotesRecencyAndFlowIsolation() {
        let suiteName = "UserEntryDefaultsStoreTests.\(UUID().uuidString)"
        let defaults = UserDefaults(suiteName: suiteName)!
        defer { defaults.removePersistentDomain(forName: suiteName) }
        let store = UserEntryDefaultsStore(defaults: defaults)

        store.recordRecentPeriodNote("Mood changes", flowIntensity: .spotting)
        store.recordRecentPeriodNote("Clotting", flowIntensity: .spotting)
        store.recordRecentPeriodNote("mood changes", flowIntensity: .spotting)
        store.recordRecentPeriodNote("Heavy clotting", flowIntensity: .heavy)

        let spotting = store.recentPeriodNotes(flowIntensity: .spotting, limit: 5)
        let heavy = store.recentPeriodNotes(flowIntensity: .heavy, limit: 5)

        #expect(spotting == ["mood changes", "Clotting"])
        #expect(heavy == ["Heavy clotting"])
    }

    @Test("Flow intensity round-trips through the store")
    func flowIntensityRoundTrip() {
        let suiteName = "UserEntryDefaultsStoreTests.\(UUID().uuidString)"
        let defaults = UserDefaults(suiteName: suiteName)!
        defer { defaults.removePersistentDomain(forName: suiteName) }
        let store = UserEntryDefaultsStore(defaults: defaults)

        #expect(store.lastFlowIntensity == nil)

        store.lastFlowIntensity = .heavy
        #expect(store.lastFlowIntensity == .heavy)

        store.lastFlowIntensity = nil
        #expect(store.lastFlowIntensity == nil)
    }

    @Test("Flow intensity keeps the legacy defaults key for existing users")
    func flowIntensityLegacyKeyContinuity() {
        let suiteName = "UserEntryDefaultsStoreTests.\(UUID().uuidString)"
        let defaults = UserDefaults(suiteName: suiteName)!
        defer { defaults.removePersistentDomain(forName: suiteName) }
        let store = UserEntryDefaultsStore(defaults: defaults)

        store.lastFlowIntensity = .light
        #expect(defaults.string(forKey: "cycle.lastFlowIntensity") == FlowIntensity.light.rawValue)

        // Values written under the legacy key by older app versions must round-trip.
        defaults.set(FlowIntensity.spotting.rawValue, forKey: "cycle.lastFlowIntensity")
        #expect(store.lastFlowIntensity == .spotting)

        store.lastFlowIntensity = nil
        #expect(defaults.object(forKey: "cycle.lastFlowIntensity") == nil)
    }
}
