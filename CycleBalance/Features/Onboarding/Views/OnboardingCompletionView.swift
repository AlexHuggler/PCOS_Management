import SwiftUI

/// Brief celebratory screen shown after completing onboarding.
/// Auto-advances after 1.8 seconds, with a manual button for accessibility.
struct OnboardingCompletionView: View {
    let onFinish: () -> Void

    @State private var appeared = false
    @State private var dismissTask: Task<Void, Never>?

    @ScaledMetric(relativeTo: .largeTitle) private var iconSize: CGFloat = 72

    var body: some View {
        VStack(spacing: AppTheme.spacing24) {
            Spacer()

            Image(systemName: "checkmark.circle.fill")
                .font(.system(size: iconSize))
                .foregroundStyle(AppTheme.accentColor)
                .symbolEffect(.bounce, value: appeared)
                .accessibilityHidden(true)

            Text("You're all set!")
                .font(.title)
                .fontWeight(.bold)

            Text("Your CycleBalance journey starts now.")
                .font(.body)
                .foregroundStyle(.secondary)

            Spacer()

            Button {
                dismissTask?.cancel()
                onFinish()
            } label: {
                Text("Continue")
                    .font(.headline)
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, AppTheme.spacing12)
                    .background(
                        RoundedRectangle(cornerRadius: 14)
                            .fill(AppTheme.accentColor)
                    )
                    .foregroundStyle(.white)
            }
            .buttonStyle(.plain)
            .padding(.horizontal, AppTheme.spacing24)
            .padding(.bottom, AppTheme.spacing32)
        }
        .background(AppTheme.warmNeutral.ignoresSafeArea())
        .onAppear {
            appeared = true
            dismissTask?.cancel()
            dismissTask = Task {
                try? await Task.sleep(for: .seconds(1.8))
                guard !Task.isCancelled else { return }
                onFinish()
            }
        }
        .onDisappear {
            dismissTask?.cancel()
        }
    }
}

#Preview {
    OnboardingCompletionView(onFinish: {})
}
