import Foundation

extension Calendar {
    /// Returns the start of the next day for the given date (i.e., midnight ending the day).
    func endOfDay(for date: Date) -> Date? {
        self.date(byAdding: .day, value: 1, to: startOfDay(for: date))
    }

    /// Returns the first moment of the month containing the given date.
    func startOfMonth(for date: Date) -> Date? {
        self.date(from: dateComponents([.year, .month], from: date))
    }

    /// Returns the first moment of the month *after* the one containing the given date.
    func endOfMonth(for date: Date) -> Date? {
        guard let start = startOfMonth(for: date),
              let dayCount = range(of: .day, in: .month, for: start)?.count else {
            return nil
        }
        return self.date(byAdding: .day, value: dayCount, to: start)
    }
}
