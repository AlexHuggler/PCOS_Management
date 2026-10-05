import Charts
import SwiftUI
import SwiftData

struct InsightsView: View {
    @Environment(\.modelContext) private var modelContext
    @Environment(AppState.self) private var appState
    @Environment(ReportAccessPolicy.self) private var reportAccessPolicy
    @State private var viewModel: InsightsViewModel?
    @State private var trackingPreferences = TrackingPreferences.shared
    @State private var activeDisclosure: InsightDisclosureContent?
    @State private var showingLogPeriod = false
    @State private var showingLogSymptoms = false
    @State private var showingReportSheet = false
    @State private var topAhaMoment: AhaMoment?

    private var audiencePreferences: InsightAudiencePreferences {
        InsightAudiencePreferences(profile: appState.onboardingProfile)
    }

    private var currentLanguage: AppLanguage {
        appState.selectedAppLanguage
    }

    private var presentationPlan: InsightPresentationPlan {
        viewModel?.presentationPlan(
            preferences: audiencePreferences,
            isPremium: appState.allowsPremiumAccess
        ) ?? InsightPresentationPlan(visibleInsights: [], lockedPremiumCards: [])
    }

    private var visibleInsights: [Insight] {
        presentationPlan.visibleInsights
    }

    private var lockedPremiumCards: [PremiumInsightTeaser] {
        presentationPlan.lockedPremiumCards
    }

    private var emptyStateContent: InsightEmptyStateContent {
        viewModel?.emptyStateContent(preferences: audiencePreferences) ?? InsightEmptyStateContent(
            title: L10n.string(
                "Build your first insights",
                defaultValue: "Build your first insights",
                language: currentLanguage
            ),
            message: L10n.string(
                "Keep logging period starts and symptoms so this tab can start surfacing useful patterns.",
                defaultValue: "Keep logging period starts and symptoms so this tab can start surfacing useful patterns.",
                language: currentLanguage
            )
        )
    }

    private var insightErrorMessage: String? {
        viewModel?.errorMessage
    }

    private var shouldShowReportBanner: Bool {
        reportAccessPolicy.shouldShowInsightsBanner(completedCycles: viewModel?.completedCycleCount ?? 0)
    }

    private var completedCycleCount: Int {
        viewModel?.completedCycleCount ?? 0
    }

    var body: some View {
        NavigationStack {
            VStack(spacing: AppTheme.spacing12) {
                if let insightErrorMessage, !insightErrorMessage.isEmpty {
                    insightErrorBanner(insightErrorMessage, retryAction: retryInsights)
                }

                if !AppTheme.usesImmersiveHomeShell, let topAhaMoment {
                    AhaMomentCard(moment: topAhaMoment)
                        .padding(.horizontal, AppTheme.spacing16)
                }

                Group {
                    if viewModel?.isGenerating == true {
                        VStack(spacing: AppTheme.spacing12) {
                            ProgressView()
                            Text(viewModel?.generationProgress ?? L10n.string("Generating insights...", defaultValue: "Generating insights..."))
                                .appFont(.caption)
                                .foregroundStyle(.secondary)
                                .contentTransition(.numericText())
                        }
                        .accessibilityIdentifier("insights.loading")
                    } else {
                        insightsList
                    }
                }

            }
            .navigationTitle(AppTheme.usesImmersiveHomeShell ? "" : L10n.string("Insights", defaultValue: "Insights", language: currentLanguage))
            .toolbarColorScheme(AppTheme.preferredColorScheme, for: .navigationBar)
            .navigationBarTitleDisplayMode(AppTheme.usesImmersiveHomeShell ? .inline : .automatic)
            .accessibilityIdentifier("screen.insights")
            .lunarInsightsPresentation(isPresented: $showingLogPeriod) {
                CycleLogView()
            }
            .lunarInsightsPresentation(isPresented: $showingLogSymptoms) {
                SymptomLogView()
            }
            .lunarInsightsPresentation(isPresented: $showingReportSheet) {
                ReportConfigView()
            }
            .lunarInsightsItemPresentation(item: $activeDisclosure) { disclosure in
                EvidenceDisclosureSheet(content: disclosure, language: currentLanguage)
            }
            .sensoryFeedback(.selection, trigger: showingLogPeriod)
            .sensoryFeedback(.selection, trigger: showingLogSymptoms)
            .refreshable {
                await viewModel?.refreshInsights()
                refreshAhaMoment()
            }
            .background(BotanicalScreenBackground(style: .quiet))
            .safeAreaInset(edge: .bottom, spacing: 0) {
                VStack(spacing: 0) {
                    insightsFooter
                }
                .padding(.bottom, AppTheme.botanicalScrollableBottomPadding)
            }
            .onAppear {
                if viewModel == nil {
                    viewModel = InsightsViewModel(modelContext: modelContext)
                }
                Task {
                    await viewModel?.loadInsights()
                    refreshAhaMoment()
                }
            }
            .onReceive(NotificationCenter.default.publisher(for: InsightRefreshCoordinator.notificationName)) { _ in
                Task {
                    await viewModel?.loadInsights(forceRefresh: true)
                }
            }
        }
        .id(appState.languageRenderKey)
    }

    private func insightErrorBanner(_ message: String, retryAction: @escaping () -> Void) -> some View {
        HStack(alignment: .top, spacing: AppTheme.spacing8) {
            Image(systemName: "exclamationmark.triangle.fill")
                .foregroundStyle(.orange)
                .appFont(.caption)
                .padding(.top, 2)

            VStack(alignment: .leading, spacing: AppTheme.spacing8) {
                Text(message)
                    .appFont(.footnote)
                    .foregroundStyle(.primary)

                Button(action: retryAction) {
                    Label(
                        L10n.string("Try Again", defaultValue: "Try Again", language: currentLanguage),
                        systemImage: "arrow.clockwise"
                    )
                    .appFont(.caption, weight: .semibold)
                }
                .buttonStyle(.bordered)
                .tint(.orange)
                .accessibilityIdentifier("insights.error_retry")
            }

            Spacer(minLength: 0)
        }
        .padding(.horizontal, AppTheme.spacing12)
        .padding(.vertical, AppTheme.spacing8)
        .background(
            RoundedRectangle(cornerRadius: AppTheme.cornerRadiusMedium)
                .fill(Color.orange.opacity(AppTheme.opacityMedium))
        )
        .overlay(
            RoundedRectangle(cornerRadius: AppTheme.cornerRadiusMedium)
                .stroke(Color.orange.opacity(AppTheme.opacityStrong), lineWidth: 1)
        )
        .accessibilityIdentifier("insights.error_banner")
        .accessibilityElement(children: .contain)
        .accessibilityLabel(
            L10n.format(
                "Insight refresh error. %@",
                defaultValue: "Insight refresh error. %@",
                language: currentLanguage,
                message
            )
        )
    }

    private func retryInsights() {
        Task {
            await viewModel?.refreshInsights()
            refreshAhaMoment()
        }
    }

    private func refreshAhaMoment() {
        do {
            topAhaMoment = try AhaMomentService(modelContext: modelContext)
                .topMoment(isPremium: appState.allowsPremiumAccess)
        } catch {
            topAhaMoment = nil
        }
    }

    private var emptyState: some View {
        AppEmptyStateView(
            title: emptyStateContent.title,
            message: emptyStateContent.message,
            systemImage: "chart.line.uptrend.xyaxis",
            animateSymbol: true
        ) {
            HStack(spacing: AppTheme.spacing12) {
                if appState.onboardingProfile.primaryGoal == .understandSymptoms {
                    logSymptomsButton
                    logPeriodButton
                } else {
                    logPeriodButton
                    logSymptomsButton
                }
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .accessibilityIdentifier("insights.empty_state")
    }

    private var insightsList: some View {
        List {
            Group {
                RecordedInsightsOverview(
                    snapshot: viewModel?.observationSnapshot ?? .empty,
                    language: currentLanguage,
                    onOpenReport: { showingReportSheet = true }
                )
            }
            .listRowInsets(EdgeInsets(top: 10, leading: 0, bottom: 8, trailing: 0))
            .listRowBackground(Color.clear)
            .listRowSeparator(.hidden)

            if visibleInsights.isEmpty && lockedPremiumCards.isEmpty {
                Text(emptyStateContent.message)
                    .appFont(.subheadline)
                    .foregroundStyle(.secondary)
                    .listRowBackground(Color.clear)
                    .accessibilityIdentifier("insights.empty_state")
            }

            if viewModel?.shouldShowFirstVisitTip == true {
                InsightsFirstVisitTipCard(language: currentLanguage) {
                    viewModel?.markFirstVisitTipShown()
                }
                .listRowInsets(EdgeInsets(top: 6, leading: 0, bottom: 6, trailing: 0))
                .listRowBackground(Color.clear)
                .listRowSeparator(.hidden)
            }

            if shouldShowReportBanner {
                InsightsReportBannerCard(
                    language: currentLanguage,
                    onOpenReport: {
                        showingReportSheet = true
                    },
                    onDismiss: {
                        reportAccessPolicy.dismissInsightsBanner()
                    }
                )
                .listRowInsets(EdgeInsets(top: 6, leading: 0, bottom: 6, trailing: 0))
                .listRowBackground(Color.clear)
                .listRowSeparator(.hidden)
            }

            if !visibleInsights.isEmpty {
                InsightsSharedIntroCard(language: currentLanguage)
                    .listRowInsets(EdgeInsets(top: 6, leading: 0, bottom: 6, trailing: 0))
                    .listRowBackground(Color.clear)
                    .listRowSeparator(.hidden)

                ForEach(Array(visibleInsights.enumerated()), id: \.element.id) { index, insight in
                    InsightCard(insight: insight, index: index, language: currentLanguage, detailed: trackingPreferences.informationDetail == .detailed) {
                        activeDisclosure = InsightEvidenceCatalog.disclosure(for: insight, language: currentLanguage)
                    }
                    .modifier(LunarInsightListRowModifier())
                }
            }

            if !lockedPremiumCards.isEmpty {
                Section {
                    ForEach(Array(lockedPremiumCards.enumerated()), id: \.element.id) { index, teaser in
                        PremiumInsightTeaserCard(teaser: teaser, index: index)
                    }
                } header: {
                    Text(L10n.string("Premium Insights", defaultValue: "Premium Insights", language: currentLanguage))
                        .appFont(.caption, weight: .semibold)
                        .foregroundStyle(.secondary)
                        .accessibilityIdentifier("insights.premium.section_title")
                }
            }
        }
        .listStyle(.insetGrouped)
        .scrollContentBackground(.hidden)
        .background(Color.clear)
        .accessibilityIdentifier("insights.list")
    }

    private var insightsFooter: some View {
        Text(
            L10n.string(
                "Insights are based on your personal data and on-device analysis. They are not medical advice.",
                defaultValue: "Insights are based on your personal data and on-device analysis. They are not medical advice.",
                language: currentLanguage
            )
        )
        .appFont(.caption)
        .foregroundStyle(.secondary)
        .multilineTextAlignment(.center)
        .padding(.horizontal, AppTheme.spacing16)
        .padding(.vertical, AppTheme.spacing12)
        .frame(maxWidth: .infinity)
        .background(insightsFooterBackground)
        .accessibilityIdentifier("insights.footer.disclaimer")
    }

    private var insightsFooterBackground: some ShapeStyle {
        AppTheme.usesImmersiveHomeShell
            ? AppTheme.premiumEditorBackground.opacity(0.94)
            : AppTheme.botanicalCreamAltRGB.color.opacity(AppTheme.isBotanicalJournal ? 0.88 : 1)
    }

    private var logPeriodButton: some View {
        Button {
            showingLogPeriod = true
        } label: {
            Label(
                L10n.string("Log Period", defaultValue: "Log Period", language: currentLanguage),
                systemImage: "drop.fill"
            )
        }
        .buttonStyle(.bordered)
        .appFont(.subheadline, weight: .medium)
        .tint(AppTheme.coralAccent)
    }

    private var logSymptomsButton: some View {
        Button {
            showingLogSymptoms = true
        } label: {
            Label(
                L10n.string("Log Symptoms", defaultValue: "Log Symptoms", language: currentLanguage),
                systemImage: "list.bullet.clipboard"
            )
        }
        .buttonStyle(.bordered)
        .appFont(.subheadline, weight: .medium)
        .tint(AppTheme.accentColor)
    }
}

private struct InsightsSharedIntroCard: View {
    let language: AppLanguage

    var body: some View {
        VStack(alignment: .leading, spacing: AppTheme.spacing12) {
            BotanicalOrnamentalDivider(width: 180)
                .frame(maxWidth: .infinity)

            Label(
                L10n.string(
                    "How to read your insights",
                    defaultValue: "How to read your insights",
                    language: language
                ),
                systemImage: "text.magnifyingglass"
            )
            .appFont(.headline)
            .foregroundStyle(.primary)
            .accessibilityIdentifier("insights.shared_intro_card.title")

            InsightsSharedIntroRow(
                systemImage: "chart.bar.doc.horizontal",
                title: L10n.string(
                    "Built from your logs",
                    defaultValue: "Built from your logs",
                    language: language
                ),
                message: L10n.string(
                    "Each insight comes from patterns in the cycle, symptom, meal, supplement, sleep, and daily data you track on this device.",
                    defaultValue: "Each insight comes from patterns in the cycle, symptom, meal, supplement, sleep, and daily data you track on this device.",
                    language: language
                ),
                accessibilityIdentifier: "insights.shared_intro_card.logs"
            )

            InsightsSharedIntroRow(
                systemImage: "gauge.medium",
                title: L10n.string(
                    "Coverage gives context",
                    defaultValue: "Coverage gives context",
                    language: language
                ),
                message: L10n.string(
                    "Recorded days and missing days help you judge how much evidence is available. Associations do not establish causes.",
                    defaultValue: "Recorded days and missing days help you judge how much evidence is available. Associations do not establish causes.",
                    language: language
                ),
                accessibilityIdentifier: "insights.shared_intro_card.confidence"
            )

            InsightsSharedIntroRow(
                systemImage: "books.vertical",
                title: L10n.string(
                    "Research adds context",
                    defaultValue: "Research adds context",
                    language: language
                ),
                message: L10n.string(
                    "Research helps explain why a pattern may matter, but it does not prove that a study finding caused your specific result.",
                    defaultValue: "Research helps explain why a pattern may matter, but it does not prove that a study finding caused your specific result.",
                    language: language
                ),
                accessibilityIdentifier: "insights.shared_intro_card.research"
            )
        }
        .cardStyle()
        .accessibilityElement(children: .contain)
        .accessibilityIdentifier("insights.shared_intro_card")
    }
}

private struct InsightsSharedIntroRow: View {
    let systemImage: String
    let title: String
    let message: String
    let accessibilityIdentifier: String

    var body: some View {
        HStack(alignment: .top, spacing: AppTheme.spacing8) {
            Image(systemName: systemImage)
                .appFont(.subheadline)
                .foregroundStyle(AppTheme.accentColor)
                .frame(width: 20)
                .padding(.top, 2)

            VStack(alignment: .leading, spacing: AppTheme.spacing4) {
                Text(title)
                    .appFont(.subheadline, weight: .semibold)
                    .foregroundStyle(.primary)
                    .accessibilityIdentifier("\(accessibilityIdentifier).title")
                Text(message)
                    .appFont(.caption)
                    .foregroundStyle(.secondary)
                    .accessibilityIdentifier("\(accessibilityIdentifier).message")
            }
        }
        .accessibilityElement(children: .contain)
        .accessibilityIdentifier(accessibilityIdentifier)
    }
}

private struct LunarInsightListRowModifier: ViewModifier {
    @ViewBuilder
    func body(content: Content) -> some View {
        if AppTheme.usesImmersiveHomeShell {
            content
                .cardStyle(cornerRadius: AppTheme.largeCardCornerRadius)
                .listRowInsets(EdgeInsets(top: 6, leading: 0, bottom: 6, trailing: 0))
                .listRowBackground(Color.clear)
                .listRowSeparator(.hidden)
        } else {
            content
        }
    }
}

struct InsightCard: View {
    @Environment(AppState.self) private var appState
    let insight: Insight
    let index: Int
    let language: AppLanguage
    var detailed: Bool = false
    let onHowItWorks: () -> Void

    @State private var hasAppeared = false

    private var baseAccessibilityIdentifier: String {
        "insights.card.\(index).\(insight.insightType.rawValue)"
    }

    private var learnMoreLabel: String {
        L10n.string("Learn more", defaultValue: "Learn more", language: language)
    }

    var body: some View {
        VStack(alignment: .leading, spacing: AppTheme.spacing12) {
            HStack {
                Image(systemName: insight.insightType.systemImage)
                    .foregroundStyle(AppTheme.accentColor)
                Text(insight.insightType.displayName)
                    .appFont(.caption)
                    .foregroundStyle(.secondary)
                    .accessibilityIdentifier("\(baseAccessibilityIdentifier).type")
                Spacer()
                if insight.actionable {
                    Image(systemName: "lightbulb.fill")
                        .appFont(.caption)
                        .foregroundStyle(.yellow)
                }
            }

            Text(insight.title)
                .appFont(.headline)
                .accessibilityIdentifier("\(baseAccessibilityIdentifier).title")

            insightSection(
                title: L10n.string("What your logs show", defaultValue: "What your logs show", language: language),
                bodyText: displayContent,
                identifierSuffix: "content"
            )

            if detailed && InsightGuidanceCatalog.showsPhaseContext(for: insight) {
                insightSection(
                    title: L10n.string("Cycle phase context", defaultValue: "Cycle phase context", language: language),
                    bodyText: phaseContextMessage,
                    identifierSuffix: "phase_context"
                )
            }

            if detailed && !recommendedActions.isEmpty {
                VStack(alignment: .leading, spacing: AppTheme.spacing8) {
                    Text(
                        L10n.string("What you can do", defaultValue: "What you can do", language: language)
                    )
                    .appFont(.caption, weight: .semibold)
                    .foregroundStyle(.secondary)

                    ForEach(Array(recommendedActions.enumerated()), id: \.offset) { index, action in
                        HStack(alignment: .top, spacing: AppTheme.spacing8) {
                            Text("\(index + 1).")
                                .appFont(.caption, weight: .semibold)
                                .foregroundStyle(AppTheme.coralAccent)
                            Text(action)
                                .appFont(.subheadline)
                                .foregroundStyle(.primary)
                                .fixedSize(horizontal: false, vertical: true)
                        }
                    }
                }
            }

            insightSection(
                title: L10n.string("Evidence", defaultValue: "Evidence", language: language),
                bodyText: confidenceSummary,
                identifierSuffix: "confidence_summary"
            )

            if insight.insightType == .supplementEfficacy {
                Text(L10n.string("Supplement comparisons use up to 365 days of records to cover longer cycles.", defaultValue: "Supplement comparisons use up to 365 days of records to cover longer cycles."))
                    .appFont(.caption)
                    .foregroundStyle(.secondary)
            }

            Button(action: onHowItWorks) {
                Label(
                    learnMoreLabel,
                    systemImage: "info.circle"
                )
                .appFont(.caption, weight: .semibold)
            }
            .buttonStyle(.plain)
            .foregroundStyle(AppTheme.accentColor)
            .accessibilityLabel(learnMoreLabel)
            .accessibilityIdentifier("\(baseAccessibilityIdentifier).learn_more_button")
        }
        .padding(.vertical, 4)
        .opacity(hasAppeared ? 1 : 0)
        .offset(y: hasAppeared ? 0 : 12)
        .onAppear {
            withAnimation(.easeOut(duration: 0.35).delay(Double(index) * 0.08)) {
                hasAppeared = true
            }
        }
        .accessibilityElement(children: .contain)
    }

    private var displayContent: String {
        if detailed, let scientific = insight.scientificContent {
            return scientific
        }
        return insight.content
    }

    private var recommendedActions: [String] {
        Array(InsightGuidanceCatalog.recommendedActions(for: insight).prefix(4))
    }

    private var phaseContextMessage: String {
        if let phase = InsightGuidanceCatalog.inferredPhase(for: insight) {
            return InsightGuidanceCatalog.phaseSummary(for: phase)
        }
        return InsightGuidanceCatalog.unavailablePhaseMessage()
    }

    private var confidenceSummary: String {
        L10n.format("%lld observations used · Updated %@. Missing records can change this pattern.", defaultValue: "%lld observations used · Updated %@. Missing records can change this pattern.", insight.dataPointsUsed, insight.generatedDate.formatted(date: .abbreviated, time: .shortened))
    }

    @ViewBuilder
    private func insightSection(title: String, bodyText: String, identifierSuffix: String) -> some View {
        VStack(alignment: .leading, spacing: AppTheme.spacing4) {
            Text(title)
                .appFont(.caption, weight: .semibold)
                .foregroundStyle(.secondary)
            Text(bodyText)
                .appFont(.subheadline)
                .foregroundStyle(.secondary)
                .accessibilityIdentifier("\(baseAccessibilityIdentifier).\(identifierSuffix)")
        }
    }
}

private struct InsightsFirstVisitTipCard: View {
    let language: AppLanguage
    let dismissAction: () -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: AppTheme.spacing12) {
            HStack(alignment: .top) {
                Label(
                    L10n.string("Insights explained", defaultValue: "Insights explained", language: language),
                    systemImage: "sparkles.rectangle.stack"
                )
                .appFont(.headline)
                Spacer()
                Button(action: dismissAction) {
                    Image(systemName: "xmark")
                        .appFont(.caption, weight: .semibold)
                        .foregroundStyle(.secondary)
                }
                .buttonStyle(.plain)
            }

            Text(
                L10n.string(
                    "This tab looks for patterns in the cycle, symptom, meal, supplement, and daily data you log. Missing days are not treated as symptom-free days.",
                    defaultValue: "This tab looks for patterns in the cycle, symptom, meal, supplement, and daily data you log. Missing days are not treated as symptom-free days.",
                    language: language
                )
            )
            .appFont(.subheadline)
            .foregroundStyle(.secondary)
        }
        .cardStyle()
    }
}

private struct InsightsReportBannerCard: View {
    let language: AppLanguage
    let onOpenReport: () -> Void
    let onDismiss: () -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: AppTheme.spacing12) {
            HStack(alignment: .top) {
                Label(
                    L10n.string("Share report with your doctor", defaultValue: "Share report with your doctor", language: language),
                    systemImage: "doc.richtext"
                )
                .appFont(.headline)
                Spacer()
                Button(action: onDismiss) {
                    Image(systemName: "xmark")
                        .appFont(.caption, weight: .semibold)
                        .foregroundStyle(.secondary)
                }
                .buttonStyle(.plain)
                .accessibilityIdentifier("insights.report_banner.dismiss")
            }

            Text(
                L10n.string(
                    "You have enough cycle data to generate a PDF report you can email, AirDrop, or save to Files.",
                    defaultValue: "You have enough cycle data to generate a PDF report you can email, AirDrop, or save to Files.",
                    language: language
                )
            )
            .appFont(.subheadline)
            .foregroundStyle(.secondary)

            Button(action: onOpenReport) {
                ZStack {
                    RoundedRectangle(cornerRadius: AppTheme.cornerRadiusMedium)
                        .fill(AppTheme.coralAccent)

                    Label(
                        L10n.string("Export PDF", defaultValue: "Export PDF", language: language),
                        systemImage: "square.and.arrow.up"
                    )
                    .appFont(.subheadline, weight: .semibold)
                    .foregroundStyle(.white)
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, AppTheme.spacing12)
                }
                .contentShape(RoundedRectangle(cornerRadius: AppTheme.cornerRadiusMedium))
            }
            .buttonStyle(.plain)
            .accessibilityIdentifier("insights.report_banner.export")
        }
        .cardStyle()
        .accessibilityIdentifier("insights.report_banner")
    }
}

private extension View {
    @ViewBuilder
    func lunarInsightsPresentation<Destination: View>(
        isPresented: Binding<Bool>,
        @ViewBuilder destination: @escaping () -> Destination
    ) -> some View {
        if AppTheme.usesImmersivePresentation {
            fullScreenCover(isPresented: isPresented, content: destination)
        } else {
            sheet(isPresented: isPresented, content: destination)
        }
    }

    @ViewBuilder
    func lunarInsightsItemPresentation<Item: Identifiable, Destination: View>(
        item: Binding<Item?>,
        @ViewBuilder destination: @escaping (Item) -> Destination
    ) -> some View {
        if AppTheme.usesImmersivePresentation {
            fullScreenCover(item: item, content: destination)
        } else {
            sheet(item: item, content: destination)
        }
    }
}

struct PremiumInsightTeaserCard: View {
    @Environment(AppState.self) private var appState
    let teaser: PremiumInsightTeaser
    let index: Int

    @State private var hasAppeared = false

    private var accessibilityIdentifier: String {
        "insights.premium.\(index).\(teaser.id)"
    }

    var body: some View {
        VStack(alignment: .leading, spacing: AppTheme.spacing8) {
            HStack {
                Image(systemName: "lock.fill")
                    .foregroundStyle(AppTheme.coralAccent)
                Text(teaser.title)
                    .appFont(.headline)
                    .accessibilityIdentifier("\(accessibilityIdentifier).title")
                Spacer()
                Button(L10n.string("Upgrade", defaultValue: "Upgrade")) {
                    appState.presentPremiumPaywall()
                }
                .buttonStyle(.borderless)
                .appFont(.caption, weight: .semibold)
                .foregroundStyle(AppTheme.accentColor)
                .accessibilityIdentifier("\(accessibilityIdentifier).upgrade")
            }

            Text(teaser.message)
                .appFont(.subheadline)
                .foregroundStyle(.secondary)
                .accessibilityIdentifier("\(accessibilityIdentifier).message")
        }
        .padding(.vertical, 4)
        .opacity(hasAppeared ? 1 : 0)
        .offset(y: hasAppeared ? 0 : 12)
        .onAppear {
            withAnimation(.easeOut(duration: 0.35).delay(Double(index) * 0.08)) {
                hasAppeared = true
            }
        }
        .accessibilityIdentifier(accessibilityIdentifier)
    }
}

#Preview {
    InsightsView()
        .modelContainer(for: [
            CycleEntry.self,
            Cycle.self,
            SymptomEntry.self,
            Insight.self,
            BloodSugarReading.self,
            SupplementLog.self,
            MealEntry.self,
            HairPhotoEntry.self,
            DailyLog.self,
        ], inMemory: true)
        .environment(AppState())
        .environment(ReportAccessPolicy())
}
