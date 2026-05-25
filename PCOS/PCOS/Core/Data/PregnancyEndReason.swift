import Foundation

enum PregnancyEndReason: String, Codable, CaseIterable, Identifiable, Sendable {
    case delivery
    case loss
    case other

    var id: String { rawValue }

    var displayName: String {
        switch self {
        case .delivery:
            L10n.string("Delivery", defaultValue: "Delivery")
        case .loss:
            L10n.string("Pregnancy loss", defaultValue: "Pregnancy loss")
        case .other:
            L10n.string("Other", defaultValue: "Other")
        }
    }
}
