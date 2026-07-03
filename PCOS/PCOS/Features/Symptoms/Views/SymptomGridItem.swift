import SwiftUI

struct SymptomGridItem: View {
    let symptomType: SymptomType
    let severity: Int
    let onSeverityChange: (Int) -> Void

    private enum SymptomIntensityOption: Int, CaseIterable, Identifiable {
        case none = 0
        case mild = 1
        case moderate = 3
        case severe = 5

        var id: Int { rawValue }

        var title: String {
            switch self {
            case .none: "None"
            case .mild: "Mild"
            case .moderate: "Moderate"
            case .severe: "Severe"
            }
        }
    }

    var body: some View {
        VStack(alignment: .leading, spacing: AppTheme.spacing8) {
            HStack(alignment: .center, spacing: AppTheme.spacing8) {
                Image(systemName: symptomType.systemImage)
                    .appFont(.title3, weight: .semibold)
                    .foregroundStyle(severity > 0 ? severityColor : .secondary)
                    .frame(width: 28, height: 28)

                Text(symptomType.displayName)
                    .appFont(.subheadline, weight: .semibold)
                    .foregroundStyle(AppTheme.primaryText)
                    .lineLimit(2)
                    .minimumScaleFactor(0.78)
                    .fixedSize(horizontal: false, vertical: true)
            }

            LazyVGrid(columns: [GridItem(.flexible()), GridItem(.flexible())], spacing: 6) {
                ForEach(SymptomIntensityOption.allCases) { option in
                    Button {
                        onSeverityChange(option.rawValue)
                    } label: {
                        Text(option.title)
                            .appFont(.caption2, weight: selectedOption == option ? .semibold : .medium)
                            .foregroundStyle(selectedOption == option ? selectedTextColor(for: option) : AppTheme.secondaryText)
                            .lineLimit(1)
                            .minimumScaleFactor(0.75)
                            .frame(maxWidth: .infinity, minHeight: 28)
                            .padding(.horizontal, 6)
                            .background(
                                Capsule()
                                    .fill(selectedOption == option ? severityColor.opacity(0.18) : Color(.secondarySystemFill).opacity(0.55))
                            )
                            .overlay(
                                Capsule()
                                    .stroke(selectedOption == option ? severityColor.opacity(AppTheme.opacityStrong) : Color.clear, lineWidth: 0.8)
                            )
                    }
                    .buttonStyle(.plain)
                    .accessibilityIdentifier("symptom_log.tile.\(symptomType.rawValue).intensity.\(option.rawValue)")
                }
            }
        }
        .padding(AppTheme.spacing12)
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
            let options = SymptomIntensityOption.allCases
            let currentIndex = options.firstIndex(of: selectedOption) ?? 0
            let next = options[(currentIndex + 1) % options.count].rawValue
            onSeverityChange(next)
        }
        .contextMenu {
            ForEach(SymptomIntensityOption.allCases) { option in
                Button {
                    onSeverityChange(option.rawValue)
                } label: {
                    Label(option.title, systemImage: selectedOption == option ? "checkmark.circle.fill" : "circle")
                }
            }
        }
        .scaleEffect(severity > 0 ? 1.0 : 0.98)
        .animation(.easeInOut(duration: 0.2), value: severity)
        .sensoryFeedback(.selection, trigger: severity)
        .accessibilityElement(children: .combine)
        .accessibilityLabel(
            String(
                localized: "\(symptomType.displayName), \(selectedOption.title)",
                comment: "Accessibility label for a symptom selection tile."
            )
        )
        .accessibilityHint(
            String(
                localized: "Tap to cycle intensity, or use the visible choices to select None, Mild, Moderate, or Severe.",
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

    private var selectedOption: SymptomIntensityOption {
        switch severity {
        case ..<1:
            .none
        case 1...2:
            .mild
        case 3...4:
            .moderate
        default:
            .severe
        }
    }

    private func selectedTextColor(for option: SymptomIntensityOption) -> Color {
        option == .none ? AppTheme.primaryText : severityColor
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
