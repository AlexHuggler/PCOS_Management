import Foundation
import SwiftData
import Testing
@testable import PCOS

@Suite("Truthful daily check-in", .serialized)
@MainActor
struct DailyCheckInServiceTests {
    @Test("Editing or removing acne preserves each untouched Health fatigue contribution", arguments: [0, 5], [false, true])
    func editingOneSymptomPreservesOtherContributions(acneSeverity: Int, submitChanges: Bool) throws {
        let container = try TestHelpers.makeModelContainer()
        let context = container.mainContext
        let date = Date()
        let fatigueRows = [
            SymptomEntry(date: date, type: .fatigue, severity: 2, notes: "Source one"),
            SymptomEntry(date: date, type: .fatigue, severity: 4, notes: "Source two")
        ]
        for row in fatigueRows {
            context.insert(row)
            context.insert(HealthKitImportedSampleRecord(sampleUUID: row.id.uuidString,
                healthKitIdentifier: "HKCategoryTypeIdentifierFatigue", startDate: date,
                derivedRecordKind: .symptomEntry, derivedRecordID: row.id,
                lastAppliedFingerprint: "original-\(row.id)"))
        }
        context.insert(SymptomEntry(date: date, type: .acne, severity: 2))
        try context.save()
        let expectedIDs = Set(fatigueRows.map(\.id))
        let service = DailyCheckInService(modelContext: context)
        let original = try service.load(on: date)
        var edited = original
        var selections = edited.symptoms.value ?? [:]
        if acneSeverity == 0 { selections.removeValue(forKey: .acne) }
        else { selections[.acne] = acneSeverity }
        edited.symptoms = .set(selections)
        try service.save(submitChanges ? edited.changes(since: original) : edited)
        let rows = try context.fetch(FetchDescriptor<SymptomEntry>())
        let fatigue = rows.filter { $0.symptomType == .fatigue }
        #expect(Set(fatigue.map(\.id)) == expectedIDs)
        #expect(Set(fatigue.map(\.severity)) == Set([2, 4]))
        #expect(Set(fatigue.compactMap(\.notes)) == Set(["Source one", "Source two"]))
        #expect(rows.filter { $0.symptomType == .acne }.map(\.severity) == (acneSeverity == 0 ? [] : [acneSeverity]))
        let provenance = try context.fetch(FetchDescriptor<HealthKitImportedSampleRecord>())
        #expect(Set(provenance.compactMap(\.derivedRecordID)) == expectedIDs)
        #expect(provenance.allSatisfy { record in
            guard let id = record.derivedRecordID else { return false }
            return record.lastAppliedFingerprint == "original-\(id)"
        })
    }

    @Test("Explicit no symptoms clears even contributions arriving after an empty day was loaded")
    func explicitNoSymptomsClearsLateContributions() throws {
        let container = try TestHelpers.makeModelContainer()
        let context = container.mainContext
        let service = DailyCheckInService(modelContext: context)
        let date = Date()
        var initial = DailyCheckInDraft(date: date)
        initial.recordNoSymptoms()
        try service.save(initial)
        let original = try service.load(on: date)
        context.insert(SymptomEntry(date: date, type: .fatigue, severity: 4))
        try context.save()
        var edited = original
        edited.recordNoSymptoms()
        try service.save(edited.changes(since: original))
        #expect(try context.fetchCount(FetchDescriptor<SymptomEntry>()) == 0)
        #expect(try service.load(on: date).symptomsReviewed)
    }

    @Test("A mood-only edit preserves duplicate imported symptoms, notes, and identifiers")
    func moodOnlyEditPreservesSymptoms() throws {
        let container = try TestHelpers.makeModelContainer()
        let context = container.mainContext
        let first = SymptomEntry(date: Date(), type: .fatigue, severity: 2, notes: "Watch context")
        let second = SymptomEntry(date: first.date, type: .fatigue, severity: 4, notes: "Personal context")
        context.insert(first); context.insert(second)
        try context.save()
        let service = DailyCheckInService(modelContext: context)
        let original = try service.load(on: first.date)
        var edited = original
        edited.mood = .set(.good)
        try service.save(edited.changes(since: original))
        let saved = try context.fetch(FetchDescriptor<SymptomEntry>())
        #expect(Set(saved.map(\.id)) == Set([first.id, second.id]))
        #expect(Set(saved.compactMap(\.notes)) == Set(["Watch context", "Personal context"]))
        #expect(Set(saved.map(\.severity)) == Set([2, 4]))
    }

    @Test("A cleared symptom review returns to unknown and clears selected symptoms")
    func clearReviewedState() throws {
        let container = try TestHelpers.makeModelContainer()
        let service = DailyCheckInService(modelContext: container.mainContext)
        var draft = DailyCheckInDraft(date: Date())
        draft.symptoms = .set([.fatigue: 3])
        draft.symptomsReviewed = true
        try service.save(draft)
        draft = try service.load(on: Date())
        draft.symptoms = .clear
        draft.symptomsReviewed = false
        try service.save(draft)
        let loaded = try service.load(on: Date())
        #expect(!loaded.symptomsReviewed)
        #expect(loaded.symptoms == .untouched)
    }

    @Test("Legacy daily-log backups decode absent check-in fields")
    func legacyDailyLogDecoding() throws {
        let json = "{\"id\":\"00000000-0000-0000-0000-000000000001\",\"date\":\"2026-09-01T00:00:00Z\",\"energyLevel\":3}"
        let record = try SettingsDataBackupCoding.makeDecoder().decode(DailyLogRecord.self, from: Data(json.utf8))
        #expect(record.energyLevel == 3)
        #expect(record.moodRawValue == nil)
        #expect(record.symptomsReviewed == nil)
        #expect(record.privateNote == nil)
    }

    @Test("Missing fields stay missing and reviewing no symptoms is explicit")
    func missingAndReviewedAreDifferent() throws {
        let container = try TestHelpers.makeModelContainer()
        let service = DailyCheckInService(modelContext: container.mainContext)
        var draft = try service.load(on: Date())
        #expect(draft.mood.value == nil)
        #expect(draft.energy.value == nil)
        #expect(!draft.symptomsReviewed)
        draft.symptomsReviewed = true
        draft.symptoms = .set([:])
        try service.save(draft)
        let reloaded = try service.load(on: Date())
        #expect(reloaded.symptomsReviewed)
        #expect(reloaded.symptoms.value?.isEmpty == true)
        #expect(reloaded.energy.value == nil)
    }

    @Test("Low to Good mood never creates clinical symptoms")
    func moodDoesNotInferSymptoms() throws {
        let container = try TestHelpers.makeModelContainer()
        let service = DailyCheckInService(modelContext: container.mainContext)
        var draft = DailyCheckInDraft(date: Date())
        draft.mood = .set(.low)
        draft.energy = .set(2)
        draft.note = .set("Rest helped")
        try service.save(draft)
        var loaded = try service.load(on: Date())
        #expect(loaded.energy.value == 2)
        #expect(loaded.note.value == "Rest helped")
        loaded.mood = .set(.good)
        try service.save(loaded)
        #expect(try service.load(on: Date()).mood.value == .good)
        #expect(try container.mainContext.fetchCount(FetchDescriptor<SymptomEntry>()) == 0)
    }

    @Test("Untouched preserves existing values while clear removes them")
    func clearAndUntouched() throws {
        let container = try TestHelpers.makeModelContainer()
        let service = DailyCheckInService(modelContext: container.mainContext)
        var first = DailyCheckInDraft(date: Date())
        first.energy = .set(5)
        first.pain = .set(0)
        first.note = .set("Existing note")
        try service.save(first)
        var patch = DailyCheckInDraft(date: Date())
        patch.note = .clear
        try service.save(patch)
        let loaded = try service.load(on: Date())
        #expect(loaded.energy.value == 5)
        #expect(loaded.pain.value == 0)
        #expect(loaded.note.value == nil)
    }

    @Test("Invalid check-in leaves symptoms and daily fields unchanged")
    func invalidSaveDoesNotPartiallyWrite() throws {
        let container = try TestHelpers.makeModelContainer()
        let service = DailyCheckInService(modelContext: container.mainContext)
        var draft = DailyCheckInDraft(date: Date())
        draft.energy = .set(6)
        draft.symptoms = .set([.fatigue: 2])
        #expect(throws: DailyCheckInService.ValidationError.self) { try service.save(draft) }
        #expect(try container.mainContext.fetchCount(FetchDescriptor<DailyLog>()) == 0)
        #expect(try container.mainContext.fetchCount(FetchDescriptor<SymptomEntry>()) == 0)
    }
}
