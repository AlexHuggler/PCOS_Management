import SwiftUI
import SwiftData
import os

struct AdherenceStats {
    let totalScheduled: Int
    let totalTaken: Int
    var percentage: Double {
        totalScheduled > 0 ? Double(totalTaken) / Double(totalScheduled) * 100 : 0
    }
}

@Observable
@MainActor
final class SupplementViewModel {
    private let modelContext: ModelContext
    private let defaultsStore: UserEntryDefaultsStore
    private let suggestionProvider: SuggestionProvider

    // MARK: - Form State

    var supplementName: String = ""
    var dosageText: String = ""
    var brand: String = ""
    var scheduledTime: Date = Date()

    var supplementNameSuggestions: [String] {
        suggestionProvider.supplementNames()
    }

    var supplementBrandSuggestions: [String] {
        suggestionProvider.supplementBrands()
    }

    var preferredSupplementName: String {
        defaultsStore.lastSupplementName ?? ""
    }

    var preferredSupplementBrand: String {
        defaultsStore.lastSupplementBrand ?? ""
    }

    var preferredSupplementTime: Date {
        defaultsStore.lastSupplementTime
    }

    var hasPreferredSupplementTime: Bool {
        defaultsStore.hasLastSupplementTime
    }

    init(
        modelContext: ModelContext,
        defaultsStore: UserEntryDefaultsStore = .shared,
        suggestionProvider: SuggestionProvider? = nil
    ) {
        self.modelContext = modelContext
        self.defaultsStore = defaultsStore
        self.suggestionProvider = suggestionProvider ?? SuggestionProvider(defaultsStore: defaultsStore)
        self.supplementName = preferredSupplementName
        self.brand = preferredSupplementBrand
        self.scheduledTime = preferredSupplementTime
    }

    // MARK: - CRUD

    /// Create a new supplement log entry.
    func logSupplement(name: String, dosageMg: Double?, brand: String?, time: Date) throws {
        let calendar = Calendar.current
        let logDate = calendar.startOfDay(for: time)

        let entry = SupplementLog(
            date: logDate,
            supplementName: name,
            dosageMg: dosageMg,
            timeTaken: time,
            taken: true,
            brand: brand
        )
        modelContext.insert(entry)

        do {
            try modelContext.save()
            defaultsStore.lastSupplementName = name
            defaultsStore.lastSupplementBrand = brand
            defaultsStore.lastSupplementTime = time
            suggestionProvider.recordSupplementName(name)
            if let brand {
                suggestionProvider.recordSupplementBrand(brand)
            }
        } catch {
            Logger.database.error("Failed to save supplement log: \(error.localizedDescription)")
            throw error
        }
    }

    /// Toggle the taken boolean on an existing log and save.
    func toggleTaken(_ log: SupplementLog) {
        log.taken.toggle()
        do {
            try modelContext.save()
        } catch {
            Logger.database.error("Failed to toggle supplement taken state: \(error.localizedDescription)")
        }
    }

    /// Fetch all supplement logs for today.
    func fetchTodaysLogs() -> [SupplementLog] {
        let calendar = Calendar.current
        let startOfDay = calendar.startOfDay(for: Date())
        guard let endOfDay = calendar.endOfDay(for: Date()) else { return [] }

        let descriptor = FetchDescriptor<SupplementLog>(
            predicate: #Predicate<SupplementLog> { log in
                log.date >= startOfDay && log.date < endOfDay
            },
            sortBy: [SortDescriptor(\.timeTaken)]
        )

        do {
            return try modelContext.fetch(descriptor)
        } catch {
            Logger.database.error("Failed to fetch today's supplement logs: \(error.localizedDescription)")
            return []
        }
    }

    /// Fetch distinct supplement names the user has ever logged.
    func fetchUserSupplements() -> [String] {
        let descriptor = FetchDescriptor<SupplementLog>(
            sortBy: [SortDescriptor(\.supplementName)]
        )

        do {
            let allLogs = try modelContext.fetch(descriptor)
            let names = Set(allLogs.map(\.supplementName))
            return names.sorted()
        } catch {
            Logger.database.error("Failed to fetch user supplements: \(error.localizedDescription)")
            return []
        }
    }

    /// Calculate adherence stats over a given number of past days.
    func calculateAdherence(days: Int) -> AdherenceStats {
        let calendar = Calendar.current
        guard let startDate = calendar.date(byAdding: .day, value: -days, to: calendar.startOfDay(for: Date())) else {
            return AdherenceStats(totalScheduled: 0, totalTaken: 0)
        }

        let descriptor = FetchDescriptor<SupplementLog>(
            predicate: #Predicate<SupplementLog> { log in
                log.date >= startDate
            }
        )

        do {
            let logs = try modelContext.fetch(descriptor)
            let totalScheduled = logs.count
            let totalTaken = logs.filter(\.taken).count
            return AdherenceStats(totalScheduled: totalScheduled, totalTaken: totalTaken)
        } catch {
            Logger.database.error("Failed to calculate adherence: \(error.localizedDescription)")
            return AdherenceStats(totalScheduled: 0, totalTaken: 0)
        }
    }

    /// Fetch all supplement logs within a given number of past days.
    func fetchLogs(days: Int) -> [SupplementLog] {
        let calendar = Calendar.current
        guard let startDate = calendar.date(byAdding: .day, value: -days, to: calendar.startOfDay(for: Date())) else {
            return []
        }

        let descriptor = FetchDescriptor<SupplementLog>(
            predicate: #Predicate<SupplementLog> { log in
                log.date >= startDate
            },
            sortBy: [SortDescriptor(\.supplementName)]
        )

        do {
            return try modelContext.fetch(descriptor)
        } catch {
            Logger.database.error("Failed to fetch supplement logs for \(days) days: \(error.localizedDescription)")
            return []
        }
    }

    /// Delete a supplement log entry.
    func deleteLog(_ log: SupplementLog) {
        modelContext.delete(log)
        do {
            try modelContext.save()
        } catch {
            Logger.database.error("Failed to delete supplement log: \(error.localizedDescription)")
        }
    }

    /// Reset the form state.
    func reset() {
        supplementName = preferredSupplementName
        dosageText = ""
        brand = preferredSupplementBrand
        scheduledTime = preferredSupplementTime
    }

    func recommendedDosageMg(for supplement: PCOSSupplement?) -> Double? {
        guard let supplement, supplement.defaultDosageMg > 0 else {
            return nil
        }
        return supplement.defaultDosageMg
    }

    func recommendedDosageLabel(for supplement: PCOSSupplement?) -> String {
        guard let dosage = recommendedDosageMg(for: supplement) else {
            return "No default dosage"
        }
        return "Recommended dosage: \(formattedDosage(dosage)) mg"
    }

    func recommendedDosageValue(for supplement: PCOSSupplement?) -> String? {
        guard let dosage = recommendedDosageMg(for: supplement) else { return nil }
        return formattedDosage(dosage)
    }

    private func formattedDosage(_ dosage: Double) -> String {
        dosage.rounded(.towardZero) == dosage ? "\(Int(dosage))" : String(format: "%.1f", dosage)
    }
}
