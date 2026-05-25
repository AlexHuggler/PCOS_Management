import SwiftUI
import SwiftData
import os

@Observable
@MainActor
final class CycleViewModel {
    private let modelContext: ModelContext
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
        self.modelContext = modelContext
        self.queryService = CycleQueryService(modelContext: modelContext)
        self.logService = CycleLogService(modelContext: modelContext)
    }

    // MARK: - Data Loading

    func loadData(referenceDate: Date = Date()) {
        cleanUpOrphanedEntries()
        fetchCycles()
        fetchCurrentCycleEntries(referenceDate: referenceDate)
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

    private func fetchCurrentCycleEntries(referenceDate: Date = Date()) {
        do {
            currentCycleEntries = try queryService.fetchCurrentCycleEntries(referenceDate: referenceDate)
        } catch {
            Logger.database.error("Failed to fetch current cycle entries: \(error.localizedDescription)")
            currentCycleEntries = []
        }
    }

    // MARK: - Period Logging

    func evaluatePeriodTransition(startDate: Date) -> CycleTransitionDecision {
        logService.evaluatePeriodTransition(
            startDate: startDate,
            existingCycles: cycles,
            recentEntries: currentCycleEntries
        )
    }

    @discardableResult
    func savePeriodDay(
        date: Date,
        flowIntensity: FlowIntensity,
        notes: String,
        startingNewCycle: Bool = false
    ) throws -> CycleRangeSaveResult {
        let result = try logService.logPeriodDay(
            date: date,
            flowIntensity: flowIntensity,
            notes: notes,
            existingCycles: cycles,
            recentEntries: currentCycleEntries,
            startingNewCycle: startingNewCycle
        )
        resetLogForm()
        loadData(referenceDate: date)
        return result
    }

    @discardableResult
    func savePeriodRange(
        startDate: Date,
        endDate: Date,
        flowIntensity: FlowIntensity,
        notes: String,
        startingNewCycle: Bool = false
    ) throws -> CycleRangeSaveResult {
        let result = try logService.logPeriodRange(
            startDate: startDate,
            endDate: endDate,
            flowIntensity: flowIntensity,
            notes: notes,
            existingCycles: cycles,
            recentEntries: currentCycleEntries,
            startingNewCycle: startingNewCycle
        )
        resetLogForm()
        loadData(referenceDate: endDate)
        return result
    }

    @discardableResult
    func logPeriodDay() throws -> CycleRangeSaveResult {
        try savePeriodDay(
            date: selectedDate,
            flowIntensity: selectedFlowIntensity,
            notes: periodNotes
        )
    }

    @discardableResult
    func saveNoPeriodDay(date: Date = Date()) throws -> CycleRangeSaveResult {
        let result = try logService.logNoPeriodDay(
            date: date,
            existingCycles: cycles
        )
        loadData(referenceDate: date)
        return result
    }

    @discardableResult
    func logNoPeriodToday() throws -> CycleRangeSaveResult {
        try saveNoPeriodDay(date: Date())
    }

    func undoPeriodSave(using snapshot: CycleLogUndoSnapshot, referenceDate: Date = Date()) throws {
        try logService.undoSave(using: snapshot)
        loadData(referenceDate: referenceDate)
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

    func updateCurrentCycleSettings(
        manualCycleLengthOverrideDays: Int?,
        ovulationStatus: OvulationStatus
    ) throws {
        guard let currentCycle = cycles.last else { return }

        if let manualCycleLengthOverrideDays {
            currentCycle.manualCycleLengthOverrideDays = min(max(manualCycleLengthOverrideDays, 15), 120)
        } else {
            currentCycle.manualCycleLengthOverrideDays = nil
        }
        currentCycle.ovulationStatus = ovulationStatus

        try modelContext.save()
        updatePrediction()
        updateStatistics()
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

    var predictionPresentation: CyclePredictionPresentationState? {
        predictionService.presentation(for: prediction)
    }

    var hasActionablePrediction: Bool {
        guard let predictionPresentation else { return false }
        if case .actionable = predictionPresentation {
            return true
        }
        return false
    }

    var predictionRangeText: String? {
        guard case .actionable(let prediction) = predictionPresentation else { return nil }
        return formattedPredictionRangeText(for: prediction)
    }

    var predictionPrimaryText: String? {
        switch predictionPresentation {
        case .actionable(let prediction):
            return formattedPredictionRangeText(for: prediction)
        case .uncertain:
            return L10n.string(
                "Your next period is harder to estimate right now.",
                defaultValue: "Your next period is harder to estimate right now."
            )
        case .postpartumReEntry:
            return postpartumPredictionText
        case nil:
            return nil
        }
    }

    var predictionSecondaryText: String? {
        switch predictionPresentation {
        case .actionable(let prediction):
            return L10n.format(
                "%lld%% confidence • %lld-day window",
                defaultValue: "%lld%% confidence • %lld-day window",
                Int64((prediction.confidence * 100).rounded()),
                Int64(prediction.windowDays)
            )
        case .uncertain(let prediction, let reason):
            let confidencePercent = Int((prediction.confidence * 100).rounded())
            let windowDays = prediction.windowDays
            let explanation: String

            switch reason {
            case .wideWindow:
                explanation = L10n.format(
                    "Recent cycle variability is creating a broad %lld-day estimate.",
                    defaultValue: "Recent cycle variability is creating a broad %lld-day estimate.",
                    Int64(windowDays)
                )
            case .lowConfidence:
                explanation = L10n.format(
                    "Forecast confidence is %lld%% right now.",
                    defaultValue: "Forecast confidence is %lld%% right now.",
                    Int64(confidencePercent)
                )
            case .wideWindowAndLowConfidence:
                explanation = L10n.format(
                    "Recent cycle variability is creating a broad %lld-day estimate, and forecast confidence is %lld%%.",
                    defaultValue: "Recent cycle variability is creating a broad %lld-day estimate, and forecast confidence is %lld%%.",
                    Int64(windowDays),
                    Int64(confidencePercent)
                )
            }

            let suffix = L10n.string(
                "Keep logging period starts and symptoms to narrow future estimates.",
                defaultValue: "Keep logging period starts and symptoms to narrow future estimates."
            )
            return "\(explanation) \(suffix)"
        case .postpartumReEntry:
            return postpartumPredictionText
        case nil:
            return nil
        }
    }

    var predictionConfidenceValue: Double? {
        prediction?.confidence
    }

    var predictionWindowDays: Int? {
        prediction?.windowDays
    }

    var predictionConfidenceText: String? {
        guard let prediction else { return nil }
        return L10n.format(
            "%lld%% confidence",
            defaultValue: "%lld%% confidence",
            Int64((prediction.confidence * 100).rounded())
        )
    }

    private func formattedPredictionRangeText(for prediction: CyclePredictionEngine.Prediction) -> String {
        let formatStyle = Date.FormatStyle()
            .locale(L10n.locale())
            .month(.abbreviated)
            .day(.defaultDigits)
        let start = prediction.earliestDate.formatted(formatStyle)
        let end = prediction.latestDate.formatted(formatStyle)
        return L10n.format(
            "Your period may arrive between %@–%@",
            defaultValue: "Your period may arrive between %@–%@",
            start,
            end
        )
    }

    var averageCycleLengthText: String? {
        guard let stats = statistics else { return nil }
        return L10n.format(
            "Your cycles average %@ days (range: %@)",
            defaultValue: "Your cycles average %@ days (range: %@)",
            stats.formattedAverage,
            stats.rangeDescription
        )
    }

    var currentManualCycleLengthOverride: Int? {
        cycles.last?.manualCycleLengthOverrideDays
    }

    var currentOvulationStatus: OvulationStatus {
        cycles.last?.ovulationStatus ?? .unknown
    }

    // MARK: - Lifecycle-Aware Helpers

    /// Filter cycles that occurred before any pregnancy
    func prePregnancyCycles() -> [Cycle] {
        var result: [Cycle] = []
        for cycle in cycles {
            if cycle.endReason == .pregnancy { break }
            result.append(cycle)
        }
        return result
    }

    /// Filter cycles that occurred after the most recent pregnancy
    func postpartumCycles() -> [Cycle] {
        guard let lastPregnancyIndex = cycles.lastIndex(where: { $0.endReason == .pregnancy }) else {
            return cycles
        }
        let startIndex = cycles.index(after: lastPregnancyIndex)
        guard startIndex < cycles.endIndex else { return [] }
        return Array(cycles[startIndex...])
    }

    var postpartumCompletedCycleCount: Int {
        postpartumCycles().filter { $0.lengthDays != nil && !$0.isPredicted }.count
    }

    var postpartumPredictionText: String? {
        let count = postpartumCompletedCycleCount
        if count < 2 {
            return L10n.string(
                "We're learning your new cycle pattern. Keep logging period starts and we'll have an estimate for you soon.",
                defaultValue: "We're learning your new cycle pattern. Keep logging period starts and we'll have an estimate for you soon."
            )
        }
        return nil
    }

    func resetLogForm() {
        selectedDate = Date()
        selectedFlowIntensity = .medium
        periodNotes = ""
        showingLogSheet = false
    }

    /// Returns cycle entries for a given month, keyed by day-of-month.
    func entriesForMonth(year: Int, month: Int, earliestDate: Date? = nil) -> [Int: CycleEntry] {
        do {
            return try queryService.entriesForMonth(year: year, month: month, earliestDate: earliestDate)
        } catch {
            Logger.database.error("Failed to fetch entries for \(year)-\(month): \(error.localizedDescription)")
            return [:]
        }
    }
}
