import Foundation
import SwiftData

@MainActor
struct SleepActivityInsightAnalyzer {
    let fetcher: InsightDataFetcher

    /// Correlates sleep hours and activity with symptom severity.
    /// Requires at least 7 days of DailyLog data.
    func analyze() throws -> [Insight] {
        let logDescriptor = FetchDescriptor<DailyLog>(
            sortBy: [SortDescriptor(\.date, order: .forward)]
        )
        let dailyLogs: [DailyLog] = try fetcher.fetch(logDescriptor, stage: .sleepActivity)

        let logsWithSleep = dailyLogs.filter { $0.sleepHours != nil }
        guard logsWithSleep.count >= 7 else { return [] }

        let calendar = Calendar.current
        var insights: [Insight] = []

        // Fetch symptoms for the same period
        let earliestLog = logsWithSleep.first?.date ?? Date()
        let symptomDescriptor = FetchDescriptor<SymptomEntry>(
            predicate: #Predicate<SymptomEntry> { $0.date >= earliestLog },
            sortBy: [SortDescriptor(\.date, order: .forward)]
        )
        let symptoms: [SymptomEntry] = try fetcher.fetch(symptomDescriptor, stage: .sleepActivitySymptoms)
        let symptomsByDay = Dictionary(grouping: symptoms) { calendar.startOfDay(for: $0.date) }

        // Correlate sleep hours with next-day symptom severity
        var lowSleepSeverities: [Double] = []
        var goodSleepSeverities: [Double] = []
        let sleepThreshold = 7.0

        for log in logsWithSleep {
            guard let sleepHours = log.sleepHours else { continue }
            let logDay = calendar.startOfDay(for: log.date)
            guard let nextDay = calendar.date(byAdding: .day, value: 1, to: logDay),
                  let nextDaySymptoms = symptomsByDay[nextDay],
                  !nextDaySymptoms.isEmpty else { continue }

            let avgSeverity = Double(nextDaySymptoms.map(\.severity).reduce(0, +))
                / Double(nextDaySymptoms.count)

            if sleepHours < sleepThreshold {
                lowSleepSeverities.append(avgSeverity)
            } else {
                goodSleepSeverities.append(avgSeverity)
            }
        }

        if lowSleepSeverities.count >= 3, goodSleepSeverities.count >= 3 {
            let lowSleepAvg = lowSleepSeverities.reduce(0, +) / Double(lowSleepSeverities.count)
            let goodSleepAvg = goodSleepSeverities.reduce(0, +) / Double(goodSleepSeverities.count)
            let diff = lowSleepAvg - goodSleepAvg

            if diff > 0.5 {
                let totalPoints = lowSleepSeverities.count + goodSleepSeverities.count
                let confidence = min(0.35 + Double(totalPoints) * 0.02, 0.75)
                let diffWord = InsightNarrativeHelpers.differenceWord(diff)
                let insight = Insight(
                    insightType: .sleepActivity,
                    title: L10n.string(
                        "Less sleep, more symptoms",
                        defaultValue: "Less sleep, more symptoms"
                    ),
                    content: L10n.format(
                        "Your body seems to respond to sleep — after shorter nights, your symptoms tend to feel %@ worse. Sleep looks like one of the stronger levers in your recent data.",
                        defaultValue: "Your body seems to respond to sleep — after shorter nights, your symptoms tend to feel %@ worse. Sleep looks like one of the stronger levers in your recent data.",
                        diffWord
                    ),
                    scientificContent: L10n.format(
                        "After nights with less than %lld hours of sleep, your symptom severity averages %@/5, compared to %@/5 after better sleep. That difference is large enough to keep watching.",
                        defaultValue: "After nights with less than %lld hours of sleep, your symptom severity averages %@/5, compared to %@/5 after better sleep. That difference is large enough to keep watching.",
                        Int(sleepThreshold),
                        L10n.decimal(lowSleepAvg),
                        L10n.decimal(goodSleepAvg)
                    ),
                    confidence: confidence,
                    dataPointsUsed: totalPoints,
                    actionable: true
                )
                insights.append(insight)
            }
        }

        // Energy level patterns
        let logsWithEnergy = dailyLogs.filter { $0.energyLevel != nil }
        if logsWithEnergy.count >= 7 {
            let energyLevels = logsWithEnergy.compactMap(\.energyLevel)
            let avgEnergy = Double(energyLevels.reduce(0, +)) / Double(energyLevels.count)

            // Check for energy trend over time
            let midpoint = logsWithEnergy.count / 2
            let firstHalf = Array(logsWithEnergy.prefix(midpoint)).compactMap(\.energyLevel)
            let secondHalf = Array(logsWithEnergy.suffix(from: midpoint)).compactMap(\.energyLevel)

            if !firstHalf.isEmpty, !secondHalf.isEmpty {
                let firstAvg = Double(firstHalf.reduce(0, +)) / Double(firstHalf.count)
                let secondAvg = Double(secondHalf.reduce(0, +)) / Double(secondHalf.count)
                let diff = secondAvg - firstAvg

                if abs(diff) >= 0.5 {
                    let confidence = min(0.3 + Double(logsWithEnergy.count) * 0.02, 0.65)
                    let friendlyContent = diff > 0
                        ? L10n.string(
                            "Your energy has been trending upward recently — whatever you've been doing seems to be working. Keep it up!",
                            defaultValue: "Your energy has been trending upward recently — whatever you've been doing seems to be working. Keep it up!"
                        )
                        : L10n.string(
                            "Your energy has been dipping recently. It might be worth looking at changes to your sleep, activity, or routine to see what's shifted.",
                            defaultValue: "Your energy has been dipping recently. It might be worth looking at changes to your sleep, activity, or routine to see what's shifted."
                        )
                    let insight = Insight(
                        insightType: .sleepActivity,
                        title: L10n.string(
                            diff > 0
                                ? "Your energy levels are improving"
                                : "Your energy levels are declining",
                            defaultValue: diff > 0
                                ? "Your energy levels are improving"
                                : "Your energy levels are declining"
                        ),
                        content: friendlyContent,
                        scientificContent: L10n.format(
                            "Your average energy level has gone from %@ to %@ (out of 5) over your tracking period. Average energy: %@/5.",
                            defaultValue: "Your average energy level has gone from %@ to %@ (out of 5) over your tracking period. Average energy: %@/5.",
                            L10n.decimal(firstAvg),
                            L10n.decimal(secondAvg),
                            L10n.decimal(avgEnergy)
                        ),
                        confidence: confidence,
                        dataPointsUsed: logsWithEnergy.count,
                        actionable: diff < 0
                    )
                    insights.append(insight)
                }
            }
        }

        return insights
    }
}
