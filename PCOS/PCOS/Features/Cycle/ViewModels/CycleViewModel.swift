import SwiftUI
import SwiftData
import os

@Observable
@MainActor
final class CycleViewModel {
    private let queryService: CycleQueryService
    private let predictionService = CyclePredictionService()
    private let logService: CycleLogService

    var cycles: [Cycle] = []
    var currentCycleEntries: [CycleEntry] = []
    var prediction: CyclePredictionEngine.Prediction?
    var statistics: CycleStatistics?

    // Log period form state
    var selectedDate: Date = Date()
    var selectedFlowIntensity: FlowIntensity = .medium
    var periodNotes: String = ""
    var showingLogSheet: Bool = false

    init(modelContext: ModelContext) {
        self.queryService = CycleQueryService(modelContext: modelContext)
        self.logService = CycleLogService(modelContext: modelContext)
    }

    // MARK: - Data Loading

    func loadData() {
        cleanUpOrphanedEntries()
        fetchCycles()
        fetchCurrentCycleEntries()
        updatePrediction()
        updateStatistics()
    }

    private func cleanUpOrphanedEntries() {
        do {
            let orphanCount = try queryService.cleanUpOrphanedEntries()
            if orphanCount > 0 {
                Logger.database.info("Cleaned up \(orphanCount) orphaned cycle entries")
            }
        } catch {
            Logger.database.error("Failed to clean up orphaned entries: \(error.localizedDescription)")
        }
    }

    private func fetchCycles() {
        do {
            cycles = try queryService.fetchCycles()
        } catch {
            Logger.database.error("Failed to fetch cycles: \(error.localizedDescription)")
            cycles = []
        }
    }

    private func fetchCurrentCycleEntries() {
        do {
            currentCycleEntries = try queryService.fetchCurrentCycleEntries()
        } catch {
            Logger.database.error("Failed to fetch current cycle entries: \(error.localizedDescription)")
            currentCycleEntries = []
        }
    }

    // MARK: - Period Logging (delegates to CycleLogService)

    @discardableResult
    func logPeriodDay() throws -> PersistentIdentifier {
        let entryID = try logService.logPeriodDay(
            date: selectedDate,
            flowIntensity: selectedFlowIntensity,
            notes: periodNotes.isEmpty ? nil : periodNotes,
            existingCycles: cycles,
            recentEntries: currentCycleEntries
        )
        resetLogForm()
        loadData()
        return entryID
    }

    func logSkippedPeriod() throws {
        try logService.logSkippedPeriod(existingCycles: cycles)
        loadData()
    }

    // MARK: - Predictions

    private func updatePrediction() {
        prediction = predictionService.prediction(for: cycles)
    }

    private func updateStatistics() {
        statistics = predictionService.statistics(for: cycles)
    }

    // MARK: - Computed Helpers

    var currentCycleDayCount: Int? {
        guard let lastCycle = cycles.last, lastCycle.endDate == nil else { return nil }
        return Calendar.current.dateComponents(
            [.day],
            from: lastCycle.startDate,
            to: Date()
        ).day.map { $0 + 1 }
    }

    private static let dateRangeFormatter: DateFormatter = {
        let formatter = DateFormatter()
        formatter.dateFormat = "MMM d"
        return formatter
    }()

    var predictionRangeText: String? {
        guard let prediction else { return nil }
        let start = Self.dateRangeFormatter.string(from: prediction.earliestDate)
        let end = Self.dateRangeFormatter.string(from: prediction.latestDate)
        return "Your period may arrive between \(start)–\(end)"
    }

    var averageCycleLengthText: String? {
        guard let stats = statistics else { return nil }
        return "Your cycles average \(stats.formattedAverage) days (range: \(stats.rangeDescription))"
    }

    func resetLogForm() {
        selectedDate = Date()
        selectedFlowIntensity = .medium
        periodNotes = ""
        showingLogSheet = false
    }

    /// Returns cycle entries for a given month, keyed by day-of-month.
    func entriesForMonth(year: Int, month: Int) -> [Int: CycleEntry] {
        do {
            return try queryService.entriesForMonth(year: year, month: month)
        } catch {
            Logger.database.error("Failed to fetch entries for \(year)-\(month): \(error.localizedDescription)")
            return [:]
        }
    }
}
