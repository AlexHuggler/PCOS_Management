import SwiftUI

/// Horizontal picker for selecting menstrual flow intensity.
struct FlowIntensityPicker: View {
    @Binding var selection: FlowIntensity

    var body: some View {
        HStack(spacing: 0) {
            ForEach(FlowIntensity.allCases) { intensity in
                Button {
                    selection = intensity
                } label: {
                    VStack(spacing: 6) {
                        flowIcon(for: intensity)
                            .frame(height: 28)

                        Text(intensity.displayName)
                            .font(.caption)
                            .fontWeight(selection == intensity ? .semibold : .regular)
                    }
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 10)
                    .background(
                        RoundedRectangle(cornerRadius: 10)
                            .fill(selection == intensity
                                  ? flowColor(for: intensity).opacity(0.15)
                                  : .clear)
                    )
                    .overlay(
                        RoundedRectangle(cornerRadius: 10)
                            .strokeBorder(selection == intensity
                                          ? flowColor(for: intensity).opacity(0.4)
                                          : .clear, lineWidth: 1.5)
                    )
                    .foregroundStyle(selection == intensity
                                    ? flowColor(for: intensity)
                                    : .secondary)
                }
                .buttonStyle(.plain)
                .accessibilityLabel("\(intensity.displayName) flow")
                .accessibilityAddTraits(selection == intensity ? .isSelected : [])
                .accessibilityHint("Double tap to select \(intensity.displayName) flow intensity")
            }
        }
        .sensoryFeedback(.selection, trigger: selection)
    }

    @ViewBuilder
    private func flowIcon(for intensity: FlowIntensity) -> some View {
        switch intensity {
        case .none:
            Image(systemName: "drop")
                .font(.body)
        case .spotting:
            Image(systemName: "drop.fill")
                .font(.caption)
                .opacity(0.6)
        case .light:
            Image(systemName: "drop.fill")
                .font(.subheadline)
                .opacity(0.75)
        case .medium:
            Image(systemName: "drop.fill")
                .font(.body)
        case .heavy:
            HStack(spacing: 2) {
                Image(systemName: "drop.fill")
                    .font(.caption2)
                Image(systemName: "drop.fill")
                    .font(.subheadline)
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
