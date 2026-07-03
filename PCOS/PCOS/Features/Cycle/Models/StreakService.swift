import Foundation
import SwiftData
import os

/// Computes the current consecutive-day logging streak.
/// A day counts if it has at least one SymptomEntry or CycleEntry.
@MainActor
struct StreakService {
    /// Maximum reported streak; also bounds the fetch window so the
    /// computation runs exactly two fetches regardless of history size.
    private static let maxStreakDays = 366

    private let modelContext: ModelContext

    init(modelContext: ModelContext) {
        self.modelContext = modelContext
    }

    /// Returns the number of consecutive days (ending today or yesterday)
    /// that have at least one logged entry, capped at 366.
    func currentStreak() -> Int {
        let calendar = Calendar.current
        let today = calendar.startOfDay(for: Date())
        guard let lookbackStart = calendar.date(byAdding: .day, value: -Self.maxStreakDays, to: today) else {
            return 0
        }
        let windowStart = calendar.startOfDay(for: lookbackStart)

        let loggedDays = loggedDayStarts(since: windowStart, calendar: calendar)

        var streak = 0
        var checkDate = today

        while streak < Self.maxStreakDays {
            if loggedDays.contains(checkDate) {
                streak += 1
            } else if streak == 0, checkDate == today {
                // Today might not have entries yet — skip it once so
                // yesterday's streak still counts.
            } else {
                break
            }
            guard let previousDay = calendar.date(byAdding: .day, value: -1, to: checkDate) else { break }
            checkDate = calendar.startOfDay(for: previousDay)
        }

        return streak
    }

    /// Fetches all entry dates within the lookback window (one fetch per
    /// entity) and maps them to their start-of-day values.
    private func loggedDayStarts(since windowStart: Date, calendar: Calendar) -> Set<Date> {
        var days = Set<Date>()

        let symptomDescriptor = FetchDescriptor<SymptomEntry>(
            predicate: #Predicate<SymptomEntry> { $0.date >= windowStart }
        )
        do {
            for entry in try modelContext.fetch(symptomDescriptor) {
                days.insert(calendar.startOfDay(for: entry.date))
            }
        } catch {
            Logger.database.error("Failed to fetch symptom entries for streak: \(error.localizedDescription)")
        }

        let cycleDescriptor = FetchDescriptor<CycleEntry>(
            predicate: #Predicate<CycleEntry> { $0.date >= windowStart }
        )
        do {
            for entry in try modelContext.fetch(cycleDescriptor) {
                days.insert(calendar.startOfDay(for: entry.date))
            }
        } catch {
            Logger.database.error("Failed to fetch cycle entries for streak: \(error.localizedDescription)")
        }

        return days
    }
}
