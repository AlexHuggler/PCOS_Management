import SwiftUI

struct NotificationSettingsView: View {
    @State private var manager: NotificationManager?
    @State private var periodToggle = false
    @State private var symptomToggle = false
    @State private var supplementToggle = false
    @State private var reminderTime = Date()

    var body: some View {
        NavigationStack {
            List {
                // MARK: - Authorization

                Section("Authorization") {
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

                // MARK: - Period Reminders

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
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                }

                // MARK: - Daily Logging

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
                }

                // MARK: - Supplements

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
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                }

                Section {
                    VStack(alignment: .center, spacing: AppTheme.spacing4) {
                        Text("All reminders stay on your device.")
                            .font(.caption2)
                            .foregroundStyle(.secondary)
                        Text("No data is shared with notification servers.")
                            .font(.caption2)
                            .foregroundStyle(.secondary)
                    }
                    .frame(maxWidth: .infinity)
                    .listRowBackground(Color.clear)
                }
            }
            .navigationTitle("Notifications")
            .onAppear {
                let mgr = NotificationManager()
                periodToggle = mgr.periodRemindersEnabled
                symptomToggle = mgr.symptomRemindersEnabled
                supplementToggle = mgr.supplementRemindersEnabled
                reminderTime = mgr.symptomReminderTime
                manager = mgr
                Task {
                    await mgr.checkAuthorizationStatus()
                }
            }
        }
    }
}

#Preview {
    NotificationSettingsView()
}
