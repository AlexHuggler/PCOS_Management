import Foundation
import SwiftUI
import SwiftData
import os

@main
struct CycleBalanceApp: App {
    private static let cloudKitContainerID = "iCloud.com.cyclebalance.app"
    private static let startupModeDefaultsKey = "persistence.startupMode"

#if DEBUG
    private static let debugStoreDirectoryName = "CycleBalanceDebugStore"
    private static let debugStoreFileName = "CycleBalance.sqlite"
#endif

    var sharedModelContainer: ModelContainer = Self.makeSharedModelContainer()

    var body: some Scene {
        WindowGroup {
            ContentView()
#if DEBUG && targetEnvironment(simulator)
                .preferredColorScheme(.light)
#endif
        }
        .modelContainer(sharedModelContainer)
    }
}

private extension CycleBalanceApp {
    static func makeSharedModelContainer() -> ModelContainer {
        let schema = Schema([
            CycleEntry.self,
            Cycle.self,
            SymptomEntry.self,
            Insight.self,
            BloodSugarReading.self,
            SupplementLog.self,
            MealEntry.self,
            HairPhotoEntry.self,
            DailyLog.self,
        ])

        if isRunningTests {
            do {
                let testConfiguration = ModelConfiguration(
                    schema: schema,
                    isStoredInMemoryOnly: true,
                    cloudKitDatabase: .none
                )
                let container = try ModelContainer(for: schema, configurations: [testConfiguration])
                recordStartupMode("test_in_memory")
                return container
            } catch {
                fatalError("Could not create in-memory test ModelContainer: \(String(describing: error))")
            }
        }

#if DEBUG && targetEnvironment(simulator)
        let fallbackReason = CloudKitStartupPolicy.simulatorFallbackReason()
        return makeLocalFallbackContainer(
            schema: schema,
            reason: fallbackReason,
            cloudError: nil
        )
#else
        do {
            let cloudKitConfiguration = makeCloudKitConfiguration(schema: schema)
            let container = try ModelContainer(for: schema, configurations: [cloudKitConfiguration])
            recordStartupMode("cloudkit")
            return container
        } catch {
            let cloudError = String(describing: error)
            Logger.database.error("CloudKit ModelContainer init failed: \(cloudError, privacy: .public)")
            fatalError("Could not create CloudKit ModelContainer in Release: \(cloudError)")
        }
#endif
    }

    static func makeCloudKitConfiguration(schema: Schema) -> ModelConfiguration {
        ModelConfiguration(
            schema: schema,
            isStoredInMemoryOnly: false,
            cloudKitDatabase: .private(cloudKitContainerID)
        )
    }

#if DEBUG
    static func makeLocalFallbackContainer(
        schema: Schema,
        reason: CloudKitFallbackReason,
        cloudError: String?
    ) -> ModelContainer {
        do {
            let localConfiguration = try makeLocalDebugConfiguration(schema: schema)
            let container = try ModelContainer(for: schema, configurations: [localConfiguration])
            recordStartupMode("local_fallback_\(reason.rawValue)")
            Logger.database.notice("Using local SwiftData fallback store due to \(reason.rawValue, privacy: .public).")
            if let cloudError {
                Logger.database.error("CloudKit startup failure before fallback: \(cloudError, privacy: .public)")
            }
            return container
        } catch {
            let fallbackError = String(describing: error)
            Logger.database.error("Local fallback ModelContainer init failed: \(fallbackError, privacy: .public)")

            do {
                try resetDebugLocalStoreFiles()
                let localConfiguration = try makeLocalDebugConfiguration(schema: schema)
                let container = try ModelContainer(for: schema, configurations: [localConfiguration])
                recordStartupMode("local_fallback_after_reset_\(reason.rawValue)")
                Logger.database.notice("Recovered local fallback store after debug reset.")
                return container
            } catch {
                let retryError = String(describing: error)
                Logger.database.fault("Local fallback recovery failed after reset: \(retryError, privacy: .public)")
                fatalError(
                    "Could not create ModelContainer. "
                        + "CloudKit error: \(cloudError ?? "n/a"). "
                        + "Local fallback error: \(fallbackError). "
                        + "Post-reset error: \(retryError)."
                )
            }
        }
    }

    static func makeLocalDebugConfiguration(schema: Schema) throws -> ModelConfiguration {
        let storeURL = try debugLocalStoreURL()
        return ModelConfiguration(
            schema: schema,
            url: storeURL,
            cloudKitDatabase: .none
        )
    }

    static func resetDebugLocalStoreFiles() throws {
        let storeURL = try debugLocalStoreURL()
        let fileManager = FileManager.default
        let candidateURLs = [
            storeURL,
            storeURL.appendingPathExtension("wal"),
            storeURL.appendingPathExtension("shm"),
        ]

        for candidate in candidateURLs where fileManager.fileExists(atPath: candidate.path) {
            try fileManager.removeItem(at: candidate)
            Logger.database.notice("Removed debug SwiftData store file: \(candidate.path, privacy: .public)")
        }
    }

    private static func debugLocalStoreURL() throws -> URL {
        let fileManager = FileManager.default
        let appSupportURL = try fileManager.url(
            for: .applicationSupportDirectory,
            in: .userDomainMask,
            appropriateFor: nil,
            create: true
        )
        let storeDirectoryURL = appSupportURL.appendingPathComponent(debugStoreDirectoryName, isDirectory: true)

        if !fileManager.fileExists(atPath: storeDirectoryURL.path) {
            try fileManager.createDirectory(at: storeDirectoryURL, withIntermediateDirectories: true)
        }

        return storeDirectoryURL.appendingPathComponent(debugStoreFileName)
    }
#endif

    static func recordStartupMode(_ mode: String) {
        UserDefaults.standard.set(mode, forKey: startupModeDefaultsKey)
        Logger.database.info("SwiftData startup mode: \(mode, privacy: .public)")
    }

    static var isRunningTests: Bool {
        let environment = ProcessInfo.processInfo.environment
        if environment["XCTestConfigurationFilePath"] != nil {
            return true
        }
        if environment["XCInjectBundleInto"] != nil {
            return true
        }
        return ProcessInfo.processInfo.arguments.contains("UITestMode")
    }
}
