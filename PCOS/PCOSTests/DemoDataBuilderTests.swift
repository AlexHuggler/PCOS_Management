import Testing
import Foundation
@testable import PCOS

@Suite("Demo Data Builder", .serialized)
@MainActor
struct DemoDataBuilderTests {
    @Test("all scenarios generate irregular cycles and non-empty symptom history")
    func allScenariosGenerateIrregularCycleHistory() {
        let builder = DemoDataBuilder(calendar: Calendar(identifier: .gregorian))
        let referenceDate = Date(timeIntervalSince1970: 1_774_123_200) // Mar 7, 2026

        for scenario in DemoDataScenario.allCases {
            let backup = builder.makeBackup(for: scenario, referenceDate: referenceDate)
            let completedLengths = backup.records.cycles.compactMap(\.lengthDays)

            #expect(backup.source.kind == .demoScenario)
            #expect(backup.source.scenarioID == scenario.rawValue)
            #expect(completedLengths.count >= 4)
            #expect((completedLengths.max() ?? 0) - (completedLengths.min() ?? 0) >= 10)
            #expect(!backup.records.symptoms.isEmpty)
            #expect(!backup.records.bloodSugarReadings.isEmpty)
            #expect(!backup.records.supplements.isEmpty)
        }
    }

    @Test("ttc scenario contains very long completed cycles for fertility uncertainty")
    func ttcScenarioContainsLongCycles() {
        let backup = DemoDataBuilder().makeBackup(for: .ttcFertility, referenceDate: Date())
        let completedLengths = backup.records.cycles.compactMap(\.lengthDays)
        #expect((completedLengths.max() ?? 0) >= 60)
    }

    @Test("symptom management fixture stays in sync with the checked-in demo backup")
    func symptomManagementFixtureStaysInSync() throws {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(secondsFromGMT: 0)!
        let formatter = ISO8601DateFormatter()
        formatter.formatOptions = [.withInternetDateTime]
        let referenceDate = formatter.date(from: "2026-03-15T12:00:00Z")!

        let generatedBackup = DemoDataBuilder(calendar: calendar).makeBackup(
            for: .symptomManagement,
            referenceDate: referenceDate
        )
        let fixtureURL = try TestHelpers.importFixtureURL(named: TestHelpers.demoBackupFixtureName, from: #filePath)
        let fixtureData = try Data(contentsOf: fixtureURL)
        let fixtureBackup = try SettingsDataBackupCoding.makeDecoder().decode(SettingsDataBackupFile.self, from: fixtureData)
        let generatedData = try SettingsDataBackupCoding.makeEncoder().encode(generatedBackup)
        let normalizedFixtureData = try SettingsDataBackupCoding.makeEncoder().encode(fixtureBackup)

        #expect(normalizedFixtureData == generatedData)
    }

    @Test("symptom management scenario includes showcase coverage for new features")
    func symptomManagementScenarioIncludesShowcaseCoverage() {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(secondsFromGMT: 0)!
        let formatter = ISO8601DateFormatter()
        formatter.formatOptions = [.withInternetDateTime]
        let referenceDate = formatter.date(from: "2026-03-15T12:00:00Z")!
        let backup = DemoDataBuilder(calendar: calendar).makeBackup(
            for: .symptomManagement,
            referenceDate: referenceDate
        )

        let cycles = backup.records.cycles
        #expect(cycles.contains { $0.manualCycleLengthOverrideDays != nil })
        #expect(cycles.contains { $0.ovulationStatus == .anovulatory })

        let meals = backup.records.meals
        #expect(meals.contains { record in
            guard let templateID = record.selectedTemplateID else { return false }
            return !templateID.isEmpty
        })
        #expect(meals.contains { record in
            let hasFeedback = (record.postMealSymptomSeverity ?? 0) > 0
                || !(record.postMealSymptomNote?.isEmpty ?? true)
                || record.postMealFeedbackTimestamp != nil
            return hasFeedback
        })

        let readings = backup.records.bloodSugarReadings
        #expect(readings.contains { $0.readingType == .beforeMeal })
        #expect(readings.contains { $0.readingType == .afterMeal })
        #expect(hasPairedMealSpikeSamples(readings: readings, calendar: calendar))

        #expect(backup.records.dailyLogs.contains { $0.restingHeartRateBPM != nil })
        #expect(hasSupplementDosageChanges(supplements: backup.records.supplements))

        let photos = backup.records.hairPhotos
        #expect(photos.contains { !($0.analysisResult?.isEmpty ?? true) })
        #expect(photoTypesWithAtLeastTwoEntries(photos).count >= 2)

        let insights = backup.records.insights
        #expect(insights.contains { $0.insightType == .seasonalPattern })
        #expect(insights.contains { $0.title.lowercased().contains("forecast") })
        #expect(
            insights.contains { insight in
                insight.content.contains("n=")
                    && insight.content.contains("confidence")
                    && (insight.content.contains("Δ") || insight.content.lowercased().contains("delta"))
            }
        )
    }

    @Test("scenario onboarding defaults are applied to onboarding profile")
    func scenarioDefaultsApplyToOnboardingProfile() {
        let suiteName = "PCOS.DemoDataBuilderTests.scenarioDefaultsApplyToOnboardingProfile"
        let defaultsStore = UserDefaults(suiteName: suiteName)!
        defaultsStore.removePersistentDomain(forName: suiteName)
        let profile = OnboardingProfile(defaults: defaultsStore)
        defer { defaultsStore.removePersistentDomain(forName: suiteName) }

        for scenario in DemoDataScenario.allCases {
            profile.resetOnboarding()
            scenario.applyOnboardingDefaults(to: profile)

            let defaults = scenario.onboardingDefaults
            #expect(profile.primaryGoal == defaults.primaryGoal)
            #expect(profile.pcosExperience == defaults.experience)
            #expect(profile.symptomFocusAreas == defaults.focusAreas)
            #expect(profile.hasCompletedWelcome)
            #expect(profile.hasCompletedQuestionnaire)
            #expect(profile.hasCompletedGuidedAction)
        }
    }

    private func hasPairedMealSpikeSamples(
        readings: [BloodSugarReadingRecord],
        calendar: Calendar
    ) -> Bool {
        let beforeReadings = readings.filter { $0.readingType == .beforeMeal }
        let afterReadings = readings.filter { $0.readingType == .afterMeal }

        for before in beforeReadings {
            guard let context = normalizedContext(before.mealContext) else { continue }
            let beforeDay = calendar.startOfDay(for: before.timestamp)
            let hasMatch = afterReadings.contains { after in
                guard let afterContext = normalizedContext(after.mealContext) else { return false }
                guard afterContext == context else { return false }
                guard calendar.startOfDay(for: after.timestamp) == beforeDay else { return false }
                guard after.timestamp > before.timestamp else { return false }
                return after.timestamp.timeIntervalSince(before.timestamp) <= 3 * 60 * 60
            }
            if hasMatch {
                return true
            }
        }

        return false
    }

    private func hasSupplementDosageChanges(supplements: [SupplementLogRecord]) -> Bool {
        let grouped = Dictionary(grouping: supplements, by: \.supplementName)
        for logs in grouped.values {
            let distinctDosages = Set(logs.compactMap(\.dosageMg))
            if distinctDosages.count >= 2 {
                return true
            }
        }
        return false
    }

    private func photoTypesWithAtLeastTwoEntries(
        _ photos: [HairPhotoEntryRecord]
    ) -> Set<HairPhotoType> {
        let grouped = Dictionary(grouping: photos, by: \.photoType)
        return Set(
            grouped.compactMap { type, entries in
                entries.count >= 2 ? type : nil
            }
        )
    }

    private func normalizedContext(_ context: String?) -> String? {
        guard let context else { return nil }
        let trimmed = context.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        return trimmed.isEmpty ? nil : trimmed
    }
}
