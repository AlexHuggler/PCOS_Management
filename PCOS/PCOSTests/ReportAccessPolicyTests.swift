import Testing
import Foundation
import SwiftData
@testable import PCOS

@Suite("Report Access Policy", .serialized)
@MainActor
struct ReportAccessPolicyTests {
    @Test("Premium users bypass the free export limit")
    func premiumUsersBypassLimit() {
        let (defaults, suiteName) = makeDefaults()
        defer { defaults.removePersistentDomain(forName: suiteName) }

        let policy = ReportAccessPolicy(defaults: defaults)
        policy.hasConsumedFreeExport = true

        #expect(policy.canGenerateReport(isPremium: true))
    }

    @Test("Successful generation consumes the free export for non-premium users")
    func successfulGenerationConsumesFreeExport() {
        let (defaults, suiteName) = makeDefaults()
        defer { defaults.removePersistentDomain(forName: suiteName) }

        let policy = ReportAccessPolicy(defaults: defaults)
        #expect(policy.canGenerateReport(isPremium: false))

        policy.consumeFreeExportIfNeeded(isPremium: false)

        #expect(policy.hasConsumedFreeExport)
        #expect(policy.hasExportedReport)
        #expect(!policy.canGenerateReport(isPremium: false))
    }

    @Test("Cancellation or error leaves the free export available")
    func cancellationLeavesFreeExportAvailable() {
        let (defaults, suiteName) = makeDefaults()
        defer { defaults.removePersistentDomain(forName: suiteName) }

        let policy = ReportAccessPolicy(defaults: defaults)
        policy.markReportOpened()

        #expect(!policy.hasConsumedFreeExport)
        #expect(policy.canGenerateReport(isPremium: false))
    }

    @Test("Insights banner requires completed cycle data and no prior export actions")
    func insightsBannerVisibilityReflectsState() {
        let (defaults, suiteName) = makeDefaults()
        defer { defaults.removePersistentDomain(forName: suiteName) }

        let policy = ReportAccessPolicy(defaults: defaults)
        #expect(!policy.shouldShowInsightsBanner(completedCycles: 0))
        #expect(policy.shouldShowInsightsBanner(completedCycles: 1))

        policy.dismissInsightsBanner()
        #expect(!policy.shouldShowInsightsBanner(completedCycles: 2))
    }
}

private extension ReportAccessPolicyTests {
    func makeDefaults() -> (UserDefaults, String) {
        let suiteName = "ReportAccessPolicyTests.\(UUID().uuidString)"
        let defaults = UserDefaults(suiteName: suiteName)!
        defaults.removePersistentDomain(forName: suiteName)
        return (defaults, suiteName)
    }
}

@Suite("Report ViewModel Export Flow", .serialized)
@MainActor
struct ReportViewModelExportFlowTests {
    private final class GeneratorCallCounter: @unchecked Sendable {
        var count = 0
    }

    @Test("Report view model marks selected empty ranges as empty")
    func reportSelectedRangeDetectsEmptyData() throws {
        let container = try TestHelpers.makeModelContainer()
        let viewModel = ReportViewModel(modelContext: container.mainContext)

        #expect(!viewModel.hasDataForSelectedSections)
    }

    @Test("Report view model detects data for selected sections")
    func reportSelectedRangeDetectsIncludedData() throws {
        let container = try TestHelpers.makeModelContainer()
        let context = container.mainContext
        context.insert(SymptomEntry(date: Date(), type: .fatigue, severity: 3))
        try context.save()

        let viewModel = ReportViewModel(modelContext: context)
        viewModel.includeCycles = false
        viewModel.includeSymptoms = true
        viewModel.includeBloodSugar = false
        viewModel.includeSupplements = false
        viewModel.includeMeals = false
        viewModel.includeWeightTrend = false
        viewModel.includeHairPhotos = false
        viewModel.includeInsights = false
        viewModel.includePregnancy = false

        #expect(viewModel.hasDataForSelectedSections)
    }

    @Test("Preparing export reuses the current PDF when the configuration is unchanged")
    func preparingExportReusesCurrentPDFWhenConfigurationIsUnchanged() async throws {
        let container = try TestHelpers.makeModelContainer()
        let counter = GeneratorCallCounter()

        let firstURL = URL(fileURLWithPath: "/tmp/report-export-1.pdf")
        let viewModel = ReportViewModel(
            modelContext: container.mainContext,
            generatePDF: { _, _, _, _ in
                counter.count += 1
                return firstURL
            }
        )

        let firstExport = await viewModel.prepareExport(appLanguage: .en)
        #expect(firstExport == .generated(firstURL))
        #expect(counter.count == 1)

        let secondExport = await viewModel.prepareExport(appLanguage: .en)
        #expect(secondExport == .existing(firstURL))
        #expect(counter.count == 1)
    }

    @Test("Preparing export regenerates the PDF after settings change")
    func preparingExportRegeneratesAfterSettingsChange() async throws {
        let container = try TestHelpers.makeModelContainer()
        let counter = GeneratorCallCounter()
        let urls = [
            URL(fileURLWithPath: "/tmp/report-export-1.pdf"),
            URL(fileURLWithPath: "/tmp/report-export-2.pdf"),
        ]

        let viewModel = ReportViewModel(
            modelContext: container.mainContext,
            generatePDF: { _, _, _, _ in
                let index = counter.count
                counter.count += 1
                return urls[min(index, urls.count - 1)]
            }
        )

        let firstExport = await viewModel.prepareExport(appLanguage: .en)
        #expect(firstExport == .generated(urls[0]))
        #expect(counter.count == 1)

        viewModel.includeMeals.toggle()

        let secondExport = await viewModel.prepareExport(appLanguage: .en)
        #expect(secondExport == .generated(urls[1]))
        #expect(counter.count == 2)
    }
}
