import Foundation

enum CycleEndReason: String, Codable, CaseIterable, Identifiable, Sendable {
    case natural
    case pregnancy
    case postpartum

    var id: String { rawValue }
}
