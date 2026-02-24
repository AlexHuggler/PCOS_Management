import SwiftUI

/// Compact 1-5 severity picker using tappable dots.
struct SeverityPicker: View {
    let severity: Int
    let onSeverityChange: (Int) -> Void

    var body: some View {
        HStack(spacing: 4) {
            ForEach(1...5, id: \.self) { level in
                Circle()
                    .fill(level <= severity ? colorForLevel(level) : Color(.tertiarySystemFill))
                    .frame(width: 10, height: 10)
                    .onTapGesture {
                        // Tapping the current severity deselects (sets to 0)
                        if level == severity {
                            onSeverityChange(0)
                        } else {
                            onSeverityChange(level)
                        }
                    }
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

    private let labels = ["Mild", "Low", "Moderate", "High", "Severe"]

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

                            Text(labels[level - 1])
                                .font(.caption2)
                                .foregroundStyle(level == severity ? .primary : .secondary)
                        }
                    }
                    .buttonStyle(.plain)
                    .frame(maxWidth: .infinity)
                }
            }
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
