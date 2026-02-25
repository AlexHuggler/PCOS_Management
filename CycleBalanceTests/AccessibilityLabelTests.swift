import Testing
@testable import CycleBalance

@Suite("Accessibility Labels")
struct AccessibilityLabelTests {
    @Test("FlowIntensity short labels are unique and non-empty for active flows")
    func flowShortLabels() {
        let active: [FlowIntensity] = [.spotting, .light, .medium, .heavy]
        let labels = active.map(\.shortLabel)
        #expect(Set(labels).count == 4, "All short labels must be unique")
        for label in labels {
            #expect(!label.isEmpty)
        }
    }

    @Test("FlowIntensity.none has empty short label")
    func noneFlowHasEmptyLabel() {
        #expect(FlowIntensity.none.shortLabel == "")
    }

    @Test("FlowIntensity display names are non-empty")
    func displayNamesNonEmpty() {
        for intensity in FlowIntensity.allCases {
            #expect(!intensity.displayName.isEmpty)
        }
    }

    @Test("SymptomType display names are non-empty")
    func symptomDisplayNames() {
        for symptom in SymptomType.allCases {
            #expect(!symptom.displayName.isEmpty)
        }
    }

    @Test("InsightType display names and system images are non-empty")
    func insightTypeLabels() {
        for type in InsightType.allCases {
            #expect(!type.displayName.isEmpty)
            #expect(!type.systemImage.isEmpty)
        }
    }
}
