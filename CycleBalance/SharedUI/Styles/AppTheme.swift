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

    /// Warm neutral for backgrounds — adaptive for dark mode
    static let warmNeutral = Color(
        UIColor { traits in
            traits.userInterfaceStyle == .dark
                ? UIColor(red: 0.12, green: 0.11, blue: 0.10, alpha: 1)
                : UIColor(red: 0.976, green: 0.965, blue: 0.949, alpha: 1)
        }
    )

    // MARK: - Flow Intensity Colors (adaptive for dark mode)

    static let flowSpotting = Color(
        UIColor { traits in
            traits.userInterfaceStyle == .dark
                ? UIColor(red: 0.75, green: 0.55, blue: 0.53, alpha: 1)
                : UIColor(red: 0.886, green: 0.690, blue: 0.667, alpha: 1)
        }
    )
    static let flowLight = Color(
        UIColor { traits in
            traits.userInterfaceStyle == .dark
                ? UIColor(red: 0.70, green: 0.42, blue: 0.40, alpha: 1)
                : UIColor(red: 0.831, green: 0.506, blue: 0.475, alpha: 1)
        }
    )
    static let flowMedium = Color(
        UIColor { traits in
            traits.userInterfaceStyle == .dark
                ? UIColor(red: 0.63, green: 0.30, blue: 0.28, alpha: 1)
                : UIColor(red: 0.737, green: 0.337, blue: 0.310, alpha: 1)
        }
    )
    static let flowHeavy = Color(
        UIColor { traits in
            traits.userInterfaceStyle == .dark
                ? UIColor(red: 0.52, green: 0.18, blue: 0.16, alpha: 1)
                : UIColor(red: 0.600, green: 0.200, blue: 0.180, alpha: 1)
        }
    )

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

    // MARK: - Spacing Scale

    /// 4pt — tight inner spacing (icon gaps, dot grids)
    static let spacing4: CGFloat = 4
    /// 8pt — standard inner spacing (chip padding, grid gaps)
    static let spacing8: CGFloat = 8
    /// 12pt — component spacing (card content gaps)
    static let spacing12: CGFloat = 12
    /// 16pt — section spacing (screen-edge padding, between cards)
    static let spacing16: CGFloat = 16
    /// 24pt — large spacing (card vertical padding)
    static let spacing24: CGFloat = 24
    /// 32pt — hero spacing (hero card padding)
    static let spacing32: CGFloat = 32

    // MARK: - Typography Helpers

    static func sectionHeader(_ text: String) -> some View {
        Text(text)
            .font(.headline)
            .foregroundStyle(.primary)
    }
}

// MARK: - Card Style ViewModifier

struct CardStyle: ViewModifier {
    var cornerRadius: CGFloat = 12

    func body(content: Content) -> some View {
        content
            .padding()
            .background(
                RoundedRectangle(cornerRadius: cornerRadius)
                    .fill(AppTheme.cardBackground)
            )
    }
}

extension View {
    func cardStyle(cornerRadius: CGFloat = 12) -> some View {
        modifier(CardStyle(cornerRadius: cornerRadius))
    }
}
