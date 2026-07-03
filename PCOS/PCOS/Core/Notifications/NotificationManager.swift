@preconcurrency import UserNotifications
import os

enum AppNotificationRoute: String, Sendable {
    case mealScan
}

extension Notification.Name {
    static let appNotificationRouteReceived = Notification.Name("app.notification.routeReceived")
}

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

    var mealScanRemindersEnabled: Bool {
        get { UserDefaults.standard.bool(forKey: "notifications.mealScanReminders") }
        set { UserDefaults.standard.set(newValue, forKey: "notifications.mealScanReminders") }
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
        content.title = String(
            localized: "Period May Be Coming",
            comment: "Notification title sent before a predicted period."
        )

        let daysBetween = calendar.dateComponents([.day], from: earliestDate, to: latestDate).day ?? 0
        if daysBetween <= 1 {
            content.body = String(
                localized: "Your period is expected in about 2 days.",
                comment: "Notification body for a narrow predicted period window."
            )
        } else {
            let formatter = DateFormatter()
            formatter.dateStyle = .medium
            formatter.timeStyle = .none
            formatter.locale = L10n.locale()
            let earliestStr = formatter.string(from: earliestDate)
            let latestStr = formatter.string(from: latestDate)
            content.body = String(
                localized: "Your period is expected between \(earliestStr) and \(latestStr).",
                comment: "Notification body for a broader predicted period date range."
            )
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
        content.title = String(
            localized: "Log Your Symptoms",
            comment: "Daily symptom reminder notification title."
        )
        content.body = String(
            localized: "Take a moment to record how you're feeling today.",
            comment: "Daily symptom reminder notification body."
        )
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
        content.title = String(
            localized: "Supplement Reminder",
            comment: "Supplement reminder notification title."
        )
        content.body = String(
            localized: "Time to take your \(name).",
            comment: "Supplement reminder notification body with the supplement name."
        )
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

    // MARK: - AI Meal Scan Reminder

    /// Schedules a repeating meal check-in that routes back to the meal scanner.
    func scheduleMealScanReminder(time: Date = NotificationManager.defaultMealScanReminderTime()) {
        guard mealScanRemindersEnabled else {
            logger.debug("Meal scan reminders disabled, skipping schedule")
            return
        }

        cancelReminders(withPrefix: "mealScan.")

        let content = UNMutableNotificationContent()
        content.title = String(
            localized: "Ready to log your meal?",
            comment: "AI meal scan reminder notification title."
        )
        content.body = String(
            localized: "Scan a meal with AI or add nutrition manually when it is fresh in your mind.",
            comment: "AI meal scan reminder notification body."
        )
        content.sound = .default
        content.userInfo = ["route": AppNotificationRoute.mealScan.rawValue]

        let calendar = Calendar.current
        let timeComponents = calendar.dateComponents([.hour, .minute], from: time)
        let trigger = UNCalendarNotificationTrigger(dateMatching: timeComponents, repeats: true)

        let request = UNNotificationRequest(
            identifier: "mealScan.daily",
            content: content,
            trigger: trigger
        )

        center.add(request) { [logger] error in
            if let error {
                logger.error("Failed to schedule meal scan reminder: \(error.localizedDescription)")
            } else {
                logger.info("Meal scan reminder scheduled at \(timeComponents.hour ?? 0):\(timeComponents.minute ?? 0)")
            }
        }
    }

    static func defaultMealScanReminderTime(calendar: Calendar = .current) -> Date {
        var components = DateComponents()
        components.hour = 12
        components.minute = 30
        return calendar.date(from: components) ?? Date()
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

    // MARK: - Lifecycle Mode

    /// Suspends period prediction reminders during pregnancy.
    func suspendPeriodReminders() {
        cancelReminders(withPrefix: "period.")
        logger.info("Period reminders suspended for pregnancy mode")
    }

    /// Resumes period-related reminders after pregnancy ends.
    func resumePeriodRemindersIfEnabled() {
        guard periodRemindersEnabled else { return }
        logger.info("Period reminders re-enabled after pregnancy mode")
    }
}
