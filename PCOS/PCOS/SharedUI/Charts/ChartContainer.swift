import SwiftUI

/// Standardized wrapper for chart components with consistent height, title, and styling.
struct ChartContainer<Content: View>: View {
    let title: String
    var subtitle: String? = nil
    var height: CGFloat = 200
    @ViewBuilder let content: () -> Content

    var body: some View {
        VStack(alignment: .leading, spacing: AppTheme.spacing8) {
            VStack(alignment: .leading, spacing: AppTheme.spacing4) {
                Text(title)
                    .appFont(.headline, weight: .semibold)

                if let subtitle {
                    Text(subtitle)
                        .appFont(.caption)
                        .foregroundStyle(.secondary)
                }
            }

            content()
                .frame(height: height)
        }
    }
}

#Preview {
    ChartContainer(title: "Blood Sugar Trend", subtitle: "Last 30 days") {
        RoundedRectangle(cornerRadius: AppTheme.cornerRadiusMedium)
            .fill(Color(.tertiarySystemFill))
            .overlay {
                Text("Chart Placeholder")
                    .foregroundStyle(.secondary)
            }
    }
    .padding()
}
