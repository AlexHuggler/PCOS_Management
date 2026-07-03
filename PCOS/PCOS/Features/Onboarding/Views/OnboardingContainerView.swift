import SwiftUI

/// Root container that orchestrates the onboarding flow:
/// language -> background/theme/font -> name -> quiz -> results -> how app helps -> permissions ->
/// Health context -> optional meal estimate demo -> your plan -> first log -> social proof -> all set.
struct OnboardingContainerView: View {
    let onComplete: () -> Void

    @Environment(AppState.self) private var appState
    @Environment(AppearancePreferences.self) private var appearancePreferences
    @State private var phase: OnboardingPhase

    init(onComplete: @escaping () -> Void) {
        self.onComplete = onComplete
        _phase = State(initialValue: Self.initialPhase())
    }

    private var progress: CGFloat {
        let currentIndex = OnboardingPhase.allCases.firstIndex(of: phase) ?? 0
        let phaseCount = max(OnboardingPhase.allCases.count - 1, 1)
        let rawProgress = CGFloat(currentIndex) / CGFloat(phaseCount)
        return LayoutDimensionSanitizer.normalizedProgress(from: rawProgress)
    }

    private var showsBackButton: Bool {
        phase != .welcomeLanguage
            && phase != .allSet
            && previousPhase(before: phase) != nil
    }

    var body: some View {
        ZStack(alignment: .top) {
            phaseContent

            // Back button + continuous progress bar, layered above the
            // step content so it stays visible over full-screen backgrounds.
            HStack(spacing: AppTheme.spacing12) {
                if showsBackButton {
                    Button {
                        retreat()
                    } label: {
                        Image(systemName: "chevron.backward")
                            .appFont(.body, weight: .semibold)
                            .foregroundStyle(AppTheme.secondaryText)
                            .frame(width: 28, height: 28)
                            .contentShape(Rectangle())
                    }
                    .buttonStyle(.plain)
                    .accessibilityLabel(L10n.string("Back", defaultValue: "Back"))
                    .accessibilityIdentifier("onboarding.back")
                }

                GeometryReader { geometry in
                    ZStack(alignment: .leading) {
                        Capsule()
                            .fill(AppTheme.isBotanicalJournal ? AppTheme.lavenderAccent.opacity(0.18) : AppTheme.accentColor.opacity(AppTheme.opacityLight))
                        Capsule()
                            .fill(AppTheme.isBotanicalJournal ? AppTheme.roseAccent : AppTheme.accentColor)
                            .frame(
                                width: LayoutDimensionSanitizer.frameDimension(
                                    from: geometry.size.width * progress
                                )
                            )
                    }
                }
                .frame(height: 6)
            }
            .padding(.horizontal, AppTheme.spacing24)
            .padding(.top, AppTheme.spacing8)
            .animation(.easeInOut(duration: 0.3), value: phase)
        }
    }

    private var phaseContent: some View {
        Group {
            switch phase {
            case .welcomeLanguage:
                OnboardingLanguageWelcomeView(
                    selectedLanguage: Binding(
                        get: { appState.selectedAppLanguage },
                        set: { appState.selectedAppLanguage = $0 }
                    ),
                    onContinue: {
                        appState.onboardingProfile.hasCompletedWelcome = true
                        advance()
                    }
                )

            case .theme:
                OnboardingThemeSelectionView(
                    appearancePreferences: appearancePreferences,
                    onContinue: { advance() }
                )

            case .name:
                OnboardingNameCaptureView(
                    profile: appState.onboardingProfile,
                    onContinue: { advance() },
                    onSkip: { advance() }
                )

            case .quiz:
                QuestionnaireView(profile: appState.onboardingProfile, onContinue: { advance() }, onSkip: { advance() })

            case .results:
                ResultsView(profile: appState.onboardingProfile, onContinue: { advance() }, onSkip: { advance() })

            case .howAppHelps:
                HowAppHelpsView(profile: appState.onboardingProfile, onContinue: { advance() }, onSkip: { advance() })

            case .permissions:
                PermissionsStepView(onContinue: { advance() }, onSkip: { advance() })

            case .healthContext:
                OnboardingHealthContextRevealView(profile: appState.onboardingProfile, onContinue: { advance() }, onSkip: { advance() })

            case .mealScanDemo:
                OnboardingMealScanDemoView(onContinue: { advance() }, onSkip: { advance() })

            case .yourPlan:
                YourPlanView(profile: appState.onboardingProfile, onContinue: { advance() }, onSkip: { advance() })

            case .firstLog:
                GuidedActionView(profile: appState.onboardingProfile, onComplete: { advance() }, onSkip: { advance() })

            case .socialProof:
                SocialProofView(onContinue: { advance() })

            case .allSet:
                OnboardingCompletionView(profile: appState.onboardingProfile, onFinish: { completeOnboarding() })
            }
        }
        .simultaneousGesture(boundedOnboardingSwipeGesture)
        .onChange(of: phase) { _, newPhase in
            appState.onboardingProfile.currentPhaseRaw = newPhase.rawValue
        }
    }

    private var boundedOnboardingSwipeGesture: some Gesture {
        DragGesture(minimumDistance: 42, coordinateSpace: .local)
            .onEnded { value in
                guard phaseAllowsContainerSwipe else { return }
                let horizontalDistance = value.translation.width
                let verticalDistance = abs(value.translation.height)
                guard abs(horizontalDistance) > max(72, verticalDistance * 1.6) else {
                    return
                }

                guard horizontalDistance > 0 else { return }
                retreat()
            }
    }

    private var phaseAllowsContainerSwipe: Bool {
        switch phase {
        case .quiz, .howAppHelps:
            false
        default:
            true
        }
    }

    private func advance() {
        guard let next = nextPhase(after: phase) else {
            completeOnboarding()
            return
        }

        withAnimation(.easeInOut(duration: 0.35)) {
            phase = next
        }
    }

    private func retreat() {
        guard let previous = previousPhase(before: phase) else { return }

        withAnimation(.easeInOut(duration: 0.35)) {
            phase = previous
        }
    }

    private func nextPhase(after currentPhase: OnboardingPhase) -> OnboardingPhase? {
        guard let currentIndex = OnboardingPhase.allCases.firstIndex(of: currentPhase) else {
            return nil
        }

        var nextIndex = currentIndex + 1
        while nextIndex < OnboardingPhase.allCases.count {
            let nextCandidate = OnboardingPhase.allCases[nextIndex]
            if isPhaseAvailable(nextCandidate) {
                return nextCandidate
            }
            nextIndex += 1
        }
        return nil
    }

    private func previousPhase(before currentPhase: OnboardingPhase) -> OnboardingPhase? {
        guard let currentIndex = OnboardingPhase.allCases.firstIndex(of: currentPhase),
              currentIndex > 0
        else {
            return nil
        }

        var previousIndex = currentIndex - 1
        while previousIndex >= 0 {
            let previousCandidate = OnboardingPhase.allCases[previousIndex]
            if isPhaseAvailable(previousCandidate) {
                return previousCandidate
            }
            previousIndex -= 1
        }
        return nil
    }

    /// Phases that depend on feature flags are skipped when the flag is off.
    /// A direct `-onboarding.startPhase` launch override bypasses this check.
    private func isPhaseAvailable(_ candidatePhase: OnboardingPhase) -> Bool {
        switch candidatePhase {
        case .mealScanDemo:
            MealScanFeatureFlags.current.enableMealScanV2
        default:
            true
        }
    }

    private func completeOnboarding() {
        appState.onboardingProfile.currentPhaseRaw = nil
        withAnimation(.easeInOut(duration: 0.35)) {
            onComplete()
        }
    }

    private static func initialPhase(
        arguments: [String] = ProcessInfo.processInfo.arguments,
        defaults: UserDefaults = .standard
    ) -> OnboardingPhase {
        // UI test launch overrides always win and keep their existing behavior.
        if arguments.contains("UITestMode") {
            guard let phaseValue = launchArgumentValue(for: "onboarding.startPhase", in: arguments) else {
                return .welcomeLanguage
            }

            return OnboardingPhase(launchArgumentValue: phaseValue) ?? .welcomeLanguage
        }

        // Resume a persisted mid-flow phase only while onboarding is incomplete.
        if !defaults.bool(forKey: "onboarding.hasCompletedOnboarding"),
           let persistedRawValue = defaults.string(forKey: "onboarding.currentPhaseRaw"),
           let persistedPhase = OnboardingPhase(rawValue: persistedRawValue),
           persistedPhase != .mealScanDemo || MealScanFeatureFlags.current.enableMealScanV2 {
            return persistedPhase
        }

        return .welcomeLanguage
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
