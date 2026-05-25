import Testing
import Foundation
@testable import PCOS

@Suite("Insight Guidance Catalog")
struct InsightGuidanceCatalogTests {
    @Test("Enriching symptom insights adds phase context, actions, and learn-more key")
    func symptomInsightsGainGuidanceMetadata() {
        L10n.withOverrides(appLanguage: .en, preferredLanguages: ["en_US"]) {
            let insight = Insight(
                insightType: .symptomCorrelation,
                title: "Symptoms peak during luteal phase",
                content: "You tend to feel more fatigued in the luteal phase.",
                confidence: 0.78,
                dataPointsUsed: 12
            )

            InsightGuidanceCatalog.enrich(insight)

            #expect(insight.phaseContext == .luteal)
            #expect(insight.recommendedActions.count >= 2)
            #expect(insight.learnMoreTopic == "\(InsightType.symptomCorrelation.rawValue).\(CyclePhase.luteal.rawValue)")
        }
    }

    @Test("Cycle-aware insight families keep the phase section even when timing is uncertain")
    func cycleAwareInsightFamiliesKeepPhaseSectionWhenUncertain() {
        let cycleAwareTypes: [InsightType] = [
            .cyclePattern,
            .symptomCorrelation,
            .supplementEfficacy,
            .dietImpact,
            .sleepActivity,
        ]

        for insightType in cycleAwareTypes {
            let insight = Insight(
                insightType: insightType,
                title: "Pattern is harder to line up lately",
                content: "Timing is less predictable right now.",
                confidence: 0.48,
                dataPointsUsed: 6
            )

            #expect(InsightGuidanceCatalog.showsPhaseContext(for: insight))
            #expect(InsightGuidanceCatalog.recommendedActions(for: insight).count >= 2)
            #expect(InsightGuidanceCatalog.recommendedActions(for: insight).count <= 4)
        }
    }

    @Test("Seasonal insights stay non-phase-specific unless a phase was explicitly stored")
    func seasonalInsightsStayNonPhaseSpecific() {
        let seasonalInsight = Insight(
            insightType: .seasonalPattern,
            title: "Symptoms vary by season",
            content: "Sample seasonal insight",
            confidence: 0.64,
            dataPointsUsed: 12
        )

        #expect(!InsightGuidanceCatalog.showsPhaseContext(for: seasonalInsight))

        seasonalInsight.phaseContext = .follicular
        #expect(InsightGuidanceCatalog.showsPhaseContext(for: seasonalInsight))
    }

    @Test("Unavailable phase messaging stays explicit when phase inference is not safe")
    func unavailablePhaseMessagingIsExplicit() {
        let insight = Insight(
            insightType: .symptomCorrelation,
            title: "Symptoms shift unpredictably",
            content: "Recent symptom timing has been harder to line up with a single phase.",
            confidence: 0.55,
            dataPointsUsed: 5
        )

        #expect(InsightGuidanceCatalog.inferredPhase(for: insight) == nil)
        #expect(!InsightGuidanceCatalog.unavailablePhaseMessage().isEmpty)
    }
}
