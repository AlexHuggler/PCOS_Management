import Foundation
import SwiftData
import os

/// Computes the current consecutive-day logging streak.
/// A day counts if it has at least one SymptomEntry or CycleEntry.
@MainActor
struct StreakService {
    private let modelContext: ModelContext

    init(modelContext: ModelContext) {
        self.modelContext = modelContext
    }

    /// Returns the number of consecutive days (ending today or yesterday)
    /// that have at least one logged entry.
    func currentStreak() -> Int {
        let calendar = Calendar.current
        var streak = 0
        var checkDate = calendar.startOfDay(for: Date())

        while true {
            guard let nextDay = calendar.date(byAdding: .day, value: 1, to: checkDate) else { break }

            let hasSymptom = entryExists(
                type: SymptomEntry.self,
                from: checkDate,
                to: nextDay
            )
            let hasCycle = entryExists(
                type: CycleEntry.self,
                from: checkDate,
                to: nextDay
            )

            if hasSymptom || hasCycle {
                streak += 1
                guard let previousDay = calendar.date(byAdding: .day, value: -1, to: checkDate) else { break }
                checkDate = previousDay
            } else if streak == 0 {
                // Today might not have entries yet — check if yesterday starts a streak
                guard let previousDay = calendar.date(byAdding: .day, value: -1, to: checkDate) else { break }
                checkDate = previousDay
                // Only allow this skip once (for today)
                guard let nextAfterYesterday = calendar.date(byAdding: .day, value: 1, to: checkDate) else { break }
                let hasYesterdaySymptom = entryExists(
                    type: SymptomEntry.self,
                    from: checkDate,
                    to: nextAfterYesterday
                )
                let hasYesterdayCycle = entryExists(
                    type: CycleEntry.self,
                    from: checkDate,
                    to: nextAfterYesterday
                )
                if hasYesterdaySymptom || hasYesterdayCycle {
                    streak += 1
                    guard let dayBefore = calendar.date(byAdding: .day, value: -1, to: checkDate) else { break }
                    checkDate = dayBefore
                } else {
                    break
                }
            } else {
                break
            }
        }

        return streak
    }

    private func entryExists<T: PersistentModel>(type: T.Type, from: Date, to: Date) -> Bool {
        // Use fetchCount for efficiency
        if type == SymptomEntry.self {
            let descriptor = FetchDescriptor<SymptomEntry>(
                predicate: #Predicate<SymptomEntry> { $0.date >= from && $0.date < to }
            )
            do {
                return try modelContext.fetchCount(descriptor) > 0
            } catch {
                Logger.database.error("Failed to count symptom entries for streak: \(error.localizedDescription)")
                return false
            }
        } else if type == CycleEntry.self {
            let descriptor = FetchDescriptor<CycleEntry>(
                predicate: #Predicate<CycleEntry> { $0.date >= from && $0.date < to }
            )
            do {
                return try modelContext.fetchCount(descriptor) > 0
            } catch {
                Logger.database.error("Failed to count cycle entries for streak: \(error.localizedDescription)")
                return false
            }
        }
        return false
    }
}
