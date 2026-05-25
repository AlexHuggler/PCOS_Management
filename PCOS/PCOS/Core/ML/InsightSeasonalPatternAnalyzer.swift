import Foundation
import SwiftData

@MainActor
struct SeasonalPatternInsightAnalyzer {
    let fetcher: InsightDataFetcher

    /// Detects symptom severity shifts across calendar months.
    /// Requires at least 90 days of symptom data.
    func analyze() throws -> [Insight] {
        let oneYearAgo = Calendar.current.date(byAdding: .day, value: -365, to: Date()) ?? Date()
        let descriptor = FetchDescriptor<SymptomEntry>(
            predicate: #Predicate<SymptomEntry> { entry in
                entry.date >= oneYearAgo
            },
            sortBy: [SortDescriptor(\.date, order: .forward)]
        )
        let symptoms: [SymptomEntry] = try fetcher.fetch(descriptor, stage: .seasonalPatternSymptoms)

        guard symptoms.count >= 30 else { return [] }

        let calendar = Calendar.current
        let trackedDays = Set(symptoms.map { calendar.startOfDay(for: $0.date) })
        guard trackedDays.count >= 90 else { return [] }

        var byMonth: [Int: [SymptomEntry]] = [:]
        for entry in symptoms {
            let month = calendar.component(.month, from: entry.date)
            byMonth[month, default: []].append(entry)
        }

        let monthStats = byMonth.compactMap { month, entries -> (month: Int, avgSeverity: Double, count: Int)? in
            guard entries.count >= 5 else { return nil }
            let avg = Double(entries.map(\.severity).reduce(0, +)) / Double(entries.count)
            return (month: month, avgSeverity: avg, count: entries.count)
        }

        guard monthStats.count >= 3 else { return [] }
        guard let highest = monthStats.max(by: { $0.avgSeverity < $1.avgSeverity }),
              let lowest = monthStats.min(by: { $0.avgSeverity < $1.avgSeverity }) else {
            return []
        }

        let delta = highest.avgSeverity - lowest.avgSeverity
        guard delta >= 0.5 else { return [] }

        let confidence = min(
            0.82,
            0.35 + (Double(symptoms.count) / 220.0) + (delta * 0.12)
        )

        let insight = Insight(
            insightType: .seasonalPattern,
            title: L10n.string(
                "Symptoms vary by season",
                defaultValue: "Symptoms vary by season"
            ),
            content: L10n.format(
                "Your symptoms tend to be stronger around %@ and calmer around %@. Planning ahead — adjusting sleep, diet, or supplements before tougher months — could help you feel more prepared.",
                defaultValue: "Your symptoms tend to be stronger around %@ and calmer around %@. Planning ahead — adjusting sleep, diet, or supplements before tougher months — could help you feel more prepared.",
                monthName(highest.month),
                monthName(lowest.month)
            ),
            scientificContent: L10n.format(
                "Your average symptom severity is highest in %@ (%@/5) and lowest in %@ (%@/5), a %@-point difference. Consider pre-planning routines before higher-symptom months.",
                defaultValue: "Your average symptom severity is highest in %@ (%@/5) and lowest in %@ (%@/5), a %@-point difference. Consider pre-planning routines before higher-symptom months.",
                monthName(highest.month),
                L10n.decimal(highest.avgSeverity),
                monthName(lowest.month),
                L10n.decimal(lowest.avgSeverity),
                L10n.decimal(delta)
            ),
            confidence: confidence,
            dataPointsUsed: symptoms.count,
            actionable: true
        )

        return [insight]
    }

    private func monthName(_ month: Int) -> String {
        let formatter = DateFormatter()
        formatter.locale = L10n.locale()
        return formatter.monthSymbols[max(min(month - 1, 11), 0)]
    }
}
