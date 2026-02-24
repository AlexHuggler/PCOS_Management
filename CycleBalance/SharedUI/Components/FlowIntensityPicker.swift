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
                            .font(.title3)
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
                    .foregroundStyle(selection == intensity
                                    ? flowColor(for: intensity)
                                    : .secondary)
                }
                .buttonStyle(.plain)
            }
        }
    }

    @ViewBuilder
    private func flowIcon(for intensity: FlowIntensity) -> some View {
        switch intensity {
        case .none:
            Image(systemName: "drop")
        case .spotting:
            Image(systemName: "drop.fill")
                .font(.caption)
        case .light:
            Image(systemName: "drop.fill")
                .font(.subheadline)
        case .medium:
            Image(systemName: "drop.fill")
                .font(.body)
        case .heavy:
            Image(systemName: "drop.fill")
                .font(.title3)
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
