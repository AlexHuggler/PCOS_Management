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
        guard completedCycles.count >= 3 else { return [] }

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
                title: "Your cycles are regular",
                content: "Your cycles average \(formatDays(mean)) days with low variation. "
                    + "This consistency is a positive sign for tracking and planning.",
                confidence: confidence,
                dataPointsUsed: dataPoints,
                actionable: false
            )
        } else if cv < 0.2 {
            let confidence = min(0.4 + Double(dataPoints) * 0.05, 0.85)
            regularityInsight = Insight(
                insightType: .cyclePattern,
                title: "Your cycles are somewhat irregular",
                content: "Your cycles average \(formatDays(mean)) days but vary by about "
                    + "\(formatDays(stddev)) days. Some variation is common with PCOS. "
                    + "Consistent tracking helps identify what influences your cycle length.",
                confidence: confidence,
                dataPointsUsed: dataPoints,
                actionable: true
            )
        } else {
            let confidence = min(0.4 + Double(dataPoints) * 0.04, 0.80)
            regularityInsight = Insight(
                insightType: .cyclePattern,
                title: "Your cycles are irregular",
                content: "Your cycles average \(formatDays(mean)) days with significant variation "
                    + "(range: \(lengths.min()!)-\(lengths.max()!) days). Irregular cycles are common "
                    + "with PCOS. Consider discussing cycle-regulating strategies with your provider.",
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
                let direction = difference > 0 ? "longer" : "shorter"
                let trend = difference > 0 ? "lengthening" : "shortening"
                let confidence = min(0.35 + Double(dataPoints) * 0.04, 0.75)

                let trendInsight = Insight(
                    insightType: .cyclePattern,
                    title: "Your recent cycles are getting \(direction)",
                    content: "Your last 3 cycles averaged \(formatDays(recentMean)) days, compared to "
                        + "your overall average of \(formatDays(mean)) days. A \(trend) trend may be "
                        + "worth mentioning to your healthcare provider if it continues.",
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
        String(format: "%.0f", value)
    }
}
