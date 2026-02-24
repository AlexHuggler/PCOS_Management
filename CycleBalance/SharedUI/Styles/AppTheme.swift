import SwiftUI

/// CycleBalance design system. Sage green, warm neutrals, soft coral.
/// Explicitly NOT pink/purple — medical-adjacent but warm.
enum AppTheme {

    // MARK: - Primary Colors

    /// Sage green accent — the app's signature color
    static let accentColor = Color("AccentColor")

    /// Fallback sage green if asset catalog color isn't available
    static let sage = Color(red: 0.384, green: 0.600, blue: 0.478)

    /// Soft coral for highlights and CTAs
    static let coralAccent = Color(red: 0.906, green: 0.486, blue: 0.416)

    /// Warm neutral for backgrounds
    static let warmNeutral = Color(red: 0.976, green: 0.965, blue: 0.949)

    // MARK: - Flow Intensity Colors

    static let flowSpotting = Color(red: 0.886, green: 0.690, blue: 0.667)
    static let flowLight = Color(red: 0.831, green: 0.506, blue: 0.475)
    static let flowMedium = Color(red: 0.737, green: 0.337, blue: 0.310)
    static let flowHeavy = Color(red: 0.600, green: 0.200, blue: 0.180)

    // MARK: - Semantic Colors

    static let cardBackground = Color(.secondarySystemGroupedBackground)
    static let groupedBackground = Color(.systemGroupedBackground)

    // MARK: - Severity Colors

    static func severityColor(for level: Int) -> Color {
        switch level {
        case 1: .green
        case 2: sage
        case 3: .orange
        case 4: coralAccent
        case 5: .red
        default: .secondary
        }
    }

    // MARK: - Typography Helpers

    static func sectionHeader(_ text: String) -> some View {
        Text(text)
            .font(.headline)
            .foregroundStyle(.primary)
    }
}
