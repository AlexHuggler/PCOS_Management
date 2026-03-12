import Testing
import Foundation
import SwiftData
@testable import PCOS

private let insightEngineSourceCandidates = [
    "../PCOS/Core/ML/InsightEngine.swift",
    "../CycleBalance/Core/ML/InsightEngine.swift"
]

private let mealLogViewSourceCandidates = [
    "../PCOS/Features/Meals/Views/MealLogView.swift",
    "../CycleBalance/Features/Meals/Views/MealLogView.swift",
]

private let photoCaptureViewSourceCandidates = [
    "../PCOS/Features/PhotoJournal/Views/PhotoCaptureView.swift",
    "../CycleBalance/Features/PhotoJournal/Views/PhotoCaptureView.swift",
]

private let todayViewSourceCandidates = [
    "../PCOS/Features/Cycle/Views/TodayView.swift",
    "../CycleBalance/Features/Cycle/Views/TodayView.swift",
]

private let premiumStateBridgeSourceCandidates = [
    "../PCOS/Core/StoreKit/PremiumStateBridge.swift",
    "../CycleBalance/Core/StoreKit/PremiumStateBridge.swift",
]

private let subscriptionManagerSourceCandidates = [
    "../PCOS/Core/StoreKit/SubscriptionManager.swift",
    "../CycleBalance/Core/StoreKit/SubscriptionManager.swift",
]

private func resolveInsightEngineURL(from testFileURL: URL) -> URL? {
    for candidate in insightEngineSourceCandidates {
        let candidateURL = testFileURL
            .deletingLastPathComponent()
            .appendingPathComponent(candidate)
            .standardizedFileURL
        if FileManager.default.fileExists(atPath: candidateURL.path) {
            return candidateURL
        }
    }
    return nil
}

private func resolveMealLogViewURL(from testFileURL: URL) -> URL? {
    for candidate in mealLogViewSourceCandidates {
        let candidateURL = testFileURL
            .deletingLastPathComponent()
            .appendingPathComponent(candidate)
            .standardizedFileURL
        if FileManager.default.fileExists(atPath: candidateURL.path) {
            return candidateURL
        }
    }
    return nil
}

private func resolvePhotoCaptureViewURL(from testFileURL: URL) -> URL? {
    for candidate in photoCaptureViewSourceCandidates {
        let candidateURL = testFileURL
            .deletingLastPathComponent()
            .appendingPathComponent(candidate)
            .standardizedFileURL
        if FileManager.default.fileExists(atPath: candidateURL.path) {
            return candidateURL
        }
    }
    return nil
}

private func resolveTodayViewURL(from testFileURL: URL) -> URL? {
    for candidate in todayViewSourceCandidates {
        let candidateURL = testFileURL
            .deletingLastPathComponent()
            .appendingPathComponent(candidate)
            .standardizedFileURL
        if FileManager.default.fileExists(atPath: candidateURL.path) {
            return candidateURL
        }
    }
    return nil
}

private func resolvePremiumStateBridgeURL(from testFileURL: URL) -> URL? {
    for candidate in premiumStateBridgeSourceCandidates {
        let candidateURL = testFileURL
            .deletingLastPathComponent()
            .appendingPathComponent(candidate)
            .standardizedFileURL
        if FileManager.default.fileExists(atPath: candidateURL.path) {
            return candidateURL
        }
    }
    return nil
}

private func resolveSubscriptionManagerURL(from testFileURL: URL) -> URL? {
    for candidate in subscriptionManagerSourceCandidates {
        let candidateURL = testFileURL
            .deletingLastPathComponent()
            .appendingPathComponent(candidate)
            .standardizedFileURL
        if FileManager.default.fileExists(atPath: candidateURL.path) {
            return candidateURL
        }
    }
    return nil
}

@Suite("StoreKit Lifecycle Regressions", .serialized)
@MainActor
struct StoreKitLifecycleRegressionTests {
    @Test("PremiumStateBridge exposes explicit stop hook and teardown cleanup")
    func premiumStateBridgeExposesLifecycleTeardown() throws {
        let testFileURL = URL(fileURLWithPath: #filePath)
        guard let premiumStateBridgeURL = resolvePremiumStateBridgeURL(from: testFileURL) else {
            Issue.record("Unable to locate PremiumStateBridge.swift in expected mirrored paths.")
            return
        }

        let source = try String(contentsOf: premiumStateBridgeURL)
        #expect(source.contains("func stop()"))
        #expect(source.contains("deinit"))
        #expect(source.contains("observerTask?.cancel()"))
    }

    @Test("SubscriptionManager exposes explicit listener stop and avoids strong self loop")
    func subscriptionManagerExposesListenerTeardown() throws {
        let testFileURL = URL(fileURLWithPath: #filePath)
        guard let subscriptionManagerURL = resolveSubscriptionManagerURL(from: testFileURL) else {
            Issue.record("Unable to locate SubscriptionManager.swift in expected mirrored paths.")
            return
        }

        let source = try String(contentsOf: subscriptionManagerURL)
        #expect(source.contains("func stopEntitlementListener()"))
        #expect(source.contains("deinit"))
        #expect(source.contains("transactionListener?.cancel()"))
        #expect(source.contains("for await entitlements in billingClient.makeEntitlementUpdatesStream()"))
        #expect(!source.contains("for await entitlements in self.billingClient.makeEntitlementUpdatesStream()"))
    }
}

@Suite("Insight Error Handling Regressions", .serialized)
@MainActor
struct InsightErrorHandlingRegressionTests {
    @Test("InsightEngine does not use silent try? fetch fallbacks")
    func insightEngineHasNoSilentFetchFallbacks() throws {
        let testFileURL = URL(fileURLWithPath: #filePath)
        guard let insightEngineURL = resolveInsightEngineURL(from: testFileURL) else {
            Issue.record("Unable to locate InsightEngine.swift in expected mirrored paths.")
            return
        }

        let source = try String(contentsOf: insightEngineURL)
        #expect(!source.contains("try? modelContext.fetch"))
    }
}

@Suite("Insight Architecture Regressions", .serialized)
@MainActor
struct InsightArchitectureRegressionTests {
    @Test("InsightEngine delegates analyzers, fetch, and dedup to focused components")
    func insightEngineDelegatesToSplitComponents() throws {
        let testFileURL = URL(fileURLWithPath: #filePath)
        guard let insightEngineURL = resolveInsightEngineURL(from: testFileURL) else {
            Issue.record("Unable to locate InsightEngine.swift in expected mirrored paths.")
            return
        }

        let source = try String(contentsOf: insightEngineURL)

        // Coordinator should no longer contain analyzer bodies.
        #expect(!source.contains("private func analyzeCyclePatterns()"))
        #expect(!source.contains("private func analyzeSymptomCorrelations()"))
        #expect(!source.contains("private func analyzeSupplementEfficacy()"))
        #expect(!source.contains("private func analyzeDietImpact()"))
        #expect(!source.contains("private func analyzeSleepActivity()"))

        // Fetch/dedup logic should be extracted out of the coordinator.
        #expect(!source.contains("private func fetchOrThrow<T: PersistentModel>"))

        // Coordinator should delegate to focused components.
        #expect(source.contains("CyclePatternInsightAnalyzer"))
        #expect(source.contains("SymptomCorrelationInsightAnalyzer"))
        #expect(source.contains("SupplementEfficacyInsightAnalyzer"))
        #expect(source.contains("DietImpactInsightAnalyzer"))
        #expect(source.contains("SleepActivityInsightAnalyzer"))
        #expect(source.contains("InsightDataFetcher"))
        #expect(source.contains("InsightDeduplicator"))
    }
}

private enum TestInsightRefreshError: LocalizedError {
    case forcedFailure

    var errorDescription: String? {
        "Insight generation couldn't read meals. Please try again."
    }
}

@Suite("Insights ViewModel Error Propagation", .serialized)
@MainActor
struct InsightsViewModelErrorPropagationTests {
    @Test("Refresh sets error message and does not persist insights when generation fails")
    func refreshSetsErrorAndDoesNotPersistOnGenerationFailure() async throws {
        let container = try TestHelpers.makeModelContainer()
        let context = container.mainContext
        let viewModel = InsightsViewModel(
            modelContext: context,
            insightGenerator: { throw TestInsightRefreshError.forcedFailure }
        )

        await viewModel.refreshInsights()

        #expect(viewModel.errorMessage == TestInsightRefreshError.forcedFailure.errorDescription)
        #expect(viewModel.insights.isEmpty)

        let persistedInsights = try context.fetch(FetchDescriptor<Insight>())
        #expect(persistedInsights.isEmpty)
    }

    @Test("Refresh clears stale error and persists generated insights on success")
    func refreshClearsErrorAndPersistsOnSuccess() async throws {
        let container = try TestHelpers.makeModelContainer()
        let context = container.mainContext
        let generatedInsights = [
            Insight(
                insightType: .cyclePattern,
                title: "Stable cycle trend",
                content: "Generated in test",
                confidence: 0.8,
                dataPointsUsed: 10,
                actionable: false
            )
        ]

        let viewModel = InsightsViewModel(
            modelContext: context,
            insightGenerator: { generatedInsights }
        )
        viewModel.errorMessage = "stale"

        await viewModel.refreshInsights()

        #expect(viewModel.errorMessage == nil)
        #expect(viewModel.insights.count == 1)

        let persistedInsights = try context.fetch(FetchDescriptor<Insight>())
        #expect(persistedInsights.count == 1)
    }
}

@Suite("Silent Failure Regressions", .serialized)
@MainActor
struct SilentFailureRegressionTests {

    // MARK: - Media import handlers use explicit do/try/catch

    @Test("Meal photo import does not use silent try? loadTransferable fallback")
    func mealPhotoImportAvoidsSilentTransferableFallback() throws {
        let testFileURL = URL(fileURLWithPath: #filePath)
        guard let mealLogViewURL = resolveMealLogViewURL(from: testFileURL) else {
            Issue.record("Unable to locate MealLogView.swift in expected mirrored paths.")
            return
        }

        let source = try String(contentsOf: mealLogViewURL)
        #expect(!source.contains("try? await newItem.loadTransferable(type: Data.self)"))
    }

    @Test("Photo journal import does not use silent try? loadTransferable fallback")
    func photoJournalImportAvoidsSilentTransferableFallback() throws {
        let testFileURL = URL(fileURLWithPath: #filePath)
        guard let photoCaptureViewURL = resolvePhotoCaptureViewURL(from: testFileURL) else {
            Issue.record("Unable to locate PhotoCaptureView.swift in expected mirrored paths.")
            return
        }

        let source = try String(contentsOf: photoCaptureViewURL)
        #expect(!source.contains("try? await newItem?.loadTransferable(type: Data.self)"))
    }

    // MARK: - Today quick log uses explicit error propagation

    @Test("Today quick log does not use silent try? fetch fallback for undo anchor")
    func todayQuickLogAvoidsSilentFetchFallback() throws {
        let testFileURL = URL(fileURLWithPath: #filePath)
        guard let todayViewURL = resolveTodayViewURL(from: testFileURL) else {
            Issue.record("Unable to locate TodayView.swift in expected mirrored paths.")
            return
        }

        let source = try String(contentsOf: todayViewURL)
        #expect(!source.contains("try? modelContext.fetch(descriptor)"))
    }

    @Test("Today quick log does not suppress save errors with empty catch")
    func todayQuickLogAvoidsSilentCatchSuppression() throws {
        let testFileURL = URL(fileURLWithPath: #filePath)
        guard let todayViewURL = resolveTodayViewURL(from: testFileURL) else {
            Issue.record("Unable to locate TodayView.swift in expected mirrored paths.")
            return
        }

        let source = try String(contentsOf: todayViewURL)
        #expect(!source.contains("Quick log is best-effort; full form available via sheet"))
    }

    // MARK: - SymptomViewModel.frequentSymptoms uses do/catch

    @Test("frequentSymptoms returns results from valid data")
    func frequentSymptomsReturnsData() throws {
        let container = try TestHelpers.makeModelContainer()
        let context = container.mainContext
        let vm = SymptomViewModel(modelContext: context)

        // Insert symptoms over the last 30 days
        let calendar = Calendar.current
        for offset in 0..<10 {
            guard let date = calendar.date(byAdding: .day, value: -offset, to: Date()) else { continue }
            let entry = SymptomEntry(date: date, type: .fatigue, severity: 3)
            context.insert(entry)
        }
        for offset in 0..<5 {
            guard let date = calendar.date(byAdding: .day, value: -offset, to: Date()) else { continue }
            let entry = SymptomEntry(date: date, type: .bloating, severity: 2)
            context.insert(entry)
        }
        try context.save()

        let frequent = vm.frequentSymptoms(limit: 3)
        #expect(!frequent.isEmpty)
        #expect(frequent.first == .fatigue)
    }

    @Test("frequentSymptoms returns empty with no data")
    func frequentSymptomsEmptyWhenNoData() throws {
        let container = try TestHelpers.makeModelContainer()
        let context = container.mainContext
        let vm = SymptomViewModel(modelContext: context)

        let frequent = vm.frequentSymptoms()
        #expect(frequent.isEmpty)
    }

    // MARK: - StreakService.entryExists uses do/catch

    @Test("Streak service returns zero with empty database")
    func streakZeroWithNoData() throws {
        let container = try TestHelpers.makeModelContainer()
        let context = container.mainContext
        let service = StreakService(modelContext: context)

        #expect(service.currentStreak() == 0)
    }

    @Test("Streak service counts entries correctly")
    func streakCountsCorrectly() throws {
        let container = try TestHelpers.makeModelContainer()
        let context = container.mainContext
        let calendar = Calendar.current

        // Insert a symptom for today and yesterday
        let today = SymptomEntry(date: Date(), type: .cramps, severity: 3)
        context.insert(today)

        if let yesterday = calendar.date(byAdding: .day, value: -1, to: Date()) {
            let yesterdayEntry = SymptomEntry(date: yesterday, type: .fatigue, severity: 2)
            context.insert(yesterdayEntry)
        }
        try context.save()

        let service = StreakService(modelContext: context)
        #expect(service.currentStreak() == 2)
    }

    // MARK: - BloodSugarViewModel.fetchTodaysReadings safe date

    @Test("BloodSugar fetchTodaysReadings returns today's entries")
    func bloodSugarFetchTodaysReadings() throws {
        let container = try TestHelpers.makeModelContainer()
        let context = container.mainContext
        let vm = BloodSugarViewModel(modelContext: context)

        let reading = BloodSugarReading(
            timestamp: Date(),
            glucoseValue: 110,
            readingType: .fasting,
            mealContext: nil,
            fromHealthKit: false,
            notes: nil
        )
        context.insert(reading)
        try context.save()

        let results = vm.fetchTodaysReadings()
        #expect(results.count == 1)
        #expect(results.first?.glucoseValue == 110)
    }

    // MARK: - SupplementViewModel.fetchTodaysLogs safe date

    @Test("Supplement fetchTodaysLogs returns today's logs")
    func supplementFetchTodaysLogs() throws {
        let container = try TestHelpers.makeModelContainer()
        let context = container.mainContext
        let vm = SupplementViewModel(modelContext: context)

        let log = SupplementLog(
            date: Calendar.current.startOfDay(for: Date()),
            supplementName: "Inositol",
            dosageMg: 2000,
            timeTaken: Date(),
            taken: true,
            brand: nil
        )
        context.insert(log)
        try context.save()

        let results = vm.fetchTodaysLogs()
        #expect(results.count == 1)
        #expect(results.first?.supplementName == "Inositol")
    }

    // MARK: - MealViewModel.fetchTodaysMeals safe date

    @Test("Meal fetchTodaysMeals returns today's meals")
    func mealFetchTodaysMeals() throws {
        let container = try TestHelpers.makeModelContainer()
        let context = container.mainContext
        let vm = MealViewModel(modelContext: context)

        let meal = MealEntry(
            timestamp: Date(),
            mealType: .lunch,
            mealDescription: "Grilled chicken salad",
            glycemicImpact: .low,
            photoData: nil,
            carbsGrams: 20,
            proteinGrams: 35,
            notes: nil
        )
        context.insert(meal)
        try context.save()

        let results = vm.fetchTodaysMeals()
        #expect(results.count == 1)
        #expect(results.first?.mealDescription == "Grilled chicken salad")
    }

    // MARK: - CycleViewModel safe date calculations

    @Test("CycleViewModel entriesForMonth handles edge dates")
    func cycleViewModelEntriesForMonth() throws {
        let container = try TestHelpers.makeModelContainer()
        let context = container.mainContext
        let vm = CycleViewModel(modelContext: context)

        let calendar = Calendar.current
        let components = calendar.dateComponents([.year, .month], from: Date())
        let result = vm.entriesForMonth(year: components.year!, month: components.month!)
        // Should return empty dict without crashing (no force unwraps)
        #expect(result.isEmpty)
    }

    @Test("CycleViewModel loadData does not crash on empty database")
    func cycleViewModelLoadDataEmpty() throws {
        let container = try TestHelpers.makeModelContainer()
        let context = container.mainContext
        let vm = CycleViewModel(modelContext: context)

        // Should not crash
        vm.loadData()
        #expect(vm.cycles.isEmpty)
        #expect(vm.currentCycleEntries.isEmpty)
        #expect(vm.prediction == nil)
    }
}
