import Testing
import Foundation
import SwiftData
@testable import PCOS

@Suite("Streak Service", .serialized)
@MainActor
struct StreakServiceTests {
    @Test("Returns zero with no entries")
    func noEntriesReturnsZero() throws {
        let container = try TestHelpers.makeModelContainer()
        let context = container.mainContext
        let service = StreakService(modelContext: context)

        #expect(service.currentStreak() == 0)
    }

    @Test("Returns 1 for a single entry today")
    func singleEntryToday() throws {
        let container = try TestHelpers.makeModelContainer()
        let context = container.mainContext

        let entry = SymptomEntry(date: Date(), type: .fatigue, severity: 3)
        context.insert(entry)
        try context.save()

        let service = StreakService(modelContext: context)
        #expect(service.currentStreak() == 1)
    }

    @Test("Counts consecutive days")
    func consecutiveDays() throws {
        let container = try TestHelpers.makeModelContainer()
        let context = container.mainContext
        let calendar = Calendar.current

        // Create entries for today, yesterday, and day before
        for offset in 0...2 {
            let date = calendar.date(byAdding: .day, value: -offset, to: Date())!
            let entry = CycleEntry(date: date, flowIntensity: .medium, isPeriodDay: true)
            context.insert(entry)
        }
        try context.save()

        let service = StreakService(modelContext: context)
        #expect(service.currentStreak() == 3)
    }

    @Test("Gap breaks the streak")
    func gapBreaksStreak() throws {
        let container = try TestHelpers.makeModelContainer()
        let context = container.mainContext
        let calendar = Calendar.current

        // Today and yesterday have entries, but 2 days ago does not,
        // and 3 days ago does — streak should be 2
        for offset in [0, 1, 3] {
            let date = calendar.date(byAdding: .day, value: -offset, to: Date())!
            let entry = SymptomEntry(date: date, type: .bloating, severity: 2)
            context.insert(entry)
        }
        try context.save()

        let service = StreakService(modelContext: context)
        #expect(service.currentStreak() == 2)
    }

    @Test("Mixed entry types count")
    func mixedEntryTypes() throws {
        let container = try TestHelpers.makeModelContainer()
        let context = container.mainContext
        let calendar = Calendar.current

        // Today: symptom entry. Yesterday: cycle entry.
        let symptom = SymptomEntry(date: Date(), type: .cramps, severity: 4)
        context.insert(symptom)

        let cycleEntry = CycleEntry(
            date: calendar.date(byAdding: .day, value: -1, to: Date())!,
            flowIntensity: .light,
            isPeriodDay: true
        )
        context.insert(cycleEntry)
        try context.save()

        let service = StreakService(modelContext: context)
        #expect(service.currentStreak() == 2)
    }
}
