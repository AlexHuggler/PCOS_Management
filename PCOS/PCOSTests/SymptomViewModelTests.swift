import Testing
import Foundation
import SwiftData
@testable import PCOS

@Suite("Symptom ViewModel", .serialized)
@MainActor
struct SymptomViewModelTests {
    @Test("Setting severity to 0 removes the symptom")
    func zeroSeverityRemoves() throws {
        let container = try TestHelpers.makeModelContainer()
        let vm = SymptomViewModel(modelContext: container.mainContext)

        vm.setSeverity(3, for: .fatigue)
        #expect(vm.severity(for: .fatigue) == 3)
        #expect(vm.selectionCount == 1)

        vm.setSeverity(0, for: .fatigue)
        #expect(vm.severity(for: .fatigue) == 0)
        #expect(vm.selectionCount == 0)
    }

    @Test("Severity clamped to 1-5 range")
    func severityClamped() throws {
        let container = try TestHelpers.makeModelContainer()
        let vm = SymptomViewModel(modelContext: container.mainContext)

        vm.setSeverity(10, for: .bloating)
        #expect(vm.severity(for: .bloating) == 5)

        vm.setSeverity(-1, for: .cramps)
        #expect(vm.severity(for: .cramps) == 1)
    }

    @Test("Reset clears all state")
    func resetClearsState() throws {
        let container = try TestHelpers.makeModelContainer()
        let vm = SymptomViewModel(modelContext: container.mainContext)

        vm.setSeverity(3, for: .fatigue)
        vm.setSeverity(2, for: .bloating)
        vm.selectedCategory = .physical

        vm.reset()

        #expect(vm.selectionCount == 0)
        #expect(vm.selectedCategory == nil)
        #expect(!vm.hasSelections)
    }

    @Test("hasSelections is true when symptoms are logged")
    func hasSelectionsReflectsState() throws {
        let container = try TestHelpers.makeModelContainer()
        let vm = SymptomViewModel(modelContext: container.mainContext)

        #expect(!vm.hasSelections)
        vm.setSeverity(2, for: .headache)
        #expect(vm.hasSelections)
    }

    @Test("Visible symptom types filter by category")
    func visibleSymptomTypesFilter() throws {
        let container = try TestHelpers.makeModelContainer()
        let vm = SymptomViewModel(modelContext: container.mainContext)

        // All types when no category
        let allCount = vm.visibleSymptomTypes.count
        #expect(allCount == SymptomType.allCases.count)

        // Filtered by physical
        vm.selectedCategory = .physical
        let physicalTypes = vm.visibleSymptomTypes
        #expect(physicalTypes.count == SymptomCategory.physical.symptomTypes.count)
        for type in physicalTypes {
            #expect(type.category == .physical)
        }
    }

    @Test("Fetch today's symptoms returns deterministic sorted order")
    func fetchTodaysSymptomsDeterministicOrder() throws {
        let container = try TestHelpers.makeModelContainer()
        let context = container.mainContext
        let startOfDay = Calendar.current.startOfDay(for: Date())

        let entries = [
            SymptomEntry(date: startOfDay.addingTimeInterval(9 * 3600), type: .hunger, severity: 2),
            SymptomEntry(date: startOfDay.addingTimeInterval(10 * 3600), type: .anxious, severity: 3),
            SymptomEntry(date: startOfDay.addingTimeInterval(12 * 3600), type: .acne, severity: 1),
            SymptomEntry(date: startOfDay.addingTimeInterval(8 * 3600), type: .acne, severity: 4),
            SymptomEntry(date: startOfDay.addingTimeInterval(11 * 3600), type: .bloating, severity: 2),
        ]

        for entry in entries {
            context.insert(entry)
        }
        try context.save()

        let vm = SymptomViewModel(modelContext: context)
        let fetched = vm.fetchTodaysSymptoms()

        #expect(fetched.count == 5)
        #expect(fetched.map(\.symptomType) == [.hunger, .anxious, .acne, .acne, .bloating])

        let acneEntries = fetched.filter { $0.symptomType == .acne }
        #expect(acneEntries.count == 2)
        #expect(acneEntries[0].date < acneEntries[1].date)
    }
}
