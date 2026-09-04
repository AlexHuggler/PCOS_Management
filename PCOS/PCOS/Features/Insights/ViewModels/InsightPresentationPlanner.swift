import Foundation

struct InsightAudiencePreferences: Sendable, Equatable {
    let primaryGoal: PrimaryGoal?
    let experience: PCOSExperience?
    let focusAreas: [SymptomFocusArea]

    init(
        primaryGoal: PrimaryGoal? = nil,
        experience: PCOSExperience? = nil,
        focusAreas: [SymptomFocusArea] = []
    ) {
        self.primaryGoal = primaryGoal
        self.experience = experience
        self.focusAreas = focusAreas
    }

    @MainActor
    init(profile: OnboardingProfile) {
        self.init(
            primaryGoal: profile.primaryGoal,
            experience: profile.pcosExperience,
            focusAreas: profile.symptomFocusAreas
        )
    }

    var preferredCategories: [SymptomCategory] {
        focusAreas.flatMap(\.relatedCategories)
    }
}

struct InsightsDataReadiness: Sendable, Equatable {
    let completedCycles: Int
    let symptomDays: Int
    let mealDays: Int
    let supplementDays: Int
    let dailyLogDays: Int
    let bloodSugarDays: Int

    static let empty = InsightsDataReadiness(
        completedCycles: 0,
        symptomDays: 0,
        mealDays: 0,
        supplementDays: 0,
        dailyLogDays: 0,
        bloodSugarDays: 0
    )
}

struct InsightEmptyStateContent: Sendable, Equatable {
    let title: String
    let message: String
}

struct PremiumInsightTeaser: Identifiable, Equatable, Sendable {
    let id: String
    let title: String
    let message: String
}

struct InsightPresentationPlan {
    let visibleInsights: [Insight]
    let lockedPremiumCards: [PremiumInsightTeaser]
}

struct InsightPresentationPlanner {
    func makePlan(
        insights: [Insight],
        preferences: InsightAudiencePreferences,
        isPremium: Bool
    ) -> InsightPresentationPlan {
        let prioritized = prioritize(insights: insights, preferences: preferences)
        guard !isPremium else {
            return InsightPresentationPlan(visibleInsights: prioritized, lockedPremiumCards: [])
        }

        let visibleInsights = prioritized.filter(\.isBasicFreeInsight)
        let premiumInsights = prioritized.filter(\.isPremiumOnlyInsight)

        return InsightPresentationPlan(
            visibleInsights: visibleInsights,
            lockedPremiumCards: premiumInsights.isEmpty ? [] : lockedPremiumCards(from: premiumInsights)
        )
    }

    func emptyStateContent(
        readiness: InsightsDataReadiness,
        preferences: InsightAudiencePreferences
    ) -> InsightEmptyStateContent {
        if readiness.completedCycles < InsightThresholds.completedCyclesForCyclePatterns && readiness.symptomDays < InsightThresholds.trackedSymptomDaysForCorrelations {
            if preferences.primaryGoal == .understandSymptoms {
                return InsightEmptyStateContent(
                    title: L10n.string("Build your first symptom insights", defaultValue: "Build your first symptom insights"),
                    message: L10n.string(
                        "Symptom correlations need about 14 tracked days, and cycle pattern summaries need 3 complete cycles. Start with daily symptoms and period starts.",
                        defaultValue: "Symptom correlations need about 14 tracked days, and cycle pattern summaries need 3 complete cycles. Start with daily symptoms and period starts."
                    )
                )
            }

            return InsightEmptyStateContent(
                title: L10n.string("Build your first cycle insights", defaultValue: "Build your first cycle insights"),
                message: L10n.string(
                    "Cycle pattern summaries need 3 complete cycles, and symptom correlations need about 14 tracked days. Keep logging period starts and daily symptoms.",
                    defaultValue: "Cycle pattern summaries need 3 complete cycles, and symptom correlations need about 14 tracked days. Keep logging period starts and daily symptoms."
                )
            )
        }

        if readiness.completedCycles < InsightThresholds.completedCyclesForCyclePatterns {
            return InsightEmptyStateContent(
                title: L10n.string("More cycle data will sharpen your insights", defaultValue: "More cycle data will sharpen your insights"),
                message: L10n.string(
                    "Cycle pattern summaries become reliable after 3 complete cycles. Keep logging each period start so your pattern can stabilize.",
                    defaultValue: "Cycle pattern summaries become reliable after 3 complete cycles. Keep logging each period start so your pattern can stabilize."
                )
            )
        }

        if readiness.symptomDays < InsightThresholds.trackedSymptomDaysForCorrelations {
            return InsightEmptyStateContent(
                title: L10n.string("More symptom days will unlock correlations", defaultValue: "More symptom days will unlock correlations"),
                message: L10n.string(
                    "Symptom correlations and trends need about 14 tracked days. Daily symptom check-ins are the fastest way to make this tab more useful.",
                    defaultValue: "Symptom correlations and trends need about 14 tracked days. Daily symptom check-ins are the fastest way to make this tab more useful."
                )
            )
        }

        if readiness.mealDays + readiness.supplementDays + readiness.dailyLogDays + readiness.bloodSugarDays == 0 {
            return InsightEmptyStateContent(
                title: L10n.string("You have the basics covered", defaultValue: "You have the basics covered"),
                message: L10n.string(
                    "Log meals, supplements, sleep, activity, or blood sugar to unlock deeper lifestyle correlations and predictive insights.",
                    defaultValue: "Log meals, supplements, sleep, activity, or blood sugar to unlock deeper lifestyle correlations and predictive insights."
                )
            )
        }

        return InsightEmptyStateContent(
            title: L10n.string("Insights are still taking shape", defaultValue: "Insights are still taking shape"),
            message: L10n.string(
                "Keep logging consistently. As your data fills in, this tab will highlight stronger cycle and symptom patterns.",
                defaultValue: "Keep logging consistently. As your data fills in, this tab will highlight stronger cycle and symptom patterns."
            )
        )
    }

    private func prioritize(
        insights: [Insight],
        preferences: InsightAudiencePreferences
    ) -> [Insight] {
        insights.sorted { lhs, rhs in
            let lhsScore = score(for: lhs, preferences: preferences)
            let rhsScore = score(for: rhs, preferences: preferences)

            if lhsScore != rhsScore {
                return lhsScore > rhsScore
            }

            if lhs.generatedDate != rhs.generatedDate {
                return lhs.generatedDate > rhs.generatedDate
            }

            if lhs.confidence != rhs.confidence {
                return lhs.confidence > rhs.confidence
            }

            return lhs.title < rhs.title
        }
    }

    private func score(
        for insight: Insight,
        preferences: InsightAudiencePreferences
    ) -> Int {
        var score = Int((insight.confidence * 100).rounded())

        switch preferences.primaryGoal {
        case .trackCycles:
            if insight.insightType == .cyclePattern {
                score += 40
            } else if insight.insightType == .symptomCorrelation {
                score += 15
            }
        case .understandSymptoms:
            if insight.insightType == .symptomCorrelation {
                score += 40
            } else if insight.insightType == .cyclePattern {
                score += 15
            }
        case nil:
            break
        }

        if insight.actionable {
            score += 8
        }

        if preferences.experience == .newlyDiagnosed {
            score += insight.actionable ? 6 : 0
        }

        let preferredCategories = preferences.preferredCategories
        if !preferredCategories.isEmpty {
            let relatedCategories = Set(
                insight.relatedSymptoms.compactMap { symptomName in
                    SymptomType.allCases.first {
                        $0.displayName.caseInsensitiveCompare(symptomName) == .orderedSame
                    }?.category
                }
            )

            let focusMatches = relatedCategories.intersection(preferredCategories).count
            score += focusMatches * 18
        }

        return score
    }

    private func lockedPremiumCards(from premiumInsights: [Insight]) -> [PremiumInsightTeaser] {
        let grouped = Dictionary(grouping: premiumInsights, by: premiumBucket(for:))
        let teasers = grouped.keys.sorted().compactMap { bucket in
            teaser(for: bucket)
        }

        return teasers
    }

    private func premiumBucket(for insight: Insight) -> String {
        if insight.isPredictiveForecast {
            return "predictive"
        }

        switch insight.insightType {
        case .dietImpact:
            return "diet"
        case .supplementEfficacy:
            return "supplements"
        case .sleepActivity:
            return "sleep"
        case .seasonalPattern:
            return "seasonal"
        case .cyclePattern, .symptomCorrelation:
            return "predictive"
        }
    }

    private func teaser(for bucket: String) -> PremiumInsightTeaser? {
        switch bucket {
        case "predictive":
            return PremiumInsightTeaser(
                id: "premium.predictive",
                title: L10n.string("Predictive forecasts", defaultValue: "Predictive forecasts"),
                message: L10n.string(
                    "Unlock forecast ranges for cycle length and next-week symptom severity when enough data is available.",
                    defaultValue: "Unlock forecast ranges for cycle length and next-week symptom severity when enough data is available."
                )
            )
        case "diet":
            return PremiumInsightTeaser(
                id: "premium.diet",
                title: L10n.string("Meal impact insights", defaultValue: "Meal impact insights"),
                message: L10n.string(
                    "Unlock meal and glycemic impact correlations tied to your next-day symptoms.",
                    defaultValue: "Unlock meal and glycemic impact correlations tied to your next-day symptoms."
                )
            )
        case "supplements":
            return PremiumInsightTeaser(
                id: "premium.supplements",
                title: L10n.string("Supplement response insights", defaultValue: "Supplement response insights"),
                message: L10n.string(
                    "Unlock adherence and symptom-delta insights for the supplements you track.",
                    defaultValue: "Unlock adherence and symptom-delta insights for the supplements you track."
                )
            )
        case "sleep":
            return PremiumInsightTeaser(
                id: "premium.sleep",
                title: L10n.string("Sleep and activity insights", defaultValue: "Sleep and activity insights"),
                message: L10n.string(
                    "Unlock sleep, activity, and recovery patterns linked to symptom severity.",
                    defaultValue: "Unlock sleep, activity, and recovery patterns linked to symptom severity."
                )
            )
        case "seasonal":
            return PremiumInsightTeaser(
                id: "premium.seasonal",
                title: L10n.string("Seasonal pattern insights", defaultValue: "Seasonal pattern insights"),
                message: L10n.string(
                    "Unlock month-to-month symptom pattern changes as you log across seasons.",
                    defaultValue: "Unlock month-to-month symptom pattern changes as you log across seasons."
                )
            )
        default:
            return nil
        }
    }
}

extension Insight {
    var isPredictiveForecast: Bool {
        title == L10n.string("7-day symptom severity forecast", defaultValue: "7-day symptom severity forecast")
            || title == L10n.string("Cycle length forecast range", defaultValue: "Cycle length forecast range")
    }

    var isPremiumOnlyInsight: Bool {
        if isPredictiveForecast {
            return true
        }

        switch insightType {
        case .supplementEfficacy, .dietImpact, .sleepActivity, .seasonalPattern:
            return true
        case .cyclePattern, .symptomCorrelation:
            return false
        }
    }

    var isBasicFreeInsight: Bool {
        !isPremiumOnlyInsight
    }
}
