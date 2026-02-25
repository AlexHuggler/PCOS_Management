import Testing
import SwiftData
@testable import CycleBalance

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
}
