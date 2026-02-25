import Testing
@testable import CycleBalance

@Suite("Enum Consistency")
struct EnumTests {
    @Test("SymptomCategory covers all SymptomTypes")
    func categoryCoversAllTypes() {
        var coveredTypes = Set<SymptomType>()
        for category in SymptomCategory.allCases {
            for type in category.symptomTypes {
                coveredTypes.insert(type)
            }
        }
        #expect(coveredTypes.count == SymptomType.allCases.count,
                "Every SymptomType must belong to exactly one category")
    }

    @Test("SymptomType.category is consistent with SymptomCategory.symptomTypes")
    func categoryConsistency() {
        for type in SymptomType.allCases {
            let category = type.category
            #expect(category.symptomTypes.contains(type),
                    "\(type) claims category \(category) but is not in its symptomTypes")
        }
    }

    @Test("FlowIntensity raw values are unique")
    func uniqueFlowRawValues() {
        let rawValues = FlowIntensity.allCases.map(\.rawValue)
        #expect(Set(rawValues).count == rawValues.count)
    }

    @Test("CyclePhase has 4 phases")
    func cyclePhaseCount() {
        #expect(CyclePhase.allCases.count == 4)
    }
}
