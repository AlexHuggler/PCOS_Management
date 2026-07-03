import Foundation
import os

struct EvidenceReference: Identifiable, Hashable, Sendable {
    let title: String
    let sourceLabel: String
    let url: URL
    let relevanceNote: String

    var id: String {
        "\(title)|\(sourceLabel)|\(url.absoluteString)|\(relevanceNote)"
    }
}

enum EvidenceStrength: String, CaseIterable, Hashable, Sendable {
    case pcosStudied
    case mixedEvidence
    case emergingEvidence
    case limitedEvidence
    case generalGuidance

    var displayName: String {
        switch self {
        case .pcosStudied:
            L10n.string("PCOS-studied", defaultValue: "PCOS-studied")
        case .mixedEvidence:
            L10n.string("Mixed evidence", defaultValue: "Mixed evidence")
        case .emergingEvidence:
            L10n.string("Emerging evidence", defaultValue: "Emerging evidence")
        case .limitedEvidence:
            L10n.string("Limited evidence", defaultValue: "Limited evidence")
        case .generalGuidance:
            L10n.string("General guidance", defaultValue: "General guidance")
        }
    }
}

enum EvidenceDisplayMode: String, Hashable, Sendable {
    case none
    case summaryOnly
    case curatedDocket
}

struct InsightDisclosureContent: Identifiable, Hashable, Sendable {
    let id: String
    let navigationTitle: String
    let headerTitle: String
    let specificExplanation: String
    let evidenceSummary: String?
    let evidenceStrength: EvidenceStrength?
    let referenceDocket: [EvidenceReference]

    var evidenceDisplayMode: EvidenceDisplayMode {
        if !referenceDocket.isEmpty {
            return .curatedDocket
        }
        if evidenceSummary != nil {
            return .summaryOnly
        }
        return .none
    }
}

enum InsightEvidenceCatalog {
    static func disclosure(
        for insight: Insight,
        language: AppLanguage? = nil
    ) -> InsightDisclosureContent {
        let resolvedLanguage = L10n.resolvedAppLanguage(language)

        return L10n.withOverrides(appLanguage: resolvedLanguage) {
            if insight.isPredictiveForecast {
                return InsightDisclosureContent(
                    id: "insight.predictive.\(insight.id.uuidString)",
                    navigationTitle: L10n.string("How this works", defaultValue: "Learn more"),
                    headerTitle: insight.title,
                    specificExplanation: L10n.string(
                        "Forecast cards compare your recent cycle, symptom, meal, supplement, blood sugar, and daily-log history on this device to estimate a likely range. If the app does not have enough recent or consistent data, it stays cautious or skips the forecast.",
                        defaultValue: "Forecast cards compare your recent cycle, symptom, meal, supplement, blood sugar, and daily-log history on this device to estimate a likely range. If the app does not have enough recent or consistent data, it stays cautious or skips the forecast."
                    ),
                    evidenceSummary: L10n.string(
                        "This forecast is driven mostly by your own logging history rather than a specific external study, so it should be treated as a personalized estimate, not a medical prediction.",
                        defaultValue: "This forecast is driven mostly by your own logging history rather than a specific external study, so it should be treated as a personalized estimate, not a medical prediction."
                    ),
                    evidenceStrength: nil,
                    referenceDocket: []
                )
            }

            switch insight.insightType {
            case .cyclePattern:
                return InsightDisclosureContent(
                    id: "insight.cycle.\(insight.id.uuidString)",
                    navigationTitle: L10n.string("How this works", defaultValue: "Learn more"),
                    headerTitle: insight.title,
                    specificExplanation: L10n.string(
                        "This card compares the length and variability of your completed, non-predicted cycles logged on this device.",
                        defaultValue: "This card compares the length and variability of your completed, non-predicted cycles logged on this device."
                    ),
                    evidenceSummary: L10n.string(
                        "PCOS guidelines and review papers treat cycle regularity as an important signal, but this card is still describing your own logged cycle pattern rather than making a diagnosis.",
                        defaultValue: "PCOS guidelines and review papers treat cycle regularity as an important signal, but this card is still describing your own logged cycle pattern rather than making a diagnosis."
                    ),
                    evidenceStrength: .pcosStudied,
                    referenceDocket: cyclePatternReferences
                )
            case .symptomCorrelation:
                return InsightDisclosureContent(
                    id: "insight.symptom.\(insight.id.uuidString)",
                    navigationTitle: L10n.string("How this works", defaultValue: "Learn more"),
                    headerTitle: insight.title,
                    specificExplanation: L10n.string(
                        "This card looks for symptom timing, clustering, and trend changes across the symptom days and cycle phases you have logged.",
                        defaultValue: "This card looks for symptom timing, clustering, and trend changes across the symptom days and cycle phases you have logged."
                    ),
                    evidenceSummary: L10n.string(
                        "PCOS research shows that symptom burden can affect daily life and emotional wellbeing, but this card is still a personal pattern from your own symptom history rather than proof of a cause.",
                        defaultValue: "PCOS research shows that symptom burden can affect daily life and emotional wellbeing, but this card is still a personal pattern from your own symptom history rather than proof of a cause."
                    ),
                    evidenceStrength: .mixedEvidence,
                    referenceDocket: symptomCorrelationReferences
                )
            case .supplementEfficacy:
                return supplementInsightDisclosure(for: insight, language: resolvedLanguage)
            case .dietImpact:
                return InsightDisclosureContent(
                    id: "insight.diet.\(insight.id.uuidString)",
                    navigationTitle: L10n.string("How this works", defaultValue: "Learn more"),
                    headerTitle: insight.title,
                    specificExplanation: L10n.string(
                        "This card compares the glycemic pattern of your logged meals with later symptoms and breakout timing from meals saved on this device.",
                        defaultValue: "This card compares the glycemic pattern of your logged meals with later symptoms and breakout timing from meals saved on this device."
                    ),
                    evidenceSummary: L10n.string(
                        "PCOS lifestyle guidance often focuses on meal quality, blood sugar, and sustainable activity habits. This card uses that context, but the relationship shown here still comes from your own meal and symptom logs.",
                        defaultValue: "PCOS lifestyle guidance often focuses on meal quality, blood sugar, and sustainable activity habits. This card uses that context, but the relationship shown here still comes from your own meal and symptom logs."
                    ),
                    evidenceStrength: .mixedEvidence,
                    referenceDocket: dietImpactReferences
                )
            case .sleepActivity:
                return InsightDisclosureContent(
                    id: "insight.sleep.\(insight.id.uuidString)",
                    navigationTitle: L10n.string("How this works", defaultValue: "Learn more"),
                    headerTitle: insight.title,
                    specificExplanation: L10n.string(
                        "This card compares your logged sleep, energy, and activity trends with symptom severity from daily logs saved on this device.",
                        defaultValue: "This card compares your logged sleep, energy, and activity trends with symptom severity from daily logs saved on this device."
                    ),
                    evidenceSummary: L10n.string(
                        "Sleep problems are more common in PCOS populations, but this card is still mainly a personal recovery-pattern check from your own logs rather than proof of a cause.",
                        defaultValue: "Sleep problems are more common in PCOS populations, but this card is still mainly a personal recovery-pattern check from your own logs rather than proof of a cause."
                    ),
                    evidenceStrength: .mixedEvidence,
                    referenceDocket: sleepActivityReferences
                )
            case .seasonalPattern:
                return InsightDisclosureContent(
                    id: "insight.seasonal.\(insight.id.uuidString)",
                    navigationTitle: L10n.string("How this works", defaultValue: "Learn more"),
                    headerTitle: insight.title,
                    specificExplanation: L10n.string(
                        "This card compares symptom averages across months using the history you have logged on this device.",
                        defaultValue: "This card compares symptom averages across months using the history you have logged on this device."
                    ),
                    evidenceSummary: L10n.string(
                        "Seasonal shifts are not a core benchmark topic in PCOS research, so this card should be read mostly as a personal pattern from your own logs.",
                        defaultValue: "Seasonal shifts are not a core benchmark topic in PCOS research, so this card should be read mostly as a personal pattern from your own logs."
                    ),
                    evidenceStrength: .limitedEvidence,
                    referenceDocket: []
                )
            }
        }
    }

    static func disclosure(
        for supplement: PCOSSupplement,
        language: AppLanguage? = nil
    ) -> InsightDisclosureContent {
        let resolvedLanguage = L10n.resolvedAppLanguage(language)

        return L10n.withOverrides(appLanguage: resolvedLanguage) {
            let localizedSupplement = PCOSSupplements.catalog.first { $0.key == supplement.key } ?? supplement

            return InsightDisclosureContent(
                id: "supplement.\(localizedSupplement.key)",
                navigationTitle: L10n.string("Sources", defaultValue: "Sources"),
                headerTitle: localizedSupplement.name,
                specificExplanation: L10n.string(
                    "These catalog presets are tracking-friendly starting points for commonly discussed supplements. They are not prescriptions, treatment plans, or personalized medical recommendations.",
                    defaultValue: "These catalog presets are tracking-friendly starting points for commonly discussed supplements. They are not prescriptions, treatment plans, or personalized medical recommendations."
                ),
                evidenceSummary: localizedSupplement.evidenceSummary,
                evidenceStrength: localizedSupplement.evidenceStrength,
                referenceDocket: localizedSupplement.sources
            )
        }
    }

    static func supplement(
        for insight: Insight,
        language: AppLanguage? = nil
    ) -> PCOSSupplement? {
        let resolvedLanguage = L10n.resolvedAppLanguage(language)

        return L10n.withOverrides(appLanguage: resolvedLanguage) {
            let haystacks = [
                insight.title,
                insight.content,
                insight.scientificContent ?? ""
            ]
            return PCOSSupplements.catalog.first { supplement in
                haystacks.contains { text in
                    text.localizedCaseInsensitiveContains(supplement.name)
                }
            }
        }
    }

    private static func supplementInsightDisclosure(
        for insight: Insight,
        language: AppLanguage
    ) -> InsightDisclosureContent {
        guard let supplement = supplement(for: insight, language: language) else {
            return InsightDisclosureContent(
                id: "insight.supplement.generic.\(insight.id.uuidString)",
                navigationTitle: L10n.string("How this works", defaultValue: "Learn more"),
                headerTitle: insight.title,
                specificExplanation: L10n.string(
                    "This card compares your logged taken versus missed days, symptom severity, and cycle patterns from supplement entries saved on this device.",
                    defaultValue: "This card compares your logged taken versus missed days, symptom severity, and cycle patterns from supplement entries saved on this device."
                ),
                evidenceSummary: L10n.string(
                    "This result is mostly a personal adherence pattern from your own logs. Because the supplement does not match a curated preset, the app avoids attaching a broader study list that could feel misleading.",
                    defaultValue: "This result is mostly a personal adherence pattern from your own logs. Because the supplement does not match a curated preset, the app avoids attaching a broader study list that could feel misleading."
                ),
                evidenceStrength: nil,
                referenceDocket: []
            )
        }

        return InsightDisclosureContent(
            id: "insight.supplement.\(supplement.key).\(insight.id.uuidString)",
            navigationTitle: L10n.string("How this works", defaultValue: "Learn more"),
            headerTitle: insight.title,
            specificExplanation: L10n.string(
                "This card compares your logged taken versus missed days, symptom severity, and cycle patterns for the supplement you tracked.",
                defaultValue: "This card compares your logged taken versus missed days, symptom severity, and cycle patterns for the supplement you tracked."
            ),
            evidenceSummary: "\(supplement.evidenceSummary) \(L10n.string("Your card still does not prove that the supplement caused the change; it highlights a pattern worth tracking over time.", defaultValue: "Your card still does not prove that the supplement caused the change; it highlights a pattern worth tracking over time."))",
            evidenceStrength: supplement.evidenceStrength,
            referenceDocket: supplement.sources + [guidelineReference].compactMap { $0 }
        )
    }

    private static func reference(
        title: String,
        sourceLabel: String,
        urlString: String,
        relevanceNote: String
    ) -> EvidenceReference? {
        guard let url = URL(string: urlString) else {
            Logger.insights.error("InsightEvidenceCatalog: Dropping reference with invalid URL for \(title)")
            return nil
        }
        return EvidenceReference(
            title: title,
            sourceLabel: sourceLabel,
            url: url,
            relevanceNote: relevanceNote
        )
    }

    private static var guidelineReference: EvidenceReference? {
        reference(
            title: "Recommendations from the 2023 International Evidence-based Guideline for the Assessment and Management of Polycystic Ovarian Syndrome",
            sourceLabel: L10n.string("International PCOS guideline (2023)", defaultValue: "International PCOS guideline (2023)"),
            urlString: "https://www.monash.edu/__data/assets/pdf_file/0003/3379521/Evidence-Based-Guidelines-2023.pdf",
            relevanceNote: L10n.string(
                "Benchmark international guideline used for broad PCOS assessment and management context.",
                defaultValue: "Benchmark international guideline used for broad PCOS assessment and management context."
            )
        )
    }

    private static var bmjOverviewReference: EvidenceReference? {
        reference(
            title: "Polycystic ovary syndrome: pathophysiology and therapeutic opportunities",
            sourceLabel: L10n.string("BMJ Medicine review (2023)", defaultValue: "BMJ Medicine review (2023)"),
            urlString: "https://bmjmedicine.bmj.com/content/2/1/e000548",
            relevanceNote: L10n.string(
                "High-level review explaining core PCOS mechanisms and why cycle and metabolic patterns matter.",
                defaultValue: "High-level review explaining core PCOS mechanisms and why cycle and metabolic patterns matter."
            )
        )
    }

    private static var womensHealthCycleReference: EvidenceReference? {
        reference(
            title: "Your menstrual cycle",
            sourceLabel: L10n.string("Office on Women's Health", defaultValue: "Office on Women's Health"),
            urlString: "https://womenshealth.gov/menstrual-cycle/your-menstrual-cycle",
            relevanceNote: L10n.string(
                "Official patient guidance explaining menstrual-cycle timing, ovulation, and common symptom changes across the cycle.",
                defaultValue: "Official patient guidance explaining menstrual-cycle timing, ovulation, and common symptom changes across the cycle."
            )
        )
    }

    private static var dietBehaviorsReference: EvidenceReference? {
        reference(
            title: "Dietary and Physical Activity Behaviors in Women with Polycystic Ovary Syndrome per the New International Evidence-Based Guideline",
            sourceLabel: L10n.string("PubMed review (2019)", defaultValue: "PubMed review (2019)"),
            urlString: "https://pubmed.ncbi.nlm.nih.gov/31717369/",
            relevanceNote: L10n.string(
                "Guideline-linked review summarizing diet and activity patterns discussed in PCOS care.",
                defaultValue: "Guideline-linked review summarizing diet and activity patterns discussed in PCOS care."
            )
        )
    }

    private static var exerciseMetaReference: EvidenceReference? {
        reference(
            title: "Exercise, or exercise and diet, for the management of polycystic ovary syndrome: a systematic review and meta-analysis",
            sourceLabel: L10n.string("PubMed meta-analysis (2019)", defaultValue: "PubMed meta-analysis (2019)"),
            urlString: "https://pubmed.ncbi.nlm.nih.gov/30755271/",
            relevanceNote: L10n.string(
                "Commonly cited evidence showing why exercise and lifestyle patterns are discussed in PCOS management.",
                defaultValue: "Commonly cited evidence showing why exercise and lifestyle patterns are discussed in PCOS management."
            )
        )
    }

    private static var physicalActivityGuidelinesReference: EvidenceReference? {
        reference(
            title: "Physical Activity Guidelines for Americans, 2nd edition",
            sourceLabel: L10n.string("U.S. Department of Health and Human Services", defaultValue: "U.S. Department of Health and Human Services"),
            urlString: "https://health.gov/sites/default/files/2019-09/Physical_Activity_Guidelines_2nd_edition.pdf",
            relevanceNote: L10n.string(
                "Official U.S. physical-activity guidance used for general movement and exercise recommendations when interpreting lifestyle patterns.",
                defaultValue: "Official U.S. physical-activity guidance used for general movement and exercise recommendations when interpreting lifestyle patterns."
            )
        )
    }

    private static var sleepMetaReference: EvidenceReference? {
        reference(
            title: "Eating, sleeping and sexual function disorders in women with polycystic ovary syndrome: a systematic review and meta-analysis",
            sourceLabel: L10n.string("PubMed systematic review (2019)", defaultValue: "PubMed systematic review (2019)"),
            urlString: "https://pubmed.ncbi.nlm.nih.gov/31917860/",
            relevanceNote: L10n.string(
                "Overview of sleep-related difficulties reported more often in PCOS populations.",
                defaultValue: "Overview of sleep-related difficulties reported more often in PCOS populations."
            )
        )
    }

    private static var heartRateVariabilityReference: EvidenceReference? {
        reference(
            title: "Exploring heart rate variability in polycystic ovary syndrome: implications for cardiovascular health: a systematic review and meta-analysis",
            sourceLabel: L10n.string("PubMed meta-analysis (2024)", defaultValue: "PubMed meta-analysis (2024)"),
            urlString: "https://pubmed.ncbi.nlm.nih.gov/39049099/",
            relevanceNote: L10n.string(
                "PCOS-studied context for why HRV and resting-heart-rate patterns can be useful recovery signals when interpreted cautiously.",
                defaultValue: "PCOS-studied context for why HRV and resting-heart-rate patterns can be useful recovery signals when interpreted cautiously."
            )
        )
    }

    private static var healthySleepReference: EvidenceReference? {
        reference(
            title: "Healthy Sleep",
            sourceLabel: L10n.string("MedlinePlus", defaultValue: "MedlinePlus"),
            urlString: "https://medlineplus.gov/healthysleep.html",
            relevanceNote: L10n.string(
                "Official patient guidance for sleep habits and practical sleep-hygiene steps that can support recovery and energy.",
                defaultValue: "Official patient guidance for sleep habits and practical sleep-hygiene steps that can support recovery and energy."
            )
        )
    }

    private static var mentalHealthOverviewReference: EvidenceReference? {
        reference(
            title: "Anxiety and depression in polycystic ovary syndrome: an overview of systematic reviews with meta-analysis",
            sourceLabel: L10n.string("PubMed overview (2024)", defaultValue: "PubMed overview (2024)"),
            urlString: "https://pubmed.ncbi.nlm.nih.gov/39453529/",
            relevanceNote: L10n.string(
                "Shows why symptom burden and emotional wellbeing are often discussed together in PCOS care.",
                defaultValue: "Shows why symptom burden and emotional wellbeing are often discussed together in PCOS care."
            )
        )
    }

    private static var cyclePatternReferences: [EvidenceReference] {
        [guidelineReference, bmjOverviewReference, womensHealthCycleReference].compactMap { $0 }
    }

    private static var symptomCorrelationReferences: [EvidenceReference] {
        [guidelineReference, mentalHealthOverviewReference, womensHealthCycleReference].compactMap { $0 }
    }

    private static var dietImpactReferences: [EvidenceReference] {
        [guidelineReference, dietBehaviorsReference, exerciseMetaReference, physicalActivityGuidelinesReference].compactMap { $0 }
    }

    private static var sleepActivityReferences: [EvidenceReference] {
        [guidelineReference, sleepMetaReference, heartRateVariabilityReference, healthySleepReference].compactMap { $0 }
    }
}
