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
                BotanicalIconBadge(
                    systemImage: systemImage,
                    color: isSelected ? AppTheme.accentColor : AppTheme.sage,
                    size: 44
                )
                .opacity(isSelected ? 1 : 0.72)

                VStack(alignment: .leading, spacing: AppTheme.spacing4) {
                    Text(title)
                        .appFont(.body, weight: .semibold)
                        .foregroundStyle(AppTheme.primaryText)
                        .fixedSize(horizontal: false, vertical: true)
                    Text(subtitle)
                        .appFont(.caption)
                        .foregroundStyle(AppTheme.secondaryText)
                        .fixedSize(horizontal: false, vertical: true)
                }

                Spacer(minLength: 0)

                Image(systemName: "checkmark.circle.fill")
                    .foregroundStyle(AppTheme.accentColor)
                    .opacity(isSelected ? 1 : 0)
                    .scaleEffect(isSelected ? 1 : 0.5)
            }
            .padding(AppTheme.isBotanicalJournal ? AppTheme.spacing20 : AppTheme.spacing16)
            .background(
                RoundedRectangle(cornerRadius: AppTheme.defaultCardCornerRadius, style: .continuous)
                    .fill(isSelected ? AppTheme.accentColor.opacity(AppTheme.opacitySubtle) : AppTheme.cardBackground)
            )
            .overlay(
                RoundedRectangle(cornerRadius: AppTheme.defaultCardCornerRadius, style: .continuous)
                    .strokeBorder(
                        isSelected ? AppTheme.accentColor.opacity(0.4) : AppTheme.cardBorder,
                        lineWidth: AppTheme.isBotanicalJournal ? 0.8 : 1.5
                    )
            )
            .shadow(
                color: AppTheme.cardShadowColor,
                radius: AppTheme.isBotanicalJournal ? 10 : 0,
                x: 0,
                y: AppTheme.isBotanicalJournal ? 6 : 0
            )
            .animation(.spring(response: 0.3, dampingFraction: 0.7), value: isSelected)
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
