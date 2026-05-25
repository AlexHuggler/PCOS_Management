import SwiftUI

/// Horizontal picker for selecting menstrual flow intensity.
/// Excludes `.none` since this picker is used when actively logging a period day.
struct FlowIntensityPicker: View {
    @Binding var selection: FlowIntensity

    /// Flow intensities relevant for period logging (excludes `.none`).
    private static let pickableCases = FlowIntensity.allCases.filter { $0 != .none }

    var body: some View {
        HStack(spacing: 0) {
            ForEach(Self.pickableCases) { intensity in
                Button {
                    selection = intensity
                } label: {
                    VStack(spacing: AppTheme.spacing8) {
                        flowIcon(for: intensity)
                            .frame(height: 28)

                        Text(intensity.displayName)
                            .appFont(.caption, weight: selection == intensity ? .semibold : .regular)
                            .multilineTextAlignment(.center)
                            .lineLimit(2)
                            .minimumScaleFactor(0.85)
                    }
                    .frame(maxWidth: .infinity)
                    .fixedSize(horizontal: false, vertical: true)
                    .padding(.vertical, 14)
                    .background(
                        RoundedRectangle(cornerRadius: AppTheme.cornerRadiusSmall)
                            .fill(selection == intensity
                                  ? flowColor(for: intensity).opacity(AppTheme.opacityMedium)
                                  : .clear)
                    )
                    .overlay(
                        RoundedRectangle(cornerRadius: AppTheme.cornerRadiusSmall)
                            .strokeBorder(selection == intensity
                                          ? flowColor(for: intensity).opacity(0.4)
                                          : .clear, lineWidth: 1.5)
                    )
                    .foregroundStyle(selection == intensity
                                    ? flowColor(for: intensity)
                                    : .secondary)
                }
                .buttonStyle(.plain)
                .accessibilityLabel(
                    L10n.flowAccessibilityLabel(for: intensity)
                )
                .accessibilityAddTraits(selection == intensity ? .isSelected : [])
                .accessibilityHint(
                    L10n.flowAccessibilityHint(for: intensity)
                )
            }
        }
        .sensoryFeedback(.selection, trigger: selection)
        .animation(.easeInOut(duration: 0.2), value: selection)
    }

    @ViewBuilder
    private func flowIcon(for intensity: FlowIntensity) -> some View {
        switch intensity {
        case .none:
            Image(systemName: "drop")
                .appFont(.body)
        case .spotting:
            Image(systemName: "drop.fill")
                .appFont(.caption)
                .opacity(0.6)
        case .light:
            Image(systemName: "drop.fill")
                .appFont(.subheadline)
                .opacity(0.75)
        case .medium:
            Image(systemName: "drop.fill")
                .appFont(.body)
        case .heavy:
            HStack(spacing: 2) {
                Image(systemName: "drop.fill")
                    .appFont(.caption2)
                Image(systemName: "drop.fill")
                    .appFont(.subheadline)
            }
        }
    }

    private func flowColor(for intensity: FlowIntensity) -> Color {
        switch intensity {
        case .none: .secondary
        case .spotting: AppTheme.flowSpotting
        case .light: AppTheme.flowLight
        case .medium: AppTheme.flowMedium
        case .heavy: AppTheme.flowHeavy
        }
    }
}

#Preview {
    FlowIntensityPicker(selection: .constant(.medium))
        .padding()
}
