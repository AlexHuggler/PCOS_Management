import Foundation
import SwiftData
import os

@MainActor
protocol InsightGenerating {
    func generateInsights(lifecycleMode: LifecycleMode) throws -> [Insight]
}

enum InsightEngineStage: String {
    case existingInsights = "existing insights"
    case cyclePatterns = "cycle patterns"
    case symptomCorrelations = "symptom correlations"
    case symptomCorrelationCycles = "cycles for symptom correlation"
    case supplementEfficacy = "supplements"
    case supplementEfficacySymptoms = "symptoms for supplement analysis"
    case supplementEfficacyCycles = "cycles for supplement analysis"
    case dietImpact = "meals"
    case dietImpactSymptoms = "symptoms for diet impact"
    case sleepActivity = "daily logs"
    case sleepActivitySymptoms = "symptoms for sleep and activity analysis"
    case seasonalPatterns = "seasonal patterns"
    case seasonalPatternSymptoms = "symptoms for seasonal analysis"
    case predictiveCycles = "cycles for predictive forecasts"
    case predictiveDailyLogs = "daily logs for predictive forecasts"
    case predictiveMeals = "meals for predictive forecasts"
    case predictiveSupplements = "supplements for predictive forecasts"
    case predictiveBloodSugar = "blood sugar readings for predictive forecasts"
    case predictiveSymptoms = "symptoms for predictive forecasts"

    var displayName: String {
        switch self {
        case .existingInsights:
            L10n.string("existing insights", defaultValue: "existing insights")
        case .cyclePatterns:
            L10n.string("cycle patterns", defaultValue: "cycle patterns")
        case .symptomCorrelations:
            L10n.string("symptom correlations", defaultValue: "symptom correlations")
        case .symptomCorrelationCycles:
            L10n.string("cycles for symptom correlation", defaultValue: "cycles for symptom correlation")
        case .supplementEfficacy:
            L10n.string("supplements", defaultValue: "supplements")
        case .supplementEfficacySymptoms:
            L10n.string("symptoms for supplement analysis", defaultValue: "symptoms for supplement analysis")
        case .supplementEfficacyCycles:
            L10n.string("cycles for supplement analysis", defaultValue: "cycles for supplement analysis")
        case .dietImpact:
            L10n.string("meals", defaultValue: "meals")
        case .dietImpactSymptoms:
            L10n.string("symptoms for diet impact", defaultValue: "symptoms for diet impact")
        case .sleepActivity:
            L10n.string("daily logs", defaultValue: "daily logs")
        case .sleepActivitySymptoms:
            L10n.string("symptoms for sleep and activity analysis", defaultValue: "symptoms for sleep and activity analysis")
        case .seasonalPatterns:
            L10n.string("seasonal patterns", defaultValue: "seasonal patterns")
        case .seasonalPatternSymptoms:
            L10n.string("symptoms for seasonal analysis", defaultValue: "symptoms for seasonal analysis")
        case .predictiveCycles:
            L10n.string("cycles for predictive forecasts", defaultValue: "cycles for predictive forecasts")
        case .predictiveDailyLogs:
            L10n.string("daily logs for predictive forecasts", defaultValue: "daily logs for predictive forecasts")
        case .predictiveMeals:
            L10n.string("meals for predictive forecasts", defaultValue: "meals for predictive forecasts")
        case .predictiveSupplements:
            L10n.string("supplements for predictive forecasts", defaultValue: "supplements for predictive forecasts")
        case .predictiveBloodSugar:
            L10n.string("blood sugar readings for predictive forecasts", defaultValue: "blood sugar readings for predictive forecasts")
        case .predictiveSymptoms:
            L10n.string("symptoms for predictive forecasts", defaultValue: "symptoms for predictive forecasts")
        }
    }
}

enum InsightEngineError: LocalizedError {
    case fetchFailed(stage: InsightEngineStage, underlying: Error)

    var errorDescription: String? {
        switch self {
        case .fetchFailed(let stage, _):
            return L10n.format(
                "Insight generation couldn't read %@. Please try again.",
                defaultValue: "Insight generation couldn't read %@. Please try again.",
                stage.displayName
            )
        }
    }

    var recoverySuggestion: String? {
        switch self {
        case .fetchFailed:
            return L10n.string(
                "Refresh insights again in a moment.",
                defaultValue: "Refresh insights again in a moment."
            )
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
    func generateInsights(lifecycleMode: LifecycleMode = .cycling) throws -> [Insight] {
        let fetcher = InsightDataFetcher(modelContext: modelContext)
        let existingInsights: [Insight] = try fetcher.fetch(
            FetchDescriptor<Insight>(
                sortBy: [SortDescriptor(\.generatedDate, order: .reverse)]
            ),
            stage: .existingInsights
        )

        var newInsights: [Insight] = []

        // Cycle pattern analyzer: suppressed during pregnancy
        if lifecycleMode != .pregnant {
            newInsights.append(contentsOf: try CyclePatternInsightAnalyzer(fetcher: fetcher).analyze())
        }

        // Symptom correlation: active in all modes
        newInsights.append(contentsOf: try SymptomCorrelationInsightAnalyzer(fetcher: fetcher).analyze())

        // Supplement efficacy: active in all modes
        newInsights.append(contentsOf: try SupplementEfficacyInsightAnalyzer(fetcher: fetcher).analyze())

        // Diet impact: active in all modes
        newInsights.append(contentsOf: try DietImpactInsightAnalyzer(fetcher: fetcher).analyze())

        // Sleep/activity: active in all modes
        newInsights.append(contentsOf: try SleepActivityInsightAnalyzer(fetcher: fetcher).analyze())

        // Seasonal patterns: active in all modes
        newInsights.append(contentsOf: try SeasonalPatternInsightAnalyzer(fetcher: fetcher).analyze())

        // Predictive forecasts: suppressed during pregnancy
        if lifecycleMode != .pregnant {
            newInsights.append(contentsOf: try PredictiveForecastInsightAnalyzer(fetcher: fetcher).analyze())
        }

        // Filter below minimum confidence
        newInsights = newInsights.filter { $0.confidence >= Self.minimumConfidence }

        for insight in newInsights {
            InsightGuidanceCatalog.enrich(insight)
        }

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

@MainActor
private struct PredictiveForecastInsightAnalyzer {
    let fetcher: InsightDataFetcher
    let pipeline: PredictiveFeaturePipeline
    let symptomForecaster: SymptomSeverityForecasting
    let cycleForecaster: CycleLengthForecasting

    init(
        fetcher: InsightDataFetcher,
        pipeline: PredictiveFeaturePipeline = PredictiveFeaturePipeline(),
        symptomForecaster: SymptomSeverityForecasting = CoreMLSymptomSeverityForecaster(),
        cycleForecaster: CycleLengthForecasting = CoreMLCycleLengthForecaster()
    ) {
        self.fetcher = fetcher
        self.pipeline = pipeline
        self.symptomForecaster = symptomForecaster
        self.cycleForecaster = cycleForecaster
    }

    func analyze(now: Date = Date()) throws -> [Insight] {
        let calendar = Calendar.current
        let sixMonthsAgo = calendar.date(byAdding: .month, value: -6, to: now) ?? now

        let cycles: [Cycle] = try fetcher.fetch(
            FetchDescriptor<Cycle>(
                sortBy: [SortDescriptor(\.startDate, order: .forward)]
            ),
            stage: .predictiveCycles
        )
        let dailyLogs: [DailyLog] = try fetcher.fetch(
            FetchDescriptor<DailyLog>(
                predicate: #Predicate<DailyLog> { $0.date >= sixMonthsAgo },
                sortBy: [SortDescriptor(\.date, order: .forward)]
            ),
            stage: .predictiveDailyLogs
        )
        let meals: [MealEntry] = try fetcher.fetch(
            FetchDescriptor<MealEntry>(
                predicate: #Predicate<MealEntry> { $0.timestamp >= sixMonthsAgo },
                sortBy: [SortDescriptor(\.timestamp, order: .forward)]
            ),
            stage: .predictiveMeals
        )
        let supplements: [SupplementLog] = try fetcher.fetch(
            FetchDescriptor<SupplementLog>(
                predicate: #Predicate<SupplementLog> { $0.date >= sixMonthsAgo },
                sortBy: [SortDescriptor(\.date, order: .forward)]
            ),
            stage: .predictiveSupplements
        )
        let bloodSugar: [BloodSugarReading] = try fetcher.fetch(
            FetchDescriptor<BloodSugarReading>(
                predicate: #Predicate<BloodSugarReading> { $0.timestamp >= sixMonthsAgo },
                sortBy: [SortDescriptor(\.timestamp, order: .forward)]
            ),
            stage: .predictiveBloodSugar
        )
        let symptoms: [SymptomEntry] = try fetcher.fetch(
            FetchDescriptor<SymptomEntry>(
                predicate: #Predicate<SymptomEntry> { $0.date >= sixMonthsAgo },
                sortBy: [SortDescriptor(\.date, order: .forward)]
            ),
            stage: .predictiveSymptoms
        )

        var insights: [Insight] = []

        if let symptomFeatures = pipeline.buildSymptomFeatureVector(
            now: now,
            cycles: cycles,
            dailyLogs: dailyLogs,
            meals: meals,
            supplementLogs: supplements,
            bloodSugarReadings: bloodSugar
        ), symptoms.count >= 7 {
            let forecast = symptomForecaster.forecast(
                using: symptomFeatures,
                historicalSymptoms: symptoms
            )
            let predictedAverage = average(forecast.dailyPredictions) ?? 0
            let predictedMin = forecast.dailyPredictions.min() ?? predictedAverage
            let predictedMax = forecast.dailyPredictions.max() ?? predictedAverage
            let confidence = symptomConfidence(symptoms: symptoms, dailyLogs: dailyLogs)

            let topDriversScientific = forecast.featureImportance
                .prefix(3)
                .map { "\($0.name) \(Int(($0.weight * 100).rounded()))%" }
                .joined(separator: ", ")

            let topDriversFriendly = forecast.featureImportance
                .prefix(3)
                .map(\.name)
                .joined(separator: ", ")

            let severityWord = InsightNarrativeHelpers.severityWord(predictedAverage)

            insights.append(
                Insight(
                    insightType: .symptomCorrelation,
                    title: L10n.string(
                        "7-day symptom severity forecast",
                        defaultValue: "7-day symptom severity forecast"
                    ),
                    content: L10n.format(
                        "Over the next week, your symptoms may feel %@ overall. The factors that seem to matter most right now are %@ — small shifts in those areas could help.",
                        defaultValue: "Over the next week, your symptoms may feel %@ overall. The factors that seem to matter most right now are %@ — small shifts in those areas could help.",
                        severityWord,
                        topDriversFriendly
                    ),
                    scientificContent: L10n.format(
                        "Predicted symptom severity for the next 7 days averages %@/5 (range %@-%@/5). Top weighted drivers: %@. Forecast confidence: %lld%%.",
                        defaultValue: "Predicted symptom severity for the next 7 days averages %@/5 (range %@-%@/5). Top weighted drivers: %@. Forecast confidence: %lld%%.",
                        L10n.decimal(predictedAverage),
                        L10n.decimal(predictedMin),
                        L10n.decimal(predictedMax),
                        topDriversScientific,
                        Int((confidence * 100).rounded())
                    ),
                    confidence: confidence,
                    dataPointsUsed: symptoms.count + dailyLogs.count + meals.count + supplements.count + bloodSugar.count,
                    actionable: true
                )
            )
        }

        let completedCycles = cycles.filter { !$0.isPredicted && ($0.manualCycleLengthOverrideDays != nil || $0.lengthDays != nil) }
        if let cycleInput = pipeline.buildCycleForecastInput(
            now: now,
            cycles: cycles,
            dailyLogs: dailyLogs,
            supplementLogs: supplements,
            symptoms: symptoms
        ),
        completedCycles.count >= 3,
        let cycleForecast = cycleForecaster.forecast(
            cycles: cycles,
            weightTrendDelta: cycleInput.weightTrendDelta,
            activityLevelAverage: cycleInput.activityLevelAverage,
            supplementAdherencePercent: cycleInput.supplementAdherencePercent,
            averageSymptomSeverity: cycleInput.averageSymptomSeverity
        ) {
            insights.append(
                Insight(
                    insightType: .cyclePattern,
                    title: L10n.string(
                        "Cycle length forecast range",
                        defaultValue: "Cycle length forecast range"
                    ),
                    content: L10n.format(
                        "Your next cycle will likely last around %lld days, give or take a few. We'll keep refining this estimate as you log more cycles.",
                        defaultValue: "Your next cycle will likely last around %lld days, give or take a few. We'll keep refining this estimate as you log more cycles.",
                        cycleForecast.predictedLengthDays
                    ),
                    scientificContent: L10n.format(
                        "Predicted next cycle length is %lld days (range %lld-%lld days, %lld%% confidence).",
                        defaultValue: "Predicted next cycle length is %lld days (range %lld-%lld days, %lld%% confidence).",
                        cycleForecast.predictedLengthDays,
                        cycleForecast.earliestLengthDays,
                        cycleForecast.latestLengthDays,
                        Int((cycleForecast.confidence * 100).rounded())
                    ),
                    confidence: cycleForecast.confidence,
                    dataPointsUsed: completedCycles.count + dailyLogs.count + supplements.count + symptoms.count,
                    actionable: true
                )
            )
        }

        return insights
    }

    private func average(_ values: [Double]) -> Double? {
        guard !values.isEmpty else { return nil }
        return values.reduce(0, +) / Double(values.count)
    }

    private func symptomConfidence(symptoms: [SymptomEntry], dailyLogs: [DailyLog]) -> Double {
        let distinctSymptomDays = Set(symptoms.map { Calendar.current.startOfDay(for: $0.date) }).count
        let dailyLogCount = dailyLogs.count
        let base = 0.42 + (Double(distinctSymptomDays) * 0.012) + (Double(dailyLogCount) * 0.004)
        return min(0.85, max(0.4, base))
    }
}
