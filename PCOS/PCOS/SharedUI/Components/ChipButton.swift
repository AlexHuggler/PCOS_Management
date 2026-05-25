import SwiftUI

/// Reusable capsule chip button used for suggestion pills, tag chips, and quick-select actions.
struct ChipButton: View {
    let title: String
    var systemImage: String? = nil
    var isSelected: Bool = false
    var color: Color = AppTheme.accentColor
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            HStack(spacing: 4) {
                if isSelected {
                    Image(systemName: "checkmark")
                        .appFont(.caption2)
                }
                if let systemImage {
                    Image(systemName: systemImage)
                        .appFont(.caption2)
                }
                Text(title)
                    .appFont(.caption)
            }
            .padding(.horizontal, 10)
            .padding(.vertical, 6)
            .background(
                Capsule()
                    .fill(color.opacity(isSelected ? AppTheme.opacityMedium : AppTheme.opacityLight))
            )
            .foregroundStyle(color)
        }
        .buttonStyle(.plain)
        .sensoryFeedback(.selection, trigger: isSelected)
    }
}

#Preview {
    VStack(spacing: 12) {
        ChipButton(title: "Cramps", systemImage: "bolt.fill", color: AppTheme.coralAccent) {}
        ChipButton(title: "Selected", isSelected: true) {}
        ChipButton(title: "500 mg", color: AppTheme.sage) {}
    }
    .padding()
}
