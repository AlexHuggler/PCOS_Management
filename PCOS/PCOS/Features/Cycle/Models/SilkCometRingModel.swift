import Foundation

/// Pure geometry and gradient recipe for the Silk Comet hero ring: a single
/// arc whose gradient fades in from nothing at the tail (cycle day 1) and
/// gathers full color at the leading tip (today). Positions are fractions of
/// the full circle; colors are indices into the theme's silk palette.
struct SilkCometRingModel: Equatable {
    struct Stop: Equatable {
        let position: Double
        let opacity: Double
        let colorIndex: Int
    }

    let arcEnd: Double
    let stops: [Stop]
    let showsTip: Bool

    static let minimumArcEnd = 0.02
    static let maximumArcEnd = 0.98
    static let welcomeArcEnd = 0.25

    /// The silk recipe, relative to arc length (fraction, opacity, colorIndex).
    private static let relativeStops: [(Double, Double, Int)] = [
        (0.00, 0.00, 0),
        (0.17, 0.14, 0),
        (0.36, 0.45, 1),
        (0.62, 0.85, 2),
        (1.00, 1.00, 3),
    ]

    init(progress: Double, isWelcome: Bool = false, tailFloorOpacity: Double = 0) {
        let end = isWelcome
            ? Self.welcomeArcEnd
            : min(max(progress, Self.minimumArcEnd), Self.maximumArcEnd)

        arcEnd = end
        showsTip = !isWelcome
        stops = Self.relativeStops.map { fraction, opacity, colorIndex in
            Stop(
                position: fraction * end,
                opacity: max(opacity, tailFloorOpacity),
                colorIndex: colorIndex
            )
        }
    }
}
