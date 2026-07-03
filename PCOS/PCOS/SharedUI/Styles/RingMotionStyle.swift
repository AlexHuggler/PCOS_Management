import Foundation

/// Motion treatment for the Silk Comet hero ring. `subtle` is the shipped
/// default; `alive` is kept for on-device comparison and is only reachable
/// via the DEBUG settings toggle or the launch argument.
enum RingMotionStyle: String, CaseIterable {
    case subtle
    case alive
    case off

    static let defaultsKey = "appearance.ringMotionStyle"

    static func stored(defaults: UserDefaults = .standard) -> RingMotionStyle {
        guard let raw = defaults.string(forKey: defaultsKey),
              let style = RingMotionStyle(rawValue: raw) else {
            return .subtle
        }
        return style
    }

    static func store(_ style: RingMotionStyle, defaults: UserDefaults = .standard) {
        defaults.set(style.rawValue, forKey: defaultsKey)
    }

    /// Effective style after accessibility: Reduce Motion always wins.
    static func resolved(defaults: UserDefaults = .standard, reduceMotion: Bool) -> RingMotionStyle {
        reduceMotion ? .off : stored(defaults: defaults)
    }
}
