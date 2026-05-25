import Foundation

protocol FreeTierPolicyEnforcing {
    var symptomDailyLimit: Int? { get }
    var cycleHistoryDays: Int? { get }
    var symptomHistoryDays: Int? { get }

    func isSymptomSaveAllowed(selectedCount: Int, isPremium: Bool) -> Bool
    func earliestAccessibleCycleHistoryDate(now: Date, isPremium: Bool) -> Date?
    func earliestAccessibleSymptomHistoryDate(now: Date, isPremium: Bool) -> Date?
    func isCycleDateAccessible(_ date: Date, now: Date, isPremium: Bool) -> Bool
}

struct FreeTierPolicyService: FreeTierPolicyEnforcing {
    let symptomDailyLimit: Int?
    let cycleHistoryDays: Int?
    let symptomHistoryDays: Int?

    init(
        symptomDailyLimit: Int? = nil,
        cycleHistoryDays: Int? = 30,
        symptomHistoryDays: Int? = nil
    ) {
        self.symptomDailyLimit = symptomDailyLimit
        self.cycleHistoryDays = cycleHistoryDays
        self.symptomHistoryDays = symptomHistoryDays
    }

    func isSymptomSaveAllowed(selectedCount: Int, isPremium: Bool) -> Bool {
        guard !isPremium else { return true }
        guard let symptomDailyLimit else { return true }
        return selectedCount <= symptomDailyLimit
    }

    func earliestAccessibleCycleHistoryDate(now: Date, isPremium: Bool) -> Date? {
        guard !isPremium, let cycleHistoryDays else { return nil }
        let calendar = Calendar.current
        return calendar.date(byAdding: .day, value: -cycleHistoryDays, to: calendar.startOfDay(for: now))
    }

    func earliestAccessibleSymptomHistoryDate(now: Date, isPremium: Bool) -> Date? {
        guard !isPremium, let symptomHistoryDays else { return nil }
        let calendar = Calendar.current
        return calendar.date(byAdding: .day, value: -symptomHistoryDays, to: calendar.startOfDay(for: now))
    }

    func isCycleDateAccessible(_ date: Date, now: Date, isPremium: Bool) -> Bool {
        guard let earliest = earliestAccessibleCycleHistoryDate(now: now, isPremium: isPremium) else {
            return true
        }
        return date >= earliest
    }
}
