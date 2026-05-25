import Foundation

enum LifecycleMode: String, Codable, CaseIterable, Identifiable, Sendable {
    case cycling
    case pregnant
    case postpartum

    var id: String { rawValue }
}
