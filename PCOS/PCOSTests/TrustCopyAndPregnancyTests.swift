import Testing
import Foundation
import SwiftData
@testable import PCOS

@Suite("Insight thresholds are shared by analyzers and copy", .serialized)
@MainActor
struct InsightThresholdTests {
    @Test("Thresholds match the analyzers' real requirements")
    func thresholdValues() {
        #expect(InsightThresholds.completedCyclesForCyclePatterns == 3)
        #expect(InsightThresholds.trackedSymptomDaysForCorrelations == 14)
    }

    @Test("Analyzers and planner read the shared constants instead of literals")
    func analyzersUseSharedConstants() throws {
        let projectRoot = try TestHelpers.projectRoot(from: #filePath)
        func source(_ path: String) throws -> String {
            try String(contentsOf: projectRoot.appendingPathComponent(path), encoding: .utf8)
        }
        let cycle = try source("PCOS/PCOS/Core/ML/InsightCyclePatternAnalyzer.swift")
        #expect(cycle.contains("InsightThresholds.completedCyclesForCyclePatterns"))
        #expect(!cycle.contains("completedCycles.count >= 3"))
        let symptom = try source("PCOS/PCOS/Core/ML/InsightSymptomCorrelationAnalyzer.swift")
        #expect(symptom.contains("InsightThresholds.trackedSymptomDaysForCorrelations"))
        #expect(!symptom.contains("distinctDays.count >= 14"))
        let planner = try source("PCOS/PCOS/Features/Insights/ViewModels/InsightPresentationPlanner.swift")
        #expect(planner.contains("InsightThresholds."))
    }

    @Test("Onboarding timeline copy is derived from the thresholds and no longer promises two cycles")
    func onboardingTimelineCopy() throws {
        let cycles = OnboardingThresholdCopy.timelineNote(for: .trackCycles)
        #expect(cycles.contains("\(InsightThresholds.completedCyclesForCyclePatterns)"))
        #expect(cycles.contains("\(InsightThresholds.trackedSymptomDaysForCorrelations)"))
        #expect(!cycles.contains("After 2 cycles"))
        let symptoms = OnboardingThresholdCopy.timelineNote(for: .understandSymptoms)
        #expect(symptoms.contains("\(InsightThresholds.trackedSymptomDaysForCorrelations)"))

        let projectRoot = try TestHelpers.projectRoot(from: #filePath)
        let plan = try String(contentsOf: projectRoot.appendingPathComponent("PCOS/PCOS/Features/Onboarding/Views/YourPlanView.swift"), encoding: .utf8)
        #expect(!plan.contains("After 2 cycles"))
        #expect(plan.contains("OnboardingThresholdCopy.timelineNote("))
    }

    @Test("Onboarding no longer promises a community and uses inclusive wording")
    func onboardingCopyKeepsPromises() throws {
        let projectRoot = try TestHelpers.projectRoot(from: #filePath)
        for path in [
            "PCOS/PCOS/Features/Onboarding/Views/OnboardingCompletionView.swift",
            "PCOS/PCOS/Features/Onboarding/Views/SocialProofView.swift",
        ] {
            let source = try String(contentsOf: projectRoot.appendingPathComponent(path), encoding: .utf8)
            #expect(!source.contains("growing community"), "\(path)")
            #expect(!source.contains("women with PCOS"), "\(path)")
            #expect(!source.contains("community of women"), "\(path)")
        }
    }
}

@Suite("Pregnancy handling", .serialized)
@MainActor
struct PregnancyHandlingTests {
    private func insertCompletedCycles(count: Int, into context: ModelContext) {
        let calendar = Calendar.current
        var start = calendar.date(byAdding: .day, value: -30 * (count + 1), to: Date())!
        for index in 0..<count {
            let length = 27 + (index % 3)
            let end = calendar.date(byAdding: .day, value: length, to: start)!
            let cycle = Cycle(startDate: start, endDate: end, lengthDays: length, ovulationStatus: .ovulatory)
            context.insert(cycle)
            context.insert(CycleEntry(date: start, flowIntensity: .medium, isPeriodDay: true))
            start = end
        }
        context.insert(Cycle(startDate: start))
    }

    @Test("Insights generated for a pregnant user contain no cycle-pattern insights")
    func pregnantUsersGetNoCycleInsights() async throws {
        let container = try TestHelpers.makeModelContainer()
        let context = container.mainContext
        insertCompletedCycles(count: 4, into: context)
        try context.save()

        let cyclingViewModel = InsightsViewModel(modelContext: context, defaults: UserDefaults(suiteName: "PregnancyHandlingTests.cycling.\(UUID().uuidString)")!, lifecycleModeProvider: { .cycling })
        await cyclingViewModel.refreshInsights()
        #expect(cyclingViewModel.insights.contains { $0.insightType == .cyclePattern }, "sanity: cycling users get cycle insights from four completed cycles")

        for insight in try context.fetch(FetchDescriptor<Insight>()) {
            context.delete(insight)
        }
        try context.save()

        let pregnantViewModel = InsightsViewModel(modelContext: context, defaults: UserDefaults(suiteName: "PregnancyHandlingTests.pregnant.\(UUID().uuidString)")!, lifecycleModeProvider: { .pregnant })
        await pregnantViewModel.refreshInsights()
        #expect(!pregnantViewModel.insights.contains { $0.insightType == .cyclePattern })
    }

    @Test("Insights view, relocalization and first-open seeding pass the lifecycle mode")
    func lifecycleModeIsPassedEverywhere() throws {
        let projectRoot = try TestHelpers.projectRoot(from: #filePath)
        func source(_ path: String) throws -> String {
            try String(contentsOf: projectRoot.appendingPathComponent(path), encoding: .utf8)
        }
        let view = try source("PCOS/PCOS/Features/Insights/Views/InsightsView.swift")
        #expect(view.contains("lifecycleModeProvider: { appState.lifecycleMode }"))
        let viewModel = try source("PCOS/PCOS/Features/Insights/ViewModels/InsightsViewModel.swift")
        #expect(!viewModel.contains("engine.generateInsights()") && !viewModel.contains("InsightEngine(modelContext: modelContext).generateInsights()"), "every engine call must pass lifecycleMode")
        let app = try source("PCOS/PCOS/App/CycleBalanceApp.swift")
        #expect(!app.contains(".generateInsights()\n"), "first-open seeding must pass the stored lifecycle mode")
    }

    @Test("Pregnancy loss and other endings are not presented as postpartum day counts")
    func lossIsNotPostpartumDayCount() {
        let deliveryHeadline = PregnancyCopy.postpartumHeadline(dayCount: 12, endReason: .delivery)
        #expect(deliveryHeadline.contains("12"))

        let lossHeadline = PregnancyCopy.postpartumHeadline(dayCount: 12, endReason: .loss)
        #expect(!lossHeadline.contains("12"))
        #expect(!lossHeadline.lowercased().contains("postpartum"))

        let lossSubtitle = PregnancyCopy.postpartumSubtitle(endReason: .loss)
        #expect(!lossSubtitle.lowercased().contains("resume"))
        #expect(lossSubtitle != PregnancyCopy.postpartumSubtitle(endReason: .delivery))

        let otherHeadline = PregnancyCopy.postpartumHeadline(dayCount: 3, endReason: .other)
        #expect(!otherHeadline.contains("3"))

        #expect(PregnancyCopy.endConfirmationMessage(for: .loss) != PregnancyCopy.endConfirmationMessage(for: .delivery))
        #expect(!PregnancyCopy.endConfirmationMessage(for: .loss).contains("Cycle tracking will resume"))
    }

    @Test("View model exposes the latest end reason and suppresses the day count after a loss")
    func viewModelTracksEndReason() throws {
        let container = try TestHelpers.makeModelContainer()
        let context = container.mainContext
        let defaults = UserDefaults(suiteName: "PregnancyHandlingTests.vm.\(UUID().uuidString)")!
        let record = PregnancyRecord(startDate: Date().addingTimeInterval(-90 * 86_400), endDate: Date().addingTimeInterval(-5 * 86_400), endReason: .loss, isActive: false)
        context.insert(record)
        try context.save()

        let viewModel = PregnancyViewModel(modelContext: context, defaults: defaults)
        viewModel.loadData()
        #expect(viewModel.latestEndedPregnancyEndReason == .loss)
        #expect(viewModel.postpartumDayCount == nil)

        record.endReason = .delivery
        try context.save()
        viewModel.loadData()
        #expect(viewModel.latestEndedPregnancyEndReason == .delivery)
        #expect(viewModel.postpartumDayCount == 6, "day count starts at 1 on the end date")
    }

    @Test("Dashboard card and end sheet use the shared pregnancy copy")
    func viewsUsePregnancyCopy() throws {
        let projectRoot = try TestHelpers.projectRoot(from: #filePath)
        let card = try String(contentsOf: projectRoot.appendingPathComponent("PCOS/PCOS/Features/Pregnancy/PregnancyDashboardCard.swift"), encoding: .utf8)
        #expect(card.contains("PregnancyCopy.postpartumHeadline("))
        #expect(card.contains("PregnancyCopy.postpartumSubtitle("))
        #expect(!card.contains("\"Postpartum — Day %lld\""))
        let end = try String(contentsOf: projectRoot.appendingPathComponent("PCOS/PCOS/Features/Pregnancy/PregnancyEndView.swift"), encoding: .utf8)
        #expect(end.contains("PregnancyCopy.endConfirmationMessage("))
    }

    @Test("Supplement catalog flags pregnancy cautions and the logger shows them in pregnancy mode")
    func supplementPregnancyCaution() throws {
        let berberine = try #require(PCOSSupplements.catalog.first { $0.key == "berberine" })
        #expect(berberine.pregnancyCaution?.isEmpty == false)
        let folate = try #require(PCOSSupplements.catalog.first { $0.key == "folate" })
        #expect(folate.pregnancyCaution == nil)

        let projectRoot = try TestHelpers.projectRoot(from: #filePath)
        let logView = try String(contentsOf: projectRoot.appendingPathComponent("PCOS/PCOS/Features/Supplements/Views/SupplementLogView.swift"), encoding: .utf8)
        #expect(logView.contains("SupplementPregnancyGuidance"))
        #expect(logView.contains("appState.lifecycleMode == .pregnant"))
    }
}

@Suite("Glucose pattern phase guardrails", .serialized)
@MainActor
struct GlucosePhaseGuardrailTests {
    private func reading(daysAgo: Int, value: Double, type: GlucoseReadingType = .fasting) -> BloodSugarReading {
        BloodSugarReading(timestamp: Calendar.current.date(byAdding: .day, value: -daysAgo, to: Date())!, glucoseValue: value, readingType: type)
    }

    @Test("A single long anovulatory cycle yields no phase split")
    func longCycleYieldsNoPhaseSplit() {
        let service = InsulinResistanceMetricService()
        let start = Calendar.current.date(byAdding: .day, value: -60, to: Date())!
        let cycle = Cycle(startDate: start, endDate: Date(), lengthDays: 60, ovulationStatus: .anovulatory)
        let readings = (1...40).map { reading(daysAgo: $0, value: 90 + Double($0 % 7)) }

        #expect(service.cyclePhaseAverages(readings: readings, cycles: [cycle]).isEmpty)
        #expect(service.calculateMetrics(readings: readings, cycles: [cycle]).lutealVsFollicularDelta == nil)
    }

    @Test("Stable ovulatory cycles still produce phase averages")
    func stableCyclesProducePhases() {
        let service = InsulinResistanceMetricService()
        let calendar = Calendar.current
        var cycles: [Cycle] = []
        var start = calendar.date(byAdding: .day, value: -84, to: Date())!
        for _ in 0..<3 {
            let end = calendar.date(byAdding: .day, value: 28, to: start)!
            cycles.append(Cycle(startDate: start, endDate: end, lengthDays: 28, ovulationStatus: .ovulatory))
            start = end
        }
        let readings = (1...80).map { reading(daysAgo: $0, value: 88 + Double($0 % 9)) }
        #expect(!service.cyclePhaseAverages(readings: readings, cycles: cycles).isEmpty)
    }

    @Test("History screen frames the metrics as glucose patterns, not an insulin-resistance verdict")
    func historyCopyIsHonest() throws {
        let projectRoot = try TestHelpers.projectRoot(from: #filePath)
        let source = try String(contentsOf: projectRoot.appendingPathComponent("PCOS/PCOS/Features/BloodSugar/Views/BloodSugarHistoryView.swift"), encoding: .utf8)
        #expect(!source.contains("\"Insulin Resistance Indicators\""))
        #expect(source.contains("Normal fingerstick glucose does not rule out insulin resistance"))
    }
}
