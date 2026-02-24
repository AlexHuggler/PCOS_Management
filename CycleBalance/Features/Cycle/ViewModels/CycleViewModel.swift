import SwiftUI
import SwiftData
import os

@Observable
@MainActor
final class CycleViewModel {
    private let modelContext: ModelContext
    private let predictionEngine = CyclePredictionEngine()

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
    }

    // MARK: - Data Loading

    func loadData() {
        fetchCycles()
        fetchCurrentCycleEntries()
        updatePrediction()
        updateStatistics()
    }

    private func fetchCycles() {
        let descriptor = FetchDescriptor<Cycle>(
            sortBy: [SortDescriptor(\.startDate, order: .forward)]
        )
        do {
            cycles = try modelContext.fetch(descriptor)
        } catch {
            Logger.database.error("Failed to fetch cycles: \(error.localizedDescription)")
            cycles = []
        }
    }

    private func fetchCurrentCycleEntries() {
        let calendar = Calendar.current
        let startOfMonth = calendar.date(from: calendar.dateComponents([.year, .month], from: Date()))!
        let descriptor = FetchDescriptor<CycleEntry>(
            predicate: #Predicate<CycleEntry> { entry in
                entry.date >= startOfMonth
            },
            sortBy: [SortDescriptor(\.date, order: .forward)]
        )
        do {
            currentCycleEntries = try modelContext.fetch(descriptor)
        } catch {
            Logger.database.error("Failed to fetch current cycle entries: \(error.localizedDescription)")
            currentCycleEntries = []
        }
    }

    // MARK: - Period Logging

    func logPeriodDay() throws {
        let entry = CycleEntry(
            date: selectedDate,
            flowIntensity: selectedFlowIntensity,
            isPeriodDay: true,
            cyclePhase: .menstrual,
            notes: periodNotes.isEmpty ? nil : periodNotes
        )

        modelContext.insert(entry)
        assignEntryToCycle(entry)

        try modelContext.save()
        resetLogForm()
        loadData()
    }

    func logSkippedPeriod() throws {
        // Close the current cycle without an end period
        if let lastCycle = cycles.last, lastCycle.endDate == nil {
            lastCycle.endDate = Date()
            let daysBetween = Calendar.current.dateComponents(
                [.day],
                from: lastCycle.startDate,
                to: Date()
            ).day
            lastCycle.lengthDays = daysBetween
        }

        // Start a new cycle from today
        let newCycle = Cycle(startDate: Date(), isPredicted: false)
        modelContext.insert(newCycle)

        try modelContext.save()
        loadData()
    }

    // MARK: - Predictions

    private func updatePrediction() {
        guard let lastCycle = cycles.last else {
            prediction = nil
            return
        }
        prediction = predictionEngine.predictNextPeriod(
            cycles: cycles,
            lastPeriodStart: lastCycle.startDate
        )
    }

    private func updateStatistics() {
        statistics = predictionEngine.cycleStatistics(cycles: cycles)
    }

    // MARK: - Cycle Management

    private func assignEntryToCycle(_ entry: CycleEntry) {
        if let currentCycle = cycles.last, currentCycle.endDate == nil {
            // Check if this entry is part of the current period or a new one
            let lastPeriodEntry = currentCycleEntries.last { $0.isPeriodDay }
            if let lastEntry = lastPeriodEntry {
                let daysSinceLastPeriod = Calendar.current.dateComponents(
                    [.day],
                    from: lastEntry.date,
                    to: entry.date
                ).day ?? 0

                if daysSinceLastPeriod > 10 {
                    // New period started — close old cycle, create new one
                    currentCycle.endDate = entry.date
                    let length = Calendar.current.dateComponents(
                        [.day],
                        from: currentCycle.startDate,
                        to: entry.date
                    ).day
                    currentCycle.lengthDays = length

                    let newCycle = Cycle(startDate: entry.date)
                    modelContext.insert(newCycle)
                    entry.cycle = newCycle
                    return
                }
            }
            entry.cycle = currentCycle
        } else {
            // No open cycle — start a new one
            let newCycle = Cycle(startDate: entry.date)
            modelContext.insert(newCycle)
            entry.cycle = newCycle
        }
    }

    // MARK: - Helpers

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
        let calendar = Calendar.current
        var components = DateComponents()
        components.year = year
        components.month = month
        components.day = 1
        guard let startOfMonth = calendar.date(from: components),
              let range = calendar.range(of: .day, in: .month, for: startOfMonth) else {
            return [:]
        }

        let endOfMonth = calendar.date(byAdding: .day, value: range.count, to: startOfMonth)!
        let descriptor = FetchDescriptor<CycleEntry>(
            predicate: #Predicate<CycleEntry> { entry in
                entry.date >= startOfMonth && entry.date < endOfMonth
            },
            sortBy: [SortDescriptor(\.date)]
        )

        do {
            let entries = try modelContext.fetch(descriptor)
            var result: [Int: CycleEntry] = [:]
            for entry in entries {
                let day = calendar.component(.day, from: entry.date)
                result[day] = entry
            }
            return result
        } catch {
            Logger.database.error("Failed to fetch entries for \(year)-\(month): \(error.localizedDescription)")
            return [:]
        }
    }
}
