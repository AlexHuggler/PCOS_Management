import SwiftUI

/// Celebratory screen shown after completing onboarding.
/// Displays a personalized goal message based on the user's questionnaire answers.
struct OnboardingCompletionView: View {
    let profile: OnboardingProfile
    let onFinish: () -> Void

    @State private var appeared = false
    @State private var notificationManager = NotificationManager()
    @State private var reminderState: ReminderState = .idle

    @ScaledMetric(relativeTo: .largeTitle) private var iconSize: CGFloat = 72

    private enum ReminderState {
        case idle
        case enabled
        case denied
    }

    var body: some View {
        VStack(spacing: AppTheme.spacing24) {
            Spacer()

            Image(systemName: "checkmark.circle.fill")
                .font(.system(size: iconSize))
                .foregroundStyle(AppTheme.accentColor)
                .symbolEffect(.bounce, value: appeared)
                .accessibilityHidden(true)

            Text(completionTitle)
                .appHeadingFont(.title, weight: .regular)
                .foregroundStyle(AppTheme.primaryText)

            Text(personalizedMessage)
                .appFont(.body)
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)
                .padding(.horizontal, AppTheme.spacing24)

            Text(String(localized: "We're a small team building this for you — find \"Share Feedback\" in Settings anytime.", comment: "Feedback invitation on the completion screen."))
                .appFont(.caption)
                .foregroundStyle(.tertiary)
                .multilineTextAlignment(.center)
                .padding(.horizontal, AppTheme.spacing24)

            reminderCard

            Spacer()

            Button {
                onFinish()
            } label: {
                Text(String(localized: "Start Exploring", comment: "Primary onboarding completion button label."))
                    .appFont(.headline)
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, AppTheme.spacing12)
                    .background(
                        RoundedRectangle(cornerRadius: 14)
                            .fill(AppTheme.accentColor)
                    )
                    .foregroundStyle(.white)
            }
            .buttonStyle(.plain)
            .accessibilityIdentifier("onboarding.completion.finish")
            .padding(.horizontal, AppTheme.spacing24)
            .padding(.bottom, AppTheme.spacing32)
        }
        .background(BotanicalScreenBackground(style: .dense))
        .accessibilityElement(children: .contain)
        .accessibilityIdentifier("screen.onboarding.completion")
        .onAppear {
            appeared = true
        }
    }

    private var reminderCard: some View {
        Button {
            Task { await enableDailyReminder() }
        } label: {
            HStack(alignment: .top, spacing: AppTheme.spacing12) {
                Image(systemName: reminderState == .enabled ? "checkmark.circle.fill" : "bell.badge")
                    .appFont(.title3, weight: .semibold)
                    .foregroundStyle(reminderState == .enabled ? AppTheme.sage : AppTheme.accentColor)
                    .frame(width: 38, height: 38)
                    .background(Circle().fill(AppTheme.cardBackground.opacity(0.78)))
                    .accessibilityHidden(true)

                VStack(alignment: .leading, spacing: AppTheme.spacing4) {
                    Text(reminderTitle)
                        .appFont(.subheadline, weight: .semibold)
                        .foregroundStyle(AppTheme.primaryText)
                    Text(reminderMessage)
                        .appFont(.caption)
                        .foregroundStyle(.secondary)
                        .fixedSize(horizontal: false, vertical: true)
                }

                Spacer(minLength: AppTheme.spacing8)
            }
            .padding(AppTheme.spacing16)
            .background(
                RoundedRectangle(cornerRadius: AppTheme.cornerRadiusMedium, style: .continuous)
                    .fill(AppTheme.cardBackground.opacity(0.86))
            )
            .overlay(
                RoundedRectangle(cornerRadius: AppTheme.cornerRadiusMedium, style: .continuous)
                    .stroke(AppTheme.cardBorder, lineWidth: 1)
            )
        }
        .buttonStyle(.plain)
        .padding(.horizontal, AppTheme.spacing24)
        .accessibilityIdentifier("onboarding.completion.reminder")
    }

    private var reminderTitle: String {
        switch reminderState {
        case .idle:
            String(localized: "Set a daily check-in reminder", comment: "Onboarding completion reminder opt-in title.")
        case .enabled:
            String(localized: "Daily reminder is on", comment: "Onboarding completion reminder enabled title.")
        case .denied:
            String(localized: "Reminder permission was skipped", comment: "Onboarding completion reminder denied title.")
        }
    }

    private var reminderMessage: String {
        switch reminderState {
        case .idle:
            String(localized: "A gentle evening nudge can help symptoms, meals, and journal notes stay easier to remember.", comment: "Onboarding completion reminder opt-in message.")
        case .enabled:
            String(localized: "We'll remind you once a day. You can change this anytime in Settings.", comment: "Onboarding completion reminder enabled message.")
        case .denied:
            String(localized: "No problem. You can turn reminders on later from Settings.", comment: "Onboarding completion reminder denied message.")
        }
    }

    private func enableDailyReminder() async {
        guard reminderState != .enabled else { return }
        await notificationManager.requestAuthorization()
        if notificationManager.isAuthorized {
            notificationManager.symptomRemindersEnabled = true
            notificationManager.scheduleSymptomLoggingReminder()
            reminderState = .enabled
        } else {
            reminderState = .denied
        }
    }

    private var personalizedMessage: String {
        switch profile.primaryGoal {
        case .trackCycles:
            String(localized: "Everything's set. Log when you're ready — CycleBalance adapts to your rhythm, not the other way around.", comment: "Onboarding completion message for users focused on cycle tracking.")
        case .understandSymptoms:
            String(localized: "Your tracking journey starts now. Your first symptom patterns can appear after about two weeks of check-ins.", comment: "Onboarding completion message for users focused on symptoms.")
        case nil:
            String(localized: "Everything you log stays on this device, and your first patterns build with each check-in. We're glad you're here.", comment: "Generic onboarding completion message.")
        }
    }

    private var completionTitle: String {
        if let name = profile.preferredDisplayName {
            "\(String(localized: "You're all set", comment: "Onboarding completion headline prefix with name")), \(name)!"
        } else {
            String(localized: "You're all set!", comment: "Onboarding completion headline.")
        }
    }
}

#Preview {
    OnboardingCompletionView(profile: OnboardingProfile(), onFinish: {})
}
