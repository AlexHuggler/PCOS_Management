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

struct SupplementDosageChange: Identifiable {
    let id: String
    let supplementName: String
    let date: Date
    let previousDosageMg: Double
    let newDosageMg: Double
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
            InsightRefreshCoordinator.invalidate()
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
            InsightRefreshCoordinator.invalidate()
        } catch {
            Logger.database.error("Failed to toggle supplement taken state: \(error.localizedDescription)")
        }
    }

    /// Fetch all supplement logs for today.
    func fetchTodaysLogs() -> [SupplementLog] {
        let calendar = Calendar.current
        let startOfDay = calendar.startOfDay(for: Date())
        guard let endOfDay = calendar.endOfDay(for: Date()) else { return [] }

        return fetchLogs(startDate: startOfDay, endDate: endOfDay)
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

    func hasYesterdayLogs() -> Bool {
        !fetchYesterdayLogs().isEmpty
    }

    func repeatYesterdaySupplements() throws -> Int {
        let calendar = Calendar.current
        let todayStart = calendar.startOfDay(for: Date())
        let yesterdayLogs = fetchYesterdayLogs()

        guard !yesterdayLogs.isEmpty else { return 0 }

        var existingKeys = Set(fetchTodaysLogs().map { repeatKey(for: $0, calendar: calendar) })
        var insertedCount = 0

        for log in yesterdayLogs {
            let trimmedName = log.supplementName.trimmingCharacters(in: .whitespacesAndNewlines)
            guard !trimmedName.isEmpty else { continue }

            let trimmedBrand = log.brand?.trimmingCharacters(in: .whitespacesAndNewlines)
            let repeatedTime = repeatedTime(from: log.timeTaken, on: todayStart, calendar: calendar)
            let key = repeatKey(
                name: trimmedName,
                dosage: log.dosageMg,
                brand: trimmedBrand,
                time: repeatedTime,
                calendar: calendar
            )

            guard existingKeys.insert(key).inserted else { continue }

            modelContext.insert(
                SupplementLog(
                    date: todayStart,
                    supplementName: trimmedName,
                    dosageMg: log.dosageMg,
                    timeTaken: repeatedTime,
                    taken: true,
                    brand: trimmedBrand?.isEmpty == false ? trimmedBrand : nil
                )
            )
            insertedCount += 1
        }

        guard insertedCount > 0 else { return 0 }

        do {
            try modelContext.save()
            InsightRefreshCoordinator.invalidate()
            return insertedCount
        } catch {
            Logger.database.error("Failed to repeat yesterday's supplements: \(error.localizedDescription)")
            throw error
        }
    }

    func dosageChanges(days: Int) -> [SupplementDosageChange] {
        let logs = fetchLogs(days: days)
            .filter { $0.dosageMg != nil }
            .sorted { lhs, rhs in
                if lhs.supplementName != rhs.supplementName {
                    return lhs.supplementName < rhs.supplementName
                }
                return lhs.timeTaken < rhs.timeTaken
            }

        let grouped = Dictionary(grouping: logs, by: \.supplementName)
        var changes: [SupplementDosageChange] = []

        for (name, entries) in grouped {
            var lastDosage: Double?
            for entry in entries {
                guard let dosage = entry.dosageMg else { continue }
                if let lastDosage, abs(lastDosage - dosage) >= 0.001 {
                    changes.append(
                        SupplementDosageChange(
                            id: "\(name)-\(entry.id.uuidString)",
                            supplementName: name,
                            date: entry.timeTaken,
                            previousDosageMg: lastDosage,
                            newDosageMg: dosage
                        )
                    )
                }
                lastDosage = dosage
            }
        }

        return changes.sorted { $0.date > $1.date }
    }

    /// Delete a supplement log entry.
    func deleteLog(_ log: SupplementLog) {
        modelContext.delete(log)
        do {
            try modelContext.save()
            InsightRefreshCoordinator.invalidate()
        } catch {
            Logger.database.error("Failed to delete supplement log: \(error.localizedDescription)")
        }
    }

    /// Reset the form state.
    func reset() {
        supplementName = ""
        dosageText = ""
        brand = ""
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
            return String(localized: "No default dosage", comment: "Supplement picker helper text when a supplement has no default dosage.")
        }
        return String(
            localized: "Recommended dosage: \(formattedDosage(dosage)) mg",
            comment: "Supplement picker helper text showing the recommended dosage in milligrams."
        )
    }

    func recommendedDosageValue(for supplement: PCOSSupplement?) -> String? {
        guard let dosage = recommendedDosageMg(for: supplement) else { return nil }
        return formattedDosage(dosage)
    }

    private func formattedDosage(_ dosage: Double) -> String {
        if dosage.rounded(.towardZero) == dosage {
            return L10n.decimal(dosage, fractionDigits: 0)
        }
        return L10n.decimal(dosage, fractionDigits: 1)
    }

    private func fetchYesterdayLogs() -> [SupplementLog] {
        let calendar = Calendar.current
        let todayStart = calendar.startOfDay(for: Date())
        guard let yesterdayStart = calendar.date(byAdding: .day, value: -1, to: todayStart) else {
            return []
        }

        return fetchLogs(startDate: yesterdayStart, endDate: todayStart)
    }

    private func fetchLogs(
        startDate: Date,
        endDate: Date,
        sortBy: [SortDescriptor<SupplementLog>] = [SortDescriptor(\.timeTaken)]
    ) -> [SupplementLog] {
        let descriptor = FetchDescriptor<SupplementLog>(
            predicate: #Predicate<SupplementLog> { log in
                log.date >= startDate && log.date < endDate
            },
            sortBy: sortBy
        )

        do {
            return try modelContext.fetch(descriptor)
        } catch {
            Logger.database.error("Failed to fetch supplement logs between dates: \(error.localizedDescription)")
            return []
        }
    }

    private func repeatedTime(from time: Date, on day: Date, calendar: Calendar) -> Date {
        let components = calendar.dateComponents([.hour, .minute], from: time)
        return calendar.date(
            bySettingHour: components.hour ?? 0,
            minute: components.minute ?? 0,
            second: 0,
            of: day
        ) ?? day
    }

    private func repeatKey(for log: SupplementLog, calendar: Calendar) -> SupplementRepeatKey {
        repeatKey(
            name: log.supplementName,
            dosage: log.dosageMg,
            brand: log.brand,
            time: log.timeTaken,
            calendar: calendar
        )
    }

    private func repeatKey(
        name: String,
        dosage: Double?,
        brand: String?,
        time: Date,
        calendar: Calendar
    ) -> SupplementRepeatKey {
        let components = calendar.dateComponents([.hour, .minute], from: time)

        return SupplementRepeatKey(
            name: normalized(name),
            dosageKey: dosage.map { Int(($0 * 1_000).rounded()) },
            brand: normalized(brand ?? ""),
            hour: components.hour ?? 0,
            minute: components.minute ?? 0
        )
    }

    private func normalized(_ value: String) -> String {
        value.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
    }
}

private struct SupplementRepeatKey: Hashable {
    let name: String
    let dosageKey: Int?
    let brand: String
    let hour: Int
    let minute: Int
}
