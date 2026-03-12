import SwiftUI

/// Horizontal pager showing two welcome screens introducing CycleBalance.
struct WelcomePagerView: View {
    let onContinue: () -> Void
    let onSkip: () -> Void

    @State private var currentPage = 0

    private let pages: [(systemImage: String, headline: String, body: String)] = [
        (
            "calendar.badge.clock",
            "Your Cycle, Your Way",
            "PCOS makes every cycle unique. CycleBalance tracks your patterns without assuming regularity."
        ),
        (
            "lock.shield",
            "Private by Design",
            "Your health data stays on your device. No accounts, no servers, no exceptions."
        ),
    ]

    private var isLastPage: Bool { currentPage == pages.count - 1 }

    var body: some View {
        VStack(spacing: 0) {
            TabView(selection: $currentPage) {
                ForEach(Array(pages.enumerated()), id: \.offset) { index, page in
                    WelcomePageView(
                        systemImage: page.systemImage,
                        headline: page.headline,
                        bodyText: page.body
                    )
                    .tag(index)
                }
            }
            .tabViewStyle(.page(indexDisplayMode: .never))

            // Page dots
            HStack(spacing: AppTheme.spacing8) {
                ForEach(0..<pages.count, id: \.self) { index in
                    Circle()
                        .fill(index == currentPage ? AppTheme.accentColor : Color(.tertiarySystemFill))
                        .frame(width: 8, height: 8)
                        .animation(.easeInOut(duration: 0.2), value: currentPage)
                }
            }
            .padding(.bottom, AppTheme.spacing16)

            // Action buttons
            VStack(spacing: AppTheme.spacing12) {
                Button {
                    if isLastPage {
                        onContinue()
                    } else {
                        withAnimation {
                            currentPage += 1
                        }
                    }
                } label: {
                    Text(isLastPage ? "Get Started" : "Next")
                        .font(.headline)
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, AppTheme.spacing12)
                        .background(
                            RoundedRectangle(cornerRadius: 14)
                                .fill(isLastPage ? AppTheme.coralAccent : AppTheme.accentColor)
                        )
                        .foregroundStyle(.white)
                }
                .buttonStyle(.plain)
                .sensoryFeedback(.impact(flexibility: .soft), trigger: currentPage)

                Button("Skip", action: onSkip)
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
                    .accessibilityHint("Skip the welcome tour and go directly to the app")
            }
            .padding(.horizontal, AppTheme.spacing24)
            .padding(.bottom, AppTheme.spacing32)
        }
        .background(AppTheme.warmNeutral.ignoresSafeArea())
        .accessibilityElement(children: .contain)
        .accessibilityLabel("Welcome page \(currentPage + 1) of \(pages.count)")
    }
}

#Preview {
    WelcomePagerView(onContinue: {}, onSkip: {})
}
