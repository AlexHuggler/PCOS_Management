import Testing
import Foundation
import SwiftData
@testable import PCOS

@Suite("App Language Preferences", .serialized)
@MainActor
struct AppLanguagePreferenceTests {
    @Test("Invalid stored raw value falls back to system default")
    func invalidStoredValueFallsBackToSystemDefault() {
        let (defaults, suiteName) = makeDefaults()
        defer { defaults.removePersistentDomain(forName: suiteName) }

        defaults.set("unsupported", forKey: AppLanguage.defaultsKey)

        #expect(AppLanguage.stored(defaults: defaults) == .system)
    }

    @Test("Non-system selection applies Apple language and locale overrides")
    func nonSystemSelectionAppliesLaunchOverride() {
        let (defaults, suiteName) = makeDefaults()
        defer { defaults.removePersistentDomain(forName: suiteName) }

        AppLanguage.fr.persist(defaults: defaults)
        AppLanguage.fr.applyLaunchOverride(defaults: defaults)

        #expect(AppLanguage.stored(defaults: defaults) == .fr)
        #expect((defaults.array(forKey: AppLanguage.appleLanguagesDefaultsKey) as? [String]) == ["fr"])
        #expect(defaults.string(forKey: AppLanguage.appleLocaleDefaultsKey) == "fr_FR")
    }

    @Test("System default clears stored launch overrides")
    func systemDefaultClearsLaunchOverrides() {
        let (defaults, suiteName) = makeDefaults()
        defer { defaults.removePersistentDomain(forName: suiteName) }

        defaults.set(["de"], forKey: AppLanguage.appleLanguagesDefaultsKey)
        defaults.set("de_DE", forKey: AppLanguage.appleLocaleDefaultsKey)

        AppLanguage.system.persist(defaults: defaults)
        AppLanguage.system.applyLaunchOverride(defaults: defaults)

        let persistentDomain = defaults.persistentDomain(forName: suiteName) ?? [:]

        #expect(persistentDomain[AppLanguage.defaultsKey] == nil)
        #expect(persistentDomain[AppLanguage.appleLanguagesDefaultsKey] == nil)
        #expect(persistentDomain[AppLanguage.appleLocaleDefaultsKey] == nil)
    }

    @Test("Explicit Apple language launch arguments suppress stored override application")
    func explicitAppleLaunchArgsAreDetected() {
        #expect(AppLanguage.hasExplicitLaunchOverride(in: ["UITestMode", "-AppleLanguages", "(fr)"]))
        #expect(AppLanguage.hasExplicitLaunchOverride(in: ["UITestMode", "-AppleLocale", "fr_FR"]))
        #expect(!AppLanguage.hasExplicitLaunchOverride(in: ["UITestMode", "-app.language", "fr"]))

        let (defaults, suiteName) = makeDefaults()
        defer { defaults.removePersistentDomain(forName: suiteName) }

        defaults.set(AppLanguage.de.rawValue, forKey: AppLanguage.defaultsKey)

        #expect(
            AppLanguage.launchSnapshot(
                defaults: defaults,
                arguments: ["UITestMode", "-AppleLanguages", "(fr)"]
            ) == .system
        )
    }

    @Test("AppState persists the selected language without changing the launch snapshot")
    func appStatePersistsSelectionButKeepsLaunchSnapshot() {
        let (defaults, suiteName) = makeDefaults()
        defer { defaults.removePersistentDomain(forName: suiteName) }

        defaults.set(AppLanguage.ja.rawValue, forKey: AppLanguage.defaultsKey)

        let appState = AppState(defaults: defaults)
        #expect(appState.launchAppLanguage == .ja)
        #expect(appState.selectedAppLanguage == .ja)

        appState.selectedAppLanguage = .de

        #expect(appState.launchAppLanguage == .ja)
        #expect(appState.selectedAppLanguage == .de)
        #expect(defaults.string(forKey: AppLanguage.defaultsKey) == AppLanguage.de.rawValue)
        #expect((defaults.array(forKey: AppLanguage.appleLanguagesDefaultsKey) as? [String]) == ["de"])
        #expect(defaults.string(forKey: AppLanguage.appleLocaleDefaultsKey) == "de_DE")
    }

    @Test("System rendering falls back to English for unsupported device languages")
    func systemRenderingFallsBackToEnglishForUnsupportedLanguages() {
        #expect(L10n.resolvedLanguageIdentifier(for: .system, preferredLanguages: ["es_ES"]) == "en")
        #expect(L10n.locale(for: .system, preferredLanguages: ["es_ES"]).identifier == "en_US")
        #expect(L10n.resolvedLanguageIdentifier(for: .system, preferredLanguages: ["fr_CA"]) == "fr")
    }

    @Test("Changing app language regenerates persisted insights in the new locale")
    func changingAppLanguageRelocalizesPersistedInsights() throws {
        let container = try TestHelpers.makeModelContainer()
        let context = container.mainContext
        let (defaults, suiteName) = makeDefaults()
        defer { defaults.removePersistentDomain(forName: suiteName) }

        try seedScenario(.symptomManagement, in: context)

        AppLanguage.fr.persist(defaults: defaults)
        AppLanguage.fr.applyLaunchOverride(defaults: defaults)

        let initialInsights = try persistFreshInsights(
            in: context,
            appLanguage: .fr,
            preferredLanguages: ["fr_FR"]
        )
        InsightLocalizationRefreshService.markCurrentLanguage(
            defaults: defaults,
            appLanguage: .fr,
            preferredLanguages: ["fr_FR"]
        )

        let localizedRegenerator = InsightLocalizationRefreshService(
            modelContext: context,
            defaults: defaults
        )

        AppLanguage.en.persist(defaults: defaults)
        AppLanguage.en.applyLaunchOverride(defaults: defaults)

        let didRefresh = try localizedRegenerator.refreshIfNeeded(
            appLanguage: .en,
            preferredLanguages: ["en_US"]
        )
        #expect(didRefresh)

        let refreshedInsights = try fetchInsights(from: context)
        #expect(refreshedInsights.count == initialInsights.count)

        let initialSummaries = summarizeInsights(initialInsights)
        let refreshedSummaries = summarizeInsights(refreshedInsights)

        #expect(initialSummaries.map(\.signature) == refreshedSummaries.map(\.signature))
        #expect(initialSummaries.map(\.displayText) != refreshedSummaries.map(\.displayText))
        #expect(defaults.string(forKey: InsightLocalizationRefreshService.defaultsKey) == "en")
    }

    private func makeDefaults() -> (UserDefaults, String) {
        let suiteName = "AppLanguagePreferenceTests.\(UUID().uuidString)"
        let defaults = UserDefaults(suiteName: suiteName)!
        defaults.removePersistentDomain(forName: suiteName)
        return (defaults, suiteName)
    }

    private func seedScenario(
        _ scenario: DemoDataScenario,
        in context: ModelContext
    ) throws {
        var backup = DemoDataBuilder(calendar: referenceCalendar).makeBackup(
            for: scenario,
            referenceDate: referenceDate
        )
        backup.records.insights = []

        let importService = SettingsDataImportService(modelContext: context)
        _ = try importService.replaceAll(with: backup)
    }

    private func persistFreshInsights(
        in context: ModelContext,
        appLanguage: AppLanguage,
        preferredLanguages: [String]
    ) throws -> [Insight] {
        let generatedInsights = try L10n.withOverrides(
            appLanguage: appLanguage,
            preferredLanguages: preferredLanguages
        ) {
            try InsightEngine(modelContext: context).generateInsights()
        }
        for insight in generatedInsights {
            context.insert(insight)
        }
        try context.save()
        return try fetchInsights(from: context)
    }

    private func fetchInsights(from context: ModelContext) throws -> [Insight] {
        try context.fetch(
            FetchDescriptor<Insight>(
                sortBy: [SortDescriptor(\.generatedDate, order: .reverse)]
            )
        )
    }

    private func summarizeInsights(_ insights: [Insight]) -> [(signature: String, displayText: String)] {
        insights
            .sorted {
                if $0.insightType.rawValue != $1.insightType.rawValue {
                    return $0.insightType.rawValue < $1.insightType.rawValue
                }
                if $0.dataPointsUsed != $1.dataPointsUsed {
                    return $0.dataPointsUsed < $1.dataPointsUsed
                }
                return $0.confidence < $1.confidence
            }
            .map { insight in
                let roundedConfidence = Int((insight.confidence * 1000).rounded())
                let signature = "\(insight.insightType.rawValue)|\(insight.dataPointsUsed)|\(roundedConfidence)"
                let displayText = "\(insight.title)|\(insight.content)"
                return (signature, displayText)
            }
    }

    private var referenceCalendar: Calendar {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(secondsFromGMT: 0) ?? .current
        return calendar
    }

    private var referenceDate: Date {
        Date(timeIntervalSince1970: 1_773_878_400) // 2026-03-15 12:00:00 UTC
    }
}
