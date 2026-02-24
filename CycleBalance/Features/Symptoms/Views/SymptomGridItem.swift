import SwiftUI

struct SymptomGridItem: View {
    let symptomType: SymptomType
    let severity: Int
    let onSeverityChange: (Int) -> Void

    var body: some View {
        VStack(spacing: 6) {
            // Icon
            Image(systemName: symptomType.systemImage)
                .font(.title2)
                .foregroundStyle(severity > 0 ? severityColor : .secondary)
                .frame(height: 32)

            // Name
            Text(symptomType.displayName)
                .font(.caption2)
                .fontWeight(.medium)
                .lineLimit(2)
                .multilineTextAlignment(.center)
                .frame(height: 28)

            // Severity dots
            SeverityPicker(severity: severity, onSeverityChange: onSeverityChange)
        }
        .padding(.vertical, 12)
        .padding(.horizontal, 4)
        .frame(maxWidth: .infinity)
        .background(
            RoundedRectangle(cornerRadius: 12)
                .fill(severity > 0 ? severityColor.opacity(0.08) : Color(.tertiarySystemFill))
        )
        .overlay(
            RoundedRectangle(cornerRadius: 12)
                .strokeBorder(severity > 0 ? severityColor.opacity(0.3) : .clear, lineWidth: 1)
        )
        .contentShape(Rectangle())
        .onTapGesture {
            // Cycle through: 0 -> 1 -> 2 -> 3 -> 4 -> 5 -> 0
            let next = severity >= 5 ? 0 : severity + 1
            onSeverityChange(next)
        }
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
