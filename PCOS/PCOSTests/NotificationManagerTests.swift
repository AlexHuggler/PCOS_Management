import Testing
import Foundation
import UserNotifications
@testable import PCOS

@Suite("Notification Manager", .serialized)
@MainActor
struct NotificationManagerTests {

    @Test("A daily check-in request is nonrepeating and opens symptoms")
    func checkInRequestUsesConcreteDayAndRoute() throws {
        let date = Date(timeIntervalSince1970: 1_788_638_400)
        let request = NotificationManager.dailyCheckInRequest(on: date)
        let trigger = try #require(request.trigger as? UNCalendarNotificationTrigger)
        #expect(!trigger.repeats)
        #expect(trigger.dateComponents.year != nil)
        #expect(trigger.dateComponents.day != nil)
        #expect(request.content.userInfo["route"] as? String == AppNotificationRoute.symptoms.rawValue)
    }

    @Test("Rolling check-in dates skip completed today and never repeat")
    func completedDayIsExcluded() throws {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(secondsFromGMT: 0)!
        let now = try #require(calendar.date(from: DateComponents(year: 2026, month: 9, day: 5, hour: 10)))
        let reminder = try #require(calendar.date(bySettingHour: 20, minute: 0, second: 0, of: now))
        let dates = NotificationManager.dailyCheckInReminderDates(now: now, reminderTime: reminder, completedDays: [calendar.startOfDay(for: now)], calendar: calendar)
        #expect(dates.count == 13)
        #expect(dates.allSatisfy { !calendar.isDate($0, inSameDayAs: now) && $0 > now })
        #expect(Set(dates).count == dates.count)
    }

    @Test("Imported health context alone never counts as a completed check-in")
    func healthDataIsNotCheckIn() {
        let log = DailyLog(date: Date(), sleepHours: 8, activeMinutes: 30)
        #expect(!NotificationManager.isCompletedCheckIn(log))
        log.moodRawValue = "good"
        #expect(NotificationManager.isCompletedCheckIn(log))
        log.moodRawValue = nil
        log.symptomsReviewed = true
        #expect(NotificationManager.isCompletedCheckIn(log))
    }

    /// Clean up notification-related UserDefaults keys before each test
    /// to avoid state leaking between runs.
    private func cleanDefaults() {
        let keys = [
            "notifications.periodReminders",
            "notifications.symptomReminders",
            "notifications.supplementReminders",
            "notifications.mealScanReminders",
            "notifications.symptomReminderTime",
        ]
        for key in keys {
            UserDefaults.standard.removeObject(forKey: key)
        }
    }

    @Test("isAuthorized starts as false")
    func initialAuthorizationIsFalse() {
        let manager = NotificationManager()
        #expect(manager.isAuthorized == false)
    }

    @Test("Default period reminders preference is false")
    func defaultPeriodRemindersDisabled() {
        cleanDefaults()
        let manager = NotificationManager()
        #expect(manager.periodRemindersEnabled == false)
    }

    @Test("Default symptom reminders preference is false")
    func defaultSymptomRemindersDisabled() {
        cleanDefaults()
        let manager = NotificationManager()
        #expect(manager.symptomRemindersEnabled == false)
    }

    @Test("Default supplement reminders preference is false")
    func defaultSupplementRemindersDisabled() {
        cleanDefaults()
        let manager = NotificationManager()
        #expect(manager.supplementRemindersEnabled == false)
    }

    @Test("Default meal scan reminders preference is false")
    func defaultMealScanRemindersDisabled() {
        cleanDefaults()
        let manager = NotificationManager()
        #expect(manager.mealScanRemindersEnabled == false)
    }

    @Test("Setting period reminders persists to UserDefaults")
    func periodRemindersPersists() {
        cleanDefaults()
        let manager = NotificationManager()
        manager.periodRemindersEnabled = true
        #expect(UserDefaults.standard.bool(forKey: "notifications.periodReminders") == true)

        // A new instance should read the persisted value
        let manager2 = NotificationManager()
        #expect(manager2.periodRemindersEnabled == true)
    }

    @Test("Setting symptom reminders persists to UserDefaults")
    func symptomRemindersPersists() {
        cleanDefaults()
        let manager = NotificationManager()
        manager.symptomRemindersEnabled = true
        #expect(UserDefaults.standard.bool(forKey: "notifications.symptomReminders") == true)

        let manager2 = NotificationManager()
        #expect(manager2.symptomRemindersEnabled == true)
    }

    @Test("Setting supplement reminders persists to UserDefaults")
    func supplementRemindersPersists() {
        cleanDefaults()
        let manager = NotificationManager()
        manager.supplementRemindersEnabled = true
        #expect(UserDefaults.standard.bool(forKey: "notifications.supplementReminders") == true)

        let manager2 = NotificationManager()
        #expect(manager2.supplementRemindersEnabled == true)
    }

    @Test("Setting meal scan reminders persists to UserDefaults")
    func mealScanRemindersPersists() {
        cleanDefaults()
        let manager = NotificationManager()
        manager.mealScanRemindersEnabled = true
        #expect(UserDefaults.standard.bool(forKey: "notifications.mealScanReminders") == true)

        let manager2 = NotificationManager()
        #expect(manager2.mealScanRemindersEnabled == true)
    }

    @Test("Default symptom reminder time is 8 PM")
    func defaultSymptomReminderTimeIs8PM() {
        cleanDefaults()
        let manager = NotificationManager()
        let calendar = Calendar.current
        let components = calendar.dateComponents([.hour, .minute], from: manager.symptomReminderTime)
        #expect(components.hour == 20)
        #expect(components.minute == 0)
    }

    @Test("Setting symptom reminder time persists to UserDefaults")
    func symptomReminderTimePersists() {
        cleanDefaults()
        let manager = NotificationManager()

        // Set to 9:30 AM
        var components = DateComponents()
        components.hour = 9
        components.minute = 30
        let targetTime = Calendar.current.date(from: components)!
        manager.symptomReminderTime = targetTime

        // A new instance should read the persisted time
        let manager2 = NotificationManager()
        let readComponents = Calendar.current.dateComponents([.hour, .minute], from: manager2.symptomReminderTime)
        #expect(readComponents.hour == 9)
        #expect(readComponents.minute == 30)
    }

    @Test("Toggling preferences off and back on works correctly")
    func togglePreferencesRoundTrip() {
        cleanDefaults()
        let manager = NotificationManager()

        manager.periodRemindersEnabled = true
        manager.symptomRemindersEnabled = true
        manager.supplementRemindersEnabled = true
        manager.mealScanRemindersEnabled = true

        #expect(manager.periodRemindersEnabled == true)
        #expect(manager.symptomRemindersEnabled == true)
        #expect(manager.supplementRemindersEnabled == true)
        #expect(manager.mealScanRemindersEnabled == true)

        manager.periodRemindersEnabled = false
        manager.symptomRemindersEnabled = false
        manager.supplementRemindersEnabled = false
        manager.mealScanRemindersEnabled = false

        #expect(manager.periodRemindersEnabled == false)
        #expect(manager.symptomRemindersEnabled == false)
        #expect(manager.supplementRemindersEnabled == false)
        #expect(manager.mealScanRemindersEnabled == false)
    }

    @Test("Meal scan notification route selects Track and can be consumed")
    func mealScanNotificationRouteSelectsTrackAndCanBeConsumed() {
        let suiteName = "notification-route-tests-\(UUID().uuidString)"
        let defaults = UserDefaults(suiteName: suiteName)!
        defer { defaults.removePersistentDomain(forName: suiteName) }

        let appState = AppState(defaults: defaults, launchArguments: [])
        #expect(appState.selectedTab == .today)
        #expect(appState.pendingNotificationRoute == nil)

        appState.handleNotificationRoute(.mealScan)

        #expect(appState.selectedTab == .track)
        #expect(appState.pendingNotificationRoute == .mealScan)

        appState.consumeNotificationRoute(.mealScan)
        #expect(appState.pendingNotificationRoute == nil)
    }
}
