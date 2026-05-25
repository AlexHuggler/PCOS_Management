import os

extension Logger {
    private static let subsystem = "com.cyclebalance.app"

    static let ui = Logger(subsystem: subsystem, category: "ui")
    static let database = Logger(subsystem: subsystem, category: "database")
    static let prediction = Logger(subsystem: subsystem, category: "prediction")
    static let onboarding = Logger(subsystem: subsystem, category: "onboarding")
    static let bloodSugar = Logger(subsystem: subsystem, category: "bloodSugar")
    static let supplements = Logger(subsystem: subsystem, category: "supplements")
    static let meals = Logger(subsystem: subsystem, category: "meals")
    static let photoJournal = Logger(subsystem: subsystem, category: "photoJournal")
    static let reports = Logger(subsystem: subsystem, category: "reports")
    static let healthKit = Logger(subsystem: subsystem, category: "healthKit")
    static let insights = Logger(subsystem: subsystem, category: "insights")
    static let notifications = Logger(subsystem: subsystem, category: "notifications")
    static let storeKit = Logger(subsystem: subsystem, category: "storeKit")
    static let attribution = Logger(subsystem: subsystem, category: "attribution")
    static let haptics = Logger(subsystem: subsystem, category: "haptics")
    static let symptoms = Logger(subsystem: subsystem, category: "symptoms")
#if DEBUG
    static let symptomsSignposter = OSSignposter(logger: symptoms)
#endif
}
