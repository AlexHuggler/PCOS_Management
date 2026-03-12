import Testing
import Foundation
import SwiftData
@testable import PCOS

@Suite("Settings Data Export Service", .serialized)
@MainActor
struct SettingsDataExportServiceTests {
    private enum MockWriteError: Error {
        case forcedFailure
    }

    @Test("generateCSVExport creates CSV with expected sections")
    func generateCSVExportCreatesCSV() throws {
        let container = try TestHelpers.makeModelContainer()
        let context = container.mainContext

        let cycle = Cycle(startDate: Date())
        context.insert(cycle)

        let cycleEntry = CycleEntry(
            date: Date(),
            flowIntensity: .medium,
            isPeriodDay: true,
            notes: "period,note"
        )
        cycleEntry.cycle = cycle
        context.insert(cycleEntry)

        let symptom = SymptomEntry(
            date: Date(),
            type: .cramps,
            severity: 3,
            notes: "symptom,note"
        )
        context.insert(symptom)

        let meal = MealEntry(
            timestamp: Date(),
            mealType: .lunch,
            mealDescription: "salad,berries",
            glycemicImpact: .low
        )
        context.insert(meal)
        try context.save()

        let service = SettingsDataExportService(modelContext: context)
        let exportURL = try service.generateCSVExport()
        let csv = try String(contentsOf: exportURL, encoding: .utf8)

        #expect(csv.hasPrefix("Type,Date,Detail,Value,Notes\n"))
        #expect(csv.contains("Cycle,"))
        #expect(csv.contains("Period,"))
        #expect(csv.contains("Symptom,"))
        #expect(csv.contains("Meal,"))
        #expect(csv.contains("period;note"))
        #expect(csv.contains("symptom;note"))
        #expect(csv.contains("salad;berries"))
    }

    @Test("generateCSVExport throws when writing file fails")
    func generateCSVExportThrowsOnWriteFailure() throws {
        let container = try TestHelpers.makeModelContainer()
        let context = container.mainContext

        let service = SettingsDataExportService(
            modelContext: context,
            fileWriter: { _, _ in
                throw MockWriteError.forcedFailure
            }
        )

        #expect(throws: MockWriteError.self) {
            _ = try service.generateCSVExport()
        }
    }
}
