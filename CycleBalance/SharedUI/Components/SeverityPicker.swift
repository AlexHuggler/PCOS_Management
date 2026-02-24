import SwiftUI

/// Compact 1-5 severity picker using tappable dots with text labels.
struct SeverityPicker: View {
    let severity: Int
    let onSeverityChange: (Int) -> Void

    static let labels = ["Mild", "Low", "Moderate", "High", "Severe"]
    private static let shortLabels = ["Mild", "Low", "Med", "High", "Severe"]

    var body: some View {
        VStack(spacing: 2) {
            HStack(spacing: 2) {
                ForEach(1...5, id: \.self) { level in
                    Circle()
                        .fill(level <= severity ? colorForLevel(level) : Color(.tertiarySystemFill))
                        .frame(width: 14, height: 14)
                        .frame(width: 28, height: 28)
                        .contentShape(Rectangle())
                        .onTapGesture {
                            if level == severity {
                                onSeverityChange(0)
                            } else {
                                onSeverityChange(level)
                            }
                        }
                        .accessibilityLabel("\(Self.labels[level - 1]) severity")
                        .accessibilityAddTraits(level == severity ? .isSelected : [])
                        .accessibilityHint(level == severity ? "Double tap to deselect" : "Double tap to select")
                }
            }
            .sensoryFeedback(.selection, trigger: severity)

            if severity > 0 {
                Text(Self.shortLabels[severity - 1])
                    .font(.caption2.weight(.medium))
                    .foregroundStyle(colorForLevel(severity))
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
        VStack(spacing: 8) {
            HStack {
                ForEach(1...5, id: \.self) { level in
                    Button {
                        severity = level
                    } label: {
                        VStack(spacing: 4) {
                            Circle()
                                .fill(level <= severity
                                      ? AppTheme.severityColor(for: level)
                                      : Color(.tertiarySystemFill))
                                .frame(width: 28, height: 28)

                            Text(SeverityPicker.labels[level - 1])
                                .font(.caption2)
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
