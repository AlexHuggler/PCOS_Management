import Testing
import Foundation
@testable import PCOS

@Suite("Calendar+SafeDate")
struct CalendarSafeDateTests {
    let calendar = Calendar.current

    // MARK: - endOfDay

    @Test("endOfDay returns start of next day")
    func endOfDayReturnsNextDayStart() {
        let date = Date()
        let startOfDay = calendar.startOfDay(for: date)
        let endOfDay = calendar.endOfDay(for: date)

        #expect(endOfDay != nil)
        let expected = calendar.date(byAdding: .day, value: 1, to: startOfDay)
        #expect(endOfDay == expected)
    }

    @Test("endOfDay for midnight returns next midnight")
    func endOfDayAtMidnight() {
        let midnight = calendar.startOfDay(for: Date())
        let endOfDay = calendar.endOfDay(for: midnight)

        #expect(endOfDay != nil)
        if let endOfDay {
            let components = calendar.dateComponents([.hour, .minute, .second], from: endOfDay)
            #expect(components.hour == 0)
            #expect(components.minute == 0)
            #expect(components.second == 0)
        }
    }

    @Test("endOfDay for year boundary")
    func endOfDayYearBoundary() {
        // Dec 31
        var components = DateComponents()
        components.year = 2025
        components.month = 12
        components.day = 31
        let dec31 = calendar.date(from: components)!
        let endOfDay = calendar.endOfDay(for: dec31)

        #expect(endOfDay != nil)
        if let endOfDay {
            let result = calendar.dateComponents([.year, .month, .day], from: endOfDay)
            #expect(result.year == 2026)
            #expect(result.month == 1)
            #expect(result.day == 1)
        }
    }

    // MARK: - startOfMonth

    @Test("startOfMonth returns first of month")
    func startOfMonthReturnsFirst() {
        let date = Date()
        let startOfMonth = calendar.startOfMonth(for: date)

        #expect(startOfMonth != nil)
        if let startOfMonth {
            let components = calendar.dateComponents([.day, .hour, .minute], from: startOfMonth)
            #expect(components.day == 1)
            #expect(components.hour == 0)
            #expect(components.minute == 0)
        }
    }

    @Test("startOfMonth preserves year and month")
    func startOfMonthPreservesYearMonth() {
        var components = DateComponents()
        components.year = 2026
        components.month = 7
        components.day = 15
        let midJuly = calendar.date(from: components)!
        let startOfMonth = calendar.startOfMonth(for: midJuly)

        #expect(startOfMonth != nil)
        if let startOfMonth {
            let result = calendar.dateComponents([.year, .month, .day], from: startOfMonth)
            #expect(result.year == 2026)
            #expect(result.month == 7)
            #expect(result.day == 1)
        }
    }

    // MARK: - endOfMonth

    @Test("endOfMonth returns first of next month")
    func endOfMonthReturnsNextMonthStart() {
        var components = DateComponents()
        components.year = 2026
        components.month = 3
        components.day = 15
        let midMarch = calendar.date(from: components)!
        let endOfMonth = calendar.endOfMonth(for: midMarch)

        #expect(endOfMonth != nil)
        if let endOfMonth {
            let result = calendar.dateComponents([.year, .month, .day], from: endOfMonth)
            #expect(result.year == 2026)
            #expect(result.month == 4)
            #expect(result.day == 1)
        }
    }

    @Test("endOfMonth handles February in leap year")
    func endOfMonthFebruaryLeapYear() {
        var components = DateComponents()
        components.year = 2024
        components.month = 2
        components.day = 10
        let feb2024 = calendar.date(from: components)!
        let endOfMonth = calendar.endOfMonth(for: feb2024)

        #expect(endOfMonth != nil)
        if let endOfMonth {
            let result = calendar.dateComponents([.year, .month, .day], from: endOfMonth)
            #expect(result.year == 2024)
            #expect(result.month == 3)
            #expect(result.day == 1)
        }
    }

    @Test("endOfMonth handles February in non-leap year")
    func endOfMonthFebruaryNonLeapYear() {
        var components = DateComponents()
        components.year = 2025
        components.month = 2
        components.day = 5
        let feb2025 = calendar.date(from: components)!
        let endOfMonth = calendar.endOfMonth(for: feb2025)

        #expect(endOfMonth != nil)
        if let endOfMonth {
            let result = calendar.dateComponents([.year, .month, .day], from: endOfMonth)
            #expect(result.year == 2025)
            #expect(result.month == 3)
            #expect(result.day == 1)
        }
    }

    @Test("endOfMonth handles December year boundary")
    func endOfMonthDecember() {
        var components = DateComponents()
        components.year = 2025
        components.month = 12
        components.day = 20
        let dec2025 = calendar.date(from: components)!
        let endOfMonth = calendar.endOfMonth(for: dec2025)

        #expect(endOfMonth != nil)
        if let endOfMonth {
            let result = calendar.dateComponents([.year, .month, .day], from: endOfMonth)
            #expect(result.year == 2026)
            #expect(result.month == 1)
            #expect(result.day == 1)
        }
    }
}
