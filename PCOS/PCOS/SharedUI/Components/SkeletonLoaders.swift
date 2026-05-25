import SwiftUI

/// Skeleton loading card for list rows
struct SkeletonListRow: View {
    @State private var isAnimating = false

    var body: some View {
        HStack(spacing: AppTheme.spacing12) {
            RoundedRectangle(cornerRadius: AppTheme.cornerRadiusSmall)
                .fill(Color(.tertiarySystemFill))
                .frame(width: 40, height: 40)

            VStack(alignment: .leading, spacing: AppTheme.spacing4) {
                RoundedRectangle(cornerRadius: 4)
                    .fill(Color(.tertiarySystemFill))
                    .frame(height: 14)
                    .frame(maxWidth: 160)

                RoundedRectangle(cornerRadius: 4)
                    .fill(Color(.tertiarySystemFill))
                    .frame(height: 10)
                    .frame(maxWidth: 100)
            }

            Spacer()
        }
        .padding(.vertical, AppTheme.spacing8)
        .opacity(isAnimating ? 0.4 : 1.0)
        .animation(.easeInOut(duration: 0.8).repeatForever(autoreverses: true), value: isAnimating)
        .onAppear { isAnimating = true }
    }
}

/// Skeleton for chart placeholders
struct SkeletonChart: View {
    @State private var isAnimating = false
    var height: CGFloat = 180

    var body: some View {
        RoundedRectangle(cornerRadius: AppTheme.cornerRadiusMedium)
            .fill(Color(.tertiarySystemFill))
            .frame(height: height)
            .overlay {
                Image(systemName: "chart.line.uptrend.xyaxis")
                    .appFont(.title)
                    .foregroundStyle(Color(.quaternarySystemFill))
            }
            .opacity(isAnimating ? 0.4 : 1.0)
            .animation(.easeInOut(duration: 0.8).repeatForever(autoreverses: true), value: isAnimating)
            .onAppear { isAnimating = true }
    }
}

/// Skeleton for adherence ring
struct SkeletonRing: View {
    @State private var isAnimating = false

    var body: some View {
        Circle()
            .stroke(Color(.tertiarySystemFill), lineWidth: 12)
            .frame(width: 120, height: 120)
            .opacity(isAnimating ? 0.4 : 1.0)
            .animation(.easeInOut(duration: 0.8).repeatForever(autoreverses: true), value: isAnimating)
            .onAppear { isAnimating = true }
    }
}
