import SwiftUI
import SwiftData
import os

@Observable
@MainActor
final class PregnancyViewModel {
    private let modelContext: ModelContext
    private let defaults: UserDefaults

    var activePregnancy: PregnancyRecord?
    var pregnancyHistory: [PregnancyRecord] = []

    // Activation form state
    var activationStartDate: Date = Date()
    var activationDueDate: Date?
    var activationConfirmedByClinician: Bool = false

    // End form state
    var endDate: Date = Date()
    var endReason: PregnancyEndReason = .delivery

    init(modelContext: ModelContext, defaults: UserDefaults = .standard) {
        self.modelContext = modelContext
        self.defaults = defaults
    }

    // MARK: - Data Loading

    func loadData() {
        fetchActivePregnancy()
        fetchPregnancyHistory()
    }

    private func fetchActivePregnancy() {
        do {
            var descriptor = FetchDescriptor<PregnancyRecord>(
                predicate: #Predicate<PregnancyRecord> { $0.isActive == true }
            )
            descriptor.fetchLimit = 1
            activePregnancy = try modelContext.fetch(descriptor).first
        } catch {
            Logger.database.error("Failed to fetch active pregnancy: \(error.localizedDescription)")
            activePregnancy = nil
        }
    }

    private func fetchPregnancyHistory() {
        do {
            let descriptor = FetchDescriptor<PregnancyRecord>(
                sortBy: [SortDescriptor(\.startDate, order: .reverse)]
            )
            pregnancyHistory = try modelContext.fetch(descriptor)
        } catch {
            Logger.database.error("Failed to fetch pregnancy history: \(error.localizedDescription)")
            pregnancyHistory = []
        }
    }

    // MARK: - Activation

    func activatePregnancyMode(appState: AppState) throws {
        // Close current open cycle if any
        let cycleDescriptor = FetchDescriptor<Cycle>(
            sortBy: [SortDescriptor(\.startDate, order: .reverse)]
        )
        let cycles = try modelContext.fetch(cycleDescriptor)
        if let openCycle = cycles.first, openCycle.endDate == nil {
            openCycle.endDate = activationStartDate
            let calendar = Calendar.current
            let days = calendar.dateComponents([.day], from: openCycle.startDate, to: activationStartDate).day
            openCycle.lengthDays = days
            openCycle.endReason = .pregnancy
        }

        // Create pregnancy record
        let record = PregnancyRecord(
            startDate: activationStartDate,
            estimatedDueDate: activationDueDate,
            isActive: true
        )
        modelContext.insert(record)
        try modelContext.save()

        // Update app state
        appState.lifecycleMode = .pregnant

        // Record activation time for undo window
        defaults.set(Date().timeIntervalSince1970, forKey: "pregnancy.activationTimestamp")

        activePregnancy = record
        Logger.database.info("Pregnancy mode activated with start date \(self.activationStartDate)")
    }

    // MARK: - Undo Activation

    var canUndoActivation: Bool {
        guard activePregnancy != nil else { return false }
        let activationTimestamp = defaults.double(forKey: "pregnancy.activationTimestamp")
        guard activationTimestamp > 0 else { return false }
        let activationDate = Date(timeIntervalSince1970: activationTimestamp)
        return Date().timeIntervalSince(activationDate) < 24 * 60 * 60 // 24 hours
    }

    func undoActivation(appState: AppState) throws {
        guard let record = activePregnancy else { return }

        // Reopen the cycle that was closed by pregnancy activation
        let cycleDescriptor = FetchDescriptor<Cycle>(
            sortBy: [SortDescriptor(\.startDate, order: .reverse)]
        )
        let cycles = try modelContext.fetch(cycleDescriptor)
        if let lastCycle = cycles.first, lastCycle.endReason == .pregnancy {
            lastCycle.endDate = nil
            lastCycle.lengthDays = nil
            lastCycle.endReason = nil
        }

        // Delete pregnancy record
        modelContext.delete(record)
        try modelContext.save()

        // Reset app state
        appState.lifecycleMode = .cycling
        defaults.removeObject(forKey: "pregnancy.activationTimestamp")

        activePregnancy = nil
        Logger.database.info("Pregnancy mode activation undone")
    }

    // MARK: - End Pregnancy

    func endPregnancyMode(appState: AppState) throws {
        guard let record = activePregnancy else { return }

        record.endDate = endDate
        record.endReason = endReason
        record.isActive = false

        try modelContext.save()

        // Transition to postpartum
        appState.lifecycleMode = .postpartum
        defaults.removeObject(forKey: "pregnancy.activationTimestamp")

        activePregnancy = nil
        Logger.database.info("Pregnancy mode ended with reason: \(self.endReason.rawValue)")
    }

    // MARK: - Return to Cycling

    func returnToCycling(appState: AppState) {
        appState.lifecycleMode = .cycling
    }

    // MARK: - Gestational Calculations

    var gestationalWeeks: Int? {
        guard let pregnancy = activePregnancy else { return nil }
        let days = Calendar.current.dateComponents([.day], from: pregnancy.startDate, to: Date()).day ?? 0
        return max(0, days / 7)
    }

    var gestationalDays: Int? {
        guard let pregnancy = activePregnancy else { return nil }
        return Calendar.current.dateComponents([.day], from: pregnancy.startDate, to: Date()).day
    }

    var currentTrimester: Int? {
        guard let weeks = gestationalWeeks else { return nil }
        if weeks <= 12 { return 1 }
        if weeks <= 27 { return 2 }
        return 3
    }

    var gestationalDisplayText: String? {
        guard let weeks = gestationalWeeks else { return nil }
        if let trimester = currentTrimester {
            return L10n.format(
                "Week %lld • Trimester %lld",
                defaultValue: "Week %lld • Trimester %lld",
                Int64(weeks),
                Int64(trimester)
            )
        }
        return L10n.format(
            "Week %lld",
            defaultValue: "Week %lld",
            Int64(weeks)
        )
    }

    /// End reason of the most recent completed pregnancy, used to choose supportive copy.
    var latestEndedPregnancyEndReason: PregnancyEndReason? {
        pregnancyHistory.first { !$0.isActive && $0.endDate != nil }?.endReason
    }

    /// Day count is only meaningful after a delivery; a loss or other ending must not show one.
    var postpartumDayCount: Int? {
        guard let lastPregnancy = pregnancyHistory.first,
              !lastPregnancy.isActive,
              lastPregnancy.endReason == .delivery,
              let endDate = lastPregnancy.endDate else { return nil }
        return Calendar.current.dateComponents([.day], from: endDate, to: Date()).day.map { $0 + 1 }
    }

    // MARK: - Form Reset

    func resetActivationForm() {
        activationStartDate = Date()
        activationDueDate = nil
        activationConfirmedByClinician = false
    }

    func resetEndForm() {
        endDate = Date()
        endReason = .delivery
    }
}
