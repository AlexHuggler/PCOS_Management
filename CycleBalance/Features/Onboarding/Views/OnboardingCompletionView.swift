import SwiftUI

/// Brief celebratory screen shown after completing onboarding.
/// Auto-advances after 1.8 seconds, with a manual button for accessibility.
struct OnboardingCompletionView: View {
    let onFinish: () -> Void

    @State private var appeared = false

    var body: some View {
        VStack(spacing: AppTheme.spacing24) {
            Spacer()

            Image(systemName: "checkmark.circle.fill")
                .font(.system(size: 72))
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
            Task {
                try? await Task.sleep(for: .seconds(1.8))
                onFinish()
            }
        }
    }
}

#Preview {
    OnboardingCompletionView(onFinish: {})
}
