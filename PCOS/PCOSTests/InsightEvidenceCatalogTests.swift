import Testing
import Foundation
@testable import PCOS

@Suite("Insight Evidence Catalog")
struct InsightEvidenceCatalogTests {
    @Test("Every insight type resolves disclosure content")
    func everyInsightTypeResolvesDisclosureContent() {
        let samples: [InsightType: Insight] = [
            .cyclePattern: makeInsight(
                type: .cyclePattern,
                title: "Your cycles are regular",
                content: "Sample cycle insight"
            ),
            .symptomCorrelation: makeInsight(
                type: .symptomCorrelation,
                title: "Symptoms peak during luteal phase",
                content: "Sample symptom insight"
            ),
            .supplementEfficacy: makeInsight(
                type: .supplementEfficacy,
                title: "Inositol: symptom severity delta",
                content: "Sample supplement insight"
            ),
            .dietImpact: makeInsight(
                type: .dietImpact,
                title: "High-GI meals align with higher next-day symptom severity",
                content: "Sample diet insight"
            ),
            .sleepActivity: makeInsight(
                type: .sleepActivity,
                title: "Less sleep, more symptoms",
                content: "Sample sleep insight"
            ),
            .seasonalPattern: makeInsight(
                type: .seasonalPattern,
                title: "Symptoms vary by season",
                content: "Sample seasonal insight"
            ),
        ]

        for insightType in InsightType.allCases {
            guard let insight = samples[insightType] else {
                Issue.record("Missing sample insight for \(insightType.rawValue)")
                continue
            }

            let disclosure = InsightEvidenceCatalog.disclosure(for: insight)
            #expect(!disclosure.navigationTitle.isEmpty)
            #expect(!disclosure.headerTitle.isEmpty)
            #expect(!disclosure.specificExplanation.isEmpty)
        }
    }

    @Test("Predictive insights resolve summary without research citations")
    func predictiveInsightsResolveSummaryOnly() {
        let predictiveInsight = makeInsight(
            type: .cyclePattern,
            title: L10n.string("7-day symptom severity forecast", defaultValue: "7-day symptom severity forecast"),
            content: "Forecast insight"
        )

        let disclosure = InsightEvidenceCatalog.disclosure(for: predictiveInsight)
        #expect(disclosure.referenceDocket.isEmpty)
        #expect(disclosure.evidenceSummary != nil)
        #expect(disclosure.evidenceDisplayMode == .summaryOnly)
    }

    @Test("Supplement catalog retains ten source-backed presets")
    func supplementCatalogRetainsTenSourceBackedPresets() {
        let catalog = PCOSSupplements.catalog

        #expect(catalog.count == 10)
        for supplement in catalog {
            #expect(!supplement.key.isEmpty)
            #expect(!supplement.sources.isEmpty)
            for source in supplement.sources {
                #expect(source.url.scheme?.hasPrefix("http") == true)
                #expect(!source.relevanceNote.isEmpty)
            }
        }
    }

    @Test("Insight families resolve expected evidence display modes")
    func insightFamiliesResolveExpectedEvidenceDisplayModes() {
        let samples: [(Insight, EvidenceDisplayMode)] = [
            (
                makeInsight(type: .cyclePattern, title: "Your cycles are regular", content: "Sample"),
                .curatedDocket
            ),
            (
                makeInsight(type: .symptomCorrelation, title: "Symptoms peak during luteal phase", content: "Sample"),
                .curatedDocket
            ),
            (
                makeInsight(type: .supplementEfficacy, title: "Inositol: symptom severity delta", content: "Sample"),
                .curatedDocket
            ),
            (
                makeInsight(type: .dietImpact, title: "High-GI meals align with higher next-day symptom severity", content: "Sample"),
                .curatedDocket
            ),
            (
                makeInsight(type: .sleepActivity, title: "Less sleep, more symptoms", content: "Sample"),
                .curatedDocket
            ),
            (
                makeInsight(type: .seasonalPattern, title: "Symptoms vary by season", content: "Sample"),
                .summaryOnly
            ),
        ]

        for (insight, expectedMode) in samples {
            let disclosure = InsightEvidenceCatalog.disclosure(for: insight)
            #expect(disclosure.evidenceDisplayMode == expectedMode)
        }
    }

    @Test("Cycle-aware disclosures include evidence strength and curated source domains")
    func cycleAwareDisclosuresIncludeEvidenceStrengthAndCuratedSources() {
        let cycleDisclosure = InsightEvidenceCatalog.disclosure(
            for: makeInsight(type: .cyclePattern, title: "Your cycles are regular", content: "Sample")
        )
        #expect(cycleDisclosure.evidenceStrength == .pcosStudied)
        #expect(cycleDisclosure.referenceDocket.contains { $0.url.host?.contains("womenshealth.gov") == true })

        let dietDisclosure = InsightEvidenceCatalog.disclosure(
            for: makeInsight(type: .dietImpact, title: "Meals affect symptoms", content: "Sample")
        )
        #expect(dietDisclosure.evidenceStrength == .mixedEvidence)
        #expect(dietDisclosure.referenceDocket.contains { $0.url.host?.contains("health.gov") == true })

        let sleepDisclosure = InsightEvidenceCatalog.disclosure(
            for: makeInsight(type: .sleepActivity, title: "Sleep affects symptoms", content: "Sample")
        )
        #expect(sleepDisclosure.evidenceStrength == .mixedEvidence)
        #expect(sleepDisclosure.referenceDocket.contains { $0.url.host?.contains("medlineplus.gov") == true })
        #expect(sleepDisclosure.referenceDocket.contains { $0.title.localizedCaseInsensitiveContains("heart rate variability") })
        #expect(sleepDisclosure.referenceDocket.contains { $0.url.absoluteString.contains("39049099") })
    }

    @Test("Supplement insight matching resolves preset names without schema changes")
    func supplementInsightMatchingResolvesPresetNames() {
        let insight = makeInsight(
            type: .supplementEfficacy,
            title: "Inositol: symptom severity delta",
            content: "On days you took Inositol, your symptoms tended to feel milder."
        )

        let supplement = InsightEvidenceCatalog.supplement(for: insight)
        #expect(supplement?.key == "inositol")

        let disclosure = InsightEvidenceCatalog.disclosure(for: insight)
        #expect(disclosure.evidenceStrength == .pcosStudied)
        #expect(disclosure.referenceDocket.count >= 2)
    }

    @Test("Insight disclosures honor the selected app language override")
    func insightDisclosuresHonorSelectedLanguageOverride() {
        let insight = makeInsight(
            type: .cyclePattern,
            title: "Your cycles are regular",
            content: "Sample cycle insight"
        )

        let disclosure = L10n.withOverrides(appLanguage: .ja, preferredLanguages: ["en_US"]) {
            InsightEvidenceCatalog.disclosure(for: insight)
        }

        #expect(disclosure.navigationTitle == "仕組み")
        #expect(disclosure.specificExplanation == "このカードは、この端末に記録された完了済みで予測ではない周期の長さとばらつきを比較します。")
        #expect(disclosure.evidenceSummary == "PCOS のガイドラインや総説では周期の規則性を重要な手がかりとみなしますが、このカードが示しているのはあくまであなた自身の記録パターンであり、診断ではありません。")
        #expect(disclosure.referenceDocket.first?.sourceLabel == "PCOS国際ガイドライン（2023）")
    }

    @Test("Supplement insight evidence copy honors the selected app language override")
    func supplementInsightEvidenceCopyHonorsSelectedLanguageOverride() {
        let insight = makeInsight(
            type: .supplementEfficacy,
            title: "Inositol: symptom severity delta",
            content: "On days you took Inositol, your symptoms tended to feel milder."
        )

        let disclosure = L10n.withOverrides(appLanguage: .ja, preferredLanguages: ["en_US"]) {
            InsightEvidenceCatalog.disclosure(for: insight)
        }

        #expect(disclosure.navigationTitle == "仕組み")
        #expect(disclosure.evidenceSummary?.contains("イノシトール") == true)
        #expect(disclosure.referenceDocket.first?.sourceLabel == "PubMedアンブレラレビュー（2024）")
        #expect(disclosure.referenceDocket.last?.sourceLabel == "PCOS国際ガイドライン（2023）")
    }

    private func makeInsight(
        type: InsightType,
        title: String,
        content: String
    ) -> Insight {
        Insight(
            insightType: type,
            title: title,
            content: content,
            confidence: 0.72,
            dataPointsUsed: 18
        )
    }
}
