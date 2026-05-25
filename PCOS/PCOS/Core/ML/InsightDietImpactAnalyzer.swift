import Foundation
import SwiftData

@MainActor
struct DietImpactInsightAnalyzer {
    let fetcher: InsightDataFetcher

    /// Quantitative-only diet insights with explicit deltas, lag windows,
    /// confidence, and sample-size gates.
    func analyze() throws -> [Insight] {
        let mealDescriptor = FetchDescriptor<MealEntry>(
            sortBy: [SortDescriptor(\.timestamp, order: .forward)]
        )
        let meals: [MealEntry] = try fetcher.fetch(mealDescriptor, stage: .dietImpact)

        guard meals.count >= 7 else { return [] }

        let calendar = Calendar.current
        let mealDays = Set(meals.map { calendar.startOfDay(for: $0.timestamp) })
        guard mealDays.count >= 7 else { return [] }

        var insights: [Insight] = []

        let giCounts: [GlycemicImpact: Int] = Dictionary(grouping: meals, by: \.glycemicImpact).mapValues(\.count)
        let totalMeals = meals.count
        let highGICount = giCounts[.high] ?? 0
        let lowGICount = giCounts[.low] ?? 0
        let highGIRatio = Double(highGICount) / Double(totalMeals)
        let lowGIRatio = Double(lowGICount) / Double(totalMeals)

        let earliestMeal = meals.first?.timestamp ?? Date()
        let symptomDescriptor = FetchDescriptor<SymptomEntry>(
            predicate: #Predicate<SymptomEntry> { $0.date >= earliestMeal },
            sortBy: [SortDescriptor(\.date, order: .forward)]
        )
        let symptoms: [SymptomEntry] = try fetcher.fetch(symptomDescriptor, stage: .dietImpactSymptoms)
        let symptomsByDay = Dictionary(grouping: symptoms) { calendar.startOfDay(for: $0.date) }
        let mealsByDay = Dictionary(grouping: meals) { calendar.startOfDay(for: $0.timestamp) }

        var nextDayHighGICohort: [Double] = []
        var nextDayLowGICohort: [Double] = []

        var breakoutLag2HighGICohort: [Double] = []
        var breakoutLag2LowGICohort: [Double] = []
        var breakoutLag3HighGICohort: [Double] = []
        var breakoutLag3LowGICohort: [Double] = []

        for (day, dayMeals) in mealsByDay {
            let highCount = dayMeals.filter { $0.glycemicImpact == .high }.count
            let lowCount = dayMeals.filter { $0.glycemicImpact == .low }.count

            let cohort: GlycemicImpact
            if highCount > lowCount {
                cohort = .high
            } else if lowCount > highCount {
                cohort = .low
            } else {
                continue
            }

            if let nextDay = calendar.date(byAdding: .day, value: 1, to: day),
               let nextDaySymptoms = symptomsByDay[nextDay],
               !nextDaySymptoms.isEmpty {
                let nextDaySeverity = average(nextDaySymptoms.map { Double($0.severity) })
                if cohort == .high {
                    nextDayHighGICohort.append(nextDaySeverity)
                } else {
                    nextDayLowGICohort.append(nextDaySeverity)
                }
            }

            for lag in [2, 3] {
                guard let lagDay = calendar.date(byAdding: .day, value: lag, to: day),
                      let daySymptoms = symptomsByDay[lagDay] else { continue }

                let lagBreakoutSymptoms = daySymptoms.filter { $0.symptomType == .acne || $0.symptomType == .breakouts }
                guard !lagBreakoutSymptoms.isEmpty else { continue }

                let lagSeverity = average(lagBreakoutSymptoms.map { Double($0.severity) })

                if cohort == .high {
                    if lag == 2 {
                        breakoutLag2HighGICohort.append(lagSeverity)
                    } else {
                        breakoutLag3HighGICohort.append(lagSeverity)
                    }
                } else if lag == 2 {
                    breakoutLag2LowGICohort.append(lagSeverity)
                } else {
                    breakoutLag3LowGICohort.append(lagSeverity)
                }
            }
        }

        if nextDayHighGICohort.count >= 3, nextDayLowGICohort.count >= 3 {
            let highAvg = average(nextDayHighGICohort)
            let lowAvg = average(nextDayLowGICohort)
            let delta = highAvg - lowAvg

            if delta >= 0.4 {
                let sampleCount = nextDayHighGICohort.count + nextDayLowGICohort.count
                let confidence = min(0.86, max(0.45, 0.50 + Double(sampleCount) * 0.02 + delta * 0.05))
                let diffWord = InsightNarrativeHelpers.differenceWord(delta)

                insights.append(
                    Insight(
                        insightType: .dietImpact,
                        title: L10n.string(
                            "High-GI meals align with higher next-day symptom severity",
                            defaultValue: "High-GI meals align with higher next-day symptom severity"
                        ),
                        content: L10n.format(
                            "Your symptoms tend to feel %@ worse the day after meals that spike blood sugar. That makes steadier meal choices worth experimenting with in your routine.",
                            defaultValue: "Your symptoms tend to feel %@ worse the day after meals that spike blood sugar. That makes steadier meal choices worth experimenting with in your routine.",
                            diffWord
                        ),
                        scientificContent: L10n.format(
                            "The day after high-GI meals, your symptom severity averaged %@/5, compared to %@/5 after low-GI days. This gives you a concrete meal pattern to keep testing.",
                            defaultValue: "The day after high-GI meals, your symptom severity averaged %@/5, compared to %@/5 after low-GI days. This gives you a concrete meal pattern to keep testing.",
                            L10n.decimal(highAvg),
                            L10n.decimal(lowAvg)
                        ),
                        confidence: confidence,
                        dataPointsUsed: sampleCount,
                        actionable: true
                    )
                )
            }
        }

        struct BreakoutLagCandidate {
            let lagWindowLabel: String
            let highAvg: Double
            let lowAvg: Double
            let delta: Double
            let sampleCount: Int
            let confidence: Double
        }

        func buildBreakoutLagCandidate(
            highCohort: [Double],
            lowCohort: [Double],
            lagWindowLabel: String
        ) -> BreakoutLagCandidate? {
            guard highCohort.count >= 4, lowCohort.count >= 4 else { return nil }
            let highAvg = average(highCohort)
            let lowAvg = average(lowCohort)
            let delta = highAvg - lowAvg
            guard delta >= 0.35 else { return nil }

            let sampleCount = highCohort.count + lowCohort.count
            let confidence = min(0.88, max(0.50, 0.54 + Double(sampleCount) * 0.02 + delta * 0.06))

            return BreakoutLagCandidate(
                lagWindowLabel: lagWindowLabel,
                highAvg: highAvg,
                lowAvg: lowAvg,
                delta: delta,
                sampleCount: sampleCount,
                confidence: confidence
            )
        }

        let lagCandidates = [
            buildBreakoutLagCandidate(
                highCohort: breakoutLag2HighGICohort,
                lowCohort: breakoutLag2LowGICohort,
                lagWindowLabel: "2 days"
            ),
            buildBreakoutLagCandidate(
                highCohort: breakoutLag3HighGICohort,
                lowCohort: breakoutLag3LowGICohort,
                lagWindowLabel: "3 days"
            ),
        ].compactMap { $0 }

        if let bestLag = lagCandidates.max(by: { $0.delta < $1.delta }) {
            insights.append(
                Insight(
                    insightType: .dietImpact,
                    title: L10n.string(
                        "Acne breakouts correlate with high-GI meals 2-3 days prior",
                        defaultValue: "Acne breakouts correlate with high-GI meals 2-3 days prior"
                    ),
                    content: L10n.string(
                        "Your skin looks more reactive a couple of days after higher-GI meals. That gives you a useful food-and-skin pattern to keep an eye on.",
                        defaultValue: "Your skin looks more reactive a couple of days after higher-GI meals. That gives you a useful food-and-skin pattern to keep an eye on."
                    ),
                    scientificContent: L10n.format(
                        "About %@ after high-GI meals, breakout severity averaged %@/5, compared to %@/5 after low-GI days. That lag gives you a concrete window to compare against future logs.",
                        defaultValue: "About %@ after high-GI meals, breakout severity averaged %@/5, compared to %@/5 after low-GI days. That lag gives you a concrete window to compare against future logs.",
                        bestLag.lagWindowLabel,
                        L10n.decimal(bestLag.highAvg),
                        L10n.decimal(bestLag.lowAvg)
                    ),
                    confidence: bestLag.confidence,
                    dataPointsUsed: bestLag.sampleCount,
                    actionable: true,
                    relatedSymptoms: [SymptomType.acne.displayName, SymptomType.breakouts.displayName]
                )
            )
        }

        if highGIRatio > 0.4 {
            let confidence = min(0.75, max(0.4, 0.45 + Double(totalMeals) * 0.01))
            insights.append(
                Insight(
                    insightType: .dietImpact,
                    title: L10n.string(
                        "Many of your meals are high-GI",
                        defaultValue: "Many of your meals are high-GI"
                    ),
                    content: L10n.string(
                        "A good portion of your recent meals have been on the higher-GI side. Even a few steadier swaps could be worth trying if you want to see whether symptoms settle down.",
                        defaultValue: "A good portion of your recent meals have been on the higher-GI side. Even a few steadier swaps could be worth trying if you want to see whether symptoms settle down."
                    ),
                    scientificContent: L10n.format(
                        "%lld%% of your logged meals were high GI. That gives you a clear baseline to compare against future symptom changes.",
                        defaultValue: "%lld%% of your logged meals were high GI. That gives you a clear baseline to compare against future symptom changes.",
                        Int((highGIRatio * 100).rounded())
                    ),
                    confidence: confidence,
                    dataPointsUsed: totalMeals,
                    actionable: true
                )
            )
        } else if lowGIRatio > 0.6 {
            let confidence = min(0.8, max(0.45, 0.50 + Double(totalMeals) * 0.01))
            insights.append(
                Insight(
                    insightType: .dietImpact,
                    title: L10n.string(
                        "Your diet is mostly low-GI",
                        defaultValue: "Your diet is mostly low-GI"
                    ),
                    content: L10n.string(
                        "Most of your recent meals have been low-GI. That gives you a steadier baseline, so it is worth keeping up and comparing with future symptom trends.",
                        defaultValue: "Most of your recent meals have been low-GI. That gives you a steadier baseline, so it is worth keeping up and comparing with future symptom trends."
                    ),
                    scientificContent: L10n.format(
                        "%lld%% of your logged meals were low GI. That gives you a strong baseline if you want to compare future changes in symptoms or energy.",
                        defaultValue: "%lld%% of your logged meals were low GI. That gives you a strong baseline if you want to compare future changes in symptoms or energy.",
                        Int((lowGIRatio * 100).rounded())
                    ),
                    confidence: confidence,
                    dataPointsUsed: totalMeals,
                    actionable: false
                )
            )
        }

        return insights
    }

    private func average(_ values: [Double]) -> Double {
        values.reduce(0, +) / Double(values.count)
    }
}
