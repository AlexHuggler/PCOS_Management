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
                Image(systemName: systemImage)
                    .font(.title2)
                    .foregroundStyle(isSelected ? AppTheme.accentColor : (isDisabled ? Color.secondary.opacity(0.5) : .secondary))
                    .frame(width: 44)

                VStack(alignment: .leading, spacing: AppTheme.spacing4) {
                    Text(title)
                        .font(.body)
                        .fontWeight(.semibold)
                        .foregroundStyle(isDisabled ? .secondary : .primary)
                    Text(subtitle)
                        .font(.caption)
                        .foregroundStyle(isDisabled ? .tertiary : .secondary)
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
