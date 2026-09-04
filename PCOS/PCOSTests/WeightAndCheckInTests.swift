import Testing
import Foundation
import SwiftData
@testable import PCOS

@Suite("Weight display and daily check-in", .serialized)
@MainActor
struct WeightAndCheckInTests {
    private let us = Locale(identifier: "en_US")
    private let germany = Locale(identifier: "de_DE")

    @Test("Weight is stored in kilograms and shown in the locale's unit")
    func weightFollowsLocale() {
        #expect(WeightDisplay.usesPounds(locale: us))
        #expect(!WeightDisplay.usesPounds(locale: germany))
        #expect(WeightDisplay.unitSymbol(locale: us) == "lb")
        #expect(WeightDisplay.unitSymbol(locale: germany) == "kg")

        let usText = WeightDisplay.formatted(kilograms: 70, locale: us)
        #expect(usText.contains("lb") && usText.contains("154.3"), "was \(usText)")
        let deText = WeightDisplay.formatted(kilograms: 70, locale: germany)
        #expect(deText.contains("kg") && deText.contains("70,0"), "was \(deText)")

        #expect(abs(WeightDisplay.kilograms(fromDisplayValue: 154.3, locale: us) - 70) < 0.05)
        #expect(WeightDisplay.kilograms(fromDisplayValue: 70, locale: germany) == 70)
        #expect(abs(WeightDisplay.displayValue(kilograms: 70, locale: us) - 154.3) < 0.05)
    }

    @Test("Daily check-in persists energy and weight and validates their ranges")
    func checkInPersistsEnergyAndWeight() throws {
        let container = try TestHelpers.makeModelContainer()
        let service = DailyLogService(modelContext: container.mainContext)
        let today = Date()

        let log = try service.saveDailyCheckIn(date: today, painLevel0To10: 2, privateNote: nil, energyLevel: 4, weightKg: 70.5)
        #expect(log.energyLevel == 4)
        #expect(log.weight == 70.5)

        // Omitting a field must not erase the previously saved value.
        let unchanged = try service.saveDailyCheckIn(date: today, painLevel0To10: 3, privateNote: nil)
        #expect(unchanged.energyLevel == 4)
        #expect(unchanged.weight == 70.5)

        #expect(throws: DailyLogService.ValidationError.invalidEnergyLevel) {
            try service.saveDailyCheckIn(date: today, painLevel0To10: nil, privateNote: nil, energyLevel: 6)
        }
        #expect(throws: DailyLogService.ValidationError.invalidWeight) {
            try service.saveDailyCheckIn(date: today, painLevel0To10: nil, privateNote: nil, weightKg: 500)
        }
    }

    @Test("Demo data seeds weight on the kilogram scale")
    func demoWeightsAreKilograms() {
        let backup = DemoDataBuilder().makeBackup(for: .symptomManagement, referenceDate: Date())
        let weights = backup.records.dailyLogs.compactMap(\.weight)
        #expect(!weights.isEmpty)
        #expect(weights.allSatisfy { (35...150).contains($0) }, "weights should be kilograms, got \(weights.prefix(3))")
    }

    @Test("Today, the PDF report and the symptom logger use the shared weight helper")
    func surfacesUseWeightDisplay() throws {
        let projectRoot = try TestHelpers.projectRoot(from: #filePath)
        func source(_ path: String) throws -> String {
            try String(contentsOf: projectRoot.appendingPathComponent(path), encoding: .utf8)
        }
        let today = try source("PCOS/PCOS/Features/Cycle/Views/TodayView.swift")
        #expect(today.contains("WeightDisplay.formatted("))
        #expect(!today.contains("%.1f lb"))
        let pdf = try source("PCOS/PCOS/Features/Reports/Models/PDFReportGenerator.swift")
        #expect(pdf.contains("WeightDisplay.formatted("))
        #expect(!pdf.contains("%@ kg"))
        #expect(!pdf.contains(") kg\""))
        let logger = try source("PCOS/PCOS/Features/Symptoms/Views/SymptomLogView.swift")
        #expect(logger.contains("energyLevel:"))
        #expect(logger.contains("weightKg:"))
        #expect(logger.contains("symptom_log.lunar.weight"))
    }
}
