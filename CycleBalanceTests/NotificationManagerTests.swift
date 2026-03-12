import Testing
import Foundation
@testable import CycleBalance

@Suite("Notification Manager", .serialized)
@MainActor
struct NotificationManagerTests {

    /// Clean up notification-related UserDefaults keys before each test
    /// to avoid state leaking between runs.
    private func cleanDefaults() {
        let keys = [
            "notifications.periodReminders",
            "notifications.symptomReminders",
            "notifications.supplementReminders",
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

        #expect(manager.periodRemindersEnabled == true)
        #expect(manager.symptomRemindersEnabled == true)
        #expect(manager.supplementRemindersEnabled == true)

        manager.periodRemindersEnabled = false
        manager.symptomRemindersEnabled = false
        manager.supplementRemindersEnabled = false

        #expect(manager.periodRemindersEnabled == false)
        #expect(manager.symptomRemindersEnabled == false)
        #expect(manager.supplementRemindersEnabled == false)
    }
}
