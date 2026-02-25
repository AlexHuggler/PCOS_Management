import SwiftUI

/// Reusable single-select card with icon, title, subtitle, and checkmark.
/// Used in onboarding questionnaire and anywhere a tap-to-select card is needed.
struct SelectableCard<Value: Hashable>: View {
    let systemImage: String
    let title: String
    let subtitle: String
    let value: Value
    @Binding var selection: Value?

    private var isSelected: Bool { selection == value }

    var body: some View {
        Button {
            selection = value
        } label: {
            HStack(spacing: AppTheme.spacing16) {
                Image(systemName: systemImage)
                    .font(.title2)
                    .foregroundStyle(isSelected ? AppTheme.accentColor : .secondary)
                    .frame(width: 44)

                VStack(alignment: .leading, spacing: AppTheme.spacing4) {
                    Text(title)
                        .font(.body)
                        .fontWeight(.semibold)
                        .foregroundStyle(.primary)
                    Text(subtitle)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .fixedSize(horizontal: false, vertical: true)
                }

                Spacer()

                if isSelected {
                    Image(systemName: "checkmark.circle.fill")
                        .foregroundStyle(AppTheme.accentColor)
                        .transition(.scale.combined(with: .opacity))
                }
            }
            .padding(AppTheme.spacing16)
            .background(
                RoundedRectangle(cornerRadius: 14)
                    .fill(isSelected ? AppTheme.accentColor.opacity(0.08) : AppTheme.cardBackground)
            )
            .overlay(
                RoundedRectangle(cornerRadius: 14)
                    .strokeBorder(
                        isSelected ? AppTheme.accentColor.opacity(0.4) : Color.clear,
                        lineWidth: 1.5
                    )
            )
            .animation(.easeInOut(duration: 0.2), value: isSelected)
        }
        .buttonStyle(.plain)
        .sensoryFeedback(.selection, trigger: isSelected)
        .accessibilityLabel(title)
        .accessibilityHint(subtitle)
        .accessibilityAddTraits(isSelected ? .isSelected : [])
    }
}

#Preview {
    VStack(spacing: 12) {
        SelectableCard(
            systemImage: "calendar.badge.clock",
            title: "Track my periods",
            subtitle: "Irregular cycles are unpredictable. Let's change that.",
            value: "track",
            selection: .constant("track")
        )
        SelectableCard(
            systemImage: "chart.xyaxis.line",
            title: "Understand my symptoms",
            subtitle: "Find patterns between your symptoms and your cycle.",
            value: "symptoms",
            selection: .constant("track")
        )
    }
    .padding()
}
