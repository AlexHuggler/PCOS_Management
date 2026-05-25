import Foundation

struct PCOSSupplement: Identifiable {
    let key: String
    let name: String
    let defaultDosageMg: Double
    let description: String
    let evidenceSummary: String
    let evidenceStrength: EvidenceStrength
    let sources: [EvidenceReference]

    var id: String { key }
}

enum PCOSSupplements {
    static var catalog: [PCOSSupplement] {
        [
            PCOSSupplement(
                key: "inositol",
                name: "Inositol",
                defaultDosageMg: 4000,
                description: "Studied in PCOS for insulin-sensitivity and cycle support.",
                evidenceSummary: localized("Inositol has direct PCOS literature support, especially for insulin-related and reproductive outcomes, though benefit size varies across trials."),
                evidenceStrength: .pcosStudied,
                sources: [
                    reference(
                        title: "Effects of inositol in women with polycystic ovary syndrome: an umbrella review of meta-analyses from randomized controlled trials",
                        sourceLabel: "PubMed umbrella review (2024)",
                        url: "https://pubmed.ncbi.nlm.nih.gov/41757236/"
                    )
                ]
            ),
            PCOSSupplement(
                key: "vitamin_d",
                name: "Vitamin D",
                defaultDosageMg: 2000,
                description: "Studied in PCOS for metabolic and hormonal support, especially when deficiency is present.",
                evidenceSummary: localized("Vitamin D has direct PCOS trial and meta-analysis support, but results vary and deficiency status may matter."),
                evidenceStrength: .pcosStudied,
                sources: [
                    reference(
                        title: "The effect of Vitamin D supplementation on hormonal and glycaemic profile of patients with PCOS: A meta-analysis of randomised trials",
                        sourceLabel: "PubMed meta-analysis (2017)",
                        url: "https://pubmed.ncbi.nlm.nih.gov/28524342/"
                    )
                ]
            ),
            PCOSSupplement(
                key: "omega_3",
                name: "Omega-3",
                defaultDosageMg: 1000,
                description: "Studied in PCOS for cardiometabolic support.",
                evidenceSummary: localized("Omega-3 has direct PCOS meta-analysis support for selected cardiometabolic markers, though effects are not uniform across outcomes."),
                evidenceStrength: .pcosStudied,
                sources: [
                    reference(
                        title: "Efficacy of omega-3 fatty acid supplementation on cardiovascular risk factors in patients with polycystic ovary syndrome: a systematic review and meta-analysis",
                        sourceLabel: "PubMed meta-analysis (2021)",
                        url: "https://pubmed.ncbi.nlm.nih.gov/34237964/"
                    )
                ]
            ),
            PCOSSupplement(
                key: "berberine",
                name: "Berberine",
                defaultDosageMg: 500,
                description: "Studied in PCOS for metabolic support, with still-limited trial depth.",
                evidenceSummary: localized("Berberine has direct PCOS meta-analysis support for metabolic outcomes, but the trial base is smaller than for core guideline-backed therapies."),
                evidenceStrength: .pcosStudied,
                sources: [
                    reference(
                        title: "A systematic review and meta-analysis of the effects of berberine on polycystic ovary syndrome",
                        sourceLabel: "PubMed meta-analysis (2019)",
                        url: "https://pubmed.ncbi.nlm.nih.gov/31915452/"
                    )
                ]
            ),
            PCOSSupplement(
                key: "nac",
                name: "NAC",
                defaultDosageMg: 600,
                description: "Studied in PCOS for metabolic and ovulatory support.",
                evidenceSummary: localized("N-acetylcysteine has direct PCOS meta-analysis support, but findings are still interpreted cautiously alongside standard care."),
                evidenceStrength: .pcosStudied,
                sources: [
                    reference(
                        title: "The effects of N-acetylcysteine on metabolic parameters in women with polycystic ovary syndrome: a systematic review and meta-analysis",
                        sourceLabel: "PubMed meta-analysis (2024)",
                        url: "https://pubmed.ncbi.nlm.nih.gov/39861414/"
                    )
                ]
            ),
            PCOSSupplement(
                key: "zinc",
                name: "Zinc",
                defaultDosageMg: 30,
                description: "Some PCOS studies suggest metabolic or skin-support benefits, but evidence remains mixed.",
                evidenceSummary: localized("Zinc appears in newer mineral-supplement analyses for PCOS, but the overall evidence base is still mixed and not strong enough for a broad treatment claim."),
                evidenceStrength: .mixedEvidence,
                sources: [
                    reference(
                        title: "Effectiveness of mineral supplements (magnesium, chromium, zinc, selenium, chromium picolinate) in reducing insulin resistance in polycystic ovary syndrome: a meta-analysis of randomized controlled trials",
                        sourceLabel: "PubMed meta-analysis (2024)",
                        url: "https://pubmed.ncbi.nlm.nih.gov/41580698/"
                    )
                ]
            ),
            PCOSSupplement(
                key: "magnesium",
                name: "Magnesium",
                defaultDosageMg: 400,
                description: "Some PCOS studies suggest metabolic-support benefits, but evidence remains emerging.",
                evidenceSummary: localized("Magnesium appears in newer mineral-supplement analyses for PCOS, but the evidence base is still emerging and should be framed conservatively."),
                evidenceStrength: .emergingEvidence,
                sources: [
                    reference(
                        title: "Effectiveness of mineral supplements (magnesium, chromium, zinc, selenium, chromium picolinate) in reducing insulin resistance in polycystic ovary syndrome: a meta-analysis of randomized controlled trials",
                        sourceLabel: "PubMed meta-analysis (2024)",
                        url: "https://pubmed.ncbi.nlm.nih.gov/41580698/"
                    )
                ]
            ),
            PCOSSupplement(
                key: "spearmint_tea",
                name: "Spearmint Tea",
                defaultDosageMg: 0,
                description: "Small studies suggest androgen-support potential, but evidence is limited.",
                evidenceSummary: localized("Spearmint tea has small-trial support for androgen-related symptoms, but the evidence base remains limited."),
                evidenceStrength: .limitedEvidence,
                sources: [
                    reference(
                        title: "Beneficial effect of spearmint herbal tea on androgen levels in women with hirsutism: a randomised controlled trial",
                        sourceLabel: "PubMed randomized trial (2010)",
                        url: "https://pubmed.ncbi.nlm.nih.gov/19585478/"
                    )
                ]
            ),
            PCOSSupplement(
                key: "folate",
                name: "Folate",
                defaultDosageMg: 400,
                description: "Supports preconception nutrition and general reproductive health.",
                evidenceSummary: localized("Folate is included as broader preconception and reproductive-health guidance rather than as a direct PCOS treatment recommendation."),
                evidenceStrength: .generalGuidance,
                sources: [
                    reference(
                        title: "Folic Acid Supplementation to Prevent Neural Tube Defects",
                        sourceLabel: "USPSTF recommendation",
                        url: "https://uspreventiveservicestaskforce.org/uspstf/sites/default/files/2023-10/2023-annual-report-to-congress.pdf"
                    )
                ]
            ),
            PCOSSupplement(
                key: "chromium",
                name: "Chromium",
                defaultDosageMg: 200,
                description: "Studied for insulin-related markers in PCOS, with mixed evidence.",
                evidenceSummary: localized("Chromium has direct PCOS meta-analysis support for some insulin-resistance markers, but the overall evidence remains mixed."),
                evidenceStrength: .mixedEvidence,
                sources: [
                    reference(
                        title: "The Effects of Supplementation with Chromium on Insulin Resistance Indices in Women with Polycystic Ovarian Syndrome: A Systematic Review and Meta-Analysis of Randomized Clinical Trials",
                        sourceLabel: "PubMed meta-analysis (2018)",
                        url: "https://pubmed.ncbi.nlm.nih.gov/29523006/"
                    ),
                    reference(
                        title: "Effectiveness of mineral supplements (magnesium, chromium, zinc, selenium, chromium picolinate) in reducing insulin resistance in polycystic ovary syndrome: a meta-analysis of randomized controlled trials",
                        sourceLabel: "PubMed meta-analysis (2024)",
                        url: "https://pubmed.ncbi.nlm.nih.gov/41580698/"
                    )
                ]
            ),
        ]
    }

    private static func reference(
        title: String,
        sourceLabel: String,
        url: String,
        relevanceNote: String? = nil
    ) -> EvidenceReference {
        EvidenceReference(
            title: title,
            sourceLabel: localized(sourceLabel),
            url: URL(string: url)!,
            relevanceNote: relevanceNote.map(localized)
                ?? localized("Direct study or review for this supplement in PCOS.")
        )
    }

    private static func localized(_ key: String) -> String {
        L10n.string(key, defaultValue: key)
    }
}
