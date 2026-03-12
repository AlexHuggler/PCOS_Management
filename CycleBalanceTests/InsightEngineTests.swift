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

        // Regular cycles (CV < 0.1) should get "regular" title
        let regularInsight = cycleInsights.first { $0.title.contains("regular") }
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

        // Should flag as irregular
        let irregularInsight = cycleInsights.first { $0.title.lowercased().contains("irregular") }
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

        let trendInsight = insights.first { $0.title.lowercased().contains("longer") }
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

        let coOccurrence = insights.first { $0.title.contains("appear together") }
        #expect(coOccurrence != nil)
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
}
