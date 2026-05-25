import Testing
import Foundation
import SwiftData
@testable import PCOS

@Suite("Ovulation Observation Store", .serialized)
@MainActor
struct OvulationObservationStoreTests {
    @Test("Manual observations upsert by day without creating duplicates")
    func observationsUpsertByDay() throws {
        let container = try TestHelpers.makeModelContainer()
        let context = container.mainContext
        let store = OvulationObservationStore(modelContext: context)
        let date = Date(timeIntervalSince1970: 1_715_000_000)

        try store.upsertObservation(
            date: date,
            basalBodyTemperatureCelsius: 36.45,
            cervicalMucus: .watery,
            lhTestResult: .negative,
            notes: "Morning reading"
        )

        try store.upsertObservation(
            date: date,
            basalBodyTemperatureCelsius: 36.62,
            cervicalMucus: .eggWhite,
            lhTestResult: .peak,
            notes: "Updated"
        )

        let observations = try context.fetch(FetchDescriptor<OvulationObservation>())
        #expect(observations.count == 1)
        #expect(observations.first?.basalBodyTemperatureCelsius == 36.62)
        #expect(observations.first?.cervicalMucus == .eggWhite)
        #expect(observations.first?.lhTestResult == .peak)
        #expect(observations.first?.notes == "Updated")
    }

    @Test("Clearing all signals removes an existing observation")
    func clearingSignalsDeletesObservation() throws {
        let container = try TestHelpers.makeModelContainer()
        let context = container.mainContext
        let store = OvulationObservationStore(modelContext: context)
        let date = Date(timeIntervalSince1970: 1_715_086_400)

        try store.upsertObservation(
            date: date,
            basalBodyTemperatureCelsius: 36.51,
            cervicalMucus: .creamy,
            lhTestResult: .high,
            notes: "Initial"
        )

        try store.upsertObservation(
            date: date,
            basalBodyTemperatureCelsius: nil,
            cervicalMucus: .notObserved,
            lhTestResult: .notTested,
            notes: ""
        )

        let observations = try context.fetch(FetchDescriptor<OvulationObservation>())
        #expect(observations.isEmpty)
    }
}
