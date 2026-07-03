import Testing
import Foundation
@testable import PCOS

@Suite("OnboardingProfile")
struct OnboardingProfileTests {
    @MainActor
    private func makeProfile(testName: String = #function) -> OnboardingProfile {
        let suiteName = "PCOS.OnboardingProfileTests.\(testName)"
        let defaults = UserDefaults(suiteName: suiteName)!
        defaults.removePersistentDomain(forName: suiteName)
        return OnboardingProfile(defaults: defaults)
    }

    // MARK: - SymptomFocusArea Enum

    @Test("SymptomFocusArea has 4 cases")
    func focusAreaCount() {
        #expect(SymptomFocusArea.allCases.count == 4)
    }

    @Test("SymptomFocusArea raw values are unique")
    func uniqueFocusRawValues() {
        let rawValues = SymptomFocusArea.allCases.map(\.rawValue)
        #expect(Set(rawValues).count == rawValues.count)
    }

    @Test("Each SymptomFocusArea maps to at least one SymptomCategory")
    func focusAreasMappedToCategories() {
        for area in SymptomFocusArea.allCases {
            #expect(!area.relatedCategories.isEmpty,
                    "\(area) should map to at least one SymptomCategory")
        }
    }

    @Test("SymptomFocusArea relatedCategories produce valid categories")
    func relatedCategoriesValid() {
        let allCategories = Set(SymptomCategory.allCases)
        for area in SymptomFocusArea.allCases {
            for category in area.relatedCategories {
                #expect(allCategories.contains(category),
                        "\(area) references unknown category \(category)")
            }
        }
    }

    @Test("SymptomFocusArea has displayName, subtitle, and systemImage")
    func focusAreaDisplayProperties() {
        for area in SymptomFocusArea.allCases {
            #expect(!area.displayName.isEmpty)
            #expect(!area.subtitle.isEmpty)
            #expect(!area.systemImage.isEmpty)
        }
    }

    // MARK: - OnboardingProfile Persistence

    @Test("symptomFocusAreas persists and retrieves correctly")
    @MainActor
    func focusAreasPersistence() {
        let profile = makeProfile()

        // Clear any previous state
        profile.resetOnboarding()
        #expect(profile.symptomFocusAreas.isEmpty)

        // Set areas
        profile.symptomFocusAreas = [.moodEnergy, .painCramps]
        #expect(profile.symptomFocusAreas.count == 2)
        #expect(profile.symptomFocusAreas.contains(.moodEnergy))
        #expect(profile.symptomFocusAreas.contains(.painCramps))

        // Verify reset clears them
        profile.resetOnboarding()
        #expect(profile.symptomFocusAreas.isEmpty)
    }

    @Test("preferredName trims whitespace and resets")
    @MainActor
    func preferredNameTrimsAndResets() {
        let profile = makeProfile()
        profile.resetOnboarding()

        profile.preferredName = "  Aisha  "
        #expect(profile.preferredName == "Aisha")
        #expect(profile.preferredDisplayName == "Aisha")

        profile.preferredName = "   "
        #expect(profile.preferredName.isEmpty)
        #expect(profile.preferredDisplayName == nil)

        profile.preferredName = "__unset__"
        #expect(profile.preferredName.isEmpty)
        #expect(profile.preferredDisplayName == nil)

        profile.preferredName = "Mina"
        profile.resetOnboarding()
        #expect(profile.preferredDisplayName == nil)
    }

    // MARK: - Derived State

    @Test("preferredSymptomCategories is empty when no focus areas selected")
    @MainActor
    func noFocusAreasYieldsEmptyCategories() {
        let profile = makeProfile()
        profile.resetOnboarding()
        #expect(profile.preferredSymptomCategories.isEmpty)
    }

    @Test("preferredSymptomCategories maps focus areas to categories")
    @MainActor
    func focusAreasMapToCategories() {
        let profile = makeProfile()
        profile.resetOnboarding()
        profile.symptomFocusAreas = [.moodEnergy]
        let categories = profile.preferredSymptomCategories
        #expect(categories.contains(.mood))
        #expect(categories.contains(.metabolic))
    }

    @Test("painCramps focus includes digestive category for nausea visibility")
    @MainActor
    func painFocusIncludesDigestive() {
        let profile = makeProfile()
        profile.resetOnboarding()
        profile.symptomFocusAreas = [.painCramps]

        let categories = profile.preferredSymptomCategories
        #expect(categories.contains(.pain))
        #expect(categories.contains(.digestive))
    }

    @Test("suggestedFirstAction defaults to logPeriod")
    @MainActor
    func defaultFirstAction() {
        let profile = makeProfile()
        profile.resetOnboarding()
        #expect(profile.suggestedFirstAction == .logPeriod)
    }

    @Test("suggestedFirstAction returns logSymptoms for understandSymptoms goal")
    @MainActor
    func symptomGoalFirstAction() {
        let profile = makeProfile()
        profile.resetOnboarding()
        profile.primaryGoal = .understandSymptoms
        #expect(profile.suggestedFirstAction == .logSymptoms)
        profile.resetOnboarding()
    }

    @Test("hintVerbosity is educational by default")
    @MainActor
    func defaultHintVerbosity() {
        let profile = makeProfile()
        profile.resetOnboarding()
        #expect(profile.hintVerbosity == .educational)
    }

    @Test("hintVerbosity is brief for experienced users")
    @MainActor
    func experiencedHintVerbosity() {
        let profile = makeProfile()
        profile.resetOnboarding()
        profile.pcosExperience = .experienced
        #expect(profile.hintVerbosity == .brief)
        profile.resetOnboarding()
    }

    // MARK: - Hint Management

    @Test("hints are shown by default and can be dismissed")
    @MainActor
    func hintDismissal() {
        let profile = makeProfile()
        profile.resetOnboarding()

        #expect(profile.shouldShowHint(OnboardingProfile.hintQuickLogIntro))
        profile.dismissHint(OnboardingProfile.hintQuickLogIntro)
        #expect(!profile.shouldShowHint(OnboardingProfile.hintQuickLogIntro))

        profile.resetOnboarding()
    }

    @Test("dismissing a hint twice is a no-op")
    @MainActor
    func doubleDismissIsIdempotent() {
        let profile = makeProfile()
        profile.resetOnboarding()

        profile.dismissHint(OnboardingProfile.hintCalendarTab)
        profile.dismissHint(OnboardingProfile.hintCalendarTab)
        #expect(!profile.shouldShowHint(OnboardingProfile.hintCalendarTab))

        profile.resetOnboarding()
    }

    // MARK: - Persona-Aware Hint Copy

    @Test("quickLogHintMessage varies by primary goal")
    @MainActor
    func quickLogHintCopy() {
        let profile = makeProfile()
        profile.resetOnboarding()

        profile.primaryGoal = .trackCycles
        #expect(
            profile.quickLogHintMessage == String(
                localized: "Tap Light, Medium, or Heavy to log today's flow in one tap.",
                comment: "Onboarding tooltip introducing the quick period logging buttons."
            )
        )

        profile.primaryGoal = .understandSymptoms
        #expect(
            profile.quickLogHintMessage == String(
                localized: "You can quickly log your period here — even if that's not your main focus.",
                comment: "Onboarding tooltip introducing quick period logging for users focused on symptoms."
            )
        )

        profile.resetOnboarding()
    }

    @Test("calendarHintMessage is brief for experienced users")
    @MainActor
    func calendarHintCopyExperienced() {
        let profile = makeProfile()
        profile.resetOnboarding()

        profile.pcosExperience = .experienced
        #expect(
            profile.calendarHintMessage == String(
                localized: "Your Calendar is in the second tab.",
                comment: "Onboarding tooltip pointing users to the Calendar tab."
            )
        )

        profile.pcosExperience = .newlyDiagnosed
        #expect(
            profile.calendarHintMessage == String(
                localized: "Check the Calendar tab to see your cycle at a glance.",
                comment: "Onboarding tooltip pointing users to the Calendar tab."
            )
        )

        profile.resetOnboarding()
    }

    @Test("symptomHintMessage uses focus area context")
    @MainActor
    func symptomHintUsesContext() {
        let profile = makeProfile()
        profile.resetOnboarding()

        profile.symptomFocusAreas = [.painCramps]
        #expect(
            profile.symptomHintMessage == String(
                localized: "Tracking pain alongside your cycle helps spot which days hit hardest.",
                comment: "Onboarding tooltip encouraging daily symptom logging for pain and cramps."
            )
        )

        profile.symptomFocusAreas = [.moodEnergy]
        #expect(
            profile.symptomHintMessage == String(
                localized: "Log how you're feeling each day — patterns emerge within a cycle or two.",
                comment: "Onboarding tooltip encouraging daily symptom logging for mood and energy."
            )
        )

        profile.symptomFocusAreas = []
        #expect(
            profile.symptomHintMessage == String(
                localized: "Logging symptoms daily helps surface patterns with your cycle.",
                comment: "Onboarding tooltip encouraging daily symptom logging."
            )
        )

        profile.resetOnboarding()
    }

    @Test("onboarding flow surfaces HealthKit reveal and meal scan preview before plan")
    @MainActor
    func onboardingFlowSurfacesImmediateValueBeforePlan() throws {
        let root = try TestHelpers.projectRoot(from: #filePath)
        let source = try String(contentsOf: root.appendingPathComponent("PCOS/PCOS/Features/Onboarding/Views/OnboardingContainerView.swift"))
        let completionSource = try String(contentsOf: root.appendingPathComponent("PCOS/PCOS/Features/Onboarding/Views/OnboardingCompletionView.swift"))

        #expect(source.contains("OnboardingHealthContextRevealView"))
        #expect(source.contains("OnboardingMealScanDemoView"))
        #expect(source.contains("nextPhase(after:"))
        #expect(!source.contains("candidate == .mealScanDemo && !MealScanFeatureFlags.current.enableMealScanV2"))
        #expect(source.contains("OnboardingLanguageWelcomeView"))
        #expect(source.contains("OnboardingThemeSelectionView"))
        #expect(source.contains("OnboardingNameCaptureView"))
        #expect(source.contains("Welcome to CycleBalance. We're glad you're here."))
        #expect(source.contains("Which language would you like to use?"))
        #expect(source.contains("Background, theme, and font"))
        #expect(source.contains("ForEach(FontOption.allCases)"))
        #expect(source.contains(#""onboarding.font.option.\(font.rawValue)""#))
        #expect(completionSource.contains("NotificationManager"))
        #expect(completionSource.contains("scheduleSymptomLoggingReminder()"))
        #expect(completionSource.contains("onboarding.completion.reminder"))
        #expect(!source.contains("case .aha"))
        #expect(!source.contains("case .rating"))
        #expect(!source.contains("RatingPromptView("))
        #expect(!FileManager.default.fileExists(
            atPath: root.appendingPathComponent("PCOS/PCOS/Features/Onboarding/Views/RatingPromptView.swift").path
        ))

        let languageIndex = try #require(source.range(of: "case .welcomeLanguage")?.lowerBound)
        let themeIndex = try #require(source.range(of: "case .theme")?.lowerBound)
        let nameIndex = try #require(source.range(of: "case .name")?.lowerBound)
        let quizIndex = try #require(source.range(of: "case .quiz")?.lowerBound)
        let permissionsIndex = try #require(source.range(of: "case .permissions")?.lowerBound)
        let healthRevealIndex = try #require(source.range(of: "case .healthContext")?.lowerBound)
        let mealDemoIndex = try #require(source.range(of: "case .mealScanDemo")?.lowerBound)
        let planIndex = try #require(source.range(of: "case .yourPlan")?.lowerBound)

        #expect(languageIndex < themeIndex)
        #expect(themeIndex < nameIndex)
        #expect(nameIndex < quizIndex)
        #expect(permissionsIndex < healthRevealIndex)
        #expect(healthRevealIndex < mealDemoIndex)
        #expect(mealDemoIndex < planIndex)
    }

    // MARK: - Guided Action Completion

    @Test("dismissed log sheet without a new record stays incomplete")
    func cancelledGuidedActionDismissalDoesNotComplete() {
        #expect(!GuidedActionCompletionPolicy.didCreateRecord(initialCount: 3, currentCount: 3))
    }

    @Test("saved first log completes guided action")
    func savedGuidedActionRecordCompletes() {
        #expect(GuidedActionCompletionPolicy.didCreateRecord(initialCount: 3, currentCount: 4))
    }

    @Test("missing initial guided action baseline stays incomplete")
    func missingGuidedActionBaselineStaysIncomplete() {
        #expect(!GuidedActionCompletionPolicy.didCreateRecord(initialCount: nil, currentCount: 1))
    }

    @Test("guided action skip copy accurately describes continuing setup")
    func guidedActionSkipCopy() {
        #expect(
            SuggestedFirstAction.logPeriod.guidedActionSkipTitle == L10n.string(
                "Skip for now",
                defaultValue: "Skip for now"
            )
        )
        #expect(
            SuggestedFirstAction.logSymptoms.guidedActionSkipHint == String(
                localized: "Continue setup without logging your first entry right now.",
                comment: "Accessibility hint for the guided action skip button."
            )
        )
    }

    // MARK: - Persisted Phase

    @Test("currentPhaseRaw is nil by default")
    @MainActor
    func currentPhaseRawDefaultsToNil() {
        let profile = makeProfile()
        #expect(profile.currentPhaseRaw == nil)
    }

    @Test("currentPhaseRaw persists and retrieves raw phase values")
    @MainActor
    func currentPhaseRawPersistence() {
        let profile = makeProfile()

        profile.currentPhaseRaw = "quiz"
        #expect(profile.currentPhaseRaw == "quiz")

        profile.currentPhaseRaw = "health_context"
        #expect(profile.currentPhaseRaw == "health_context")
    }

    @Test("currentPhaseRaw clears when set to nil")
    @MainActor
    func currentPhaseRawClearsOnNil() {
        let profile = makeProfile()

        profile.currentPhaseRaw = "social_proof"
        #expect(profile.currentPhaseRaw == "social_proof")

        profile.currentPhaseRaw = nil
        #expect(profile.currentPhaseRaw == nil)
    }

    @Test("resetOnboarding clears currentPhaseRaw")
    @MainActor
    func resetClearsCurrentPhaseRaw() {
        let profile = makeProfile()

        profile.currentPhaseRaw = "your_plan"
        profile.resetOnboarding()
        #expect(profile.currentPhaseRaw == nil)
    }

    // MARK: - Reset

    @Test("resetOnboarding clears all onboarding state")
    @MainActor
    func resetClearsAllState() {
        let profile = makeProfile()

        // Set everything
        profile.hasCompletedWelcome = true
        profile.hasCompletedQuestionnaire = true
        profile.hasCompletedGuidedAction = true
        profile.primaryGoal = .trackCycles
        profile.pcosExperience = .experienced
        profile.symptomFocusAreas = [.moodEnergy, .skinHair]
        profile.preferredName = "Aisha"
        profile.dismissHint(OnboardingProfile.hintCalendarTab)

        // Reset
        profile.resetOnboarding()

        // Verify all cleared
        #expect(!profile.hasCompletedWelcome)
        #expect(!profile.hasCompletedQuestionnaire)
        #expect(!profile.hasCompletedGuidedAction)
        #expect(profile.primaryGoal == nil)
        #expect(profile.pcosExperience == nil)
        #expect(profile.symptomFocusAreas.isEmpty)
        #expect(profile.preferredDisplayName == nil)
        #expect(profile.shouldShowHint(OnboardingProfile.hintCalendarTab))
    }
}
