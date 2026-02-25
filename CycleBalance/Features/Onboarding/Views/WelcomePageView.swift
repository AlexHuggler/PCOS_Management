import SwiftUI

/// A single welcome page with a large SF Symbol, headline, and body text.
/// Reused for each page of the onboarding welcome pager.
struct WelcomePageView: View {
    let systemImage: String
    let headline: String
    let bodyText: String

    @ScaledMetric(relativeTo: .largeTitle) private var iconSize: CGFloat = 72

    var body: some View {
        VStack(spacing: AppTheme.spacing24) {
            Spacer()

            Image(systemName: systemImage)
                .font(.system(size: iconSize))
                .foregroundStyle(AppTheme.accentColor)
                .symbolEffect(.pulse, options: .repeating)
                .accessibilityHidden(true)

            VStack(spacing: AppTheme.spacing12) {
                Text(headline)
                    .font(.title)
                    .fontWeight(.bold)
                    .multilineTextAlignment(.center)

                Text(bodyText)
                    .font(.body)
                    .foregroundStyle(.secondary)
                    .multilineTextAlignment(.center)
                    .fixedSize(horizontal: false, vertical: true)
            }
            .padding(.horizontal, AppTheme.spacing24)

            Spacer()
            Spacer()
        }
    }
}

#Preview {
    WelcomePageView(
        systemImage: "calendar.badge.clock",
        headline: "Your Cycle, Your Way",
        bodyText: "PCOS makes every cycle unique. CycleBalance tracks your patterns without assuming regularity."
    )
    .background(AppTheme.warmNeutral.ignoresSafeArea())
}
