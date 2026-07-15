import SwiftData
import SwiftUI

struct OnboardingHealthContextRevealView: View {
    let profile: OnboardingProfile
    let onContinue: () -> Void
    let onSkip: () -> Void

    @Environment(\.modelContext) private var modelContext
    @State private var healthKitManager = HealthKitManager()
    @State private var moment: AhaMoment?
    @State private var isLoading = true
    @State private var selectedFocus = "energy"
    @State private var selectedSignal = "sleep"

    private var showQuizFallback: Bool {
        !isLoading && (moment?.kind == .quizStarter || moment == nil)
    }

    var body: some View {
        VStack(spacing: 0) {
            ScrollView {
                VStack(spacing: AppTheme.spacing20) {
                    header

                    if isLoading {
                        loadingCard
                    } else if let moment, !showQuizFallback {
                        insightCard(moment)
                        sourceTrustCard
                    } else {
                        quizFallback
                    }
                }
                .padding(.horizontal, AppTheme.spacing24)
                .padding(.top, AppTheme.spacing24)
                .padding(.bottom, AppTheme.spacing16)
            }

            VStack(spacing: AppTheme.spacing12) {
                Button(action: onContinue) {
                    Text(continueButtonTitle)
                        .appFont(.headline)
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, AppTheme.spacing12)
                        .background(
                            RoundedRectangle(cornerRadius: AppTheme.cornerRadiusMedium)
                                .fill(AppTheme.accentColor)
                        )
                        .foregroundStyle(.white)
                }
                .buttonStyle(.plain)
                .accessibilityIdentifier("onboarding.health_context.continue")

                Button(action: onSkip) {
                    Text(L10n.string("Skip for now", defaultValue: "Skip for now"))
                }
                .appFont(.subheadline)
                .foregroundStyle(.secondary)
                .accessibilityIdentifier("onboarding.health_context.skip")
            }
            .padding(.horizontal, AppTheme.spacing24)
            .padding(.bottom, AppTheme.spacing32)
        }
        .background(BotanicalScreenBackground(style: .dense))
        .accessibilityElement(children: .contain)
        .accessibilityIdentifier(screenAccessibilityIdentifier)
        .task {
            await loadHealthContext()
        }
    }

    private var continueButtonTitle: String {
        if MealScanFeatureFlags.current.enableMealScanV2 {
            return L10n.string("See how photo estimates work", defaultValue: "See how photo estimates work")
        }

        return L10n.string("Review your plan", defaultValue: "Review your plan")
    }

    private var screenAccessibilityIdentifier: String {
        ProcessInfo.processInfo.arguments.contains("-onboarding.startPhase")
            && ProcessInfo.processInfo.arguments.contains("aha")
            ? "screen.onboarding.aha"
            : "screen.onboarding.health_context"
    }

    private var header: some View {
        VStack(spacing: AppTheme.spacing12) {
            Image(systemName: "heart.text.square.fill")
                .appFont(.largeTitle, weight: .semibold)
                .foregroundStyle(AppTheme.accentColor)
                .accessibilityHidden(true)

            Text(L10n.string("Connect what you already track", defaultValue: "Connect what you already track"))
                .appHeadingFont(.title2, weight: .regular)
                .foregroundStyle(AppTheme.primaryText)
                .multilineTextAlignment(.center)

            Text(
                L10n.string(
                    "When Apple Health has shared data, CycleBalance can organize it with source notes so you can review where each signal came from.",
                    defaultValue: "When Apple Health has shared data, CycleBalance can organize it with source notes so you can review where each signal came from."
                )
            )
            .appFont(.body)
            .foregroundStyle(.secondary)
            .multilineTextAlignment(.center)
            .fixedSize(horizontal: false, vertical: true)
        }
    }

    private var loadingCard: some View {
        VStack(spacing: AppTheme.spacing12) {
            ProgressView()
                .tint(AppTheme.accentColor)
            Text(L10n.string("Checking Apple Health context...", defaultValue: "Checking Apple Health context..."))
                .appFont(.subheadline, weight: .semibold)
            Text(L10n.string("This stays on your device and may include data shared by apps you already use.", defaultValue: "This stays on your device and may include data shared by apps you already use."))
                .appFont(.caption)
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)
        }
        .padding(AppTheme.spacing20)
        .frame(maxWidth: .infinity)
        .background(cardBackground)
    }

    private func insightCard(_ moment: AhaMoment) -> some View {
        VStack(alignment: .leading, spacing: AppTheme.spacing12) {
            Label(L10n.string("See useful context right away", defaultValue: "See useful context right away"), systemImage: "sparkles")
                .appFont(.caption, weight: .semibold)
                .foregroundStyle(AppTheme.coralAccent)

            Text(moment.title)
                .appHeadingFont(.title3, weight: .regular)
                .foregroundStyle(AppTheme.primaryText)
                .fixedSize(horizontal: false, vertical: true)

            Text(moment.body)
                .appFont(.subheadline)
                .foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)

            Text(moment.nextAction)
                .appFont(.caption, weight: .semibold)
                .foregroundStyle(AppTheme.accentColor)
                .fixedSize(horizontal: false, vertical: true)
        }
        .padding(AppTheme.spacing20)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(cardBackground)
        .accessibilityIdentifier("onboarding.health_context.insight")
    }

    private var sourceTrustCard: some View {
        HStack(alignment: .top, spacing: AppTheme.spacing12) {
            BotanicalIconBadge(systemImage: "lock.shield.fill", color: AppTheme.sage, size: 40)
                .accessibilityHidden(true)

            VStack(alignment: .leading, spacing: AppTheme.spacing8) {
                Text(L10n.string("Source notes build trust", defaultValue: "Source notes build trust"))
                    .appFont(.subheadline, weight: .semibold)
                    .foregroundStyle(AppTheme.primaryText)

                Text(L10n.string("Actual source labels appear after sync, like \"From MyFitnessPal via Apple Health\" or \"From Oura via Apple Health,\" when that source is available.", defaultValue: "Actual source labels appear after sync, like \"From MyFitnessPal via Apple Health\" or \"From Oura via Apple Health,\" when that source is available."))
                    .appFont(.caption)
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
        .padding(AppTheme.spacing16)
        .background(cardBackground)
    }

    private var quizFallback: some View {
        VStack(alignment: .leading, spacing: AppTheme.spacing16) {
            Label(L10n.string("A quick starting point", defaultValue: "A quick starting point"), systemImage: "slider.horizontal.3")
                .appFont(.caption, weight: .semibold)
                .foregroundStyle(AppTheme.accentColor)

            Text(L10n.string("No Apple Health context was available yet. Pick two signals and CycleBalance will start your first comparison without making medical claims.", defaultValue: "No Apple Health context was available yet. Pick two signals and CycleBalance will start your first comparison without making medical claims."))
                .appFont(.subheadline)
                .foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)

            pickerGroup(
                title: L10n.string("What do you want to understand first?", defaultValue: "What do you want to understand first?"),
                selection: $selectedFocus,
                options: ["energy", "cravings", "bloating", "cycle timing"]
            )

            pickerGroup(
                title: L10n.string("Which signal changed recently?", defaultValue: "Which signal changed recently?"),
                selection: $selectedSignal,
                options: ["sleep", "meals", "stress", "movement"]
            )

            Text("Start by comparing \(selectedSignal) with \(selectedFocus). One log today gives CycleBalance a useful baseline.")
                .appFont(.caption, weight: .semibold)
                .foregroundStyle(AppTheme.primaryText)
                .fixedSize(horizontal: false, vertical: true)
        }
        .padding(AppTheme.spacing20)
        .background(cardBackground)
        .accessibilityIdentifier("onboarding.health_context.quiz_fallback")
    }

    private func pickerGroup(title: String, selection: Binding<String>, options: [String]) -> some View {
        VStack(alignment: .leading, spacing: AppTheme.spacing8) {
            Text(title)
                .appFont(.caption, weight: .semibold)
                .foregroundStyle(.secondary)

            FlowLayout(spacing: AppTheme.spacing8) {
                ForEach(options, id: \.self) { option in
                    Button {
                        selection.wrappedValue = option
                    } label: {
                        Text(option.capitalized)
                            .appFont(.caption, weight: .semibold)
                            .foregroundStyle(selection.wrappedValue == option ? .white : AppTheme.primaryText)
                            .padding(.horizontal, AppTheme.spacing12)
                            .padding(.vertical, AppTheme.spacing8)
                            .background(
                                Capsule()
                                    .fill(selection.wrappedValue == option ? AppTheme.accentColor : AppTheme.accentColor.opacity(0.12))
                            )
                    }
                    .buttonStyle(.plain)
                }
            }
        }
    }

    private var cardBackground: some View {
        RoundedRectangle(cornerRadius: AppTheme.cornerRadiusMedium)
            .fill(AppTheme.cardBackground)
            .overlay(
                RoundedRectangle(cornerRadius: AppTheme.cornerRadiusMedium)
                    .stroke(Color.primary.opacity(0.06), lineWidth: 1)
            )
    }

    @MainActor
    private func loadHealthContext() async {
        isLoading = true
        let state = await healthKitManager.refreshAuthorizationState()
        if state == .configured {
            await healthKitManager.performFullSync(modelContext: modelContext)
        }

        do {
            moment = try AhaMomentService(modelContext: modelContext).onboardingMoment(
                isPremium: false,
                profile: profile
            )
        } catch {
            moment = nil
        }
        isLoading = false
    }
}

#Preview {
    OnboardingHealthContextRevealView(profile: OnboardingProfile(), onContinue: {}, onSkip: {})
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
