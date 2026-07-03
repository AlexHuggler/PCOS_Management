import SwiftUI

struct NotificationSettingsView: View {
    @State private var manager: NotificationManager?
    @State private var periodToggle = false
    @State private var symptomToggle = false
    @State private var supplementToggle = false
    @State private var mealScanToggle = false
    @State private var reminderTime = Date()

    var body: some View {
        NavigationStack {
            Group {
                if AppTheme.usesPremiumEditorStyling {
                    lunarNotificationsContent
                } else {
                    standardNotificationsList
                }
            }
            .navigationTitle("Notifications")
            .navigationBarTitleDisplayMode(AppTheme.usesPremiumEditorStyling ? .inline : .automatic)
            .lunarNotificationsNavigationBackground()
            .onAppear {
                loadManager()
            }
        }
    }

    private var standardNotificationsList: some View {
        List {
            Section("Authorization") {
                authorizationControl
            }

            Section("Period Reminders") {
                Toggle(isOn: $periodToggle) {
                    Label("Period Predictions", systemImage: "calendar.badge.clock")
                }
                .sensoryFeedback(.selection, trigger: periodToggle)
                .onChange(of: periodToggle) { _, newValue in
                    manager?.periodRemindersEnabled = newValue
                    if !newValue {
                        manager?.cancelReminders(withPrefix: "period.")
                    }
                }

                if periodToggle {
                    Text("You'll be reminded 2 days before your predicted period.")
                        .appFont(.caption)
                        .foregroundStyle(.secondary)
                }
            }

            Section("Daily Logging") {
                Toggle(isOn: $symptomToggle) {
                    Label("Symptom Reminders", systemImage: "list.bullet.clipboard")
                }
                .sensoryFeedback(.selection, trigger: symptomToggle)
                .onChange(of: symptomToggle) { _, newValue in
                    manager?.symptomRemindersEnabled = newValue
                    if newValue {
                        manager?.scheduleSymptomLoggingReminder()
                    } else {
                        manager?.cancelReminders(withPrefix: "symptom.")
                    }
                }

                if symptomToggle {
                    DatePicker(
                        "Reminder Time",
                        selection: $reminderTime,
                        displayedComponents: .hourAndMinute
                    )
                    .onChange(of: reminderTime) { _, newValue in
                        manager?.symptomReminderTime = newValue
                        manager?.scheduleSymptomLoggingReminder()
                    }
                }

                Toggle(isOn: $mealScanToggle) {
                    Label("AI Meal Check-In", systemImage: "camera.macro")
                }
                .sensoryFeedback(.selection, trigger: mealScanToggle)
                .accessibilityIdentifier("settings.notifications.meal_scan_toggle")
                .onChange(of: mealScanToggle) { _, newValue in
                    manager?.mealScanRemindersEnabled = newValue
                    if newValue {
                        manager?.scheduleMealScanReminder()
                    } else {
                        manager?.cancelReminders(withPrefix: "mealScan.")
                    }
                }

                if mealScanToggle {
                    Text("A gentle midday nudge can open the AI meal scanner or manual meal entry.")
                        .appFont(.caption)
                        .foregroundStyle(.secondary)
                }
            }

            Section("Supplements") {
                Toggle(isOn: $supplementToggle) {
                    Label("Supplement Reminders", systemImage: "pills")
                }
                .sensoryFeedback(.selection, trigger: supplementToggle)
                .onChange(of: supplementToggle) { _, newValue in
                    manager?.supplementRemindersEnabled = newValue
                    if !newValue {
                        manager?.cancelReminders(withPrefix: "supplement.")
                    }
                }

                if supplementToggle {
                    Text("Manage individual supplement times from the Supplements tab.")
                        .appFont(.caption)
                        .foregroundStyle(.secondary)
                }
            }

            Section {
                VStack(alignment: .center, spacing: AppTheme.spacing4) {
                    Text("All reminders stay on your device.")
                        .appFont(.caption2)
                        .foregroundStyle(.secondary)
                    Text("No data is shared with notification servers.")
                        .appFont(.caption2)
                        .foregroundStyle(.secondary)
                }
                .frame(maxWidth: .infinity)
                .listRowBackground(Color.clear)
            }
        }
        .accessibilityIdentifier("screen.settings.notifications")
    }

    private var lunarNotificationsContent: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: AppTheme.spacing16) {
                lunarHeader
                lunarAuthorizationCard
                lunarReminderCard
                lunarPrivacyCard
            }
            .padding(AppTheme.spacing16)
            .padding(.bottom, AppTheme.botanicalScrollableBottomPadding)
        }
        .background(AppTheme.premiumEditorBackground.ignoresSafeArea())
        .tint(AppTheme.premiumEditorAccentColor)
        .accessibilityIdentifier("screen.settings.notifications")
    }

    private var authorizationControl: some View {
        Group {
            if let manager {
                if manager.isAuthorized {
                    Label("Notifications Enabled", systemImage: "checkmark.circle.fill")
                        .foregroundStyle(AppTheme.sage)
                } else {
                    Button {
                        Task {
                            await manager.requestAuthorization()
                        }
                    } label: {
                        Label("Enable Notifications", systemImage: "bell.badge")
                    }
                }
            }
        }
    }

    private var lunarHeader: some View {
        HStack(alignment: .top, spacing: AppTheme.spacing12) {
            Image(systemName: "bell.badge.fill")
                .appFont(.title3, weight: .semibold)
                .foregroundStyle(AppTheme.premiumEditorCTAForeground)
                .frame(width: 42, height: 42)
                .background(Circle().fill(AppTheme.premiumEditorAccentGradient))
                .accessibilityHidden(true)

            VStack(alignment: .leading, spacing: AppTheme.spacing8) {
                Text("Gentle reminders")
                    .appHeadingFont(.title3, weight: .regular)
                    .foregroundStyle(AppTheme.primaryText)
                Text("Keep the useful nudges on, leave the rest quiet.")
                    .appFont(.caption)
                    .foregroundStyle(AppTheme.secondaryText)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
        .padding(AppTheme.spacing12)
        .lunarNotificationsCard()
        .accessibilityIdentifier("settings.notifications.lunar.header")
    }

    private var lunarAuthorizationCard: some View {
        HStack(spacing: AppTheme.spacing12) {
            Image(systemName: manager?.isAuthorized == true ? "checkmark.circle.fill" : "bell.badge")
                .appFont(.headline, weight: .semibold)
                .foregroundStyle(manager?.isAuthorized == true ? AppTheme.premiumEditorAccentColor : AppTheme.premiumEditorSecondaryAccentColor)
                .frame(width: 38, height: 38)
                .background(Circle().fill(AppTheme.premiumEditorRaisedSurface.opacity(0.78)))
                .accessibilityHidden(true)

            VStack(alignment: .leading, spacing: AppTheme.spacing4) {
                Text(manager?.isAuthorized == true ? "Notifications Enabled" : "Enable Notifications")
                    .appFont(.subheadline, weight: .semibold)
                    .foregroundStyle(AppTheme.primaryText)
                Text("System permission controls whether reminders can appear.")
                    .appFont(.caption)
                    .foregroundStyle(AppTheme.secondaryText)
                    .fixedSize(horizontal: false, vertical: true)
            }

            Spacer(minLength: AppTheme.spacing8)

            if manager?.isAuthorized != true {
                Button {
                    Task {
                        await manager?.requestAuthorization()
                    }
                } label: {
                    Image(systemName: "arrow.up.right")
                        .appFont(.subheadline, weight: .semibold)
                        .foregroundStyle(AppTheme.premiumEditorCTAForeground)
                        .frame(width: 34, height: 34)
                        .background(Circle().fill(AppTheme.premiumEditorAccentGradient))
                }
                .buttonStyle(.plain)
                .accessibilityLabel("Enable Notifications")
            }
        }
        .padding(AppTheme.spacing12)
        .lunarNotificationsCard()
        .accessibilityIdentifier("settings.notifications.lunar.authorization")
    }

    private var lunarReminderCard: some View {
        VStack(alignment: .leading, spacing: AppTheme.spacing12) {
            Text("Reminder schedule")
                .appFont(.headline, weight: .semibold)
                .foregroundStyle(AppTheme.primaryText)

            lunarReminderRow(
                title: "Period Predictions",
                subtitle: "2 days before your predicted period",
                systemImage: "calendar.badge.clock",
                tint: AppTheme.premiumEditorWarningAccentColor,
                isOn: $periodToggle,
                accessibilityIdentifier: "settings.notifications.period_toggle"
            )
            .onChange(of: periodToggle) { _, newValue in
                manager?.periodRemindersEnabled = newValue
                if !newValue {
                    manager?.cancelReminders(withPrefix: "period.")
                }
            }

            VStack(alignment: .leading, spacing: AppTheme.spacing8) {
                lunarReminderRow(
                    title: "Symptom Reminders",
                    subtitle: "Daily check-in nudge",
                    systemImage: "list.bullet.clipboard",
                    tint: AppTheme.premiumEditorAccentColor,
                    isOn: $symptomToggle,
                    accessibilityIdentifier: "settings.notifications.symptom_toggle"
                )
                .onChange(of: symptomToggle) { _, newValue in
                    manager?.symptomRemindersEnabled = newValue
                    if newValue {
                        manager?.scheduleSymptomLoggingReminder()
                    } else {
                        manager?.cancelReminders(withPrefix: "symptom.")
                    }
                }

                if symptomToggle {
                    DatePicker(
                        "Reminder Time",
                        selection: $reminderTime,
                        displayedComponents: .hourAndMinute
                    )
                    .appFont(.subheadline)
                    .foregroundStyle(AppTheme.primaryText)
                    .tint(AppTheme.premiumEditorAccentColor)
                    .padding(.horizontal, AppTheme.spacing8)
                    .padding(.vertical, AppTheme.spacing8)
                    .background(
                        RoundedRectangle(cornerRadius: 8, style: .continuous)
                            .fill(AppTheme.premiumEditorSurface.opacity(0.72))
                    )
                    .accessibilityIdentifier("settings.notifications.reminder_time")
                    .onChange(of: reminderTime) { _, newValue in
                        manager?.symptomReminderTime = newValue
                        manager?.scheduleSymptomLoggingReminder()
                    }
                }
            }

            lunarReminderRow(
                title: "AI Meal Check-In",
                subtitle: "Midday scan or manual nutrition nudge",
                systemImage: "camera.macro",
                tint: AppTheme.premiumEditorSecondaryAccentColor,
                isOn: $mealScanToggle,
                accessibilityIdentifier: "settings.notifications.meal_scan_toggle"
            )
            .onChange(of: mealScanToggle) { _, newValue in
                manager?.mealScanRemindersEnabled = newValue
                if newValue {
                    manager?.scheduleMealScanReminder()
                } else {
                    manager?.cancelReminders(withPrefix: "mealScan.")
                }
            }

            lunarReminderRow(
                title: "Supplement Reminders",
                subtitle: "Uses saved supplement times",
                systemImage: "pills",
                tint: AppTheme.lavenderAccent,
                isOn: $supplementToggle,
                accessibilityIdentifier: "settings.notifications.supplement_toggle"
            )
            .onChange(of: supplementToggle) { _, newValue in
                manager?.supplementRemindersEnabled = newValue
                if !newValue {
                    manager?.cancelReminders(withPrefix: "supplement.")
                }
            }
        }
        .padding(AppTheme.spacing12)
        .lunarNotificationsCard()
        .accessibilityIdentifier("settings.notifications.lunar.reminders")
    }

    private var lunarPrivacyCard: some View {
        HStack(alignment: .top, spacing: AppTheme.spacing12) {
            Image(systemName: "lock.shield.fill")
                .appFont(.headline, weight: .semibold)
                .foregroundStyle(AppTheme.premiumEditorSecondaryAccentColor)
                .frame(width: 38, height: 38)
                .background(Circle().fill(AppTheme.premiumEditorSecondaryAccentColor.opacity(0.14)))
                .accessibilityHidden(true)

            VStack(alignment: .leading, spacing: AppTheme.spacing4) {
                Text("Private by default")
                    .appFont(.subheadline, weight: .semibold)
                    .foregroundStyle(AppTheme.primaryText)
                Text("All reminders stay on your device. No data is shared with notification servers.")
                    .appFont(.caption)
                    .foregroundStyle(AppTheme.secondaryText)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
        .padding(AppTheme.spacing12)
        .lunarNotificationsCard()
        .accessibilityIdentifier("settings.notifications.lunar.privacy")
    }

    private func lunarReminderRow(
        title: String,
        subtitle: String,
        systemImage: String,
        tint: Color,
        isOn: Binding<Bool>,
        accessibilityIdentifier: String
    ) -> some View {
        HStack(spacing: AppTheme.spacing12) {
            Image(systemName: systemImage)
                .appFont(.headline, weight: .semibold)
                .symbolRenderingMode(.hierarchical)
                .foregroundStyle(tint)
                .frame(width: 38, height: 38)
                .background(Circle().fill(tint.opacity(0.15)))
                .accessibilityHidden(true)

            VStack(alignment: .leading, spacing: AppTheme.spacing4) {
                Text(title)
                    .appFont(.subheadline, weight: .semibold)
                    .foregroundStyle(AppTheme.primaryText)
                    .lineLimit(1)
                    .minimumScaleFactor(0.76)
                Text(subtitle)
                    .appFont(.caption)
                    .foregroundStyle(AppTheme.secondaryText)
                    .lineLimit(2)
                    .minimumScaleFactor(0.78)
            }

            Spacer(minLength: AppTheme.spacing8)

            Toggle("", isOn: isOn)
                .labelsHidden()
                .tint(AppTheme.premiumEditorAccentColor)
                .accessibilityIdentifier("\(accessibilityIdentifier).switch")
        }
        .padding(AppTheme.spacing8)
        .background(
            RoundedRectangle(cornerRadius: 8, style: .continuous)
                .fill(AppTheme.premiumEditorRaisedSurface.opacity(0.72))
        )
        .overlay(
            RoundedRectangle(cornerRadius: 8, style: .continuous)
                .stroke(AppTheme.premiumEditorBorder.opacity(0.5), lineWidth: 0.8)
        )
        .accessibilityElement(children: .contain)
        .accessibilityIdentifier(accessibilityIdentifier)
    }

    private func loadManager() {
        let mgr = NotificationManager()
        periodToggle = mgr.periodRemindersEnabled
        symptomToggle = mgr.symptomRemindersEnabled
        supplementToggle = mgr.supplementRemindersEnabled
        mealScanToggle = mgr.mealScanRemindersEnabled
        reminderTime = mgr.symptomReminderTime
        manager = mgr
        Task {
            await mgr.checkAuthorizationStatus()
        }
    }
}

#Preview {
    NotificationSettingsView()
}

private extension View {
    @ViewBuilder
    func lunarNotificationsNavigationBackground() -> some View {
        if AppTheme.usesPremiumEditorStyling {
            toolbarBackground(AppTheme.premiumEditorBackground, for: .navigationBar)
                .toolbarBackground(.visible, for: .navigationBar)
        } else {
            self
        }
    }

    func lunarNotificationsCard() -> some View {
        background(
            RoundedRectangle(cornerRadius: 8, style: .continuous)
                .fill(
                    LinearGradient(
                        colors: [
                            AppTheme.premiumEditorRaisedSurface.opacity(0.92),
                            AppTheme.premiumEditorSurface.opacity(0.78),
                            AppTheme.premiumEditorBackground.opacity(0.9),
                        ],
                        startPoint: .topLeading,
                        endPoint: .bottomTrailing
                    )
                )
        )
        .overlay(
            RoundedRectangle(cornerRadius: 8, style: .continuous)
                .stroke(AppTheme.premiumEditorBorderGradient, lineWidth: 0.8)
                .opacity(0.72)
        )
        .shadow(color: Color.black.opacity(0.24), radius: 14, y: 8)
    }
}
