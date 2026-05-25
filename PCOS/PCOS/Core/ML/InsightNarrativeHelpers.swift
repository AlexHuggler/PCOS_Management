import Foundation

enum InsightNarrativeHelpers {
    static func severityWord(_ score: Double) -> String {
        switch score {
        case ..<1.5:
            return L10n.string("mild", defaultValue: "mild")
        case 1.5..<2.5:
            return L10n.string("light", defaultValue: "light")
        case 2.5..<3.5:
            return L10n.string("moderate", defaultValue: "moderate")
        case 3.5..<4.5:
            return L10n.string("noticeable", defaultValue: "noticeable")
        default:
            return L10n.string("significant", defaultValue: "significant")
        }
    }

    static func differenceWord(_ delta: Double) -> String {
        let absDelta = abs(delta)
        switch absDelta {
        case ..<0.5:
            return L10n.string("slightly", defaultValue: "slightly")
        case 0.5..<1.0:
            return L10n.string("noticeably", defaultValue: "noticeably")
        case 1.0..<2.0:
            return L10n.string("meaningfully", defaultValue: "meaningfully")
        default:
            return L10n.string("significantly", defaultValue: "significantly")
        }
    }
}
