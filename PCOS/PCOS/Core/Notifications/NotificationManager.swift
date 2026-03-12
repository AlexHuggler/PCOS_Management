@preconcurrency import UserNotifications
import os

@Observable
@MainActor
final class NotificationManager {
    private let center = UNUserNotificationCenter.current()
    private let logger = Logger.database

    var isAuthorized = false

    // MARK: - User Preferences

    var periodRemindersEnabled: Bool {
        get { UserDefaults.standard.bool(forKey: "notifications.periodReminders") }
        set { UserDefaults.standard.set(newValue, forKey: "notifications.periodReminders") }
    }

    var symptomRemindersEnabled: Bool {
        get { UserDefaults.standard.bool(forKey: "notifications.symptomReminders") }
        set { UserDefaults.standard.set(newValue, forKey: "notifications.symptomReminders") }
    }

    var supplementRemindersEnabled: Bool {
        get { UserDefaults.standard.bool(forKey: "notifications.supplementReminders") }
        set { UserDefaults.standard.set(newValue, forKey: "notifications.supplementReminders") }
    }

    var symptomReminderTime: Date {
        get {
            if let timeInterval = UserDefaults.standard.object(forKey: "notifications.symptomReminderTime") as? TimeInterval {
                return Date(timeIntervalSinceReferenceDate: timeInterval)
            }
            // Default: 8 PM
            var components = DateComponents()
            components.hour = 20
            components.minute = 0
            return Calendar.current.date(from: components) ?? Date()
        }
        set {
            UserDefaults.standard.set(newValue.timeIntervalSinceReferenceDate, forKey: "notifications.symptomReminderTime")
        }
    }

    // MARK: - Authorization

    func requestAuthorization() async {
        do {
            let granted = try await center.requestAuthorization(options: [.alert, .sound, .badge])
            isAuthorized = granted
            logger.info("Notification authorization \(granted ? "granted" : "denied")")
        } catch {
            logger.error("Notification authorization request failed: \(error.localizedDescription)")
            isAuthorized = false
        }
    }

    func checkAuthorizationStatus() async {
        let settings = await center.notificationSettings()
        isAuthorized = settings.authorizationStatus == .authorized
        logger.debug("Notification authorization status: \(settings.authorizationStatus.rawValue)")
    }

    // MARK: - Period Prediction Reminder

    /// Schedules a notification 2 days before the earliest predicted period date.
    func schedulePeriodPredictionReminder(earliestDate: Date, latestDate: Date) {
        guard periodRemindersEnabled else {
            logger.debug("Period reminders disabled, skipping schedule")
            return
        }

        cancelReminders(withPrefix: "period.")

        let calendar = Calendar.current
        guard let reminderDate = calendar.date(byAdding: .day, value: -2, to: earliestDate) else {
            logger.error("Could not compute period reminder date")
            return
        }

        // Don't schedule if the reminder date is in the past
        guard reminderDate > Date() else {
            logger.debug("Period reminder date is in the past, skipping")
            return
        }

        let content = UNMutableNotificationContent()
        content.title = "Period May Be Coming"

        let daysBetween = calendar.dateComponents([.day], from: earliestDate, to: latestDate).day ?? 0
        if daysBetween <= 1 {
            content.body = "Your period is expected in about 2 days."
        } else {
            let formatter = DateFormatter()
            formatter.dateStyle = .medium
            formatter.timeStyle = .none
            let earliestStr = formatter.string(from: earliestDate)
            let latestStr = formatter.string(from: latestDate)
            content.body = "Your period is expected between \(earliestStr) and \(latestStr)."
        }
        content.sound = .default

        let triggerComponents = calendar.dateComponents([.year, .month, .day, .hour, .minute], from: reminderDate)
        let trigger = UNCalendarNotificationTrigger(dateMatching: triggerComponents, repeats: false)

        let request = UNNotificationRequest(
            identifier: "period.prediction",
            content: content,
            trigger: trigger
        )

        center.add(request) { [logger] error in
            if let error {
                logger.error("Failed to schedule period reminder: \(error.localizedDescription)")
            } else {
                logger.info("Period prediction reminder scheduled for \(reminderDate)")
            }
        }
    }

    // MARK: - Daily Symptom Logging Reminder

    /// Schedules a repeating daily notification at the configured symptom reminder time.
    func scheduleSymptomLoggingReminder() {
        guard symptomRemindersEnabled else {
            logger.debug("Symptom reminders disabled, skipping schedule")
            return
        }

        cancelReminders(withPrefix: "symptom.")

        let content = UNMutableNotificationContent()
        content.title = "Log Your Symptoms"
        content.body = "Take a moment to record how you're feeling today."
        content.sound = .default

        let calendar = Calendar.current
        let timeComponents = calendar.dateComponents([.hour, .minute], from: symptomReminderTime)
        let trigger = UNCalendarNotificationTrigger(dateMatching: timeComponents, repeats: true)

        let request = UNNotificationRequest(
            identifier: "symptom.daily",
            content: content,
            trigger: trigger
        )

        center.add(request) { [logger] error in
            if let error {
                logger.error("Failed to schedule symptom reminder: \(error.localizedDescription)")
            } else {
                logger.info("Symptom logging reminder scheduled at \(timeComponents.hour ?? 0):\(timeComponents.minute ?? 0)")
            }
        }
    }

    // MARK: - Supplement Reminders

    /// Schedules a daily repeating notification for a supplement at the given time.
    func scheduleSupplementReminder(name: String, time: Date) {
        guard supplementRemindersEnabled else {
            logger.debug("Supplement reminders disabled, skipping schedule")
            return
        }

        let sanitizedName = name
            .lowercased()
            .replacingOccurrences(of: " ", with: "_")
        let identifier = "supplement.\(sanitizedName)"

        // Remove any existing reminder for this supplement
        center.removePendingNotificationRequests(withIdentifiers: [identifier])

        let content = UNMutableNotificationContent()
        content.title = "Supplement Reminder"
        content.body = "Time to take your \(name)."
        content.sound = .default

        let calendar = Calendar.current
        let timeComponents = calendar.dateComponents([.hour, .minute], from: time)
        let trigger = UNCalendarNotificationTrigger(dateMatching: timeComponents, repeats: true)

        let request = UNNotificationRequest(
            identifier: identifier,
            content: content,
            trigger: trigger
        )

        center.add(request) { [logger] error in
            if let error {
                logger.error("Failed to schedule supplement reminder for \(name): \(error.localizedDescription)")
            } else {
                logger.info("Supplement reminder scheduled for \(name)")
            }
        }
    }

    // MARK: - Cancellation

    func cancelAllReminders() {
        center.removeAllPendingNotificationRequests()
        logger.info("All notification reminders cancelled")
    }

    /// Cancels all pending notifications whose identifier starts with the given prefix.
    /// Use prefixes like "period.", "symptom.", or "supplement." to cancel a category.
    func cancelReminders(withPrefix prefix: String) {
        Task { @MainActor in
            let requests = await center.pendingNotificationRequests()
            let matchingIdentifiers = requests
                .map(\.identifier)
                .filter { $0.hasPrefix(prefix) }

            guard !matchingIdentifiers.isEmpty else { return }

            center.removePendingNotificationRequests(withIdentifiers: matchingIdentifiers)
            logger.info("Cancelled \(matchingIdentifiers.count) reminders with prefix '\(prefix)'")
        }
    }
}
