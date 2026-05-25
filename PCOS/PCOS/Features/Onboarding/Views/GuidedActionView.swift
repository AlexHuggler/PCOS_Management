import SwiftUI
import SwiftData

enum GuidedActionCompletionPolicy {
    static func didCreateRecord(initialCount: Int?, currentCount: Int) -> Bool {
        guard let initialCount else {
            return false
        }

        return currentCount > initialCount
    }
}

/// Transitional screen that presents the user's recommended first action.
/// Opens the existing CycleLogView or SymptomLogView as a sheet.
struct GuidedActionView: View {
    let profile: OnboardingProfile
    let onComplete: () -> Void
    let onSkip: () -> Void

    @Environment(\.modelContext) private var modelContext

    @State private var showingSheet = false
    @State private var initialGuidedLogRecordCount: Int?
    @State private var guidedActionMessage: String?

    @ScaledMetric(relativeTo: .largeTitle) private var iconSize: CGFloat = 56

    private var isLogPeriod: Bool {
        profile.suggestedFirstAction == .logPeriod
    }

    /// First category from the user's symptom focus areas, used to pre-filter SymptomLogView.
    private var suggestedCategory: SymptomCategory? {
        profile.preferredSymptomCategories.first
    }

    var body: some View {
        VStack(spacing: AppTheme.spacing24) {
            Spacer()

            Image(systemName: isLogPeriod ? "drop.fill" : "list.bullet.clipboard")
                .font(.system(size: iconSize))
                .foregroundStyle(isLogPeriod ? AppTheme.coralAccent : AppTheme.accentColor)
                .symbolEffect(.bounce, value: showingSheet)
                .accessibilityHidden(true)

            Text(profile.firstLogContextLine)
                .appFont(.subheadline)
                .foregroundStyle(AppTheme.accentColor)
                .multilineTextAlignment(.center)
                .padding(.horizontal, AppTheme.spacing24)

            VStack(spacing: AppTheme.spacing12) {
                Text(isLogPeriod
                     ? String(localized: "Let's log your first period day", comment: "Guided action screen heading for users focused on period logging.")
                     : String(localized: "How are you feeling today?", comment: "Guided action screen heading for users focused on symptom logging."))
                    .appHeadingFont(.title2, weight: .regular)
                    .foregroundStyle(AppTheme.primaryText)
                    .multilineTextAlignment(.center)

                Text(isLogPeriod
                     ? String(localized: "Even if your period isn't today, you can log your most recent one. This starts your cycle tracking.", comment: "Guided action helper text for period logging.")
                     : String(localized: "Tap any symptoms you're experiencing. Even logging once helps start building your pattern.", comment: "Guided action helper text for symptom logging."))
                    .appFont(.body)
                    .foregroundStyle(.secondary)
                    .multilineTextAlignment(.center)
            }
            .padding(.horizontal, AppTheme.spacing24)

            Spacer()

            if let guidedActionMessage {
                Text(guidedActionMessage)
                    .appFont(.footnote)
                    .foregroundStyle(AppTheme.primaryText)
                    .multilineTextAlignment(.center)
                    .padding(.horizontal, AppTheme.spacing24)
                    .accessibilityIdentifier("onboarding.guided_action.message")
            }

            VStack(spacing: AppTheme.spacing12) {
                Button {
                    beginGuidedAction()
                } label: {
                    Label(
                        String(
                            localized: isLogPeriod ? "Log Period Day" : "Log Symptoms",
                            comment: "Primary guided action button label."
                        ),
                        systemImage: isLogPeriod ? "drop.fill" : "list.bullet.clipboard"
                    )
                    .appFont(.headline)
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, AppTheme.spacing12)
                    .background(
                        RoundedRectangle(cornerRadius: 14)
                            .fill(isLogPeriod ? AppTheme.coralAccent : AppTheme.accentColor)
                    )
                    .foregroundStyle(.white)
                }
                .buttonStyle(.plain)
                .accessibilityIdentifier("onboarding.guided_action.primary")

                Button {
                    onSkip()
                } label: {
                    Text(profile.suggestedFirstAction.guidedActionSkipTitle)
                }
                    .appFont(.subheadline)
                    .foregroundStyle(.secondary)
                    .accessibilityHint(Text(profile.suggestedFirstAction.guidedActionSkipHint))
                    .accessibilityIdentifier("onboarding.guided_action.skip")
            }
            .padding(.horizontal, AppTheme.spacing24)
            .padding(.bottom, AppTheme.spacing32)
        }
        .background(BotanicalScreenBackground(style: .dense))
        .accessibilityElement(children: .contain)
        .accessibilityIdentifier("screen.onboarding.guided_action")
        .sheet(isPresented: $showingSheet, onDismiss: handleGuidedActionDismissal) {
            if isLogPeriod {
                CycleLogView()
            } else {
                SymptomLogView(initialCategory: suggestedCategory)
            }
        }
    }

    private func beginGuidedAction() {
        guidedActionMessage = nil
        initialGuidedLogRecordCount = currentGuidedLogRecordCount()
        showingSheet = true
    }

    private func handleGuidedActionDismissal() {
        guard
            let currentCount = currentGuidedLogRecordCount(),
            GuidedActionCompletionPolicy.didCreateRecord(
                initialCount: initialGuidedLogRecordCount,
                currentCount: currentCount
            )
        else {
            guidedActionMessage = String(
                localized: "No log was saved yet. You can try again or continue without a first log.",
                comment: "Guided action message shown after dismissing a first-log sheet without saving."
            )
            initialGuidedLogRecordCount = nil
            return
        }

        initialGuidedLogRecordCount = nil
        profile.hasCompletedGuidedAction = true
        onComplete()
    }

    private func currentGuidedLogRecordCount() -> Int? {
        do {
            switch profile.suggestedFirstAction {
            case .logPeriod:
                return try modelContext.fetch(FetchDescriptor<CycleEntry>()).count
            case .logSymptoms:
                return try modelContext.fetch(FetchDescriptor<SymptomEntry>()).count
            }
        } catch {
            return nil
        }
    }
}

#Preview {
    GuidedActionView(
        profile: OnboardingProfile(),
        onComplete: {},
        onSkip: {}
    )
}
