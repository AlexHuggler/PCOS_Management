import Foundation

/// Time-of-day-aware greeting for the Today header.
enum TodayGreeting {
    static func title(hour: Int, name: String?) -> String {
        let greeting: String
        switch hour {
        case 5..<12:
            greeting = L10n.string("Good morning", defaultValue: "Good morning")
        case 12..<17:
            greeting = L10n.string("Good afternoon", defaultValue: "Good afternoon")
        default:
            greeting = L10n.string("Good evening", defaultValue: "Good evening")
        }

        guard let name, !name.isEmpty else { return greeting }
        return "\(greeting), \(name)"
    }
}
