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
        HStack(alignment: .bottom, spacing: AppTheme.spacing8) {
            ForEach(Array([0.45, 0.7, 0.55, 0.9, 0.6, 0.8, 0.5].enumerated()), id: \.offset) { _, value in
                RoundedRectangle(cornerRadius: AppTheme.cornerRadiusSmall)
                    .fill(Color.accentColor.opacity(0.7))
                    .frame(maxWidth: .infinity)
                    .frame(height: 160 * value)
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .bottom)
    }
    .padding()
}
