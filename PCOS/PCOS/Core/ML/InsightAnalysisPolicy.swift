import Foundation

/// Calendar-day boundaries shared by readiness, charts, and observation analysis.
struct InsightAnalysisPolicy {
    static let symptomDays = 14
    static let lifestyleDays = 90
    static let supplementHistoryDays = 365
    static let minimumCompletedCycles = 3
    static let minimumLifestyleDays = 7

    static func window(days: Int, now: Date = Date(), calendar: Calendar = .current) -> DateInterval {
        let today = calendar.startOfDay(for: now)
        let start = calendar.date(byAdding: .day, value: -(days - 1), to: today) ?? today
        let end = calendar.date(byAdding: .day, value: 1, to: today) ?? now
        return DateInterval(start: start, end: end)
    }

    static func includes(_ date: Date, days: Int, now: Date = Date(), calendar: Calendar = .current) -> Bool {
        let interval = window(days: days, now: now, calendar: calendar)
        return date >= interval.start && date < interval.end
    }

    static func distinctDays(_ dates: [Date], days: Int, now: Date = Date(), calendar: Calendar = .current) -> Int {
        Set(dates.filter { includes($0, days: days, now: now, calendar: calendar) }.map { calendar.startOfDay(for: $0) }).count
    }
}

/// An observed day's symptom burden. Zero means an explicit symptom-free check-in;
/// an untouched day has no observation. This is never persisted as a SymptomEntry.
struct InsightSymptomDay {
    let date: Date
    let value: Double
    let recordCount: Int
    let isExplicitlySymptomFree: Bool
}

extension InsightAnalysisPolicy {
    @MainActor
    static func symptomObservations(
        symptoms: [SymptomEntry],
        dailyLogs: [DailyLog],
        days: Int = symptomDays,
        now: Date = Date(),
        calendar: Calendar = .current
    ) -> [InsightSymptomDay] {
        let entriesByDay = Dictionary(grouping: symptoms.filter { includes($0.date, days: days, now: now, calendar: calendar) }) {
            calendar.startOfDay(for: $0.date)
        }
        let reviewedByDay = Dictionary(grouping: dailyLogs.filter { $0.symptomsReviewed && includes($0.date, days: days, now: now, calendar: calendar) }) {
            calendar.startOfDay(for: $0.date)
        }
        return Set(entriesByDay.keys).union(reviewedByDay.keys).sorted().map { date in
            // Real symptom rows always take precedence, including imported rows
            // received after a symptom-free check-in was saved.
            if let entries = entriesByDay[date], !entries.isEmpty {
                return InsightSymptomDay(date: date, value: Double(entries.map(\.severity).reduce(0, +)) / Double(entries.count), recordCount: entries.count, isExplicitlySymptomFree: false)
            }
            return InsightSymptomDay(date: date, value: 0, recordCount: reviewedByDay[date]?.count ?? 0, isExplicitlySymptomFree: true)
        }
    }
}
