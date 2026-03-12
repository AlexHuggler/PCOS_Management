import Foundation
import SwiftData
import os

@MainActor
protocol InsightGenerating {
    func generateInsights() throws -> [Insight]
}

enum InsightEngineStage: String {
    case existingInsights = "existing insights"
    case cyclePatterns = "cycle patterns"
    case symptomCorrelations = "symptom correlations"
    case symptomCorrelationCycles = "cycles for symptom correlation"
    case supplementEfficacy = "supplements"
    case supplementEfficacySymptoms = "symptoms for supplement analysis"
    case dietImpact = "meals"
    case dietImpactSymptoms = "symptoms for diet impact"
    case sleepActivity = "daily logs"
    case sleepActivitySymptoms = "symptoms for sleep and activity analysis"
}

enum InsightEngineError: LocalizedError {
    case fetchFailed(stage: InsightEngineStage, underlying: Error)

    var errorDescription: String? {
        switch self {
        case .fetchFailed(let stage, _):
            return "Insight generation couldn't read \(stage.rawValue). Please try again."
        }
    }

    var recoverySuggestion: String? {
        switch self {
        case .fetchFailed:
            return "Refresh insights again in a moment."
        }
    }
}

/// On-device insight generation engine that analyzes cycle, symptom, supplement,
/// diet, and lifestyle data to surface actionable PCOS management insights.
///
/// All analysis runs locally — no data leaves the device.
@MainActor
struct InsightEngine: InsightGenerating {
    let modelContext: ModelContext

    private static let minimumConfidence = 0.3
    private static let deduplicationWindowDays = 7
    private static let insightExpirationDays = 90

    /// Run all analyzers, deduplicate against existing insights, and return new insights.
    func generateInsights() throws -> [Insight] {
        let fetcher = InsightDataFetcher(modelContext: modelContext)
        let existingInsights: [Insight] = try fetcher.fetch(
            FetchDescriptor<Insight>(
                sortBy: [SortDescriptor(\.generatedDate, order: .reverse)]
            ),
            stage: .existingInsights
        )

        var newInsights: [Insight] = []
        newInsights.append(contentsOf: try CyclePatternInsightAnalyzer(fetcher: fetcher).analyze())
        newInsights.append(contentsOf: try SymptomCorrelationInsightAnalyzer(fetcher: fetcher).analyze())
        newInsights.append(contentsOf: try SupplementEfficacyInsightAnalyzer(fetcher: fetcher).analyze())
        newInsights.append(contentsOf: try DietImpactInsightAnalyzer(fetcher: fetcher).analyze())
        newInsights.append(contentsOf: try SleepActivityInsightAnalyzer(fetcher: fetcher).analyze())

        // Filter below minimum confidence
        newInsights = newInsights.filter { $0.confidence >= Self.minimumConfidence }

        // Deduplicate and clean old insights
        let deduplicator = InsightDeduplicator(
            modelContext: modelContext,
            deduplicationWindowDays: Self.deduplicationWindowDays,
            insightExpirationDays: Self.insightExpirationDays
        )

        return deduplicator.deduplicateAndClean(
            newInsights: newInsights,
            existingInsights: existingInsights
        )
    }
}
