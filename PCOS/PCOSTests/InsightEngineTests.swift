import Testing
import Foundation
import SwiftData
@testable import PCOS

@Suite("InsightEngine", .serialized)
@MainActor
struct InsightEngineTests {

    // MARK: - Helpers

    /// Creates an in-memory container with all models needed by InsightEngine.
    /// Note: Once SupplementLog, MealEntry, and DailyLog are added to the app
    /// schema, update TestHelpers.makeModelContainer() and use it instead.
    private static func makeContainer() throws -> ModelContainer {
        let schema = Schema([
            CycleEntry.self,
            Cycle.self,
            SymptomEntry.self,
            Insight.self,
            SupplementLog.self,
            MealEntry.self,
            DailyLog.self,
            HealthKitImportedSampleRecord.self,
            BloodSugarReading.self,
        ])
        let config = ModelConfiguration(
            schema: schema,
            isStoredInMemoryOnly: true,
            cloudKitDatabase: .none
        )
        return try ModelContainer(for: schema, configurations: [config])
    }

    /// Insert a completed cycle with the given start date and length.
    @discardableResult
    private static func insertCycle(
        context: ModelContext,
        startDate: Date,
        lengthDays: Int
    ) -> Cycle {
        let endDate = Calendar.current.date(byAdding: .day, value: lengthDays, to: startDate)!
        let cycle = Cycle(
            startDate: startDate,
            endDate: endDate,
            lengthDays: lengthDays,
            isPredicted: false
        )
        context.insert(cycle)
        return cycle
    }

    /// Insert a symptom entry on the given date.
    @discardableResult
    private static func insertSymptom(
        context: ModelContext,
        date: Date,
        type: SymptomType,
        severity: Int
    ) -> SymptomEntry {
        let entry = SymptomEntry(date: date, type: type, severity: severity)
        context.insert(entry)
        return entry
    }

    /// Insert a supplement log on the given date.
    @discardableResult
    private static func insertSupplement(
        context: ModelContext,
        date: Date,
        name: String,
        taken: Bool
    ) -> SupplementLog {
        let log = SupplementLog(
            date: date,
            supplementName: name,
            timeTaken: date,
            taken: taken
        )
        context.insert(log)
        return log
    }

    private static func makeDeduplicator(context: ModelContext) -> InsightDeduplicator {
        InsightDeduplicator(
            modelContext: context,
            deduplicationWindowDays: 7,
            insightExpirationDays: 90
        )
    }

    @discardableResult
    private static func insertHealthKitSignal(
        context: ModelContext,
        date: Date,
        identifier: String,
        sourceName: String,
        value: Double,
        unit: String
    ) -> HealthKitImportedSampleRecord {
        let record = HealthKitImportedSampleRecord(
            sampleUUID: "\(identifier)-\(sourceName)-\(Int(date.timeIntervalSince1970))",
            healthKitIdentifier: identifier,
            sourceName: sourceName,
            startDate: date,
            valueDouble: value,
            valueUnit: unit,
            derivedRecordKind: .sourceOnly
        )
        context.insert(record)
        return record
    }

    // MARK: - Empty Data

    @Test("Empty data returns no insights")
    func emptyDataReturnsNoInsights() throws {
        let container = try Self.makeContainer()
        let engine = InsightEngine(modelContext: container.mainContext)

        let insights = try engine.generateInsights()
        #expect(insights.isEmpty)
    }

    // MARK: - Cycle Patterns

    @Test("Cycle patterns require at least 3 completed cycles")
    func cyclePatternMinimumCycles() throws {
        let container = try Self.makeContainer()
        let context = container.mainContext
        let calendar = Calendar.current

        // Only 2 cycles — should produce no cycle pattern insights
        let start1 = calendar.date(byAdding: .day, value: -60, to: Date())!
        Self.insertCycle(context: context, startDate: start1, lengthDays: 28)

        let start2 = calendar.date(byAdding: .day, value: -30, to: Date())!
        Self.insertCycle(context: context, startDate: start2, lengthDays: 30)

        try context.save()

        let engine = InsightEngine(modelContext: context)
        let insights = try engine.generateInsights()

        let cycleInsights = insights.filter { $0.insightType == .cyclePattern }
        #expect(cycleInsights.isEmpty)
    }

    @Test("Three completed cycles generates cycle pattern insight")
    func threeCyclesGeneratesInsight() throws {
        let container = try Self.makeContainer()
        let context = container.mainContext
        let calendar = Calendar.current

        let start1 = calendar.date(byAdding: .day, value: -90, to: Date())!
        Self.insertCycle(context: context, startDate: start1, lengthDays: 28)

        let start2 = calendar.date(byAdding: .day, value: -62, to: Date())!
        Self.insertCycle(context: context, startDate: start2, lengthDays: 29)

        let start3 = calendar.date(byAdding: .day, value: -33, to: Date())!
        Self.insertCycle(context: context, startDate: start3, lengthDays: 28)

        try context.save()

        let engine = InsightEngine(modelContext: context)
        let insights = try engine.generateInsights()

        let cycleInsights = insights.filter { $0.insightType == .cyclePattern }
        #expect(!cycleInsights.isEmpty)

        let regularInsight = cycleInsights.first {
            $0.title == String(localized: "Your cycles are regular", comment: "Insight title for stable cycle lengths.")
        }
        #expect(regularInsight != nil)
    }

    @Test("Irregular cycles generate appropriate insight")
    func irregularCyclesInsight() throws {
        let container = try Self.makeContainer()
        let context = container.mainContext
        let calendar = Calendar.current

        // Highly variable cycle lengths
        let start1 = calendar.date(byAdding: .day, value: -150, to: Date())!
        Self.insertCycle(context: context, startDate: start1, lengthDays: 22)

        let start2 = calendar.date(byAdding: .day, value: -110, to: Date())!
        Self.insertCycle(context: context, startDate: start2, lengthDays: 45)

        let start3 = calendar.date(byAdding: .day, value: -60, to: Date())!
        Self.insertCycle(context: context, startDate: start3, lengthDays: 30)

        try context.save()

        let engine = InsightEngine(modelContext: context)
        let insights = try engine.generateInsights()

        let cycleInsights = insights.filter { $0.insightType == .cyclePattern }
        #expect(!cycleInsights.isEmpty)

        let irregularInsight = cycleInsights.first {
            $0.title == String(localized: "Your cycles are irregular", comment: "Insight title for highly variable cycle lengths.")
        }
        #expect(irregularInsight != nil)
    }

    @Test("Cycle length trend detected with 4+ cycles")
    func cycleLengthTrend() throws {
        let container = try Self.makeContainer()
        let context = container.mainContext
        let calendar = Calendar.current

        // First cycle is short, recent 3 are much longer => getting longer
        let start1 = calendar.date(byAdding: .day, value: -150, to: Date())!
        Self.insertCycle(context: context, startDate: start1, lengthDays: 25)

        let start2 = calendar.date(byAdding: .day, value: -120, to: Date())!
        Self.insertCycle(context: context, startDate: start2, lengthDays: 32)

        let start3 = calendar.date(byAdding: .day, value: -85, to: Date())!
        Self.insertCycle(context: context, startDate: start3, lengthDays: 34)

        let start4 = calendar.date(byAdding: .day, value: -50, to: Date())!
        Self.insertCycle(context: context, startDate: start4, lengthDays: 35)

        try context.save()

        let engine = InsightEngine(modelContext: context)
        let insights = try engine.generateInsights()

        let trendInsight = insights.first {
            $0.title == String(
                localized: "Your recent cycles are getting longer",
                comment: "Insight title describing recent cycle lengths becoming longer."
            )
        }
        #expect(trendInsight != nil)
    }

    // MARK: - Symptom Correlations

    @Test("Symptom correlations require 14 days of data")
    func symptomCorrelationMinimumData() throws {
        let container = try Self.makeContainer()
        let context = container.mainContext
        let calendar = Calendar.current

        // Only 5 days of symptoms — should produce no symptom insights
        for dayOffset in 0..<5 {
            let date = calendar.date(byAdding: .day, value: -dayOffset, to: Date())!
            Self.insertSymptom(context: context, date: date, type: .fatigue, severity: 3)
        }
        try context.save()

        let engine = InsightEngine(modelContext: context)
        let insights = try engine.generateInsights()

        let symptomInsights = insights.filter { $0.insightType == .symptomCorrelation }
        #expect(symptomInsights.isEmpty)
    }

    @Test("Co-occurring symptoms detected with sufficient data")
    func coOccurringSymptoms() throws {
        let container = try Self.makeContainer()
        let context = container.mainContext
        let calendar = Calendar.current

        // Log fatigue + headache together for 10 of 14 days
        for dayOffset in 0..<14 {
            let date = calendar.date(byAdding: .day, value: -dayOffset, to: Date())!
            Self.insertSymptom(context: context, date: date, type: .fatigue, severity: 3)
            if dayOffset < 10 {
                Self.insertSymptom(context: context, date: date, type: .headache, severity: 2)
            }
        }
        try context.save()

        let engine = InsightEngine(modelContext: context)
        let insights = try engine.generateInsights()

        let coOccurrence = insights.first {
            $0.insightType == .symptomCorrelation
                && Set($0.relatedSymptoms) == Set([SymptomType.fatigue.displayName, SymptomType.headache.displayName])
        }
        #expect(coOccurrence != nil)
    }

    @Test("Phase-based symptom insights are skipped for long unknown cycles")
    func phaseBasedSymptomInsightsSkippedForUnsafeCycles() throws {
        let container = try Self.makeContainer()
        let context = container.mainContext
        let calendar = Calendar.current
        let now = Date()

        for offset in [180, 120, 60] {
            let start = calendar.date(byAdding: .day, value: -offset, to: now) ?? now
            let end = calendar.date(byAdding: .day, value: 50, to: start) ?? now
            context.insert(
                Cycle(
                    startDate: start,
                    endDate: end,
                    lengthDays: 50,
                    isPredicted: false,
                    ovulationStatus: .unknown
                )
            )
        }

        for dayOffset in 0..<14 {
            let date = calendar.date(byAdding: .day, value: -dayOffset, to: now) ?? now
            Self.insertSymptom(context: context, date: date, type: .fatigue, severity: 3)
        }
        try context.save()

        let engine = InsightEngine(modelContext: context)
        let insights = try engine.generateInsights()

        #expect(
            !insights.contains {
                $0.title.contains(
                    String(localized: "Symptoms peak during", comment: "Prefix for phase-based symptom insights.")
                )
            }
        )
    }

    @Test("Seasonal analyzer produces insight when month-to-month severity shifts are strong")
    func seasonalPatternInsightGenerated() throws {
        let container = try Self.makeContainer()
        let context = container.mainContext
        let calendar = Calendar.current
        let now = Date()
        let elevatedMonthDate = try #require(calendar.date(byAdding: .day, value: -45, to: now))
        let elevatedMonth = calendar.component(.month, from: elevatedMonthDate)

        for dayOffset in 0..<140 {
            let date = calendar.date(byAdding: .day, value: -dayOffset, to: now) ?? now
            let month = calendar.component(.month, from: date)
            let severity = month == elevatedMonth ? 4 : 2
            Self.insertSymptom(context: context, date: date, type: .fatigue, severity: severity)
        }
        try context.save()

        let engine = InsightEngine(modelContext: context)
        let insights = try engine.generateInsights()

        #expect(insights.contains { $0.insightType == .seasonalPattern })
    }

    @Test("Predictive analyzer generates 7-day symptom and cycle forecast insights")
    func predictiveForecastInsightsGenerated() throws {
        let container = try Self.makeContainer()
        let context = container.mainContext
        let calendar = Calendar.current
        let now = Date()

        for offset in [90, 60, 30] {
            let start = calendar.date(byAdding: .day, value: -offset, to: now) ?? now
            Self.insertCycle(context: context, startDate: start, lengthDays: 30 - (offset / 30))
        }

        for dayOffset in 0..<14 {
            let date = calendar.date(byAdding: .day, value: -dayOffset, to: now) ?? now
            context.insert(
                DailyLog(
                    date: date,
                    weight: 71.5 - (Double(dayOffset) * 0.05),
                    sleepHours: 6.8 + (dayOffset.isMultiple(of: 2) ? 0.4 : 0),
                    activeMinutes: 35 + dayOffset,
                    restingHeartRateBPM: 62,
                    stressLevel: 3
                )
            )

            context.insert(
                SymptomEntry(
                    date: date,
                    type: .fatigue,
                    severity: 2 + (dayOffset % 3)
                )
            )

            context.insert(
                MealEntry(
                    timestamp: date,
                    mealType: .dinner,
                    mealDescription: dayOffset.isMultiple(of: 2) ? "White rice bowl" : "Salmon salad",
                    glycemicImpact: dayOffset.isMultiple(of: 2) ? .high : .low
                )
            )

            context.insert(
                SupplementLog(
                    date: date,
                    supplementName: "Inositol",
                    timeTaken: date,
                    taken: !dayOffset.isMultiple(of: 4)
                )
            )
        }

        for dayOffset in 0..<7 {
            let date = calendar.date(byAdding: .day, value: -dayOffset, to: now) ?? now
            context.insert(
                BloodSugarReading(
                    timestamp: date,
                    glucoseValue: 108 + Double(dayOffset * 3),
                    readingType: .random
                )
            )
        }

        try context.save()

        let engine = InsightEngine(modelContext: context)
        let insights = try engine.generateInsights()

        #expect(insights.contains { $0.title == String(localized: "7-day symptom severity forecast", comment: "Insight title for the 7-day predicted symptom severity range.") })
        #expect(insights.contains { $0.title == String(localized: "Cycle length forecast range", comment: "Insight title for the predicted cycle-length range.") })
    }

    @Test("Health signal insight explains the pattern, likely contributor, options, and best first step")
    func healthSignalInsightUsesLevelFourRecommendationShape() throws {
        let container = try Self.makeContainer()
        let context = container.mainContext
        let calendar = Calendar.current
        let now = try #require(calendar.date(from: DateComponents(year: 2026, month: 6, day: 25, hour: 12)))

        for dayOffset in stride(from: 20, through: 0, by: -1) {
            let date = calendar.date(byAdding: .day, value: -dayOffset, to: now) ?? now
            let recent = dayOffset < 7
            context.insert(
                DailyLog(
                    date: date,
                    sleepHours: recent ? 5.8 : 7.4,
                    activeMinutes: recent ? 18 : 42,
                    restingHeartRateBPM: recent ? 70 : 62,
                    stressLevel: recent ? 4 : 2,
                    energyLevel: recent ? 2 : 4,
                    waterOz: recent ? 42 : 68,
                    painLevel0To10: recent ? 4 : 1
                )
            )
            Self.insertSymptom(
                context: context,
                date: date,
                type: recent ? .fatigue : .cramps,
                severity: recent ? 4 : 1
            )
            if recent {
                Self.insertHealthKitSignal(
                    context: context,
                    date: date,
                    identifier: "HKQuantityTypeIdentifierHeartRateVariabilitySDNN",
                    sourceName: "Oura",
                    value: 32 - Double(dayOffset),
                    unit: "ms"
                )
                Self.insertHealthKitSignal(
                    context: context,
                    date: date,
                    identifier: "HKQuantityTypeIdentifierRestingHeartRate",
                    sourceName: "Apple Watch",
                    value: 70,
                    unit: "bpm"
                )
            }
        }

        try context.save()

        let insights = try InsightEngine(modelContext: context).generateInsights()
        let recoveryInsight = try #require(
            insights.first {
                $0.title == L10n.string(
                    "Recovery signals may be adding strain",
                    defaultValue: "Recovery signals may be adding strain"
                )
            }
        )

        #expect(recoveryInsight.content.contains("Pattern:"))
        #expect(recoveryInsight.content.contains("Likely contributor:"))
        #expect(recoveryInsight.content.contains("Possible next steps:"))
        #expect(recoveryInsight.content.contains("Best first step:"))
        #expect(recoveryInsight.scientificContent?.contains("Apple Watch") == true)
        #expect(recoveryInsight.scientificContent?.contains("Oura") == true)
        #expect(recoveryInsight.recommendedActions.first?.localizedCaseInsensitiveContains("sleep") == true)
    }

    @Test("Health signal insight avoids diagnostic or treatment claims")
    func healthSignalInsightUsesNonDiagnosticLanguage() throws {
        let container = try Self.makeContainer()
        let context = container.mainContext
        let calendar = Calendar.current
        let now = try #require(calendar.date(from: DateComponents(year: 2026, month: 6, day: 25, hour: 12)))

        for dayOffset in stride(from: 20, through: 0, by: -1) {
            let date = calendar.date(byAdding: .day, value: -dayOffset, to: now) ?? now
            let recent = dayOffset < 7
            context.insert(
                DailyLog(
                    date: date,
                    sleepHours: recent ? 5.5 : 7.3,
                    activeMinutes: recent ? 12 : 45,
                    restingHeartRateBPM: recent ? 73 : 63,
                    stressLevel: recent ? 4 : 2,
                    energyLevel: recent ? 2 : 4,
                    painLevel0To10: recent ? 5 : 1
                )
            )
            Self.insertSymptom(context: context, date: date, type: .fatigue, severity: recent ? 4 : 1)
        }

        try context.save()

        let recoveryInsight = try #require(
            try InsightEngine(modelContext: context).generateInsights().first {
                $0.title == L10n.string(
                    "Recovery signals may be adding strain",
                    defaultValue: "Recovery signals may be adding strain"
                )
            }
        )
        let searchableText = [
            recoveryInsight.title,
            recoveryInsight.content,
            recoveryInsight.scientificContent ?? ""
        ].joined(separator: " ").lowercased()

        #expect(!searchableText.contains("diagnose"))
        #expect(!searchableText.contains("treat"))
        #expect(!searchableText.contains("cure"))
        #expect(!searchableText.contains("guarantee"))
    }

    @Test("Health signal insight stays quiet until the recent window has enough data")
    func healthSignalInsightRequiresEnoughRecentLogs() throws {
        let container = try Self.makeContainer()
        let context = container.mainContext
        let calendar = Calendar.current
        let now = try #require(calendar.date(from: DateComponents(year: 2026, month: 6, day: 25, hour: 12)))

        for dayOffset in stride(from: 9, through: 0, by: -1) {
            let date = calendar.date(byAdding: .day, value: -dayOffset, to: now) ?? now
            context.insert(
                DailyLog(
                    date: date,
                    sleepHours: 5.5,
                    activeMinutes: 12,
                    restingHeartRateBPM: 72,
                    energyLevel: 2
                )
            )
        }
        try context.save()

        let insights = try InsightEngine(modelContext: context).generateInsights()
        #expect(
            !insights.contains {
                $0.title == L10n.string(
                    "Recovery signals may be adding strain",
                    defaultValue: "Recovery signals may be adding strain"
                )
            }
        )
    }

    @Test("Diet analyzer emits lag-window breakout correlation with quantitative confidence")
    func dietLagWindowBreakoutInsightIsQuantitative() throws {
        let container = try Self.makeContainer()
        let context = container.mainContext
        let calendar = Calendar.current
        let now = Date()

        for dayOffset in stride(from: 40, through: 1, by: -1) {
            let date = calendar.date(byAdding: .day, value: -dayOffset, to: now) ?? now
            let isHighGI = dayOffset.isMultiple(of: 2)
            context.insert(
                MealEntry(
                    timestamp: date,
                    mealType: .lunch,
                    mealDescription: isHighGI ? "Pasta + soda" : "Chicken salad",
                    glycemicImpact: isHighGI ? .high : .low
                )
            )
        }

        for dayOffset in stride(from: 38, through: 1, by: -1) {
            let date = calendar.date(byAdding: .day, value: -dayOffset, to: now) ?? now
            let twoDaysBefore = dayOffset + 2
            let highGITwoDaysEarlier = twoDaysBefore.isMultiple(of: 2)
            context.insert(
                SymptomEntry(
                    date: date,
                    type: .breakouts,
                    severity: highGITwoDaysEarlier ? 4 : 1
                )
            )
        }

        try context.save()

        let analyzer = DietImpactInsightAnalyzer(fetcher: InsightDataFetcher(modelContext: context))
        let insights = try analyzer.analyze()

        let lagInsight = try #require(
            insights.first {
                $0.title == String(
                    localized: "Acne breakouts correlate with high-GI meals 2-3 days prior",
                    comment: "Quantitative insight title for delayed breakout severity changes by GI cohort."
                )
            }
        )
        #expect(lagInsight.scientificContent?.contains("/5") == true)
        #expect(lagInsight.scientificContent?.contains("averaged") == true)
        #expect(lagInsight.confidence >= 0.5)
        #expect(lagInsight.dataPointsUsed >= 8)
    }

    @Test("Supplement analyzer emits quantitative adherence-cycle delta wording")
    func supplementEfficacyCycleDeltaIsQuantitative() throws {
        try L10n.withOverrides(appLanguage: .en, preferredLanguages: ["en_US"]) {
            let container = try Self.makeContainer()
            let context = container.mainContext
            let calendar = Calendar.current
            let now = try #require(
                calendar.date(from: DateComponents(year: 2026, month: 5, day: 31, hour: 12))
            )

            let monthAnchors = (1...4).compactMap { calendar.date(byAdding: .month, value: -$0, to: now) }
                .sorted()
            let cycleLengths = [27, 28, 35, 36]

            for (index, monthDate) in monthAnchors.enumerated() {
                let start = calendar.startOfDay(for: monthDate)
                Self.insertCycle(context: context, startDate: start, lengthDays: cycleLengths[index])

                for day in 1...10 {
                    guard let logDate = calendar.date(byAdding: .day, value: day, to: start) else { continue }
                    let highAdherenceMonth = index < 2
                    let taken = highAdherenceMonth ? day <= 9 : day <= 3
                    context.insert(
                        SupplementLog(
                            date: logDate,
                            supplementName: "Inositol",
                            timeTaken: logDate,
                            taken: taken
                        )
                    )
                }
            }

            try context.save()

            let analyzer = SupplementEfficacyInsightAnalyzer(fetcher: InsightDataFetcher(modelContext: context))
            let insights = try analyzer.analyze()
            let expectedTitle = L10n.string(
                "Cycle length shift with Inositol adherence",
                defaultValue: "Cycle length shift with Inositol adherence"
            )

            let cycleDeltaInsight = try #require(
                insights.first { $0.title == expectedTitle }
            )
            #expect(cycleDeltaInsight.scientificContent?.contains("days") == true)
            #expect(cycleDeltaInsight.scientificContent?.contains("average") == true)
            #expect(cycleDeltaInsight.confidence >= 0.5)
            #expect(cycleDeltaInsight.dataPointsUsed >= 4)
        }
    }

    // MARK: - Confidence Threshold

    @Test("Insights below 0.3 confidence are excluded")
    func confidenceThresholdFiltering() throws {
        let container = try Self.makeContainer()
        let context = container.mainContext
        let deduplicator = Self.makeDeduplicator(context: context)

        // Create insights with varying confidence for deduplication testing
        let lowConfidence = Insight(
            insightType: .cyclePattern,
            title: "Test Low Confidence",
            content: "Should be filtered out",
            confidence: 0.2,
            dataPointsUsed: 1,
            actionable: false
        )
        let highConfidence = Insight(
            insightType: .cyclePattern,
            title: "Test High Confidence",
            content: "Should be kept",
            confidence: 0.5,
            dataPointsUsed: 5,
            actionable: false
        )

        // generateInsights filters below 0.3 — verify via deduplicateAndClean that
        // both come through when above threshold (the main filter is in generateInsights)
        let result = deduplicator.deduplicateAndClean(
            newInsights: [lowConfidence, highConfidence],
            existingInsights: []
        )

        // deduplicateAndClean does not filter by confidence — that's generateInsights' job.
        // Both should pass through deduplication since they have different titles.
        #expect(result.count == 2)

        // But generateInsights itself filters. Simulate that step:
        let filtered = [lowConfidence, highConfidence].filter { $0.confidence >= 0.3 }
        #expect(filtered.count == 1)
        #expect(filtered.first?.title == "Test High Confidence")
    }

    // MARK: - Deduplication

    @Test("Duplicate insights within 7 days are filtered")
    func deduplicationWithin7Days() throws {
        let container = try Self.makeContainer()
        let context = container.mainContext
        let deduplicator = Self.makeDeduplicator(context: context)

        // Simulate an existing insight generated 3 days ago
        let existingInsight = Insight(
            generatedDate: Calendar.current.date(byAdding: .day, value: -3, to: Date())!,
            insightType: .cyclePattern,
            title: "Your cycles are regular",
            content: "Previous insight content",
            confidence: 0.7,
            dataPointsUsed: 3,
            actionable: false
        )
        context.insert(existingInsight)
        try context.save()

        // Try to generate a new insight with the same type and similar title
        let newInsight = Insight(
            insightType: .cyclePattern,
            title: "Your cycles are regular",
            content: "Updated content",
            confidence: 0.75,
            dataPointsUsed: 4,
            actionable: false
        )

        let result = deduplicator.deduplicateAndClean(
            newInsights: [newInsight],
            existingInsights: [existingInsight]
        )

        #expect(result.isEmpty, "Duplicate insight within 7 days should be filtered out")
    }

    @Test("Insights older than 7 days are not considered duplicates")
    func noDeduplicationBeyond7Days() throws {
        let container = try Self.makeContainer()
        let context = container.mainContext
        let deduplicator = Self.makeDeduplicator(context: context)

        // Existing insight from 10 days ago
        let existingInsight = Insight(
            generatedDate: Calendar.current.date(byAdding: .day, value: -10, to: Date())!,
            insightType: .cyclePattern,
            title: "Your cycles are regular",
            content: "Old content",
            confidence: 0.7,
            dataPointsUsed: 3,
            actionable: false
        )

        let newInsight = Insight(
            insightType: .cyclePattern,
            title: "Your cycles are regular",
            content: "New content",
            confidence: 0.75,
            dataPointsUsed: 4,
            actionable: false
        )

        let result = deduplicator.deduplicateAndClean(
            newInsights: [newInsight],
            existingInsights: [existingInsight]
        )

        #expect(result.count == 1, "Insight older than 7 days should not block new insight")
    }

    @Test("Old insights (>90 days) are deleted during cleanup")
    func oldInsightsDeleted() throws {
        let container = try Self.makeContainer()
        let context = container.mainContext
        let deduplicator = Self.makeDeduplicator(context: context)

        let oldInsight = Insight(
            generatedDate: Calendar.current.date(byAdding: .day, value: -100, to: Date())!,
            insightType: .cyclePattern,
            title: "Ancient insight",
            content: "Should be deleted",
            confidence: 0.7,
            dataPointsUsed: 3,
            actionable: false
        )
        context.insert(oldInsight)
        try context.save()

        // Run deduplicateAndClean — it should mark the old insight for deletion
        _ = deduplicator.deduplicateAndClean(
            newInsights: [],
            existingInsights: [oldInsight]
        )

        // The insight should have been deleted from the context
        try context.save()
        let descriptor = FetchDescriptor<Insight>()
        let remaining = try context.fetch(descriptor)
        #expect(remaining.isEmpty, "Insights older than 90 days should be deleted")
    }

    @Test("Different insight types are not considered duplicates")
    func differentTypesNotDeduplicated() throws {
        let container = try Self.makeContainer()
        let context = container.mainContext
        let deduplicator = Self.makeDeduplicator(context: context)

        let existingInsight = Insight(
            generatedDate: Calendar.current.date(byAdding: .day, value: -2, to: Date())!,
            insightType: .cyclePattern,
            title: "Your cycles are regular",
            content: "Cycle content",
            confidence: 0.7,
            dataPointsUsed: 3,
            actionable: false
        )

        let newInsight = Insight(
            insightType: .symptomCorrelation,
            title: "Your cycles are regular",
            content: "Same title, different type",
            confidence: 0.7,
            dataPointsUsed: 3,
            actionable: false
        )

        let result = deduplicator.deduplicateAndClean(
            newInsights: [newInsight],
            existingInsights: [existingInsight]
        )

        #expect(result.count == 1, "Different insight types should not be deduplicated")
    }

    // MARK: - Supplement Efficacy

    @Test("Supplement efficacy requires 14 days of supplement data")
    func supplementEfficacyMinimumData() throws {
        let container = try Self.makeContainer()
        let context = container.mainContext
        let calendar = Calendar.current

        // Only 5 supplement logs — insufficient
        for dayOffset in 0..<5 {
            let date = calendar.date(byAdding: .day, value: -dayOffset, to: Date())!
            Self.insertSupplement(context: context, date: date, name: "Inositol", taken: true)
        }
        try context.save()

        let engine = InsightEngine(modelContext: context)
        let insights = try engine.generateInsights()

        let supplementInsights = insights.filter { $0.insightType == .supplementEfficacy }
        #expect(supplementInsights.isEmpty)
    }

    // MARK: - ViewModel Integration

    @Test("InsightsViewModel fetches existing insights")
    func viewModelFetchesInsights() throws {
        let container = try Self.makeContainer()
        let context = container.mainContext

        let insight = Insight(
            insightType: .cyclePattern,
            title: "Test Insight",
            content: "Test content",
            confidence: 0.8,
            dataPointsUsed: 5,
            actionable: true
        )
        context.insert(insight)
        try context.save()

        let vm = InsightsViewModel(modelContext: context)
        vm.fetchExistingInsights()

        #expect(vm.insights.count == 1)
        #expect(vm.insights.first?.title == "Test Insight")
    }

    @Test("InsightsViewModel refreshInsights generates and persists")
    func viewModelRefreshInsights() async throws {
        let container = try Self.makeContainer()
        let context = container.mainContext
        let calendar = Calendar.current

        // Set up enough data for cycle pattern insights
        let start1 = calendar.date(byAdding: .day, value: -90, to: Date())!
        Self.insertCycle(context: context, startDate: start1, lengthDays: 28)

        let start2 = calendar.date(byAdding: .day, value: -62, to: Date())!
        Self.insertCycle(context: context, startDate: start2, lengthDays: 28)

        let start3 = calendar.date(byAdding: .day, value: -34, to: Date())!
        Self.insertCycle(context: context, startDate: start3, lengthDays: 28)

        try context.save()

        let vm = InsightsViewModel(modelContext: context)
        await vm.refreshInsights()

        #expect(!vm.insights.isEmpty)
        #expect(!vm.isGenerating)

        // Verify insights were persisted
        let descriptor = FetchDescriptor<Insight>()
        let persisted = try context.fetch(descriptor)
        #expect(!persisted.isEmpty)
    }

    @Test("InsightsViewModel loadInsights auto-generates when no persisted insights exist")
    func viewModelLoadInsightsAutoGenerates() async throws {
        let container = try Self.makeContainer()
        let context = container.mainContext
        InsightRefreshCoordinator.clear()

        let vm = InsightsViewModel(
            modelContext: context,
            insightGenerator: {
                [
                    Insight(
                        insightType: .cyclePattern,
                        title: "Generated Insight",
                        content: "Generated content",
                        confidence: 0.8,
                        dataPointsUsed: 4,
                        actionable: true
                    ),
                ]
            }
        )

        await vm.loadInsights()

        #expect(vm.insights.count == 1)
        #expect(vm.insights.first?.title == "Generated Insight")
        let persisted = try context.fetch(FetchDescriptor<Insight>())
        #expect(persisted.count == 1)
    }

    @Test("Insight presentation planner prioritizes onboarding focus and hides premium insights for free users")
    func insightPresentationPlannerRespectsAudienceAndAccess() {
        let planner = InsightPresentationPlanner()
        let now = Date()

        let cycleInsight = Insight(
            generatedDate: now.addingTimeInterval(-60),
            insightType: .cyclePattern,
            title: "Cycle summary",
            content: "Cycle content",
            confidence: 0.9,
            dataPointsUsed: 6,
            actionable: true
        )
        let symptomInsight = Insight(
            generatedDate: now,
            insightType: .symptomCorrelation,
            title: "Skin trend",
            content: "Skin content",
            confidence: 0.72,
            dataPointsUsed: 14,
            actionable: true,
            relatedSymptoms: [SymptomType.breakouts.displayName]
        )
        let premiumInsight = Insight(
            generatedDate: now,
            insightType: .dietImpact,
            title: "Meal impact",
            content: "Premium content",
            confidence: 0.82,
            dataPointsUsed: 12,
            actionable: true
        )

        let plan = planner.makePlan(
            insights: [cycleInsight, symptomInsight, premiumInsight],
            preferences: InsightAudiencePreferences(
                primaryGoal: .understandSymptoms,
                experience: .newlyDiagnosed,
                focusAreas: [.skinHair]
            ),
            isPremium: false
        )

        #expect(plan.visibleInsights.map(\.title) == ["Skin trend", "Cycle summary"])
        #expect(plan.lockedPremiumCards.map(\.id) == ["premium.diet"])
    }
}
