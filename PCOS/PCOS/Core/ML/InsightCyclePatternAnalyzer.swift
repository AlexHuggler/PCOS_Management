import Foundation
import SwiftData

@MainActor
struct CyclePatternInsightAnalyzer {
    let fetcher: InsightDataFetcher

    /// Analyzes completed cycles for regularity, length trends, and patterns.
    /// Requires at least 3 completed cycles.
    func analyze() throws -> [Insight] {
        let descriptor = FetchDescriptor<Cycle>(
            sortBy: [SortDescriptor(\.startDate, order: .forward)]
        )
        let cycles: [Cycle] = try fetcher.fetch(descriptor, stage: .cyclePatterns)

        let completedCycles = cycles.filter { $0.lengthDays != nil && !$0.isPredicted }
        guard completedCycles.count >= InsightThresholds.completedCyclesForCyclePatterns else { return [] }

        let lengths = completedCycles.compactMap { $0.lengthDays }
        guard !lengths.isEmpty else { return [] }

        var insights: [Insight] = []
        let mean = Double(lengths.reduce(0, +)) / Double(lengths.count)
        let variance = lengths.count > 1
            ? lengths.map { pow(Double($0) - mean, 2) }.reduce(0, +) / Double(lengths.count - 1)
            : 0.0
        let stddev = sqrt(variance)
        let cv = mean > 0 ? stddev / mean : 0.0

        // Regularity insight
        let regularityInsight: Insight
        let dataPoints = lengths.count

        if cv < 0.1 {
            let confidence = min(0.5 + Double(dataPoints) * 0.05, 0.95)
            regularityInsight = Insight(
                insightType: .cyclePattern,
                title: L10n.string(
                    "Your cycles are regular",
                    defaultValue: "Your cycles are regular"
                ),
                content: L10n.format(
                    "Your cycles average %@ days with low variation. This consistency is a positive sign for tracking and planning.",
                    defaultValue: "Your cycles average %@ days with low variation. This consistency is a positive sign for tracking and planning.",
                    formatDays(mean)
                ),
                confidence: confidence,
                dataPointsUsed: dataPoints,
                actionable: false
            )
        } else if cv < 0.2 {
            let confidence = min(0.4 + Double(dataPoints) * 0.05, 0.85)
            regularityInsight = Insight(
                insightType: .cyclePattern,
                title: L10n.string(
                    "Your cycles are somewhat irregular",
                    defaultValue: "Your cycles are somewhat irregular"
                ),
                content: L10n.format(
                    "Your cycles tend to land around %@ days, though they still shift by a few days. That makes this a pattern worth watching so you can spot what tends to move your cycle around.",
                    defaultValue: "Your cycles tend to land around %@ days, though they still shift by a few days. That makes this a pattern worth watching so you can spot what tends to move your cycle around.",
                    formatDays(mean)
                ),
                scientificContent: L10n.format(
                    "Your cycles average %@ days but vary by about %@ days. Continued tracking can help you compare those shifts with changes in symptoms, stress, meals, or supplements.",
                    defaultValue: "Your cycles average %@ days but vary by about %@ days. Continued tracking can help you compare those shifts with changes in symptoms, stress, meals, or supplements.",
                    formatDays(mean),
                    formatDays(stddev)
                ),
                confidence: confidence,
                dataPointsUsed: dataPoints,
                actionable: true
            )
        } else {
            let confidence = min(0.4 + Double(dataPoints) * 0.04, 0.80)
            regularityInsight = Insight(
                insightType: .cyclePattern,
                title: L10n.string(
                    "Your cycles are irregular",
                    defaultValue: "Your cycles are irregular"
                ),
                content: L10n.string(
                    "Your cycle lengths have been spread out — sometimes shorter, sometimes much longer. That is a big enough swing to keep an eye on, especially if the pattern keeps changing.",
                    defaultValue: "Your cycle lengths have been spread out — sometimes shorter, sometimes much longer. That is a big enough swing to keep an eye on, especially if the pattern keeps changing."
                ),
                scientificContent: L10n.format(
                    "Your cycles average %@ days with a wide range of %lld-%lld days. If that spread keeps shifting, it may be worth bringing to your provider along with your log history.",
                    defaultValue: "Your cycles average %@ days with a wide range of %lld-%lld days. If that spread keeps shifting, it may be worth bringing to your provider along with your log history.",
                    formatDays(mean),
                    lengths.min() ?? 0,
                    lengths.max() ?? 0
                ),
                confidence: confidence,
                dataPointsUsed: dataPoints,
                actionable: true
            )
        }
        insights.append(regularityInsight)

        // Length trend: compare recent 3 vs overall average
        if completedCycles.count >= 4 {
            let recentLengths = Array(lengths.suffix(3))
            let recentMean = Double(recentLengths.reduce(0, +)) / Double(recentLengths.count)
            let difference = recentMean - mean

            if abs(difference) >= 2.0 {
                let confidence = min(0.35 + Double(dataPoints) * 0.04, 0.75)

                let trendInsight = Insight(
                    insightType: .cyclePattern,
                    title: L10n.string(
                        difference > 0
                            ? "Your recent cycles are getting longer"
                            : "Your recent cycles are getting shorter",
                        defaultValue: difference > 0
                            ? "Your recent cycles are getting longer"
                            : "Your recent cycles are getting shorter"
                    ),
                    content: L10n.format(
                        difference > 0
                            ? "Your last 3 cycles averaged %@ days, compared to your overall average of %@ days. A lengthening trend may be worth mentioning to your healthcare provider if it continues."
                            : "Your last 3 cycles averaged %@ days, compared to your overall average of %@ days. A shortening trend may be worth mentioning to your healthcare provider if it continues.",
                        defaultValue: difference > 0
                            ? "Your last 3 cycles averaged %@ days, compared to your overall average of %@ days. A lengthening trend may be worth mentioning to your healthcare provider if it continues."
                            : "Your last 3 cycles averaged %@ days, compared to your overall average of %@ days. A shortening trend may be worth mentioning to your healthcare provider if it continues.",
                        formatDays(recentMean),
                        formatDays(mean)
                    ),
                    confidence: confidence,
                    dataPointsUsed: dataPoints,
                    actionable: true,
                    relatedSymptoms: []
                )
                insights.append(trendInsight)
            }
        }

        return insights
    }

    /// Format a Double as a whole number of days.
    private func formatDays(_ value: Double) -> String {
        L10n.decimal(value, fractionDigits: 0)
    }
}
