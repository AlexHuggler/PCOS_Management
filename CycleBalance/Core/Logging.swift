import os

extension Logger {
    private static let subsystem = "com.cyclebalance.app"

    static let database = Logger(subsystem: subsystem, category: "database")
    static let prediction = Logger(subsystem: subsystem, category: "prediction")
}
