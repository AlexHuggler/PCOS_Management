import SwiftUI

// Shared tap-first check-in controls for the onboarding first check-in (A5) and Today (A8).
// Calm by design: mood colours are small decorative dots, labels stay in the primary text colour,
// and nothing uses red alarm styling.

extension DailyMood {
    /// Decorative dot colour for the mood tile (not used to convey meaning on its own).
    var dotColor: Color {
        switch self {
        case .great: Color(red: 0.18, green: 0.53, blue: 0.34)
        case .good: Color(red: 0.42, green: 0.70, blue: 0.42)
        case .okay: Color(red: 0.83, green: 0.65, blue: 0.16)
        case .low: Color(red: 0.82, green: 0.49, blue: 0.27)
        case .awful: Color(red: 0.63, green: 0.26, blue: 0.35)
        }
    }
}

/// Five mood tiles. Tapping a tile selects it; there is no "wrong" answer.
struct MoodTileRow: View {
    let selected: DailyMood?
    var minHeight: CGFloat = 56
    let onSelect: (DailyMood) -> Void

    @Environment(\.dynamicTypeSize) private var dynamicTypeSize

    private var columns: [GridItem] {
        let count = dynamicTypeSize.isAccessibilitySize ? 3 : 5
        return Array(repeating: GridItem(.flexible(), spacing: AppTheme.spacing8), count: count)
    }

    var body: some View {
        LazyVGrid(columns: columns, spacing: AppTheme.spacing8) {
            ForEach(DailyMood.allCases) { mood in
                let isSelected = mood == selected
                Button { onSelect(mood) } label: {
                    VStack(spacing: AppTheme.spacing4) {
                        Circle()
                            .fill(mood.dotColor)
                            .frame(width: 16, height: 16)
                            .overlay(Circle().stroke(Color.white.opacity(isSelected ? 0.8 : 0), lineWidth: 1.5))
                        Text(mood.tileTitle)
                            .appFont(.caption, weight: .semibold)
                            .lineLimit(2)
                            .minimumScaleFactor(0.8)
                            .multilineTextAlignment(.center)
                    }
                    .foregroundStyle(isSelected ? AppTheme.premiumEditorCTAForeground : AppTheme.primaryText)
                    .frame(maxWidth: .infinity, minHeight: minHeight)
                    .padding(.vertical, AppTheme.spacing4)
                    .background(
                        RoundedRectangle(cornerRadius: AppTheme.cornerRadiusMedium, style: .continuous)
                            .fill(isSelected ? AppTheme.accentColor : AppTheme.cardBackground)
                    )
                    .overlay(
                        RoundedRectangle(cornerRadius: AppTheme.cornerRadiusMedium, style: .continuous)
                            .stroke(isSelected ? AppTheme.accentColor : AppTheme.cardBorder.opacity(0.35), lineWidth: 1)
                    )
                    .contentShape(RoundedRectangle(cornerRadius: AppTheme.cornerRadiusMedium, style: .continuous))
                }
                .buttonStyle(.plain)
                .accessibilityLabel(mood.tileTitle)
                .accessibilityAddTraits(isSelected ? [.isSelected] : [])
                .accessibilityIdentifier("checkin.mood.\(mood.rawValue)")
            }
        }
        .sensoryFeedback(.selection, trigger: selected)
    }
}

/// One symptom with a Mild / Moderate / Strong segmented choice (A5).
struct SymptomSeverityRow: View {
    let symptom: SymptomType
    let selected: QuickSeverity?
    let onSelect: (QuickSeverity) -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: AppTheme.spacing8) {
            Text(symptom.displayName)
                .appFont(.headline)
                .foregroundStyle(AppTheme.primaryText)
            HStack(spacing: 2) {
                ForEach(QuickSeverity.allCases) { severity in
                    let isSelected = severity == selected
                    Button { onSelect(severity) } label: {
                        Text(severity.title)
                            .appFont(.subheadline, weight: isSelected ? .semibold : .regular)
                            .lineLimit(1)
                            .minimumScaleFactor(0.75)
                            .foregroundStyle(isSelected ? AppTheme.premiumEditorCTAForeground : AppTheme.primaryText)
                            .frame(maxWidth: .infinity, minHeight: 44)
                            .background(
                                RoundedRectangle(cornerRadius: AppTheme.cornerRadiusSmall, style: .continuous)
                                    .fill(isSelected ? AppTheme.accentColor : Color.clear)
                            )
                            .contentShape(Rectangle())
                    }
                    .buttonStyle(.plain)
                    .accessibilityLabel(L10n.format("%@, %@", defaultValue: "%@, %@", symptom.displayName, severity.title))
                    .accessibilityAddTraits(isSelected ? [.isSelected] : [])
                    .accessibilityIdentifier("checkin.severity.\(symptom.rawValue).\(severity.rawValue)")
                }
            }
            .padding(2)
            .background(
                RoundedRectangle(cornerRadius: AppTheme.cornerRadiusMedium, style: .continuous)
                    .fill(Color(.tertiarySystemFill))
            )
        }
    }
}

/// Compact symptom chip for Today: one tap opens Mild / Moderate / Strong (A8).
struct SymptomQuickChip: View {
    let symptom: SymptomType
    let selected: QuickSeverity?
    let onSelect: (QuickSeverity) -> Void
    let onClear: () -> Void

    var body: some View {
        Menu {
            ForEach(QuickSeverity.allCases) { severity in
                Button { onSelect(severity) } label: {
                    if severity == selected {
                        Label(severity.title, systemImage: "checkmark")
                    } else {
                        Text(severity.title)
                    }
                }
            }
            if selected != nil {
                Button(L10n.string("Clear choice", defaultValue: "Clear choice"), action: onClear)
            }
        } label: {
            Text(selected.map { L10n.format("%@ · %@", defaultValue: "%@ · %@", symptom.displayName, $0.title) } ?? symptom.displayName)
                .appFont(.subheadline, weight: selected == nil ? .regular : .semibold)
                .foregroundStyle(selected == nil ? AppTheme.primaryText : AppTheme.premiumEditorCTAForeground)
                .padding(.horizontal, AppTheme.spacing12)
                .frame(minHeight: 44)
                .background(Capsule().fill(selected == nil ? AppTheme.cardBackground : AppTheme.accentColor))
                .overlay(Capsule().stroke(selected == nil ? AppTheme.cardBorder.opacity(0.45) : AppTheme.accentColor, lineWidth: 1))
                .contentShape(Capsule())
        }
        .accessibilityLabel(selected.map { L10n.format("%@, %@", defaultValue: "%@, %@", symptom.displayName, $0.title) } ?? symptom.displayName)
        .accessibilityIdentifier("checkin.chip.\(symptom.rawValue)")
    }
}

/// "Nothing to report today" — a recorded symptom-free day, not a skipped one.
struct NothingToReportChip: View {
    let isOn: Bool
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            Label {
                Text(L10n.string("Nothing to report today", defaultValue: "Nothing to report today"))
                    .appFont(.subheadline, weight: isOn ? .semibold : .regular)
            } icon: {
                if isOn { Image(systemName: "checkmark") }
            }
            .foregroundStyle(isOn ? AppTheme.premiumEditorCTAForeground : AppTheme.primaryText)
            .padding(.horizontal, AppTheme.spacing16)
            .frame(minHeight: 44)
            .background(Capsule().fill(isOn ? AppTheme.accentColor : AppTheme.cardBackground))
            .overlay(Capsule().stroke(isOn ? AppTheme.accentColor : AppTheme.cardBorder.opacity(0.45), lineWidth: 1))
            .contentShape(Capsule())
        }
        .buttonStyle(.plain)
        .accessibilityAddTraits(isOn ? [.isSelected] : [])
        .accessibilityIdentifier("checkin.nothing_to_report")
    }
}

/// Ring showing check-ins toward the first pattern ("3/7").
struct PatternProgressRing: View {
    let completed: Int
    let target: Int

    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    private var fraction: Double { target > 0 ? min(1, Double(completed) / Double(target)) : 0 }

    var body: some View {
        ZStack {
            Circle()
                .stroke(AppTheme.accentColor.opacity(AppTheme.opacityLight), lineWidth: 6)
            Circle()
                .trim(from: 0, to: fraction)
                .stroke(AppTheme.accentColor, style: StrokeStyle(lineWidth: 6, lineCap: .round))
                .rotationEffect(.degrees(-90))
                .animation(reduceMotion ? nil : .easeOut(duration: 0.4), value: fraction)
            Text(L10n.format("%lld/%lld", defaultValue: "%lld/%lld", Int64(completed), Int64(target)))
                .appFont(.subheadline, weight: .semibold)
                .foregroundStyle(AppTheme.primaryText)
                .minimumScaleFactor(0.7)
                .lineLimit(1)
        }
        .frame(width: 56, height: 56)
        .accessibilityHidden(true)
    }
}

/// Full-width capsule CTA used across the v1 onboarding.
struct JourneyPrimaryButton: View {
    let title: String
    var isProcessing = false
    var accessibilityIdentifier: String? = nil
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            ZStack {
                Text(title)
                    .appFont(.headline)
                    .multilineTextAlignment(.center)
                    .opacity(isProcessing ? 0 : 1)
                if isProcessing {
                    ProgressView().tint(AppTheme.premiumEditorCTAForeground)
                }
            }
            .foregroundStyle(AppTheme.premiumEditorCTAForeground)
            .frame(maxWidth: .infinity, minHeight: 52)
            .padding(.horizontal, AppTheme.spacing16)
            .background(Capsule().fill(AppTheme.accentColor))
            .contentShape(Capsule())
        }
        .buttonStyle(.plain)
        .disabled(isProcessing)
        .accessibilityIdentifier(accessibilityIdentifier ?? "journey.primary")
    }
}

/// Quiet text button under the primary CTA ("Do this later", "Not now").
struct JourneySecondaryButton: View {
    let title: String
    var accessibilityIdentifier: String? = nil
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            Text(title)
                .appFont(.subheadline, weight: .semibold)
                .foregroundStyle(AppTheme.secondaryText)
                .frame(maxWidth: .infinity, minHeight: 44)
                .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .accessibilityIdentifier(accessibilityIdentifier ?? "journey.secondary")
    }
}
