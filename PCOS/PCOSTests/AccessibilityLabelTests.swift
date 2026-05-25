import Testing
import Foundation
@testable import PCOS

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

    @Test("FlowIntensity display names honor locale overrides")
    func flowIntensityDisplayNamesHonorLocaleOverrides() {
        #expect(
            L10n.withOverrides(appLanguage: .fr) {
                FlowIntensity.heavy.displayName
            } == "Abondant"
        )
        #expect(
            L10n.withOverrides(appLanguage: .ja) {
                FlowIntensity.light.displayName
            } == "少ない"
        )
        #expect(
            L10n.withOverrides(appLanguage: .de) {
                FlowIntensity.spotting.displayName
            } == "Schmierblutung"
        )
    }

    @Test("Flow accessibility builders honor locale overrides")
    func flowAccessibilityBuildersHonorLocaleOverrides() {
        let frenchLabel = L10n.withOverrides(appLanguage: .fr) {
            L10n.flowAccessibilityLabel(for: .heavy)
        }
        #expect(frenchLabel.contains("Abondant"))
        #expect(!frenchLabel.contains("Heavy flow"))

        let germanHint = L10n.withOverrides(appLanguage: .de) {
            L10n.flowAccessibilityHint(for: .light)
        }
        #expect(germanHint.contains("Leicht"))
        #expect(!germanHint.contains("Double tap"))
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
