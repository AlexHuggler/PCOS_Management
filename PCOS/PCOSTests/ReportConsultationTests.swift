import Foundation
import SwiftData
import Testing
@testable import PCOS

@MainActor
@Suite("Consultation report privacy")
struct ReportConsultationTests {
    @Test("Date-only ranges include midnight notes on the selected first day")
    func wholeDateBoundaries() throws {
        let container = try TestHelpers.makeModelContainer()
        let start = Calendar.current.startOfDay(for: Date())
        let log = DailyLog(date: start, privateNote: "First day note")
        container.mainContext.insert(log)
        try container.mainContext.save()
        let vm = ReportViewModel(modelContext: container.mainContext)
        vm.startDate = start.addingTimeInterval(12 * 3600)
        vm.endDate = vm.startDate
        #expect(vm.availableDailyNotes.map(\.id) == [log.id])
    }

    @Test("A weight report excludes unrelated sleep sources and manual weight")
    func fieldSpecificProvenance() async throws {
        let container = try TestHelpers.makeModelContainer()
        let context = container.mainContext
        let log = DailyLog(date: Date(), weight: 140, sleepHours: 7)
        context.insert(log)
        context.insert(HealthKitImportedSampleRecord(sampleUUID: UUID().uuidString, healthKitIdentifier: "HKCategoryTypeIdentifierSleepAnalysis", sourceName: "Sleep source", startDate: Date(), derivedRecordKind: .dailyLog, derivedRecordID: log.id))
        try context.save()
        var names: [String] = []
        let vm = ReportViewModel(modelContext: context) { data, _, _, _ in names = data.sourceNames; return URL(fileURLWithPath: "/tmp/source-test.pdf") }
        vm.includeWeightTrend = true
        await vm.generateReport(appLanguage: .en)
        #expect(names.isEmpty)
        let owner = HealthKitFieldOwnership(recordID: log.id, field: "weight")
        owner.lastAppliedValue = 140
        context.insert(owner)
        context.insert(HealthKitImportedSampleRecord(sampleUUID: UUID().uuidString, healthKitIdentifier: "HKQuantityTypeIdentifierBodyMass", sourceName: "Weight source", startDate: Date(), derivedRecordKind: .dailyLog, derivedRecordID: log.id))
        try context.save()
        await vm.generateReport(appLanguage: .en)
        #expect(names == ["Weight source"])
    }

    @Test("Private notes are opt-in and changing selection refreshes report")
    func selectedNotesOnly() async throws {
        let container = try TestHelpers.makeModelContainer()
        let context = container.mainContext
        let note = DailyLog(date: Date(), privateNote: "Discuss fatigue after lunch")
        context.insert(note)
        try context.save()
        var outputs: [ReportData] = []
        let vm = ReportViewModel(modelContext: context) { data, _, _, _ in
            outputs.append(data)
            return URL(fileURLWithPath: "/tmp/consultation-test.pdf")
        }
        vm.endDate = Date().addingTimeInterval(1)
        await vm.generateReport(appLanguage: .en)
        #expect(outputs.last?.selectedNotes.isEmpty == true)
        vm.selectedNoteIDs = [note.id]
        vm.consultationConcerns = "Questions for my appointment"
        #expect(vm.hasPendingConfigurationChanges)
        await vm.generateReport(appLanguage: .en)
        #expect(outputs.last?.selectedNotes.map(\.text) == ["Discuss fatigue after lunch"])
        #expect(outputs.last?.consultationConcerns == "Questions for my appointment")
    }
}
