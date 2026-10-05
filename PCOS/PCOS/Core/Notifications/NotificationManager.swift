@preconcurrency import UserNotifications
import os
import SwiftData

enum AppNotificationRoute: String, Sendable {
    // Keep the old raw value for already scheduled meal notifications.
    case mealScan
    case period
    case symptoms
    case supplements

    var loggerShortcut: LoggerShortcut {
        switch self {
        case .mealScan: .meal
        case .period: .period
        case .symptoms: .symptoms
        case .supplements: .supplements
        }
    }

    private static let pendingKey = "notifications.pendingRoute"
    func persistPending(defaults: UserDefaults = .standard) { defaults.set(rawValue, forKey: Self.pendingKey) }
    static func pending(defaults: UserDefaults = .standard) -> Self? {
        defaults.string(forKey: pendingKey).flatMap(Self.init(rawValue:))
    }
    static func clearPending(defaults: UserDefaults = .standard) { defaults.removeObject(forKey: pendingKey) }
}

extension Notification.Name {
    static let checkInReminderRefreshRequested = Notification.Name("app.notification.checkInRefresh")
    static let appNotificationRouteReceived = Notification.Name("app.notification.routeReceived")
}

@Observable
@MainActor
final class NotificationManager {
    private let center = UNUserNotificationCenter.current()
    private let logger = Logger.database

    var isAuthorized = false
    private var refreshingDailyReminders = false
    private var dailyRefreshRequested = false

    // MARK: - User Preferences

    var periodRemindersEnabled: Bool {
        get { UserDefaults.standard.bool(forKey: "notifications.periodReminders") }
        set { UserDefaults.standard.set(newValue, forKey: "notifications.periodReminders") }
    }

    var symptomRemindersEnabled: Bool {
        get { UserDefaults.standard.bool(forKey: "notifications.symptomReminders") }
        set {
            UserDefaults.standard.set(newValue, forKey: "notifications.symptomReminders")
            scheduleSymptomLoggingReminder()
        }
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
            scheduleSymptomLoggingReminder()
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
        content.userInfo = ["route": AppNotificationRoute.period.rawValue]

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

    /// Existing settings callers request a refresh; the app supplies its local ModelContext.
    func scheduleSymptomLoggingReminder() {
        NotificationCenter.default.post(name: .checkInReminderRefreshRequested, object: nil)
    }

    static func isCompletedCheckIn(_ log: DailyLog) -> Bool {
        log.symptomsReviewed || log.moodRawValue != nil || log.energyLevel != nil
            || log.painLevel0To10 != nil || log.stressLevel != nil || log.waterOz != nil
            || !(log.privateNote?.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty ?? true)
    }

    static func dailyCheckInReminderDates(
        now: Date,
        reminderTime: Date,
        completedDays: Set<Date>,
        calendar: Calendar = .current
    ) -> [Date] {
        let time = calendar.dateComponents([.hour, .minute], from: reminderTime)
        let today = calendar.startOfDay(for: now)
        return (0..<14).compactMap { offset in
            guard let day = calendar.date(byAdding: .day, value: offset, to: today),
                  !completedDays.contains(day),
                  let date = calendar.date(bySettingHour: time.hour ?? 20, minute: time.minute ?? 0, second: 0, of: day),
                  date > now else { return nil }
            return date
        }
    }

    /// Rolling individual requests allow a completed day to be removed without affecting tomorrow.
    /// Refreshes serialize because notification-center operations suspend and may receive another save.
    func refreshDailyCheckInReminders(modelContext: ModelContext, now: Date = Date()) async {
        dailyRefreshRequested = true
        guard !refreshingDailyReminders else { return }
        refreshingDailyReminders = true
        defer { refreshingDailyReminders = false }
        repeat {
            dailyRefreshRequested = false
            do {
                let calendar = Calendar.current
                let start = calendar.startOfDay(for: now)
                let logs = try modelContext.fetch(FetchDescriptor<DailyLog>(predicate: #Predicate { $0.date >= start }))
                let completed = Set(logs.filter(Self.isCompletedCheckIn).map { calendar.startOfDay(for: $0.date) })
                let dates = symptomRemindersEnabled
                    ? Self.dailyCheckInReminderDates(now: now, reminderTime: symptomReminderTime, completedDays: completed)
                    : []
                let pending = await center.pendingNotificationRequests()
                center.removePendingNotificationRequests(withIdentifiers: pending.map(\.identifier).filter { $0.hasPrefix("symptom.") })
                for date in dates {
                    try await center.add(Self.dailyCheckInRequest(on: date, calendar: calendar))
                }
            } catch {
                logger.error("Daily check-in reminder refresh failed: \(error.localizedDescription)")
            }
        } while dailyRefreshRequested
    }

    static func dailyCheckInRequest(on date: Date, calendar: Calendar = .current) -> UNNotificationRequest {
        let content = UNMutableNotificationContent()
        content.title = L10n.string("A moment for your check-in", defaultValue: "A moment for your check-in")
        content.body = L10n.string("Record what feels useful today.", defaultValue: "Record what feels useful today.")
        content.sound = .default
        content.userInfo = ["route": AppNotificationRoute.symptoms.rawValue]
        let trigger = UNCalendarNotificationTrigger(dateMatching: calendar.dateComponents([.year, .month, .day, .hour, .minute], from: date), repeats: false)
        return UNNotificationRequest(identifier: "symptom.day.\(Int(calendar.startOfDay(for: date).timeIntervalSince1970))", content: content, trigger: trigger)
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
        content.userInfo = ["route": AppNotificationRoute.supplements.rawValue]

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

    // MARK: - Meal Check-In Reminder

    /// Schedules a repeating meal check-in that routes back to meal logging.
    func scheduleMealScanReminder(time: Date = NotificationManager.defaultMealScanReminderTime()) {
        guard mealScanRemindersEnabled else {
            logger.debug("Meal scan reminders disabled, skipping schedule")
            return
        }

        cancelReminders(withPrefix: "mealScan.")

        let content = UNMutableNotificationContent()
        content.title = String(
            localized: "Ready to log your meal?",
            comment: "Meal check-in reminder notification title."
        )
        content.body = String(
            localized: "Log a meal or scan a barcode while it is fresh in your mind.",
            comment: "Meal check-in reminder notification body."
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
        if prefix == "symptom." {
            scheduleSymptomLoggingReminder()
            return
        }
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
