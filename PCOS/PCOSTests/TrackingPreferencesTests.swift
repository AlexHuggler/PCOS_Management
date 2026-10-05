import Foundation
import Testing
@testable import PCOS

@Suite("Tracking personalization")
@MainActor
struct TrackingPreferencesTests {
    @Test func persistsWithoutChangingOtherPreferences() throws {
        let name = "TrackingPreferencesTests.\(UUID())"
        let defaults = try #require(UserDefaults(suiteName: name))
        defer { defaults.removePersistentDomain(forName: name) }
        let preferences = TrackingPreferences(defaults: defaults)
        #expect(preferences.informationDetail == .simple)
        preferences.favoriteActions = [.meal, .symptoms]
        preferences.visibleCards = [.observation, .health]
        preferences.informationDetail = .detailed
        let reopened = TrackingPreferences(defaults: defaults)
        #expect(reopened.favoriteActions == [.meal, .symptoms])
        #expect(reopened.visibleCards == [.observation, .health])
        #expect(reopened.informationDetail == .detailed)
    }

    @Test func backupRestoresPersonalization() throws {
        let first = TrackingPreferences(defaults: UserDefaults(suiteName: UUID().uuidString)!)
        first.favoriteActions = [.photo]
        first.informationDetail = .detailed
        let second = TrackingPreferences(defaults: UserDefaults(suiteName: UUID().uuidString)!)
        try second.restore(from: first.backupData())
        #expect(second.favoriteActions == [.photo])
        #expect(second.informationDetail == .detailed)
    }
}

@Suite("Body display units")
struct BodyDisplayUnitsTests {
    @Test func canonicalStorageConversions() {
        #expect(abs(BodyMeasurementStyle.metric.weight(fromPounds: 220.462262) - 100) < 0.01)
        #expect(BodyMeasurementStyle.metric.ounces(fromWater: 237) == 8)
        #expect(BodyMeasurementStyle.metric.water(fromOunces: 8) == 237)
        #expect(BodyMeasurementStyle.us.water(fromOunces: 8) == 8)
    }
}
