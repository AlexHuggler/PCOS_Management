import Foundation
import SwiftData

@MainActor
struct SupplementEfficacyInsightAnalyzer {
    let fetcher: InsightDataFetcher

    /// Compares symptom severity on days supplements were taken vs missed.
    /// Requires at least 14 days of supplement + symptom data.
    func analyze() throws -> [Insight] {
        let supplementDescriptor = FetchDescriptor<SupplementLog>(
            sortBy: [SortDescriptor(\.date, order: .forward)]
        )
        let supplements: [SupplementLog] = try fetcher.fetch(supplementDescriptor, stage: .supplementEfficacy)

        guard supplements.count >= 14 else { return [] }

        let calendar = Calendar.current
        let earliestSupplement = supplements.first?.date ?? Date()
        let symptomDescriptor = FetchDescriptor<SymptomEntry>(
            predicate: #Predicate<SymptomEntry> { $0.date >= earliestSupplement },
            sortBy: [SortDescriptor(\.date, order: .forward)]
        )

        let symptoms: [SymptomEntry] = try fetcher.fetch(
            symptomDescriptor,
            stage: .supplementEfficacySymptoms
        )

        guard !symptoms.isEmpty else { return [] }

        var insights: [Insight] = []

        // Group supplements by name
        let byName = Dictionary(grouping: supplements, by: \.supplementName)
        let symptomsByDay = Dictionary(grouping: symptoms) { calendar.startOfDay(for: $0.date) }

        for (name, logs) in byName {
            let takenDays = Set(logs.filter(\.taken).map { calendar.startOfDay(for: $0.date) })
            let missedDays = Set(logs.filter { !$0.taken }.map { calendar.startOfDay(for: $0.date) })

            guard takenDays.count >= 5, missedDays.count >= 3 else { continue }

            // Average symptom severity on taken vs missed days
            let takenSeverities = takenDays.compactMap { day -> Double? in
                guard let daySymptoms = symptomsByDay[day], !daySymptoms.isEmpty else { return nil }
                return Double(daySymptoms.map(\.severity).reduce(0, +)) / Double(daySymptoms.count)
            }
            let missedSeverities = missedDays.compactMap { day -> Double? in
                guard let daySymptoms = symptomsByDay[day], !daySymptoms.isEmpty else { return nil }
                return Double(daySymptoms.map(\.severity).reduce(0, +)) / Double(daySymptoms.count)
            }

            guard !takenSeverities.isEmpty, !missedSeverities.isEmpty else { continue }

            let takenAvg = takenSeverities.reduce(0, +) / Double(takenSeverities.count)
            let missedAvg = missedSeverities.reduce(0, +) / Double(missedSeverities.count)
            let difference = missedAvg - takenAvg

            // Only report meaningful differences (>0.5 severity points)
            guard abs(difference) > 0.5 else { continue }

            let totalDataPoints = takenDays.count + missedDays.count
            let confidence = min(0.3 + Double(totalDataPoints) * 0.02, 0.75)

            if difference > 0 {
                let insight = Insight(
                    insightType: .supplementEfficacy,
                    title: "\(name) may be helping",
                    content: "On days you take \(name), your average symptom severity is "
                        + "\(String(format: "%.1f", takenAvg))/5, compared to \(String(format: "%.1f", missedAvg))/5 "
                        + "on days you miss it. This \(String(format: "%.1f", difference))-point difference suggests "
                        + "a potential benefit.",
                    confidence: confidence,
                    dataPointsUsed: totalDataPoints,
                    actionable: true
                )
                insights.append(insight)
            } else {
                let insight = Insight(
                    insightType: .supplementEfficacy,
                    title: "No clear benefit from \(name)",
                    content: "Your symptom severity doesn't appear lower on days you take \(name) "
                        + "(taken: \(String(format: "%.1f", takenAvg))/5 vs missed: "
                        + "\(String(format: "%.1f", missedAvg))/5). Consider discussing this with your provider.",
                    confidence: confidence,
                    dataPointsUsed: totalDataPoints,
                    actionable: true
                )
                insights.append(insight)
            }
        }

        return insights
    }
}
