import SwiftUI

// Shared tap-first check-in controls for the onboarding first check-in (A5) and Today (A8).
// Calm by design: mood dots are tints of one calm hue (no red "grade"), labels stay in the primary
// text colour, every control is at least 44pt, and nothing uses alarm styling.

extension DailyMood {
    /// Tint strength of the decorative mood dot. One hue in five tints; the label carries meaning.
    var dotOpacity: Double {
        switch self {
        case .great: 1.0
        case .good: 0.78
        case .okay: 0.58
        case .low: 0.4
        case .awful: 0.26
        }
    }

    /// Decorative dot colour for the mood tile (never the only way the mood is shown).
    var dotColor: Color { AppTheme.accentColor.opacity(dotOpacity) }
}

/// The one check-in component (design review 5 Oct): mood tiles, symptom rows with 44pt
/// Mild / Moderate / Strong chips, and "Nothing to report today". Onboarding (A5) edits a draft;
/// Today (A8) saves each tap. The component only reports taps; callers decide what they mean.
struct QuickCheckInPanel: View {
    let input: QuickCheckInInput
    let symptoms: [SymptomType]
    var moodMinHeight: CGFloat = 56
    /// Onboarding sits on the grouped background, so the symptom rows get their own card there.
    var symptomsInCard = false
    var showsNothingToReport = true
    let onMood: (DailyMood) -> Void
    let onSeverity: (SymptomType, QuickSeverity) -> Void
    let onNothingToReport: () -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: AppTheme.spacing16) {
            MoodTileRow(selected: input.mood, minHeight: moodMinHeight, onSelect: onMood)

            if !symptoms.isEmpty {
                VStack(alignment: .leading, spacing: AppTheme.spacing8) {
                    Text(L10n.string("YOUR SYMPTOMS", defaultValue: "YOUR SYMPTOMS"))
                        .appFont(.caption, weight: .semibold)
                        .foregroundStyle(AppTheme.secondaryText)
                        .fixedSize(horizontal: false, vertical: true)
                        .accessibilityAddTraits(.isHeader)

                    symptomRows
                }
            }

            if showsNothingToReport {
                NothingToReportChip(isOn: input.nothingToReport, action: onNothingToReport)
            }
        }
    }

    @ViewBuilder
    private var symptomRows: some View {
        let rows = VStack(alignment: .leading, spacing: AppTheme.spacing16) {
            ForEach(symptoms, id: \.self) { symptom in
                SymptomSeverityRow(symptom: symptom, selected: input.severities[symptom]) { severity in
                    onSeverity(symptom, severity)
                }
            }
        }
        if symptomsInCard {
            rows
                .padding(AppTheme.spacing16)
                .frame(maxWidth: .infinity, alignment: .leading)
                .background(
                    RoundedRectangle(cornerRadius: AppTheme.cornerRadiusLarge, style: .continuous)
                        .fill(AppTheme.cardBackground)
                )
        } else {
            rows
        }
    }
}

/// Five mood tiles, exposed to VoiceOver as one group with the selected tile marked.
/// At accessibility text sizes the row wraps to two rows instead of shrinking the labels.
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
                            .fill(isSelected ? AppTheme.premiumEditorCTAForeground : mood.dotColor)
                            .frame(width: 16, height: 16)
                            .accessibilityHidden(true)
                        Text(mood.tileTitle)
                            .appFont(.subheadline, weight: .semibold)
                            .multilineTextAlignment(.center)
                            .fixedSize(horizontal: false, vertical: true)
                    }
                    .foregroundStyle(isSelected ? AppTheme.premiumEditorCTAForeground : AppTheme.primaryText)
                    .frame(maxWidth: .infinity, minHeight: max(minHeight, 44))
                    .padding(.vertical, AppTheme.spacing4)
                    .background(
                        RoundedRectangle(cornerRadius: AppTheme.cornerRadiusMedium, style: .continuous)
                            .fill(isSelected ? AppTheme.accentColor : AppTheme.cardBackground)
                    )
                    .overlay(
                        RoundedRectangle(cornerRadius: AppTheme.cornerRadiusMedium, style: .continuous)
                            .stroke(isSelected ? AppTheme.accentColor : AppTheme.cardBorder, lineWidth: 1)
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
        .accessibilityElement(children: .contain)
        .accessibilityLabel(L10n.string("Mood", defaultValue: "Mood"))
    }
}

/// One symptom with 44pt Mild / Moderate / Strong chips (A5, A8). VoiceOver reads
/// "Fatigue, Moderate, selected". The chips stack at accessibility text sizes.
struct SymptomSeverityRow: View {
    let symptom: SymptomType
    let selected: QuickSeverity?
    let onSelect: (QuickSeverity) -> Void

    @Environment(\.dynamicTypeSize) private var dynamicTypeSize

    private var chipLayout: AnyLayout {
        dynamicTypeSize.isAccessibilitySize
            ? AnyLayout(VStackLayout(alignment: .leading, spacing: AppTheme.spacing8))
            : AnyLayout(HStackLayout(spacing: AppTheme.spacing8))
    }

    var body: some View {
        VStack(alignment: .leading, spacing: AppTheme.spacing8) {
            Text(symptom.displayName)
                .appFont(.headline)
                .foregroundStyle(AppTheme.primaryText)
                .fixedSize(horizontal: false, vertical: true)
            chipLayout {
                ForEach(QuickSeverity.allCases) { severity in
                    let isSelected = severity == selected
                    Button { onSelect(severity) } label: {
                        Text(severity.title)
                            .appFont(.subheadline, weight: isSelected ? .semibold : .regular)
                            .multilineTextAlignment(.center)
                            .fixedSize(horizontal: false, vertical: true)
                            .foregroundStyle(isSelected ? AppTheme.premiumEditorCTAForeground : AppTheme.primaryText)
                            .padding(.horizontal, AppTheme.spacing8)
                            .frame(maxWidth: .infinity, minHeight: 44)
                            .background(Capsule().fill(isSelected ? AppTheme.accentColor : AppTheme.cardBackground))
                            .overlay(Capsule().stroke(isSelected ? AppTheme.accentColor : AppTheme.cardBorder, lineWidth: 1))
                            .contentShape(Capsule())
                    }
                    .buttonStyle(.plain)
                    .accessibilityLabel(L10n.format("%@, %@", defaultValue: "%@, %@", symptom.displayName, severity.title))
                    .accessibilityAddTraits(isSelected ? [.isSelected] : [])
                    .accessibilityIdentifier("checkin.severity.\(symptom.rawValue).\(severity.rawValue)")
                }
            }
        }
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
                    .fixedSize(horizontal: false, vertical: true)
            } icon: {
                if isOn { Image(systemName: "checkmark").accessibilityHidden(true) }
            }
            .foregroundStyle(isOn ? AppTheme.premiumEditorCTAForeground : AppTheme.primaryText)
            .padding(.horizontal, AppTheme.spacing16)
            .padding(.vertical, AppTheme.spacing8)
            .frame(minHeight: 44)
            .background(Capsule().fill(isOn ? AppTheme.accentColor : AppTheme.cardBackground))
            .overlay(Capsule().stroke(isOn ? AppTheme.accentColor : AppTheme.cardBorder, lineWidth: 1))
            .contentShape(Capsule())
        }
        .buttonStyle(.plain)
        .accessibilityAddTraits(isOn ? [.isSelected] : [])
        .accessibilityIdentifier("checkin.nothing_to_report")
    }
}

/// Ring showing check-ins toward the first pattern ("3/7"). It grows with the text size instead of
/// shrinking the count, and VoiceOver reads "3 of 7 check-ins toward your first pattern".
struct PatternProgressRing: View {
    let completed: Int
    let target: Int

    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @ScaledMetric(relativeTo: .subheadline) private var diameter: CGFloat = 56

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
                .fixedSize()
        }
        .frame(width: diameter, height: diameter)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(L10n.string("First pattern", defaultValue: "First pattern"))
        .accessibilityValue(
            L10n.format(
                "%lld of %lld check-ins toward your first pattern",
                defaultValue: "%lld of %lld check-ins toward your first pattern",
                Int64(completed),
                Int64(target)
            )
        )
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
