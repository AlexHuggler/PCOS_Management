import SwiftUI
import SwiftData
import UniformTypeIdentifiers

/// v1 onboarding (A2–A7): welcome, where you are, what to watch, an inline first check-in, what
/// unlocks next with a reminder opt-in, then optional Apple Health. Every step after the welcome can
/// be skipped; progress and answers persist on the device. "Restore from backup" (B3) imports a
/// JSON backup and goes straight to Today.
struct OnboardingContainerView: View {
    let onComplete: () -> Void
    @Environment(AppState.self) private var appState
    @Environment(\.modelContext) private var modelContext
    @State private var stage = CompanionOnboardingStage.resume()
    @State private var experience: PCOSExperience?
    @State private var topics: [OnboardingFocusTopic] = OnboardingFocusTopic.stored()
    @State private var name = ""
    @State private var checkIn = QuickCheckInInput()
    @State private var savedFirstCheckIn = false
    @State private var checkInDays = 0
    @State private var reminderTime = Date()
    @State private var notificationManager = NotificationManager()
    @State private var isRequestingReminder = false
    @State private var healthChoices = OnboardingHealthChoice.defaultSelection(for: OnboardingFocusTopic.stored())
    @State private var isConnectingHealth = false
    @State private var showingBackupImporter = false
    @State private var alertMessage: String?
    @State private var didLoadAnswers = false

    private var pinnedSymptoms: [SymptomType] {
        OnboardingPersonalizationPlan.make(topics: topics, experience: experience).pinnedSymptoms
    }

    var body: some View {
        VStack(spacing: 0) {
            if stage != .welcome {
                topBar
            }
            ScrollView {
                stageContent
                    .frame(maxWidth: 640, alignment: .leading)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .padding(.horizontal, AppTheme.spacing24)
                    .padding(.top, stage == .welcome ? AppTheme.spacing32 : AppTheme.spacing8)
                    .padding(.bottom, AppTheme.spacing24)
            }
            .scrollDismissesKeyboard(.interactively)
            .safeAreaInset(edge: .bottom, spacing: 0) {
                bottomActions
                    .frame(maxWidth: 640)
                    .padding(.horizontal, AppTheme.spacing24)
                    .padding(.top, AppTheme.spacing12)
                    .padding(.bottom, AppTheme.spacing8)
                    .background(AppTheme.groupedBackground)
            }
        }
        .background(AppTheme.groupedBackground.ignoresSafeArea())
        .accessibilityElement(children: .contain)
        .accessibilityIdentifier("onboarding.companion.\(stage.rawValue)")
        .onAppear(perform: loadAnswersIfNeeded)
        .task(id: stage) { trackStepViewed() }
        .onChange(of: stage) { _, value in appState.onboardingProfile.currentPhaseRaw = value.persistedPhase }
        .fileImporter(isPresented: $showingBackupImporter, allowedContentTypes: [UTType.json], allowsMultipleSelection: false) { result in
            handleBackupSelection(result)
        }
        .alert(
            L10n.string("Something went wrong", defaultValue: "Something went wrong"),
            isPresented: Binding(get: { alertMessage != nil }, set: { if !$0 { alertMessage = nil } })
        ) {
            Button(L10n.string("OK", defaultValue: "OK"), role: .cancel) {}
        } message: {
            Text(alertMessage ?? "")
        }
    }

    // MARK: Chrome

    private var topBar: some View {
        HStack(spacing: AppTheme.spacing8) {
            Button {
                stage = CompanionOnboardingStage(rawValue: stage.rawValue - 1) ?? .welcome
            } label: {
                Image(systemName: "chevron.left")
                    .appFont(.headline, weight: .semibold)
                    .foregroundStyle(AppTheme.accentColor)
                    .frame(width: 44, height: 44)
                    .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .accessibilityLabel(L10n.string("Back", defaultValue: "Back"))
            .accessibilityIdentifier("onboarding.back")

            Spacer(minLength: 0)
            OnboardingProgressSegments(current: stage.progressIndex ?? 0, total: CompanionOnboardingStage.progressSegments)
            Spacer(minLength: 0)

            Button(action: skipCurrentStep) {
                Text(L10n.string("Skip", defaultValue: "Skip"))
                    .appFont(.subheadline)
                    .foregroundStyle(AppTheme.secondaryText)
                    .frame(minWidth: 44, minHeight: 44)
                    .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .accessibilityIdentifier(stage == .health ? "onboarding.finish" : "onboarding.skip")
        }
        .padding(.horizontal, AppTheme.spacing12)
    }

    @ViewBuilder
    private var stageContent: some View {
        switch stage {
        case .welcome:
            OnboardingWelcomeStep()
        case .stage:
            OnboardingStageStep(selection: $experience)
        case .focus:
            OnboardingFocusStep(topics: $topics, name: $name)
        case .checkIn:
            OnboardingFirstCheckInStep(input: $checkIn, symptoms: pinnedSymptoms)
        case .unlocks:
            OnboardingUnlocksStep(
                savedFirstCheckIn: savedFirstCheckIn,
                checkInDays: checkInDays,
                reminderTime: $reminderTime
            )
        case .health:
            OnboardingHealthStep(choices: $healthChoices, isHealthAvailable: HealthKitManager.shared.isAvailable)
        }
    }

    @ViewBuilder
    private var bottomActions: some View {
        VStack(spacing: AppTheme.spacing4) {
            switch stage {
            case .welcome:
                JourneyPrimaryButton(title: L10n.string("Get started", defaultValue: "Get started"), accessibilityIdentifier: "onboarding.get_started") {
                    completeStep(skipped: false)
                }
                Button {
                    showingBackupImporter = true
                } label: {
                    Text(L10n.string("Restore from backup", defaultValue: "Restore from backup"))
                        .appFont(.subheadline, weight: .semibold)
                        .foregroundStyle(AppTheme.accentColor)
                        .frame(maxWidth: .infinity, minHeight: 44)
                        .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
                .accessibilityIdentifier("onboarding.import_backup")
            case .stage, .focus:
                JourneyPrimaryButton(title: L10n.string("Continue", defaultValue: "Continue"), accessibilityIdentifier: "onboarding.continue") {
                    completeStep(skipped: false)
                }
            case .checkIn:
                JourneyPrimaryButton(title: L10n.string("Save today's check-in", defaultValue: "Save today's check-in"), accessibilityIdentifier: "onboarding.checkin.save") {
                    saveFirstCheckIn()
                }
                .disabled(checkIn.isEmpty)
                .opacity(checkIn.isEmpty ? 0.6 : 1)
                JourneySecondaryButton(title: L10n.string("Do this later", defaultValue: "Do this later"), accessibilityIdentifier: "onboarding.checkin.later") {
                    skipCurrentStep()
                }
            case .unlocks:
                JourneyPrimaryButton(
                    title: L10n.string("Turn on reminder", defaultValue: "Turn on reminder"),
                    isProcessing: isRequestingReminder,
                    accessibilityIdentifier: "onboarding.reminder.enable"
                ) {
                    enableReminder()
                }
                JourneySecondaryButton(title: L10n.string("Not now", defaultValue: "Not now"), accessibilityIdentifier: "onboarding.reminder.not_now") {
                    AppAnalytics.shared.track(.notificationPermission(granted: false))
                    skipCurrentStep()
                }
            case .health:
                if HealthKitManager.shared.isAvailable {
                    JourneyPrimaryButton(
                        title: L10n.string("Connect Apple Health", defaultValue: "Connect Apple Health"),
                        isProcessing: isConnectingHealth,
                        accessibilityIdentifier: "onboarding.health.connect"
                    ) {
                        connectHealth()
                    }
                } else {
                    JourneyPrimaryButton(title: L10n.string("Continue", defaultValue: "Continue"), accessibilityIdentifier: "onboarding.health.continue") {
                        finish(restoredFromBackup: false)
                    }
                }
            }
        }
    }

    // MARK: Flow

    private func loadAnswersIfNeeded() {
        guard !didLoadAnswers else { return }
        didLoadAnswers = true
        let profile = appState.onboardingProfile
        experience = profile.pcosExperience
        name = profile.preferredName
        reminderTime = notificationManager.symptomReminderTime
        checkInDays = CheckInProgress.checkInDayCount(modelContext: modelContext)
        if let loaded = try? QuickCheckInService(modelContext: modelContext).load(), !loaded.isEmpty {
            checkIn = loaded
            savedFirstCheckIn = true
        }
        OnboardingTiming.markStarted()
        AppAnalytics.shared.trackOnce(.onboardingStarted, onceKey: "onboarding_started")
    }

    private func trackStepViewed() {
        AppAnalytics.shared.track(.onboardingStepViewed(stepID: stage.stepID, index: stage.rawValue))
    }

    private func completeStep(skipped: Bool) {
        let profile = appState.onboardingProfile
        switch stage {
        case .welcome:
            profile.hasCompletedWelcome = true
        case .stage:
            profile.pcosExperience = skipped ? profile.pcosExperience : experience
            AppAnalytics.shared.track(.onboardingStage(answered: !skipped && experience != nil))
        case .focus:
            if !skipped {
                profile.preferredName = name
                OnboardingFocusTopic.store(topics)
                AppAnalytics.shared.track(.onboardingFocus(areaCount: topics.count))
            }
            let appliedTopics = skipped ? OnboardingFocusTopic.stored() : topics
            OnboardingPersonalizationPlan.make(topics: appliedTopics, experience: profile.pcosExperience)
                .apply(to: TrackingPreferences.shared, profile: profile, topics: appliedTopics)
            healthChoices = OnboardingHealthChoice.defaultSelection(for: appliedTopics)
            profile.hasCompletedQuestionnaire = true
        case .checkIn, .unlocks, .health:
            break
        }
        AppAnalytics.shared.track(.onboardingStepCompleted(stepID: stage.stepID, skipped: skipped))
        advance()
    }

    private func skipCurrentStep() {
        if stage == .health {
            AppAnalytics.shared.track(.onboardingStepCompleted(stepID: stage.stepID, skipped: true))
            AppAnalytics.shared.track(.healthConnected(categoryCount: 0, completed: false))
            finish(restoredFromBackup: false)
        } else {
            completeStep(skipped: true)
        }
    }

    private func advance() {
        guard let next = stage.next else {
            finish(restoredFromBackup: false)
            return
        }
        stage = next
    }

    private func saveFirstCheckIn() {
        guard !checkIn.isEmpty else { return }
        do {
            try QuickCheckInService(modelContext: modelContext).save(checkIn)
            savedFirstCheckIn = true
            checkInDays = max(1, CheckInProgress.checkInDayCount(modelContext: modelContext))
            appState.onboardingProfile.hasCompletedGuidedAction = true
            CheckInAnalytics.recordSave(source: .onboarding)
            completeStep(skipped: false)
        } catch {
            alertMessage = L10n.string(
                "Your check-in was not saved. Please check your entries and try again.",
                defaultValue: "Your check-in was not saved. Please check your entries and try again."
            )
        }
    }

    private func enableReminder() {
        isRequestingReminder = true
        Task {
            await notificationManager.requestAuthorization()
            let granted = notificationManager.isAuthorized
            AppAnalytics.shared.track(.notificationPermission(granted: granted))
            if granted {
                notificationManager.symptomReminderTime = reminderTime
                notificationManager.symptomRemindersEnabled = true
            }
            isRequestingReminder = false
            completeStep(skipped: false)
        }
    }

    private func connectHealth() {
        let categories = OnboardingHealthChoice.categories(for: healthChoices)
        guard !categories.isEmpty else {
            AppAnalytics.shared.track(.healthConnected(categoryCount: 0, completed: false))
            finish(restoredFromBackup: false)
            return
        }
        isConnectingHealth = true
        let manager = HealthKitManager.shared
        for category in HealthKitDataTypeDescriptor.Category.allCases {
            manager.setCategory(category, enabled: categories.contains(category))
        }
        let container = modelContext.container
        Task {
            var completed = false
            do {
                try await manager.requestAuthorization(categories: categories)
                completed = true
            } catch {
                manager.lastError = error.localizedDescription
            }
            AppAnalytics.shared.track(.healthConnected(categoryCount: categories.count, completed: completed))
            AppAnalytics.shared.track(.onboardingStepCompleted(stepID: CompanionOnboardingStage.health.stepID, skipped: false))
            isConnectingHealth = false
            if completed {
                manager.startObserving(modelContainer: container)
                Task { await manager.performFullSync(modelContext: ModelContext(container)) }
            }
            finish(restoredFromBackup: false)
        }
    }

    private func handleBackupSelection(_ result: Result<[URL], Error>) {
        switch result {
        case .success(let urls):
            guard let url = urls.first else { return }
            let didAccess = url.startAccessingSecurityScopedResource()
            defer { if didAccess { url.stopAccessingSecurityScopedResource() } }
            do {
                let summary = try SettingsDataImportService(modelContext: modelContext).importJSONBackup(from: url)
                if summary.changeCounts.successful > 0 || !summary.hasIssues {
                    finish(restoredFromBackup: true)
                } else {
                    alertMessage = L10n.string(
                        "No records were imported because the backup could not be validated.",
                        defaultValue: "No records were imported because the backup could not be validated."
                    )
                }
            } catch {
                alertMessage = (error as? LocalizedError)?.errorDescription ?? L10n.string(
                    "No records were imported because the backup could not be validated.",
                    defaultValue: "No records were imported because the backup could not be validated."
                )
            }
        case .failure(let error):
            alertMessage = error.localizedDescription
        }
    }

    private func finish(restoredFromBackup: Bool) {
        AppAnalytics.shared.track(.onboardingCompleted(
            durationSeconds: OnboardingTiming.durationSeconds(),
            restoredFromBackup: restoredFromBackup
        ))
        let profile = appState.onboardingProfile
        profile.currentPhaseRaw = nil
        profile.hasCompletedWelcome = true
        appState.selectTab(.today)
        appState.hasCompletedOnboarding = true
        onComplete()
    }
}

// MARK: - Onboarding Phase

/// Raw values are persisted under "onboarding.currentPhaseRaw" and match the
/// canonical `-onboarding.startPhase` launch-argument spellings — keep them stable.
private enum OnboardingPhase: String, CaseIterable {
    case welcomeLanguage = "welcome_language"
    case theme = "theme"
    case name = "name"
    case quiz = "quiz"
    case results = "results"
    case howAppHelps = "how_app_helps"
    case permissions = "permissions"
    case healthContext = "health_context"
    case mealScanDemo = "meal_scan_demo"
    case yourPlan = "your_plan"
    case firstLog = "first_log"
    case socialProof = "social_proof"
    case allSet = "all_set"

    init?(launchArgumentValue: String) {
        switch launchArgumentValue {
        case "welcome", "language", "welcome_language":
            self = .welcomeLanguage
        case "theme", "theme_choice":
            self = .theme
        case "name", "personalize":
            self = .name
        case "quiz":
            self = .quiz
        case "results":
            self = .results
        case "how_app_helps":
            self = .howAppHelps
        case "aha", "health_context":
            self = .healthContext
        case "meal_scan_demo":
            self = .mealScanDemo
        case "social_proof":
            self = .socialProof
        case "your_plan":
            self = .yourPlan
        case "first_log", "guided_action":
            self = .firstLog
        case "permissions":
            self = .permissions
        case "all_set", "completion":
            self = .allSet
        default:
            return nil
        }
    }
}

private struct OnboardingLanguageWelcomeView: View {
    @Binding var selectedLanguage: AppLanguage
    let onContinue: () -> Void

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: AppTheme.spacing24) {
                onboardingHero(
                    systemImage: "globe",
                    title: L10n.string("Welcome to CycleBalance. We're glad you're here.", defaultValue: "Welcome to CycleBalance. We're glad you're here."),
                    subtitle: L10n.string(
                        "Choose the language you want CycleBalance to use. We'll switch right away and keep guiding you from there.",
                        defaultValue: "Choose the language you want CycleBalance to use. We'll switch right away and keep guiding you from there."
                    )
                )

                VStack(spacing: AppTheme.spacing8) {
                    Text(L10n.string("Which language would you like to use?", defaultValue: "Which language would you like to use?"))
                        .appFont(.subheadline, weight: .semibold)
                        .foregroundStyle(AppTheme.primaryText)
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .padding(.bottom, AppTheme.spacing4)

                    ForEach(AppLanguage.allCases) { language in
                        Button {
                            selectedLanguage = language
                        } label: {
                            HStack(spacing: AppTheme.spacing12) {
                                Text(language.displayName)
                                    .appFont(.body, weight: selectedLanguage == language ? .semibold : .regular)
                                    .foregroundStyle(AppTheme.primaryText)
                                    .lineLimit(1)
                                    .minimumScaleFactor(0.82)
                                Spacer(minLength: AppTheme.spacing12)
                                Image(systemName: selectedLanguage == language ? "checkmark.circle.fill" : "circle")
                                    .foregroundStyle(selectedLanguage == language ? AppTheme.accentColor : AppTheme.secondaryText.opacity(0.58))
                            }
                            .padding(AppTheme.spacing16)
                            .background(onboardingCardFill(isSelected: selectedLanguage == language))
                            .overlay(onboardingCardStroke(isSelected: selectedLanguage == language))
                        }
                        .buttonStyle(.plain)
                        .accessibilityIdentifier("onboarding.language.option.\(language.rawValue)")
                    }
                }
            }
            .padding(AppTheme.spacing24)
            .padding(.bottom, 108)
        }
        .safeAreaInset(edge: .bottom) {
            OnboardingPrimaryButton(
                title: L10n.string("Continue", defaultValue: "Continue"),
                accessibilityIdentifier: "onboarding.welcome.primary",
                action: onContinue
            )
        }
        .background(BotanicalScreenBackground(style: .dense))
        .accessibilityIdentifier("screen.onboarding.welcome_language")
    }
}

private struct OnboardingThemeSelectionView: View {
    let appearancePreferences: AppearancePreferences
    let onContinue: () -> Void

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: AppTheme.spacing24) {
                onboardingHero(
                    systemImage: "paintpalette.fill",
                    title: L10n.string("Background, theme, and font", defaultValue: "Background, theme, and font"),
                    subtitle: L10n.string(
                        "Choose the visual style that makes CycleBalance feel like your own tracker.",
                        defaultValue: "Choose the visual style that makes CycleBalance feel like your own tracker."
                    )
                )

                VStack(alignment: .leading, spacing: AppTheme.spacing16) {
                    personalizationSectionTitle(
                        L10n.string("Background and theme", defaultValue: "Background and theme")
                    )

                    VStack(spacing: AppTheme.spacing12) {
                        ForEach(appearancePreferences.availableThemeOptions) { theme in
                            Button {
                                appearancePreferences.setThemeOption(theme)
                            } label: {
                                HStack(spacing: AppTheme.spacing12) {
                                    themeSwatches(for: theme)

                                    VStack(alignment: .leading, spacing: AppTheme.spacing4) {
                                        Text(theme.displayName)
                                            .appFont(.body, weight: .semibold)
                                            .foregroundStyle(AppTheme.primaryText)
                                        Text(theme.onboardingDescription)
                                            .appFont(.caption)
                                            .foregroundStyle(AppTheme.secondaryText)
                                            .fixedSize(horizontal: false, vertical: true)
                                    }

                                    Spacer(minLength: 0)

                                    selectionIcon(isSelected: appearancePreferences.themeOption == theme)
                                }
                                .padding(AppTheme.spacing16)
                                .background(onboardingCardFill(isSelected: appearancePreferences.themeOption == theme))
                                .overlay(onboardingCardStroke(isSelected: appearancePreferences.themeOption == theme))
                            }
                            .buttonStyle(.plain)
                            .accessibilityIdentifier("onboarding.theme.option.\(theme.rawValue)")
                        }
                    }
                }

                VStack(alignment: .leading, spacing: AppTheme.spacing16) {
                    personalizationSectionTitle(
                        L10n.string("Font", defaultValue: "Font")
                    )

                    VStack(spacing: AppTheme.spacing8) {
                        ForEach(FontOption.allCases) { font in
                            Button {
                                appearancePreferences.setFontOption(font)
                            } label: {
                                HStack(spacing: AppTheme.spacing12) {
                                    VStack(alignment: .leading, spacing: AppTheme.spacing4) {
                                        Text(font.displayName)
                                            .appFont(.body, weight: .semibold)
                                            .foregroundStyle(AppTheme.primaryText)
                                        Text(font.onboardingDescription)
                                            .appFont(.caption)
                                            .foregroundStyle(AppTheme.secondaryText)
                                            .fixedSize(horizontal: false, vertical: true)
                                    }

                                    Spacer(minLength: 0)

                                    selectionIcon(isSelected: appearancePreferences.fontOption == font)
                                }
                                .padding(AppTheme.spacing16)
                                .background(onboardingCardFill(isSelected: appearancePreferences.fontOption == font))
                                .overlay(onboardingCardStroke(isSelected: appearancePreferences.fontOption == font))
                            }
                            .buttonStyle(.plain)
                            .accessibilityIdentifier("onboarding.font.option.\(font.rawValue)")
                        }
                    }
                }
            }
            .padding(AppTheme.spacing24)
            .padding(.bottom, 108)
        }
        .safeAreaInset(edge: .bottom) {
            OnboardingPrimaryButton(
                title: L10n.string("Continue", defaultValue: "Continue"),
                accessibilityIdentifier: "onboarding.theme.continue",
                action: onContinue
            )
        }
        .background(BotanicalScreenBackground(style: .dense))
        .accessibilityIdentifier("screen.onboarding.theme")
    }

    private func personalizationSectionTitle(_ title: String) -> some View {
        Text(title)
            .appFont(.subheadline, weight: .semibold)
            .foregroundStyle(AppTheme.primaryText)
            .frame(maxWidth: .infinity, alignment: .leading)
    }

    private func selectionIcon(isSelected: Bool) -> some View {
        Image(systemName: isSelected ? "checkmark.circle.fill" : "circle")
            .foregroundStyle(isSelected ? AppTheme.accentColor : AppTheme.secondaryText.opacity(0.58))
            .accessibilityHidden(true)
    }

    private func themeSwatches(for theme: ThemeOption) -> some View {
        HStack(spacing: -7) {
            Circle().fill(theme.palette.accent.color)
            Circle().fill(theme.palette.sage.color)
            Circle().fill(theme.palette.coral.color)
        }
        .frame(width: 52, height: 30)
        .padding(.horizontal, AppTheme.spacing4)
        .accessibilityHidden(true)
    }
}

private struct OnboardingNameCaptureView: View {
    let profile: OnboardingProfile
    let onContinue: () -> Void
    let onSkip: () -> Void

    @State private var nameText: String
    @FocusState private var isNameFieldFocused: Bool

    init(profile: OnboardingProfile, onContinue: @escaping () -> Void, onSkip: @escaping () -> Void) {
        self.profile = profile
        self.onContinue = onContinue
        self.onSkip = onSkip
        _nameText = State(initialValue: profile.preferredName)
    }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: AppTheme.spacing24) {
                onboardingHero(
                    systemImage: "person.crop.circle.badge.checkmark",
                    title: L10n.string("Make it feel like yours", defaultValue: "Make it feel like yours"),
                    subtitle: L10n.string(
                        "Add a first name or nickname so daily check-ins can greet you with a little more care.",
                        defaultValue: "Add a first name or nickname so daily check-ins can greet you with a little more care."
                    )
                )

                VStack(alignment: .leading, spacing: AppTheme.spacing8) {
                    Text(L10n.string("Preferred name", defaultValue: "Preferred name"))
                        .appFont(.caption, weight: .semibold)
                        .foregroundStyle(AppTheme.secondaryText)

                    TextField(L10n.string("First name or nickname", defaultValue: "First name or nickname"), text: $nameText)
                        .textContentType(.givenName)
                        .submitLabel(.continue)
                        .focused($isNameFieldFocused)
                        .appFont(.body)
                        .foregroundStyle(AppTheme.primaryText)
                        .padding(AppTheme.spacing16)
                        .background(onboardingCardFill(isSelected: isNameFieldFocused))
                        .overlay(onboardingCardStroke(isSelected: isNameFieldFocused))
                        .onSubmit { saveAndContinue() }
                        .accessibilityIdentifier("onboarding.name.field")
                }

                HStack(spacing: AppTheme.spacing12) {
                    Image(systemName: "lock.shield")
                        .foregroundStyle(AppTheme.accentColor)
                        .accessibilityHidden(true)
                    Text(L10n.string(
                        "This stays on your device and is only used to personalize the experience.",
                        defaultValue: "This stays on your device and is only used to personalize the experience."
                    ))
                    .appFont(.caption)
                    .foregroundStyle(AppTheme.secondaryText)
                }
                .padding(AppTheme.spacing16)
                .background(onboardingCardFill(isSelected: false))
                .overlay(onboardingCardStroke(isSelected: false))
            }
            .padding(AppTheme.spacing24)
            .padding(.bottom, 108)
        }
        .scrollDismissesKeyboard(.interactively)
        .safeAreaInset(edge: .bottom) {
            VStack(spacing: AppTheme.spacing12) {
                Button {
                    saveAndContinue()
                } label: {
                    onboardingPrimaryButtonLabel(title: L10n.string("Continue", defaultValue: "Continue"))
                }
                .buttonStyle(.plain)
                .accessibilityIdentifier("onboarding.name.continue")

                Button {
                    profile.preferredName = ""
                    onSkip()
                } label: {
                    Text(L10n.string("Skip for now", defaultValue: "Skip for now"))
                        .appFont(.subheadline)
                        .foregroundStyle(AppTheme.secondaryText)
                }
                .accessibilityIdentifier("onboarding.name.skip")
            }
            .padding(.horizontal, AppTheme.spacing24)
            .padding(.top, AppTheme.spacing12)
            .padding(.bottom, AppTheme.spacing24)
            .background(.ultraThinMaterial)
        }
        .background(BotanicalScreenBackground(style: .dense))
        .accessibilityIdentifier("screen.onboarding.name")
        .onAppear {
            isNameFieldFocused = true
        }
    }

    private func saveAndContinue() {
        profile.preferredName = nameText
        onContinue()
    }
}

private struct OnboardingPrimaryButton: View {
    let title: String
    let accessibilityIdentifier: String
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            onboardingPrimaryButtonLabel(title: title)
        }
        .buttonStyle(.plain)
        .accessibilityIdentifier(accessibilityIdentifier)
        .padding(.horizontal, AppTheme.spacing24)
        .padding(.top, AppTheme.spacing12)
        .padding(.bottom, AppTheme.spacing24)
        .background(.ultraThinMaterial)
    }
}

private func onboardingHero(systemImage: String, title: String, subtitle: String) -> some View {
    VStack(alignment: .leading, spacing: AppTheme.spacing16) {
        ZStack {
            Circle()
                .fill(AppTheme.usesPremiumEditorStyling ? AnyShapeStyle(AppTheme.premiumEditorAccentGradient) : AnyShapeStyle(AppTheme.accentColor.opacity(0.14)))
            Image(systemName: systemImage)
                .appFont(.title2, weight: .semibold)
                .foregroundStyle(AppTheme.usesPremiumEditorStyling ? AppTheme.premiumEditorCTAForeground : AppTheme.accentColor)
        }
        .frame(width: 58, height: 58)
        .shadow(color: AppTheme.cardShadowColor, radius: AppTheme.usesPremiumEditorStyling ? 18 : 10, y: 8)
        .accessibilityHidden(true)

        VStack(alignment: .leading, spacing: AppTheme.spacing8) {
            Text(title)
                .appHeadingFont(.largeTitle, weight: .regular)
                .foregroundStyle(AppTheme.primaryText)
                .fixedSize(horizontal: false, vertical: true)

            Text(subtitle)
                .appFont(.body)
                .foregroundStyle(AppTheme.secondaryText)
                .fixedSize(horizontal: false, vertical: true)
        }
    }
}

private func onboardingPrimaryButtonLabel(title: String) -> some View {
    Text(title)
        .appFont(.headline, weight: .semibold)
        .frame(maxWidth: .infinity)
        .padding(.vertical, AppTheme.spacing12)
        .background(
            RoundedRectangle(cornerRadius: AppTheme.cornerRadiusLarge, style: .continuous)
                .fill(AppTheme.usesPremiumEditorStyling ? AnyShapeStyle(AppTheme.premiumEditorAccentGradient) : AnyShapeStyle(AppTheme.accentColor))
        )
        .foregroundStyle(AppTheme.usesPremiumEditorStyling ? AppTheme.premiumEditorCTAForeground : .white)
        .shadow(color: AppTheme.cardShadowColor, radius: AppTheme.usesPremiumEditorStyling ? 18 : 8, y: 8)
}

private func onboardingCardFill(isSelected: Bool) -> some ShapeStyle {
    if AppTheme.usesPremiumEditorStyling {
        return AnyShapeStyle(
            LinearGradient(
                colors: [
                    AppTheme.premiumEditorRaisedSurface.opacity(isSelected ? 0.98 : 0.82),
                    AppTheme.premiumEditorSurface.opacity(isSelected ? 0.92 : 0.72),
                ],
                startPoint: .topLeading,
                endPoint: .bottomTrailing
            )
        )
    }

    return AnyShapeStyle(
        isSelected
            ? AppTheme.accentColor.opacity(AppTheme.opacitySubtle)
            : AppTheme.cardBackground
    )
}

private func onboardingCardStroke(isSelected: Bool) -> some View {
    RoundedRectangle(cornerRadius: AppTheme.defaultCardCornerRadius, style: .continuous)
        .stroke(
            AppTheme.usesPremiumEditorStyling && isSelected
                ? AnyShapeStyle(AppTheme.premiumEditorBorderGradient)
                : AnyShapeStyle((isSelected ? AppTheme.accentColor.opacity(0.42) : AppTheme.cardBorder)),
            lineWidth: AppTheme.usesPremiumEditorStyling || AppTheme.isBotanicalJournal ? 0.9 : 1.2
        )
}

private extension ThemeOption {
    var onboardingDescription: String {
        switch self {
        case .calm: L10n.string("Clear surfaces and quiet colors for everyday care.", defaultValue: "Clear surfaces and quiet colors for everyday care.")
        case .botanicalJournal:
            L10n.string("Warm, editorial, and softly botanical.", defaultValue: "Warm, editorial, and softly botanical.")
        case .lunarCalm:
            L10n.string("True-dark, glassy, and moonlit.", defaultValue: "True-dark, glassy, and moonlit.")
        case .sage:
            L10n.string("Clean, grounded, and quietly clinical.", defaultValue: "Clean, grounded, and quietly clinical.")
        case .sunrise:
            L10n.string("Warm clay tones with a steady morning feel.", defaultValue: "Warm clay tones with a steady morning feel.")
        case .ocean:
            L10n.string("Cool, clear, and data-forward.", defaultValue: "Cool, clear, and data-forward.")
        case .botanicalMist:
            L10n.string("Soft wellness color with refined contrast.", defaultValue: "Soft wellness color with refined contrast.")
        case .blushMoonrise:
            L10n.string("Bright, polished, and gently expressive.", defaultValue: "Bright, polished, and gently expressive.")
        case .fruitGrove:
            L10n.string("Fresh, energetic, and approachable.", defaultValue: "Fresh, energetic, and approachable.")
        case .highContrast:
            L10n.string("Maximum clarity with stronger separation.", defaultValue: "Maximum clarity with stronger separation.")
        }
    }
}

private extension FontOption {
    var onboardingDescription: String {
        switch self {
        case .systemDefault:
            L10n.string("Clean and familiar for everyday tracking.", defaultValue: "Clean and familiar for everyday tracking.")
        case .rounded:
            L10n.string("Soft, friendly, and easy to scan.", defaultValue: "Soft, friendly, and easy to scan.")
        case .didot:
            L10n.string("Editorial with high-contrast headings.", defaultValue: "Editorial with high-contrast headings.")
        case .newYork:
            L10n.string("Polished serif warmth with system clarity.", defaultValue: "Polished serif warmth with system clarity.")
        case .cormorantGaramond:
            L10n.string("Gentle journal-style display type.", defaultValue: "Gentle journal-style display type.")
        case .sfMono:
            L10n.string("Precise, structured, and data-forward.", defaultValue: "Precise, structured, and data-forward.")
        case .baskerville:
            L10n.string("Classic serif with a calm reading rhythm.", defaultValue: "Classic serif with a calm reading rhythm.")
        }
    }
}

#Preview {
    OnboardingContainerView(onComplete: {})
        .environment(AppState())
        .environment(AppearancePreferences.shared)
        .modelContainer(for: [
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
            NutritionImportRecord.self,
            HealthKitImportedSampleRecord.self,
            HairPhotoEntry.self,
            DailyLog.self,
            PregnancyRecord.self,
        ], inMemory: true)
}
