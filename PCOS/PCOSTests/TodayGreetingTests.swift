import Testing
import Foundation
@testable import PCOS

@Suite("Today Greeting")
struct TodayGreetingTests {
    @Test("Morning hours greet with good morning", arguments: [5, 8, 11])
    func morningHours(hour: Int) {
        #expect(TodayGreeting.title(hour: hour, name: nil) == "Good morning")
    }

    @Test("Afternoon hours greet with good afternoon", arguments: [12, 14, 16])
    func afternoonHours(hour: Int) {
        #expect(TodayGreeting.title(hour: hour, name: nil) == "Good afternoon")
    }

    @Test("Evening and night hours greet with good evening", arguments: [17, 21, 23, 0, 4])
    func eveningHours(hour: Int) {
        #expect(TodayGreeting.title(hour: hour, name: nil) == "Good evening")
    }

    @Test("Name is appended when present")
    func appendsName() {
        #expect(TodayGreeting.title(hour: 9, name: "Aisha") == "Good morning, Aisha")
    }

    @Test("Empty name is treated as absent")
    func emptyNameOmitted() {
        #expect(TodayGreeting.title(hour: 9, name: "") == "Good morning")
    }
}
