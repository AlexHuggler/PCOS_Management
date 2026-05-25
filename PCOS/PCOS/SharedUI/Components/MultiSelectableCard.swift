import SwiftUI

/// Reusable multi-select card with icon, title, subtitle, and checkmark.
/// Supports toggle selection with an optional maximum selection limit.
struct MultiSelectableCard<Value: Hashable>: View {
    let systemImage: String
    let title: String
    let subtitle: String
    let value: Value
    @Binding var selection: Set<Value>
    var maxSelection: Int = .max

    private var isSelected: Bool { selection.contains(value) }
    private var isDisabled: Bool { !isSelected && selection.count >= maxSelection }

    var body: some View {
        Button {
            toggleSelection()
        } label: {
            HStack(spacing: AppTheme.spacing16) {
                BotanicalIconBadge(
                    systemImage: systemImage,
                    color: isSelected ? AppTheme.accentColor : AppTheme.sage,
                    size: 44
                )
                .opacity(isDisabled ? 0.42 : (isSelected ? 1 : 0.72))

                VStack(alignment: .leading, spacing: AppTheme.spacing4) {
                    Text(title)
                        .appFont(.body, weight: .semibold)
                        .foregroundStyle(isDisabled ? .secondary : AppTheme.primaryText)
                        .fixedSize(horizontal: false, vertical: true)
                    Text(subtitle)
                        .appFont(.caption)
                        .foregroundStyle(isDisabled ? Color.secondary.opacity(0.55) : AppTheme.secondaryText)
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
        .disabled(isDisabled)
        .sensoryFeedback(.selection, trigger: isSelected)
        .accessibilityLabel(title)
        .accessibilityHint(subtitle)
        .accessibilityAddTraits(isSelected ? .isSelected : [])
    }

    private func toggleSelection() {
        if isSelected {
            selection.remove(value)
        } else if selection.count < maxSelection {
            selection.insert(value)
        }
    }
}

#Preview {
    struct PreviewWrapper: View {
        @State private var selection: Set<String> = ["mood"]

        var body: some View {
            VStack(spacing: 12) {
                MultiSelectableCard(
                    systemImage: "brain.head.profile",
                    title: "Mood & energy",
                    subtitle: "Track mood swings, anxiety, and energy crashes.",
                    value: "mood",
                    selection: $selection,
                    maxSelection: 3
                )
                MultiSelectableCard(
                    systemImage: "bolt.heart",
                    title: "Pain & cramps",
                    subtitle: "See how cramps and pain relate to your cycle.",
                    value: "pain",
                    selection: $selection,
                    maxSelection: 3
                )
            }
            .padding()
        }
    }
    return PreviewWrapper()
}
