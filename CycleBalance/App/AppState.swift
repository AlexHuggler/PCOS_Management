import SwiftUI

enum AppTab: String, CaseIterable, Identifiable {
    case today
    case calendar
    case track
    case insights
    case settings

    var id: String { rawValue }

    var title: String {
        switch self {
        case .today: "Today"
        case .calendar: "Calendar"
        case .track: "Track"
        case .insights: "Insights"
        case .settings: "Settings"
        }
    }

    var systemImage: String {
        switch self {
        case .today: "sun.max"
        case .calendar: "calendar"
        case .track: "plus.circle.fill"
        case .insights: "chart.line.uptrend.xyaxis"
        case .settings: "gearshape"
        }
    }
}

@Observable
@MainActor
final class AppState {
    var selectedTab: AppTab = .today
    var isPremium: Bool = false
}
