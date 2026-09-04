import Foundation
import FirebaseAppCheck
import FirebaseCore
import SwiftUI
import SwiftData
import UIKit

#if DEBUG
private enum UITestDemoSeedError: Error {
    case missingSampleMealImage
}
#endif
@preconcurrency import UserNotifications
import os

private final class CycleBalanceAppCheckProviderFactory: NSObject, AppCheckProviderFactory {
    func createProvider(with app: FirebaseApp) -> (any AppCheckProvider)? {
        #if DEBUG
        AppCheckDebugProvider(app: app)
        #else
        AppAttestProvider(app: app)
        #endif
    }
}

private enum ModelContainerStartupError: Error {
    case primaryStore(initial: String, primary: String)
    case cacheStore(initial: String, cache: String)
}

final class AppNotificationDelegate: NSObject, UIApplicationDelegate, UNUserNotificationCenterDelegate {
    func application(
        _ application: UIApplication,
        didFinishLaunchingWithOptions launchOptions: [UIApplication.LaunchOptionsKey: Any]? = nil
    ) -> Bool {
        UNUserNotificationCenter.current().delegate = self
        return true
    }

    nonisolated func userNotificationCenter(
        _ center: UNUserNotificationCenter,
        didReceive response: UNNotificationResponse
    ) async {
        guard let rawRoute = response.notification.request.content.userInfo["route"] as? String,
              let route = AppNotificationRoute(rawValue: rawRoute)
        else {
            return
        }

        await MainActor.run {
            NotificationCenter.default.post(name: .appNotificationRouteReceived, object: route)
        }
    }
}

@main
struct CycleBalanceApp: App {
    #if DEBUG
    private static let cloudKitContainerID = "iCloud.com.cyclebalance.app"
    #endif
    private static let startupModeDefaultsKey = "persistence.startupMode"
    private static let uiTestDemoScenarioKey = "uiTest.demoScenario"
    private static let uiTestFontOptionKey = "appearance.fontOption"
    private static let uiTestThemeOptionKey = "appearance.themeOption"
    private static let uiTestExperimentalThemesKey = "appearance.enableExperimentalThemes"
    private static let uiTestReportPolicyResetKey = "reports.resetPolicy"
    private static let uiTestOnboardingBooleanKeys = [
        "onboarding.hasCompletedWelcome",
        "onboarding.hasCompletedQuestionnaire",
        "onboarding.hasCompletedGuidedAction",
        "onboarding.hasCompletedOnboarding",
        "onboarding.hasPromptedForReview",
    ]

#if DEBUG
    private static let debugStoreDirectoryName = "CycleBalanceDebugStore"
    private static let debugStoreFileName = "CycleBalance.sqlite"
#endif
    private static let repeatCacheStoreFileName = "MealScanRepeatCache.sqlite"

    var sharedModelContainer: ModelContainer = Self.makeSharedModelContainer()
    @State private var appearancePreferences = AppearancePreferences.shared
    @UIApplicationDelegateAdaptor(AppNotificationDelegate.self) private var notificationDelegate

    init() {
        Self.applyUITestLaunchOverrides()
        Self.applyAppearanceLaunchOverridesIfNeeded()
        Self.applyStoredAppLanguageOverrideIfNeeded()
        Self.configureFirebaseIfNeeded()
        AppChromeTypography.apply()
        Self.configureRevenueCatIfPossible()
    }

    var body: some Scene {
        WindowGroup {
            ContentView()
                .preferredColorScheme(appearancePreferences.preferredColorScheme)
        }
        .modelContainer(sharedModelContainer)
    }
}

extension CycleBalanceApp {
    /// Firebase (App Check) exists solely to authorize the Gemini meal-photo proxy. A build that
    /// cannot run the scanner must not initialize Firebase, so no Google traffic happens for users
    /// of the hidden-scanner release.
    static func shouldConfigureFirebase(flags: MealScanFeatureFlags) -> Bool {
        flags.enableGeminiMealScan
    }

    static func configureFirebaseIfNeeded(flags: MealScanFeatureFlags = .current) {
        guard shouldConfigureFirebase(flags: flags) else {
            Logger.database.info("Skipping Firebase configuration: Gemini meal scan is disabled for this build")
            return
        }
        configureFirebase()
    }

    static func configureFirebase() {
        AppCheck.setAppCheckProviderFactory(CycleBalanceAppCheckProviderFactory())
        FirebaseApp.configure()
    }

    static let primaryModelTypes: [any PersistentModel.Type] = [
        CycleEntry.self,
        Cycle.self,
        OvulationObservation.self,
        SymptomEntry.self,
        Insight.self,
        BloodSugarReading.self,
        SupplementLog.self,
        MealEntry.self,
        MealScanFoodItem.self,
        MealScanNutritionSummary.self,
        MealScanMetadata.self,
        MealScanResultCacheRecord.self,
        NutritionImportRecord.self,
        HealthKitImportedSampleRecord.self,
        HairPhotoEntry.self,
        DailyLog.self,
        PregnancyRecord.self,
    ]

    static var primarySchema: Schema {
        Schema(primaryModelTypes)
    }

    static var repeatCacheSchema: Schema {
        Schema([MealScanRepeatCacheRecord.self])
    }

    static var completeSchema: Schema {
        Schema(primaryModelTypes + [MealScanRepeatCacheRecord.self])
    }

    static func makeSharedModelContainer() -> ModelContainer {
        let primarySchema = Self.primarySchema
        let repeatCacheSchema = Self.repeatCacheSchema
        let completeSchema = Self.completeSchema

        if isRunningTests {
            do {
                let primaryConfiguration = ModelConfiguration(
                    schema: primarySchema,
                    isStoredInMemoryOnly: true,
                    cloudKitDatabase: .none
                )
                let cacheConfiguration = ModelConfiguration(
                    "RepeatMealCacheTests",
                    schema: repeatCacheSchema,
                    isStoredInMemoryOnly: true,
                    cloudKitDatabase: .none
                )
                let container = try ModelContainer(
                    for: completeSchema,
                    configurations: [primaryConfiguration, cacheConfiguration]
                )
                try applyUITestDemoScenarioIfNeeded(to: container)
                recordStartupMode("test_in_memory")
                return container
            } catch {
                fatalError("Could not create in-memory test ModelContainer: \(String(describing: error))")
            }
        }

#if DEBUG
        if CloudKitStartupPolicy.shouldUseLocalStoreInDebug() {
            let fallbackReason = CloudKitStartupPolicy.debugFallbackReason()
            return makeLocalFallbackContainer(
                completeSchema: completeSchema,
                primarySchema: primarySchema,
                repeatCacheSchema: repeatCacheSchema,
                reason: fallbackReason,
                cloudError: nil
            )
        }

        do {
            let cloudKitConfiguration = makeCloudKitConfiguration(schema: primarySchema)
            let cacheConfiguration = try makeLocalDebugCacheConfiguration(schema: repeatCacheSchema)
            let container = try makeModelContainerRecoveringCache(
                completeSchema: completeSchema,
                primarySchema: primarySchema,
                primaryConfiguration: cloudKitConfiguration,
                cacheConfiguration: cacheConfiguration
            )
            recordStartupMode("cloudkit")
            Logger.database.notice("Using CloudKit SwiftData store in Debug due to explicit opt-in.")
            return container
        } catch {
            let cloudError = String(describing: error)
            Logger.database.error("CloudKit ModelContainer init failed in Debug: \(cloudError, privacy: .public)")
            return makeLocalFallbackContainer(
                completeSchema: completeSchema,
                primarySchema: primarySchema,
                repeatCacheSchema: repeatCacheSchema,
                reason: .cloudkitInitError,
                cloudError: cloudError
            )
        }
#else
        do {
            let primaryConfiguration = makeLocalReleaseConfiguration(schema: primarySchema)
            let cacheConfiguration = try makeLocalReleaseCacheConfiguration(schema: repeatCacheSchema)
            let container = try makeModelContainerRecoveringCache(
                completeSchema: completeSchema,
                primarySchema: primarySchema,
                primaryConfiguration: primaryConfiguration,
                cacheConfiguration: cacheConfiguration
            )
            recordStartupMode("local_only")
            Logger.database.notice("Using local-only SwiftData store in Release.")
            return container
        } catch {
            let localError = String(describing: error)
            Logger.database.fault("Local-only ModelContainer init failed in Release: \(localError, privacy: .public)")

            guard case ModelContainerStartupError.primaryStore = error else {
                fatalError("Could not create repeat-meal cache store. Primary user data was not reset. \(localError)")
            }

            do {
                let primaryConfiguration = makeLocalReleaseConfiguration(schema: primarySchema)
                try StoreRecovery.backupAndResetStoreFiles(at: primaryConfiguration.url)
                let cacheConfiguration = try makeLocalReleaseCacheConfiguration(schema: repeatCacheSchema)
                let container = try makeModelContainerRecoveringCache(
                    completeSchema: completeSchema,
                    primarySchema: primarySchema,
                    primaryConfiguration: primaryConfiguration,
                    cacheConfiguration: cacheConfiguration
                )
                recordStartupMode("local_only_after_reset")
                Logger.database.notice("Recovered local-only store after backing up unreadable store files.")
                return container
            } catch {
                let retryError = String(describing: error)
                Logger.database.fault("Local-only store recovery failed after reset: \(retryError, privacy: .public)")
                fatalError(
                    "Could not create local-only ModelContainer in Release. "
                        + "Initial error: \(localError). Post-reset error: \(retryError)."
                )
            }
        }
#endif
    }

    #if DEBUG
    static func makeCloudKitConfiguration(schema: Schema) -> ModelConfiguration {
        ModelConfiguration(
            schema: schema,
            isStoredInMemoryOnly: false,
            cloudKitDatabase: .private(cloudKitContainerID)
        )
    }

    static func makeLocalFallbackContainer(
        completeSchema: Schema,
        primarySchema: Schema,
        repeatCacheSchema: Schema,
        reason: CloudKitFallbackReason,
        cloudError: String?
    ) -> ModelContainer {
        do {
            let primaryConfiguration = try makeLocalDebugConfiguration(schema: primarySchema)
            let cacheConfiguration = try makeLocalDebugCacheConfiguration(schema: repeatCacheSchema)
            let container = try makeModelContainerRecoveringCache(
                completeSchema: completeSchema,
                primarySchema: primarySchema,
                primaryConfiguration: primaryConfiguration,
                cacheConfiguration: cacheConfiguration
            )
            recordStartupMode("local_fallback_\(reason.rawValue)")
            Logger.database.notice("Using local SwiftData fallback store due to \(reason.rawValue, privacy: .public).")
            if let cloudError {
                Logger.database.error("CloudKit startup failure before fallback: \(cloudError, privacy: .public)")
            }
            return container
        } catch {
            let fallbackError = String(describing: error)
            Logger.database.error("Local fallback ModelContainer init failed: \(fallbackError, privacy: .public)")

            guard case ModelContainerStartupError.primaryStore = error else {
                fatalError("Could not create repeat-meal cache store. Primary user data was not reset. \(fallbackError)")
            }

            do {
                try resetDebugLocalStoreFiles()
                let primaryConfiguration = try makeLocalDebugConfiguration(schema: primarySchema)
                let cacheConfiguration = try makeLocalDebugCacheConfiguration(schema: repeatCacheSchema)
                let container = try makeModelContainerRecoveringCache(
                    completeSchema: completeSchema,
                    primarySchema: primarySchema,
                    primaryConfiguration: primaryConfiguration,
                    cacheConfiguration: cacheConfiguration
                )
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

    static func makeLocalDebugCacheConfiguration(schema: Schema) throws -> ModelConfiguration {
        ModelConfiguration(
            "RepeatMealCacheDebug",
            schema: schema,
            url: try debugStoreDirectoryURL().appendingPathComponent(repeatCacheStoreFileName),
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
        try debugStoreDirectoryURL().appendingPathComponent(debugStoreFileName)
    }

    private static func debugStoreDirectoryURL() throws -> URL {
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

        return storeDirectoryURL
    }
#endif

    static func makeLocalReleaseConfiguration(schema: Schema) -> ModelConfiguration {
        ModelConfiguration(
            schema: schema,
            isStoredInMemoryOnly: false,
            cloudKitDatabase: .none
        )
    }

    static func makeLocalReleaseCacheConfiguration(schema: Schema) throws -> ModelConfiguration {
        ModelConfiguration(
            "RepeatMealCacheRelease",
            schema: schema,
            url: try repeatCacheStoreURL(),
            cloudKitDatabase: .none
        )
    }

    private static func repeatCacheStoreURL() throws -> URL {
        let applicationSupportURL = try FileManager.default.url(
            for: .applicationSupportDirectory,
            in: .userDomainMask,
            appropriateFor: nil,
            create: true
        )
        return applicationSupportURL.appendingPathComponent(repeatCacheStoreFileName)
    }

    static func makeModelContainerRecoveringCache(
        completeSchema: Schema,
        primarySchema: Schema,
        primaryConfiguration: ModelConfiguration,
        cacheConfiguration: ModelConfiguration,
        containerFactory: (Schema, [ModelConfiguration]) throws -> ModelContainer = { schema, configurations in
            try ModelContainer(for: schema, configurations: configurations)
        },
        resetStoreFiles: (URL) throws -> Void = { storeURL in
            try StoreRecovery.backupAndResetStoreFiles(at: storeURL)
        }
    ) throws -> ModelContainer {
        do {
            return try containerFactory(completeSchema, [primaryConfiguration, cacheConfiguration])
        } catch {
            let initialError = String(describing: error)

            do {
                _ = try containerFactory(primarySchema, [primaryConfiguration])
            } catch {
                throw ModelContainerStartupError.primaryStore(
                    initial: initialError,
                    primary: String(describing: error)
                )
            }

            do {
                try resetStoreFiles(cacheConfiguration.url)
                return try containerFactory(completeSchema, [primaryConfiguration, cacheConfiguration])
            } catch {
                throw ModelContainerStartupError.cacheStore(
                    initial: initialError,
                    cache: String(describing: error)
                )
            }
        }
    }

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

    static func applyUITestLaunchOverrides() {
        let arguments = ProcessInfo.processInfo.arguments
        guard arguments.contains("UITestMode") else {
            return
        }

        let defaults = UserDefaults.standard
        for key in uiTestOnboardingBooleanKeys {
            guard
                let rawValue = launchArgumentValue(for: key, in: arguments),
                let boolValue = boolValue(from: rawValue)
            else {
                continue
            }
            defaults.set(boolValue, forKey: key)
        }

        if let rawPrimaryGoal = launchArgumentValue(for: "onboarding.primaryGoal", in: arguments) {
            if rawPrimaryGoal == "__unset__" {
                defaults.removeObject(forKey: "onboarding.primaryGoal")
            } else {
                defaults.set(rawPrimaryGoal, forKey: "onboarding.primaryGoal")
            }
        }

        if let rawPCOSExperience = launchArgumentValue(for: "onboarding.pcosExperience", in: arguments) {
            if rawPCOSExperience == "__unset__" {
                defaults.removeObject(forKey: "onboarding.pcosExperience")
            } else {
                defaults.set(rawPCOSExperience, forKey: "onboarding.pcosExperience")
            }
        }

        if let rawSymptomFocusAreas = launchArgumentValue(for: "onboarding.symptomFocusAreas", in: arguments) {
            if rawSymptomFocusAreas == "__unset__" {
                defaults.removeObject(forKey: "onboarding.symptomFocusAreas")
            } else {
                let values = rawSymptomFocusAreas
                    .split(separator: ",")
                    .map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
                    .filter { !$0.isEmpty }
                defaults.set(values, forKey: "onboarding.symptomFocusAreas")
            }
        }

        if let rawPreferredName = launchArgumentValue(for: "onboarding.preferredName", in: arguments) {
            if rawPreferredName == "__unset__" {
                defaults.removeObject(forKey: "onboarding.preferredName")
            } else {
                defaults.set(
                    rawPreferredName.trimmingCharacters(in: .whitespacesAndNewlines),
                    forKey: "onboarding.preferredName"
                )
            }
        }

        if let rawAppLanguage = launchArgumentValue(for: AppLanguage.defaultsKey, in: arguments) {
            let appLanguage = AppLanguage(rawValue: rawAppLanguage) ?? .system
            appLanguage.persist(defaults: defaults)
        }

        if let rawResetReportPolicy = launchArgumentValue(for: uiTestReportPolicyResetKey, in: arguments),
           boolValue(from: rawResetReportPolicy) == true {
            [
                "reports.freeExportConsumed",
                "reports.openedReport",
                "reports.exportedReport",
                "reports.dismissedInsightsBanner",
            ].forEach(defaults.removeObject)
        }

        applyUITestAppearanceOverrideIfNeeded(
            arguments: arguments,
            appearancePreferences: .shared
        )
    }

    static func applyUITestDemoScenarioIfNeeded(to container: ModelContainer) throws {
        let arguments = ProcessInfo.processInfo.arguments
        guard arguments.contains("UITestMode") else {
            return
        }

        guard
            let rawScenario = launchArgumentValue(for: uiTestDemoScenarioKey, in: arguments),
            let scenario = DemoDataScenario(rawValue: rawScenario)
        else {
            return
        }

        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(secondsFromGMT: 0) ?? .current

        var backup = DemoDataBuilder(calendar: calendar).makeBackup(
            for: scenario,
            referenceDate: Date()
        )
        backup.records.insights = []

        let modelContext = container.mainContext
        let importService = SettingsDataImportService(modelContext: modelContext)
        _ = try importService.replaceAll(with: backup)
        try seedGeneratedInsights(in: modelContext)
        #if DEBUG
        try seedRepeatMealSuggestionIfNeeded(in: modelContext, arguments: arguments)
        #endif
        applyUITestDemoScenarioDefaults(scenario)

        Logger.database.info("Loaded UI test demo scenario \(scenario.rawValue, privacy: .public)")
    }

    #if DEBUG
    static func seedRepeatMealSuggestionIfNeeded(
        in modelContext: ModelContext,
        arguments: [String]
    ) throws {
        guard arguments.contains("UITestMode"),
              arguments.contains("SeedRepeatMealSuggestion") else {
            return
        }

        guard let sampleImage = UIImage(named: "botanical-meal-bowl") else {
            throw UITestDemoSeedError.missingSampleMealImage
        }
        let normalizedImage = try MealScanImageNormalizer().normalizeJPEGData(from: sampleImage)
        let loggedAt = Date().addingTimeInterval(-3_600)
        let sourceMealID = UUID(uuidString: "6D9979A0-0FC4-4AA2-AB8C-2D5DA356A1D4") ?? UUID()
        let sourceMeal = MealEntry(
            id: sourceMealID,
            timestamp: loggedAt,
            mealType: .lunch,
            mealDescription: "Reviewed lentil bowl",
            glycemicImpact: .medium,
            carbsGrams: 52,
            proteinGrams: 27,
            fatGrams: 14,
            sourceLabel: "Photo meal estimate",
            calories: 430,
            fiberGrams: 9,
            mealSource: NutritionImportSourceKind.aiMealScan.rawValue,
            confidenceScore: NutritionConfidence.high.score,
            userConfirmed: true
        )
        let nutrition = NutritionSnapshot(
            caloriesKcal: 430,
            proteinGrams: 27,
            carbsGrams: 52,
            fatGrams: 14,
            fiberGrams: 9
        )
        let item = MealFoodItemDraft(
            displayName: "Lentil rice bowl",
            canonicalFoodId: "lentil-rice-bowl",
            nutritionSource: .usda,
            estimatedGrams: 320,
            servingDescription: "1 reviewed bowl",
            nutrition: nutrition,
            confidence: .high,
            detectionSource: "ui_test_reviewed_meal",
            portionEstimationMethod: .servingSizeHeuristic
        )
        let snapshot = RepeatMealDraftSnapshot(
            mealName: "Reviewed lentil bowl",
            mealType: .lunch,
            items: [item],
            nutrition: nutrition,
            confidence: .high,
            warnings: [],
            hiddenIngredientEstimate: .no,
            source: RepeatMealSourceMetadata(
                modelVersion: "ui-test-reviewed-v1",
                pipelineVersion: MealScanPipeline.pipelineVersion
            )
        )
        let snapshotData = try JSONEncoder().encode(snapshot)
        guard let snapshotJSON = String(data: snapshotData, encoding: .utf8) else {
            return
        }

        modelContext.insert(sourceMeal)
        modelContext.insert(
            MealScanRepeatCacheRecord(
                sourceMealID: sourceMealID,
                sourceImageHash: normalizedImage.sourceImageHash,
                featurePrintArchive: nil,
                visionRevision: 2,
                snapshotJSON: snapshotJSON,
                snapshotSchemaVersion: snapshot.schemaVersion,
                mealName: snapshot.mealName,
                mealType: snapshot.mealType,
                caloriesKcal: snapshot.nutrition.caloriesKcal,
                proteinGrams: snapshot.nutrition.proteinGrams,
                carbsGrams: snapshot.nutrition.carbsGrams,
                fatGrams: snapshot.nutrition.fatGrams,
                sourceMealLoggedAt: loggedAt,
                createdAt: loggedAt,
                lastUsedAt: loggedAt
            )
        )
        try modelContext.save()
    }
    #endif

    static func applyStoredAppLanguageOverrideIfNeeded() {
        let arguments = ProcessInfo.processInfo.arguments
        guard !AppLanguage.hasExplicitLaunchOverride(in: arguments) else {
            return
        }

        let defaults = UserDefaults.standard
        let appLanguage = AppLanguage.stored(defaults: defaults)
        appLanguage.applyLaunchOverride(defaults: defaults)
    }

    static func configureRevenueCatIfPossible() {
        let configuration = BillingConfiguration.from(
            productIDs: [
                SubscriptionManager.monthlyProductID,
                SubscriptionManager.yearlyProductID,
            ]
        )

        guard configuration.backendMode == .revenueCat else {
            Logger.storeKit.info("Using \(configuration.backendMode.rawValue, privacy: .public) billing backend for this run")
            return
        }

        do {
            try RevenueCatBillingClient(configuration: configuration).configureIfNeeded()
        } catch {
            Logger.storeKit.error("RevenueCat startup configuration failed: \(error.localizedDescription, privacy: .public)")
        }
    }

    /// Lifecycle mode persisted by `AppState`, read here because seeding runs before the app state exists.
    static func storedLifecycleMode(defaults: UserDefaults = .standard) -> LifecycleMode {
        LifecycleMode(rawValue: defaults.string(forKey: "lifecycle.mode") ?? "") ?? .cycling
    }

    static func seedGeneratedInsights(in modelContext: ModelContext) throws {
        let appLanguage = resolvedSeedAppLanguage()
        let generatedInsights = try L10n.withOverrides(
            appLanguage: appLanguage,
            preferredLanguages: resolvedSeedPreferredLanguages(for: appLanguage)
        ) {
            try InsightEngine(modelContext: modelContext).generateInsights(lifecycleMode: storedLifecycleMode())
        }
        for insight in generatedInsights {
            modelContext.insert(insight)
        }
        try modelContext.save()
        InsightLocalizationRefreshService.markCurrentLanguage(
            appLanguage: appLanguage,
            preferredLanguages: resolvedSeedPreferredLanguages(for: appLanguage)
        )
    }

    static func applyUITestDemoScenarioDefaults(
        _ scenario: DemoDataScenario,
        defaults: UserDefaults = .standard
    ) {
        let onboardingDefaults = scenario.onboardingDefaults
        defaults.set(true, forKey: "onboarding.hasCompletedWelcome")
        defaults.set(true, forKey: "onboarding.hasCompletedQuestionnaire")
        defaults.set(true, forKey: "onboarding.hasCompletedGuidedAction")
        defaults.set(true, forKey: "onboarding.hasCompletedOnboarding")
        defaults.set(onboardingDefaults.primaryGoal.rawValue, forKey: "onboarding.primaryGoal")
        defaults.set(onboardingDefaults.experience.rawValue, forKey: "onboarding.pcosExperience")
        defaults.set(onboardingDefaults.focusAreas.map(\.rawValue), forKey: "onboarding.symptomFocusAreas")
    }

    private static func launchArgumentValue(for key: String, in arguments: [String]) -> String? {
        guard let index = arguments.firstIndex(of: "-\(key)") else {
            return nil
        }
        let valueIndex = arguments.index(after: index)
        guard valueIndex < arguments.endIndex else {
            return nil
        }
        return arguments[valueIndex]
    }

    static func applyAppearanceLaunchOverridesIfNeeded(
        arguments: [String] = ProcessInfo.processInfo.arguments,
        appearancePreferences: AppearancePreferences = .shared
    ) {
        if let rawExperimentalThemes = launchArgumentValue(for: uiTestExperimentalThemesKey, in: arguments),
           let experimentalThemesEnabled = boolValue(from: rawExperimentalThemes) {
            appearancePreferences.setExperimentalThemesEnabled(experimentalThemesEnabled)
        }

        if let rawThemeOption = launchArgumentValue(for: uiTestThemeOptionKey, in: arguments),
           let themeOption = ThemeOption(rawValue: rawThemeOption) {
            if themeOption.isExperimental {
                appearancePreferences.setExperimentalThemesEnabled(true)
            }
            appearancePreferences.setThemeOption(themeOption)
        }

        if let rawFontOption = launchArgumentValue(for: uiTestFontOptionKey, in: arguments),
           let fontOption = FontOption(rawValue: rawFontOption) {
            appearancePreferences.setFontOption(fontOption)
        }

        if let rawMotionStyle = launchArgumentValue(for: RingMotionStyle.defaultsKey, in: arguments),
           let motionStyle = RingMotionStyle(rawValue: rawMotionStyle) {
            RingMotionStyle.store(motionStyle)
        }
    }

    static func applyUITestAppearanceOverrideIfNeeded(
        arguments: [String],
        appearancePreferences: AppearancePreferences
    ) {
        guard arguments.contains("UITestMode") else {
            return
        }

        applyAppearanceLaunchOverridesIfNeeded(
            arguments: arguments,
            appearancePreferences: appearancePreferences
        )
    }

    private static func boolValue(from rawValue: String) -> Bool? {
        switch rawValue.lowercased() {
        case "1", "true", "yes":
            true
        case "0", "false", "no":
            false
        default:
            nil
        }
    }

    private static func resolvedSeedAppLanguage(
        defaults: UserDefaults = .standard,
        arguments: [String] = ProcessInfo.processInfo.arguments
    ) -> AppLanguage {
        if let rawAppLanguage = launchArgumentValue(for: AppLanguage.defaultsKey, in: arguments),
           let appLanguage = AppLanguage(rawValue: rawAppLanguage) {
            return appLanguage
        }

        return AppLanguage.stored(defaults: defaults)
    }

    private static func resolvedSeedPreferredLanguages(
        for appLanguage: AppLanguage,
        arguments: [String] = ProcessInfo.processInfo.arguments
    ) -> [String] {
        if let explicitLanguage = appLanguage.languageIdentifier {
            return [explicitLanguage]
        }

        if let rawAppleLanguages = launchArgumentValue(for: AppLanguage.appleLanguagesDefaultsKey, in: arguments) {
            let trimmed = rawAppleLanguages
                .trimmingCharacters(in: CharacterSet(charactersIn: "()"))
                .split(separator: ",")
                .map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
                .filter { !$0.isEmpty }
            if !trimmed.isEmpty {
                return trimmed
            }
        }

        return Locale.preferredLanguages
    }
}
