import SwiftUI

struct SymptomGridItem: View {
    let symptomType: SymptomType
    let severity: Int
    let onSeverityChange: (Int) -> Void

    var body: some View {
        VStack(spacing: AppTheme.spacing8) {
            // Icon
            Image(systemName: symptomType.systemImage)
                .appFont(.title2)
                .foregroundStyle(severity > 0 ? severityColor : .secondary)
                .frame(height: 32)

            // Name
            Text(symptomType.displayName)
                .appFont(.caption2, weight: .medium)
                .lineLimit(2)
                .multilineTextAlignment(.center)
                .minimumScaleFactor(0.8)
                .frame(height: 28)

            // Severity dots
            SeverityPicker(severity: severity, onSeverityChange: onSeverityChange)
        }
        .padding(.vertical, 12)
        .padding(.horizontal, 6)
        .frame(maxWidth: .infinity)
        .background(
            RoundedRectangle(cornerRadius: AppTheme.cornerRadiusMedium)
                .fill(severity > 0 ? severityColor.opacity(AppTheme.opacitySubtle) : Color(.tertiarySystemFill))
        )
        .overlay(
            RoundedRectangle(cornerRadius: AppTheme.cornerRadiusMedium)
                .strokeBorder(severity > 0 ? severityColor.opacity(AppTheme.opacityStrong) : .clear, lineWidth: 1)
        )
        .contentShape(Rectangle())
        .onTapGesture {
            // Cycle through: 0 -> 1 -> 2 -> 3 -> 4 -> 5 -> 0
            let next = severity >= 5 ? 0 : severity + 1
            onSeverityChange(next)
        }
        .contextMenu {
            ForEach(1...5, id: \.self) { level in
                Button {
                    onSeverityChange(level)
                } label: {
                    Label(SeverityPicker.labels[level - 1], systemImage: level <= severity ? "circle.fill" : "circle")
                }
            }
            if severity > 0 {
                Divider()
                Button(role: .destructive) {
                    onSeverityChange(0)
                } label: {
                    Label("Clear", systemImage: "xmark.circle")
                }
            }
        }
        .scaleEffect(severity > 0 ? 1.0 : 0.98)
        .animation(.easeInOut(duration: 0.2), value: severity)
        .sensoryFeedback(.selection, trigger: severity)
        .accessibilityElement(children: .combine)
        .accessibilityLabel(
            String(
                localized: "\(symptomType.displayName), severity \(severity > 0 ? SeverityPicker.label(for: severity) : SeverityPicker.noneLabel)",
                comment: "Accessibility label for a symptom selection tile."
            )
        )
        .accessibilityHint(
            String(
                localized: "Tap to cycle severity, long press for direct selection. Currently \(severity) of 5.",
                comment: "Accessibility hint explaining how to change symptom severity and announcing the current level."
            )
        )
        .accessibilityIdentifier("symptom_log.tile.\(symptomType.rawValue)")
    }

    private var severityColor: Color {
        switch severity {
        case 1: .green
        case 2: AppTheme.accentColor
        case 3: .orange
        case 4: AppTheme.coralAccent
        case 5: .red
        default: .secondary
        }
    }
}

#Preview {
    HStack {
        SymptomGridItem(symptomType: .fatigue, severity: 0) { _ in }
        SymptomGridItem(symptomType: .bloating, severity: 3) { _ in }
        SymptomGridItem(symptomType: .cramps, severity: 5) { _ in }
    }
    .padding()
}
