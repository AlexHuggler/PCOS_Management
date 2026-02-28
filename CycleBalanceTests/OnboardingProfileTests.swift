import Testing
@testable import CycleBalance

@Suite("OnboardingProfile")
struct OnboardingProfileTests {

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
        let profile = OnboardingProfile()

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

    // MARK: - Derived State

    @Test("preferredSymptomCategories is empty when no focus areas selected")
    @MainActor
    func noFocusAreasYieldsEmptyCategories() {
        let profile = OnboardingProfile()
        profile.resetOnboarding()
        #expect(profile.preferredSymptomCategories.isEmpty)
    }

    @Test("preferredSymptomCategories maps focus areas to categories")
    @MainActor
    func focusAreasMapToCategories() {
        let profile = OnboardingProfile()
        profile.resetOnboarding()
        profile.symptomFocusAreas = [.moodEnergy]
        let categories = profile.preferredSymptomCategories
        #expect(categories.contains(.mood))
        #expect(categories.contains(.metabolic))
    }

    @Test("suggestedFirstAction defaults to logPeriod")
    @MainActor
    func defaultFirstAction() {
        let profile = OnboardingProfile()
        profile.resetOnboarding()
        #expect(profile.suggestedFirstAction == .logPeriod)
    }

    @Test("suggestedFirstAction returns logSymptoms for understandSymptoms goal")
    @MainActor
    func symptomGoalFirstAction() {
        let profile = OnboardingProfile()
        profile.resetOnboarding()
        profile.primaryGoal = .understandSymptoms
        #expect(profile.suggestedFirstAction == .logSymptoms)
        profile.resetOnboarding()
    }

    @Test("hintVerbosity is educational by default")
    @MainActor
    func defaultHintVerbosity() {
        let profile = OnboardingProfile()
        profile.resetOnboarding()
        #expect(profile.hintVerbosity == .educational)
    }

    @Test("hintVerbosity is brief for experienced users")
    @MainActor
    func experiencedHintVerbosity() {
        let profile = OnboardingProfile()
        profile.resetOnboarding()
        profile.pcosExperience = .experienced
        #expect(profile.hintVerbosity == .brief)
        profile.resetOnboarding()
    }

    // MARK: - Hint Management

    @Test("hints are shown by default and can be dismissed")
    @MainActor
    func hintDismissal() {
        let profile = OnboardingProfile()
        profile.resetOnboarding()

        #expect(profile.shouldShowHint(OnboardingProfile.hintQuickLogIntro))
        profile.dismissHint(OnboardingProfile.hintQuickLogIntro)
        #expect(!profile.shouldShowHint(OnboardingProfile.hintQuickLogIntro))

        profile.resetOnboarding()
    }

    @Test("dismissing a hint twice is a no-op")
    @MainActor
    func doubleDismissIsIdempotent() {
        let profile = OnboardingProfile()
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
        let profile = OnboardingProfile()
        profile.resetOnboarding()

        profile.primaryGoal = .trackCycles
        #expect(profile.quickLogHintMessage.contains("Light, Medium, or Heavy"))

        profile.primaryGoal = .understandSymptoms
        #expect(profile.quickLogHintMessage.contains("even if"))

        profile.resetOnboarding()
    }

    @Test("calendarHintMessage is brief for experienced users")
    @MainActor
    func calendarHintCopyExperienced() {
        let profile = OnboardingProfile()
        profile.resetOnboarding()

        profile.pcosExperience = .experienced
        #expect(profile.calendarHintMessage.contains("second tab"))

        profile.pcosExperience = .newlyDiagnosed
        #expect(profile.calendarHintMessage.contains("at a glance"))

        profile.resetOnboarding()
    }

    @Test("symptomHintMessage uses focus area context")
    @MainActor
    func symptomHintUsesContext() {
        let profile = OnboardingProfile()
        profile.resetOnboarding()

        profile.symptomFocusAreas = [.painCramps]
        #expect(profile.symptomHintMessage.contains("pain"))

        profile.symptomFocusAreas = [.moodEnergy]
        #expect(profile.symptomHintMessage.contains("feeling"))

        profile.symptomFocusAreas = []
        #expect(profile.symptomHintMessage.contains("daily"))

        profile.resetOnboarding()
    }

    // MARK: - Reset

    @Test("resetOnboarding clears all onboarding state")
    @MainActor
    func resetClearsAllState() {
        let profile = OnboardingProfile()

        // Set everything
        profile.hasCompletedWelcome = true
        profile.hasCompletedQuestionnaire = true
        profile.hasCompletedGuidedAction = true
        profile.primaryGoal = .trackCycles
        profile.pcosExperience = .experienced
        profile.symptomFocusAreas = [.moodEnergy, .skinHair]
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
        #expect(profile.shouldShowHint(OnboardingProfile.hintCalendarTab))
    }
}
