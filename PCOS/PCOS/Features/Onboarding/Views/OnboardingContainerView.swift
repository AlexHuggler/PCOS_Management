import SwiftUI

/// Four optional steps; progress and selections persist on the device.
struct OnboardingContainerView: View {
    let onComplete: () -> Void
    @Environment(AppState.self) private var appState
    @State private var stage = CompanionOnboardingStage.resume()
    @State private var showingHealth = false
    @State private var showingCheckIn = false

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: AppTheme.spacing24) {
                    Text(L10n.format("Step %lld of 4", defaultValue: "Step %lld of 4", stage.rawValue + 1))
                        .appFont(.caption).foregroundStyle(.secondary)
                    ProgressView(value: Double(stage.rawValue + 1), total: 4)
                        .tint(AppTheme.accentColor)
                    stageContent
                }
                .padding(AppTheme.spacing24)
                .frame(maxWidth: 640)
                .frame(maxWidth: .infinity)
            }
            .background(BotanicalScreenBackground(style: .quiet))
            .navigationTitle(L10n.string("Welcome", defaultValue: "Welcome"))
            .toolbarColorScheme(AppTheme.preferredColorScheme, for: .navigationBar)
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarLeading) {
                    if stage != .welcome {
                        Button(L10n.string("Back", defaultValue: "Back")) {
                            stage = CompanionOnboardingStage(rawValue: stage.rawValue - 1) ?? .welcome
                        }
                        .accessibilityIdentifier("onboarding.back")
                    }
                }
            }
            .sheet(isPresented: $showingHealth) {
                NavigationStack {
                    HealthKitSettingsView()
                        .toolbar { ToolbarItem(placement: .confirmationAction) { Button(L10n.string("Done", defaultValue: "Done")) { showingHealth = false } } }
                }
            }
            .sheet(isPresented: $showingCheckIn) { SymptomLogView() }
            .onChange(of: stage) { _, value in appState.onboardingProfile.currentPhaseRaw = "companion_\(value.rawValue)" }
            .accessibilityIdentifier("onboarding.companion.\(stage.rawValue)")
        }
    }

    @ViewBuilder
    private var stageContent: some View {
        switch stage {
        case .welcome:
            heading("A little support for your everyday", "Make room for what matters to you. Track a little, notice patterns, and build your own routine.", symbol: "leaf")
            Label(L10n.string("Your health records stay on your device. Apple Health is optional, and you choose what to share.", defaultValue: "Your health records stay on your device. Apple Health is optional, and you choose what to share."), systemImage: "lock.shield")
                .appFont(.subheadline)
            Text(L10n.string("Tracking can help you prepare for a conversation with your care team. It does not diagnose PCOS.", defaultValue: "Tracking can help you prepare for a conversation with your care team. It does not diagnose PCOS."))
                .appFont(.caption).foregroundStyle(.secondary)
            Picker(L10n.string("Language", defaultValue: "Language"), selection: Binding(get: { appState.selectedAppLanguage }, set: { appState.selectedAppLanguage = $0 })) {
                ForEach(AppLanguage.allCases) { language in Text(language.displayName).tag(language) }
            }
            primary("Make it yours") { appState.onboardingProfile.hasCompletedWelcome = true; advance() }
            Button(L10n.string("Explore Today", defaultValue: "Explore Today"), action: finish)
                .accessibilityIdentifier("onboarding.explore")
        case .preferences:
            heading("What would you like support with?", "Choose anything that feels useful. You can change or skip every choice.", symbol: "slider.horizontal.3")
            CompanionProfileFields(profile: appState.onboardingProfile)
            primary("Continue") { appState.onboardingProfile.hasCompletedQuestionnaire = true; advance() }
            Button(L10n.string("Skip for now", defaultValue: "Skip for now"), action: advance)
        case .health:
            heading("Let Apple Health help, if you like", "Bring in supported records from Apple Health. You can review data types, connect later, or keep logging manually.", symbol: "heart")
            primary("Review Apple Health options") { showingHealth = true }
            Button(L10n.string("Continue", defaultValue: "Continue"), action: advance)
            Button(L10n.string("Not now", defaultValue: "Not now"), action: advance)
        case .checkIn:
            heading("Start with how you feel", "A short check-in is enough. There is no need to complete every field or track every day.", symbol: "checkmark.circle")
            primary("First check-in") { showingCheckIn = true }
            Button(L10n.string("Explore Today", defaultValue: "Explore Today"), action: finish)
                .accessibilityIdentifier("onboarding.finish")
        }
    }

    private func heading(_ title: String, _ message: String, symbol: String) -> some View {
        VStack(alignment: .leading, spacing: AppTheme.spacing16) {
            Image(systemName: symbol).font(.system(size: 42)).foregroundStyle(AppTheme.accentColor).accessibilityHidden(true)
            Text(L10n.string(title, defaultValue: title)).appFont(.title, weight: .semibold)
            Text(L10n.string(message, defaultValue: message)).appFont(.body).foregroundStyle(.secondary)
        }
    }

    private func primary(_ title: String, action: @escaping () -> Void) -> some View {
        Button(action: action) { Text(L10n.string(title, defaultValue: title)).frame(maxWidth: .infinity).padding(.vertical, AppTheme.spacing8) }
            .buttonStyle(.borderedProminent).tint(AppTheme.accentColor)
            .foregroundStyle(AppTheme.premiumEditorCTAForeground)
    }

    private func advance() { stage = CompanionOnboardingStage(rawValue: stage.rawValue + 1) ?? .checkIn }
    private func finish() {
        appState.onboardingProfile.currentPhaseRaw = nil
        appState.hasCompletedOnboarding = true
        onComplete()
    }
}

enum CompanionOnboardingStage: Int, CaseIterable {
    case welcome, preferences, health, checkIn

    static func resume(defaults: UserDefaults = .standard, arguments: [String] = ProcessInfo.processInfo.arguments) -> Self {
        var raw = defaults.string(forKey: "onboarding.currentPhaseRaw")
        if arguments.contains("UITestMode"), let index = arguments.firstIndex(of: "-onboarding.startPhase"), index + 1 < arguments.count {
            raw = arguments[index + 1]
        }
        if let raw, raw.hasPrefix("companion_"), let number = Int(raw.dropFirst(10)), let stage = Self(rawValue: number) { return stage }
        switch raw {
        case "theme", "name", "personalize", "quiz", "results", "how_app_helps": return .preferences
        case "permissions", "health_context", "aha": return .health
        case "meal_scan_demo", "your_plan", "first_log", "guided_action", "social_proof", "all_set", "completion": return .checkIn
        default: return .welcome
        }
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
