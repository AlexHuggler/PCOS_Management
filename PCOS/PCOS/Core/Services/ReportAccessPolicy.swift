import Foundation
import Observation

@MainActor
@Observable
final class ReportAccessPolicy {
    private enum Keys {
        static let consumedFreeExport = "reports.freeExportConsumed"
        static let openedReport = "reports.openedReport"
        static let exportedReport = "reports.exportedReport"
        static let dismissedInsightsBanner = "reports.dismissedInsightsBanner"
    }

    private let defaults: UserDefaults

    var hasConsumedFreeExport: Bool {
        didSet { defaults.set(hasConsumedFreeExport, forKey: Keys.consumedFreeExport) }
    }
    var hasOpenedReport: Bool {
        didSet { defaults.set(hasOpenedReport, forKey: Keys.openedReport) }
    }
    var hasExportedReport: Bool {
        didSet { defaults.set(hasExportedReport, forKey: Keys.exportedReport) }
    }
    var hasDismissedInsightsBanner: Bool {
        didSet { defaults.set(hasDismissedInsightsBanner, forKey: Keys.dismissedInsightsBanner) }
    }

    init(defaults: UserDefaults = .standard) {
        self.defaults = defaults
        hasConsumedFreeExport = defaults.bool(forKey: Keys.consumedFreeExport)
        hasOpenedReport = defaults.bool(forKey: Keys.openedReport)
        hasExportedReport = defaults.bool(forKey: Keys.exportedReport)
        hasDismissedInsightsBanner = defaults.bool(forKey: Keys.dismissedInsightsBanner)
    }

    func canGenerateReport(isPremium: Bool) -> Bool {
        isPremium || !hasConsumedFreeExport
    }

    func markReportOpened() {
        hasOpenedReport = true
    }

    func consumeFreeExportIfNeeded(isPremium: Bool) {
        if !isPremium {
            hasConsumedFreeExport = true
        }
        hasExportedReport = true
    }

    func dismissInsightsBanner() {
        hasDismissedInsightsBanner = true
    }

    func shouldShowInsightsBanner(completedCycles: Int) -> Bool {
        completedCycles >= 1 && !hasDismissedInsightsBanner && !hasOpenedReport && !hasExportedReport
    }
}
