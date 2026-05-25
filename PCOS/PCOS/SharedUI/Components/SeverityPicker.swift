import SwiftUI

/// Compact 1-5 severity picker using tappable dots with text labels.
struct SeverityPicker: View {
    let severity: Int
    let onSeverityChange: (Int) -> Void

    static let noneLabel = String(localized: "None", comment: "Accessibility severity label when no symptom severity is selected.")

    static var labels: [String] {
        [
            String(localized: "Mild", comment: "Full severity label for level 1 symptoms."),
            String(localized: "Low", comment: "Full severity label for level 2 symptoms."),
            String(localized: "Moderate", comment: "Full severity label for level 3 symptoms."),
            String(localized: "High", comment: "Full severity label for level 4 symptoms."),
            String(localized: "Severe", comment: "Full severity label for level 5 symptoms."),
        ]
    }

    private static var shortLabels: [String] {
        [
            String(localized: "Mild", comment: "Compact severity label for level 1 symptoms."),
            String(localized: "Low", comment: "Compact severity label for level 2 symptoms."),
            String(localized: "Med", comment: "Compact severity label for level 3 symptoms."),
            String(localized: "High", comment: "Compact severity label for level 4 symptoms."),
            String(localized: "Severe", comment: "Compact severity label for level 5 symptoms."),
        ]
    }

    static func label(for severity: Int) -> String {
        guard severity >= 1 && severity <= labels.count else { return noneLabel }
        return labels[severity - 1]
    }

    var body: some View {
        VStack(spacing: 2) {
            HStack(spacing: 2) {
                ForEach(1...5, id: \.self) { level in
                    Circle()
                        .fill(level <= severity ? colorForLevel(level) : Color(.tertiarySystemFill))
                        .frame(width: 18, height: 18)
                        .frame(width: 32, height: 32)
                        .contentShape(Rectangle())
                        .onTapGesture {
                            if level == severity {
                                onSeverityChange(0)
                            } else {
                                onSeverityChange(level)
                            }
                        }
                        .accessibilityLabel(
                            String(
                                localized: "\(Self.labels[level - 1]) severity",
                                comment: "Accessibility label for an individual severity level button."
                            )
                        )
                        .accessibilityValue(
                            String(
                                localized: "Level \(level) of 5",
                                comment: "Accessibility value indicating the numeric severity level."
                            )
                        )
                        .accessibilityAddTraits(level == severity ? .isSelected : [])
                        .accessibilityHint(
                            level == severity
                                ? String(localized: "Double tap to deselect", comment: "Accessibility hint for the selected severity button.")
                                : String(localized: "Double tap to select", comment: "Accessibility hint for an unselected severity button.")
                        )
                }
            }

            if severity > 0 {
                Text(Self.shortLabels[severity - 1])
                    .appFont(.caption2, weight: .medium)
                    .foregroundStyle(colorForLevel(severity))
                    .transition(.opacity)
            }
        }
    }

    private func colorForLevel(_ level: Int) -> Color {
        AppTheme.severityColor(for: level)
    }
}

/// Larger severity picker for detail views with labels.
struct SeveritySlider: View {
    @Binding var severity: Int

    var body: some View {
        VStack(spacing: AppTheme.spacing8) {
            HStack {
                ForEach(1...5, id: \.self) { level in
                    Button {
                        severity = level
                    } label: {
                        VStack(spacing: AppTheme.spacing4) {
                            Circle()
                                .fill(level <= severity
                                      ? AppTheme.severityColor(for: level)
                                      : Color(.tertiarySystemFill))
                                .frame(width: 28, height: 28)

                            Text(SeverityPicker.labels[level - 1])
                                .appFont(.caption2)
                                .foregroundStyle(level == severity ? .primary : .secondary)
                        }
                    }
                    .buttonStyle(.plain)
                    .frame(maxWidth: .infinity)
                }
            }
            .sensoryFeedback(.selection, trigger: severity)
        }
    }
}

#Preview {
    VStack(spacing: 20) {
        SeverityPicker(severity: 3) { _ in }

        SeveritySlider(severity: .constant(4))
    }
    .padding()
}
