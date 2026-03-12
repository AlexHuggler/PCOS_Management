import Testing
import Foundation
import UIKit
@testable import PCOS

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

    @Test("SymptomType system images resolve to available SF Symbols")
    func symptomSystemImageAvailability() {
        for type in SymptomType.allCases {
            #expect(UIImage(systemName: type.systemImage) != nil,
                    "\(type) uses unavailable SF Symbol: \(type.systemImage)")
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

    @Test("PrimaryGoal has displayName, subtitle, and systemImage")
    func primaryGoalProperties() {
        for goal in PrimaryGoal.allCases {
            #expect(!goal.displayName.isEmpty)
            #expect(!goal.subtitle.isEmpty)
            #expect(!goal.systemImage.isEmpty)
        }
    }

    @Test("PCOSExperience has displayName, subtitle, and systemImage")
    func pcosExperienceProperties() {
        for exp in PCOSExperience.allCases {
            #expect(!exp.displayName.isEmpty)
            #expect(!exp.subtitle.isEmpty)
            #expect(!exp.systemImage.isEmpty)
        }
    }

    @Test("SymptomFocusArea relatedCategories covers real categories")
    func focusAreaCategoriesValid() {
        let allCats = Set(SymptomCategory.allCases)
        for area in SymptomFocusArea.allCases {
            for cat in area.relatedCategories {
                #expect(allCats.contains(cat),
                        "\(area) maps to unknown category \(cat)")
            }
        }
    }
}
