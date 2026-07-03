import StoreKit
import SwiftUI
import SwiftData

struct InsightsView: View {
    @Environment(\.modelContext) private var modelContext
    @Environment(\.requestReview) private var requestReview
    @Environment(AppState.self) private var appState
    @Environment(ReportAccessPolicy.self) private var reportAccessPolicy
    @State private var viewModel: InsightsViewModel?
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
                    } else if visibleInsights.isEmpty && lockedPremiumCards.isEmpty {
                        emptyState
                    } else {
                        insightsList
                    }
                }
                .onChange(of: visibleInsights.count) { oldCount, newCount in
                    if oldCount == 0, newCount > 0 {
                        ReviewPromptService.requestReviewIfEligible(modelContext: modelContext, moment: .firstInsight, requestReview: requestReview)
                    }
                }
            }
            .navigationTitle(AppTheme.usesImmersiveHomeShell ? "" : L10n.string("Insights", defaultValue: "Insights", language: currentLanguage))
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
                if AppTheme.usesImmersiveHomeShell {
                    LunarInsightsOverviewDashboard(
                        insights: visibleInsights,
                        completedCycleCount: completedCycleCount,
                        language: currentLanguage,
                        onOpenReport: {
                            showingReportSheet = true
                        },
                        onOpenDisclosure: { insight in
                            activeDisclosure = InsightEvidenceCatalog.disclosure(for: insight, language: currentLanguage)
                        }
                    )
                } else {
                    BotanicalPosterHeader(
                        title: L10n.string("Patterns are not random", defaultValue: "Patterns are not random", language: currentLanguage),
                        subtitle: L10n.string("Your logs can reveal gentle signals in cycle timing, mood, cravings, energy, and symptoms.", defaultValue: "Your logs can reveal gentle signals in cycle timing, mood, cravings, energy, and symptoms.", language: currentLanguage),
                        emblemAssetName: "botanical-calendar-illustration",
                        dividerStyle: .ornamental
                    )
                }
            }
            .listRowInsets(EdgeInsets(top: 10, leading: 0, bottom: 8, trailing: 0))
            .listRowBackground(Color.clear)
            .listRowSeparator(.hidden)

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
                    InsightCard(insight: insight, index: index, language: currentLanguage) {
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
                    "Confidence shows pattern strength",
                    defaultValue: "Confidence shows pattern strength",
                    language: language
                ),
                message: L10n.string(
                    "Higher confidence usually means the app has seen the same pattern more than once in your recent history.",
                    defaultValue: "Higher confidence usually means the app has seen the same pattern more than once in your recent history.",
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

private enum LunarInsightSegment: String, CaseIterable, Identifiable {
    case overview
    case cycles
    case symptoms
    case mood

    var id: String { rawValue }

    func title(language: AppLanguage) -> String {
        switch self {
        case .overview:
            L10n.string("Overview", defaultValue: "Overview", language: language)
        case .cycles:
            L10n.string("Cycles", defaultValue: "Cycles", language: language)
        case .symptoms:
            L10n.string("Symptoms", defaultValue: "Symptoms", language: language)
        case .mood:
            L10n.string("Mood", defaultValue: "Mood", language: language)
        }
    }
}

private struct LunarInsightsOverviewDashboard: View {
    let insights: [Insight]
    let completedCycleCount: Int
    let language: AppLanguage
    let onOpenReport: () -> Void
    let onOpenDisclosure: (Insight) -> Void

    @State private var selectedSegment = LunarInsightSegment.overview

    private var averageConfidencePercent: Int {
        guard !insights.isEmpty else { return 0 }
        let average = insights.reduce(0.0) { $0 + $1.confidence } / Double(insights.count)
        return Int((average * 100).rounded())
    }

    private var activeSignalCount: Int {
        Set(insights.map(\.insightType)).count
    }

    private var totalDataPoints: Int {
        insights.reduce(0) { $0 + $1.dataPointsUsed }
    }

    private var strongestInsight: Insight? {
        insights.max { lhs, rhs in
            lhs.confidence < rhs.confidence
        }
    }

    private var relatedPatternNames: [String] {
        var seen = Set<String>()
        var symptoms: [String] = []

        for insight in insights {
            for symptom in insight.relatedSymptoms {
                let trimmed = symptom.trimmingCharacters(in: .whitespacesAndNewlines)
                guard !trimmed.isEmpty, seen.insert(trimmed).inserted else { continue }
                symptoms.append(trimmed)
            }
        }

        if !symptoms.isEmpty {
            return Array(symptoms.prefix(4))
        }

        return Array(insights.map { $0.insightType.displayName }.prefix(4))
    }

    private var trendValues: [Double] {
        let values = insights
            .prefix(6)
            .map { min(max($0.confidence, 0.22), 0.96) }
            .reversed()

        let resolved = Array(values)
        guard resolved.count >= 3 else {
            return [0.46, 0.72, 0.54, 0.82, 0.58, 0.76]
        }
        return resolved
    }

    var body: some View {
        VStack(alignment: .leading, spacing: AppTheme.spacing12) {
            HStack(alignment: .center) {
                VStack(alignment: .leading, spacing: AppTheme.spacing4) {
                    Text(L10n.string("Insights", defaultValue: "Insights", language: language))
                        .appHeadingFont(.largeTitle, weight: .regular)
                        .foregroundStyle(AppTheme.primaryText)
                        .accessibilityIdentifier("insights.lunar_dashboard.title")

                    Text(
                        L10n.string(
                            "Find patterns that matter",
                            defaultValue: "Find patterns that matter",
                            language: language
                        )
                    )
                    .appFont(.headline, weight: .semibold)
                    .foregroundStyle(AppTheme.secondaryText)
                }

                Spacer(minLength: AppTheme.spacing12)

                Button(action: onOpenReport) {
                    Image(systemName: "doc.richtext")
                        .appFont(.title3, weight: .medium)
                        .foregroundStyle(AppTheme.primaryText)
                        .frame(width: 48, height: 48)
                        .background(Circle().fill(AppTheme.premiumEditorRaisedSurface.opacity(0.9)))
                        .overlay(Circle().stroke(AppTheme.premiumEditorBorder.opacity(0.82), lineWidth: 0.8))
                }
                .buttonStyle(.plain)
                .contentShape(Rectangle())
                .accessibilityLabel(L10n.string("Export PDF", defaultValue: "Export PDF", language: language))
                .accessibilityIdentifier("insights.lunar_dashboard.report_icon_button")
            }
            .padding(.top, AppTheme.spacing8)

            LunarInsightSegmentedControl(
                selectedSegment: $selectedSegment,
                language: language
            )

            ZStack {
                RoundedRectangle(cornerRadius: AppTheme.cornerRadiusLarge, style: .continuous)
                    .fill(AppTheme.premiumEditorAccentGradient)

                HStack(spacing: AppTheme.spacing8) {
                    Image(systemName: "doc.richtext")
                    Text(L10n.string("Export PDF", defaultValue: "Export PDF", language: language))
                    Spacer(minLength: AppTheme.spacing8)
                    Image(systemName: "arrow.right")
                }
                .appFont(.subheadline, weight: .semibold)
                .foregroundStyle(AppTheme.premiumEditorCTAForeground)
                .padding(.horizontal, AppTheme.spacing16)
                .padding(.vertical, AppTheme.spacing12)
            }
            .frame(maxWidth: .infinity)
            .contentShape(RoundedRectangle(cornerRadius: AppTheme.cornerRadiusLarge, style: .continuous))
            .shadow(color: AppTheme.cardShadowColor.opacity(0.9), radius: 14, y: 8)
            .onTapGesture(perform: onOpenReport)
            .accessibilityElement(children: .ignore)
            .accessibilityLabel(L10n.string("Export PDF", defaultValue: "Export PDF", language: language))
            .accessibilityAddTraits(.isButton)
            .accessibilityAction { onOpenReport() }
            .accessibilityIdentifier("insights.lunar_dashboard.report_button")

            LunarInsightMetricCard(
                selectedSegment: selectedSegment,
                averageConfidencePercent: averageConfidencePercent,
                activeSignalCount: activeSignalCount,
                completedCycleCount: completedCycleCount,
                totalDataPoints: totalDataPoints,
                strongestInsight: strongestInsight,
                trendValues: trendValues,
                language: language,
                onOpenDisclosure: onOpenDisclosure
            )

            LunarInsightPhaseCard(
                activeSignalCount: activeSignalCount,
                strongestInsight: strongestInsight,
                language: language
            )

            LunarInsightTopPatternsCard(
                patternNames: relatedPatternNames,
                activeSignalCount: activeSignalCount,
                language: language
            )
        }
        .padding(.horizontal, AppTheme.spacing16)
        .padding(.vertical, AppTheme.spacing8)
        .accessibilityElement(children: .contain)
        .accessibilityIdentifier("insights.lunar_dashboard")
    }
}

private struct LunarInsightSegmentedControl: View {
    @Binding var selectedSegment: LunarInsightSegment
    let language: AppLanguage

    var body: some View {
        HStack(spacing: AppTheme.spacing4) {
            ForEach(LunarInsightSegment.allCases) { segment in
                Button {
                    selectedSegment = segment
                } label: {
                    Text(segment.title(language: language))
                        .appFont(.caption, weight: selectedSegment == segment ? .semibold : .regular)
                        .foregroundStyle(
                            selectedSegment == segment
                                ? AppTheme.primaryText
                                : AppTheme.secondaryText
                        )
                        .lineLimit(1)
                        .minimumScaleFactor(0.75)
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, AppTheme.spacing8)
                        .background {
                            if selectedSegment == segment {
                                RoundedRectangle(cornerRadius: AppTheme.cornerRadiusSmall, style: .continuous)
                                    .fill(AppTheme.premiumEditorRaisedSurface.opacity(0.94))
                                    .overlay(
                                        RoundedRectangle(cornerRadius: AppTheme.cornerRadiusSmall, style: .continuous)
                                            .strokeBorder(AppTheme.premiumEditorBorderGradient, lineWidth: 0.9)
                                    )
                            }
                        }
                }
                .buttonStyle(.plain)
                .accessibilityIdentifier("insights.lunar_dashboard.segment.\(segment.rawValue)")
            }
        }
        .padding(AppTheme.spacing4)
        .background(
            RoundedRectangle(cornerRadius: AppTheme.cornerRadiusMedium, style: .continuous)
                .fill(AppTheme.premiumEditorSurface.opacity(0.82))
        )
        .overlay(
            RoundedRectangle(cornerRadius: AppTheme.cornerRadiusMedium, style: .continuous)
                .stroke(AppTheme.premiumEditorBorder.opacity(0.52), lineWidth: 0.8)
        )
        .animation(.easeInOut(duration: 0.2), value: selectedSegment)
        .accessibilityIdentifier("insights.lunar_dashboard.segments")
    }
}

private struct LunarInsightMetricCard: View {
    let selectedSegment: LunarInsightSegment
    let averageConfidencePercent: Int
    let activeSignalCount: Int
    let completedCycleCount: Int
    let totalDataPoints: Int
    let strongestInsight: Insight?
    let trendValues: [Double]
    let language: AppLanguage
    let onOpenDisclosure: (Insight) -> Void

    private var metricTitle: String {
        switch selectedSegment {
        case .overview:
            L10n.string("Pattern strength", defaultValue: "Pattern strength", language: language)
        case .cycles:
            L10n.string("Cycle signal", defaultValue: "Cycle signal", language: language)
        case .symptoms:
            L10n.string("Symptom links", defaultValue: "Symptom links", language: language)
        case .mood:
            L10n.string("Wellbeing rhythm", defaultValue: "Wellbeing rhythm", language: language)
        }
    }

    private var metricValue: String {
        switch selectedSegment {
        case .overview:
            averageConfidencePercent > 0 ? "\(averageConfidencePercent)%" : "--"
        case .cycles:
            "\(max(completedCycleCount, 0))"
        case .symptoms:
            "\(max(activeSignalCount, 0))"
        case .mood:
            strongestInsight == nil ? "--" : "\(max(totalDataPoints, 0))"
        }
    }

    private var metricUnit: String {
        switch selectedSegment {
        case .overview:
            L10n.string("average", defaultValue: "average", language: language)
        case .cycles:
            L10n.string("cycles", defaultValue: "cycles", language: language)
        case .symptoms:
            L10n.string("signals", defaultValue: "signals", language: language)
        case .mood:
            L10n.string("logs", defaultValue: "logs", language: language)
        }
    }

    private var metricNote: String {
        switch selectedSegment {
        case .overview:
            L10n.string(
                "Your strongest patterns update as you keep logging.",
                defaultValue: "Your strongest patterns update as you keep logging.",
                language: language
            )
        case .cycles:
            L10n.string(
                "Cycle timing becomes clearer after more complete cycles.",
                defaultValue: "Cycle timing becomes clearer after more complete cycles.",
                language: language
            )
        case .symptoms:
            L10n.string(
                "Repeated symptom context helps separate noise from signal.",
                defaultValue: "Repeated symptom context helps separate noise from signal.",
                language: language
            )
        case .mood:
            L10n.string(
                "Mood and energy trends stay gentle until enough logs repeat.",
                defaultValue: "Mood and energy trends stay gentle until enough logs repeat.",
                language: language
            )
        }
    }

    var body: some View {
        LunarInsightGlassCard(accessibilityIdentifier: "insights.lunar_dashboard.metric_card") {
            VStack(alignment: .leading, spacing: AppTheme.spacing12) {
                HStack(alignment: .top) {
                    VStack(alignment: .leading, spacing: AppTheme.spacing4) {
                        Text(metricTitle)
                            .appFont(.headline, weight: .semibold)
                            .foregroundStyle(AppTheme.primaryText)

                        HStack(alignment: .firstTextBaseline, spacing: AppTheme.spacing4) {
                            Text(metricValue)
                                .appHeadingFont(.largeTitle, weight: .regular)
                                .foregroundStyle(AppTheme.premiumEditorAccentGradient)
                                .contentTransition(.numericText())
                                .accessibilityIdentifier("insights.lunar_dashboard.metric_value")

                            Text(metricUnit)
                                .appFont(.subheadline)
                                .foregroundStyle(AppTheme.secondaryText)
                        }
                    }

                    Spacer(minLength: AppTheme.spacing8)

                    VStack(alignment: .leading, spacing: AppTheme.spacing4) {
                        Text(deltaLabel)
                            .appFont(.subheadline, weight: .semibold)
                            .foregroundStyle(AppTheme.primaryText)
                        Text(L10n.string("current signal", defaultValue: "current signal", language: language))
                            .appFont(.caption)
                            .foregroundStyle(AppTheme.secondaryText)
                    }
                    .padding(.horizontal, AppTheme.spacing12)
                    .padding(.vertical, 10)
                    .background(
                        RoundedRectangle(cornerRadius: AppTheme.cornerRadiusMedium, style: .continuous)
                            .fill(AppTheme.premiumEditorRaisedSurface.opacity(0.82))
                    )
                    .overlay(
                        RoundedRectangle(cornerRadius: AppTheme.cornerRadiusMedium, style: .continuous)
                            .stroke(AppTheme.premiumEditorBorder.opacity(0.64), lineWidth: 0.8)
                    )
                    .accessibilityIdentifier("insights.lunar_dashboard.metric_badge")
                }

                LunarInsightTrendChart(values: trendValues)
                    .frame(height: 112)

                Text(metricNote)
                    .appFont(.caption)
                    .foregroundStyle(AppTheme.secondaryText)

                if let strongestInsight {
                    Button {
                        onOpenDisclosure(strongestInsight)
                    } label: {
                        Label(
                            L10n.string("Learn more", defaultValue: "Learn more", language: language),
                            systemImage: "info.circle"
                        )
                        .appFont(.caption, weight: .semibold)
                        .foregroundStyle(AppTheme.premiumEditorAccentColor)
                    }
                    .buttonStyle(.plain)
                    .accessibilityIdentifier("insights.lunar_dashboard.learn_more_button")
                }
            }
        }
    }

    private var deltaLabel: String {
        guard let strongestInsight else {
            return L10n.string("Growing", defaultValue: "Growing", language: language)
        }

        let percent = Int((strongestInsight.confidence * 100).rounded())
        return "\(percent)%"
    }
}

private struct LunarInsightTrendChart: View {
    let values: [Double]

    private let labels = ["Feb", "Mar", "Apr", "May", "Jun", "Jul"]

    var body: some View {
        VStack(spacing: AppTheme.spacing8) {
            GeometryReader { proxy in
                ZStack(alignment: .bottomLeading) {
                    VStack(spacing: 0) {
                        ForEach(0..<4, id: \.self) { _ in
                            Divider()
                                .overlay(AppTheme.premiumEditorBorder.opacity(0.38))
                            Spacer(minLength: 0)
                        }
                    }

                    LunarInsightTrendArea(values: values)
                        .fill(
                            LinearGradient(
                                colors: [
                                    AppTheme.premiumEditorAccentColor.opacity(0.22),
                                    AppTheme.lavenderAccent.opacity(0.08),
                                    AppTheme.premiumEditorBackground.opacity(0.01),
                                ],
                                startPoint: .top,
                                endPoint: .bottom
                            )
                        )

                    LunarInsightTrendLine(values: values)
                        .stroke(
                            AppTheme.premiumEditorAccentGradient,
                            style: StrokeStyle(lineWidth: 3, lineCap: .round, lineJoin: .round)
                        )
                        .shadow(color: AppTheme.premiumEditorAccentColor.opacity(0.24), radius: 8, y: 2)

                    ForEach(Array(normalizedPoints(in: proxy.size).enumerated()), id: \.offset) { index, point in
                        Circle()
                            .fill(pointColor(index: index))
                            .frame(width: 9, height: 9)
                            .overlay(Circle().stroke(AppTheme.primaryText.opacity(0.58), lineWidth: 1))
                            .position(point)
                    }
                }
            }

            HStack {
                ForEach(labels, id: \.self) { label in
                    Text(label)
                        .appFont(.caption2)
                        .foregroundStyle(AppTheme.secondaryText)
                        .frame(maxWidth: .infinity)
                }
            }
        }
        .accessibilityElement(children: .ignore)
        .accessibilityLabel("Insight trend chart")
        .accessibilityIdentifier("insights.lunar_dashboard.trend_chart")
    }

    private func normalizedPoints(in size: CGSize) -> [CGPoint] {
        let resolvedValues = values.isEmpty ? [0.46, 0.72, 0.54, 0.82, 0.58, 0.76] : values
        guard resolvedValues.count > 1 else { return [] }

        let maxValue = max(resolvedValues.max() ?? 1, 0.01)
        let minValue = min(resolvedValues.min() ?? 0, maxValue - 0.01)
        let range = max(maxValue - minValue, 0.01)
        let step = size.width / CGFloat(resolvedValues.count - 1)

        return resolvedValues.enumerated().map { index, value in
            let normalized = (value - minValue) / range
            let y = size.height - CGFloat(normalized) * (size.height * 0.72) - size.height * 0.14
            return CGPoint(x: CGFloat(index) * step, y: y)
        }
    }

    private func pointColor(index: Int) -> Color {
        let colors = [
            AppTheme.premiumEditorAccentColor,
            AppTheme.accentColor,
            AppTheme.lavenderAccent,
            AppTheme.premiumEditorWarningAccentColor,
            AppTheme.premiumEditorSecondaryAccentColor,
        ]
        return colors[index % colors.count]
    }
}

private struct LunarInsightTrendLine: Shape {
    let values: [Double]

    func path(in rect: CGRect) -> Path {
        Path { path in
            let points = normalizedPoints(in: rect, values: values)
            guard let first = points.first else { return }
            path.move(to: first)

            for index in points.indices.dropFirst() {
                let previous = points[index - 1]
                let current = points[index]
                let controlX = (previous.x + current.x) / 2
                path.addCurve(
                    to: current,
                    control1: CGPoint(x: controlX, y: previous.y),
                    control2: CGPoint(x: controlX, y: current.y)
                )
            }
        }
    }
}

private struct LunarInsightTrendArea: Shape {
    let values: [Double]

    func path(in rect: CGRect) -> Path {
        Path { path in
            let points = normalizedPoints(in: rect, values: values)
            guard let first = points.first, let last = points.last else { return }
            path.move(to: CGPoint(x: first.x, y: rect.maxY))
            path.addLine(to: first)

            for index in points.indices.dropFirst() {
                let previous = points[index - 1]
                let current = points[index]
                let controlX = (previous.x + current.x) / 2
                path.addCurve(
                    to: current,
                    control1: CGPoint(x: controlX, y: previous.y),
                    control2: CGPoint(x: controlX, y: current.y)
                )
            }

            path.addLine(to: CGPoint(x: last.x, y: rect.maxY))
            path.closeSubpath()
        }
    }
}

private struct LunarInsightPhaseCard: View {
    let activeSignalCount: Int
    let strongestInsight: Insight?
    let language: AppLanguage

    private var barValues: [Double] {
        let strongest = strongestInsight?.confidence ?? 0.68
        return [0.54, 0.62, strongest, 0.76]
    }

    var body: some View {
        LunarInsightGlassCard(accessibilityIdentifier: "insights.lunar_dashboard.phase_card") {
            HStack(alignment: .top, spacing: AppTheme.spacing12) {
                VStack(alignment: .leading, spacing: AppTheme.spacing8) {
                    HStack(spacing: AppTheme.spacing4) {
                        Text(
                            L10n.string(
                                "Mood by cycle phase",
                                defaultValue: "Mood by cycle phase",
                                language: language
                            )
                        )
                        .appFont(.headline, weight: .semibold)
                        .foregroundStyle(AppTheme.primaryText)

                        Image(systemName: "info.circle")
                            .appFont(.caption)
                            .foregroundStyle(AppTheme.secondaryText)
                    }

                    LunarInsightBarChart(values: barValues)
                        .frame(height: 116)
                }

                VStack(alignment: .leading, spacing: AppTheme.spacing8) {
                    Text(
                        L10n.string(
                            "You have the clearest signal in",
                            defaultValue: "You have the clearest signal in",
                            language: language
                        )
                    )
                    .appFont(.caption)
                    .foregroundStyle(AppTheme.secondaryText)

                    Text(strongestInsight?.insightType.displayName ?? L10n.string("Cycle Pattern", defaultValue: "Cycle Pattern", language: language))
                        .appFont(.subheadline, weight: .semibold)
                        .foregroundStyle(AppTheme.premiumEditorAccentColor)
                        .lineLimit(2)
                        .minimumScaleFactor(0.8)

                    Text(
                        L10n.string(
                            "More logs make this view more personal.",
                            defaultValue: "More logs make this view more personal.",
                            language: language
                        )
                    )
                    .appFont(.caption)
                    .foregroundStyle(AppTheme.secondaryText)
                }
                .frame(maxWidth: 132, alignment: .leading)
            }
        }
    }
}

private struct LunarInsightBarChart: View {
    let values: [Double]

    private let symbols = ["camera.macro", "cloud.fill", "circle.lefthalf.filled", "moon.fill"]

    var body: some View {
        HStack(alignment: .bottom, spacing: AppTheme.spacing12) {
            ForEach(Array(values.enumerated()), id: \.offset) { index, value in
                VStack(spacing: AppTheme.spacing8) {
                    GeometryReader { proxy in
                        VStack {
                            Spacer(minLength: 0)
                            RoundedRectangle(cornerRadius: 5, style: .continuous)
                                .fill(barGradient(index: index))
                                .frame(height: max(18, proxy.size.height * CGFloat(value)))
                        }
                    }

                    Image(systemName: symbols[index % symbols.count])
                        .appFont(.caption)
                        .foregroundStyle(symbolColor(index: index))
                }
                .frame(maxWidth: .infinity)
            }
        }
        .accessibilityElement(children: .ignore)
        .accessibilityLabel("Cycle phase bar chart")
        .accessibilityIdentifier("insights.lunar_dashboard.phase_bars")
    }

    private func barGradient(index: Int) -> LinearGradient {
        let color = symbolColor(index: index)
        return LinearGradient(
            colors: [
                color.opacity(0.96),
                AppTheme.accentColor.opacity(0.72),
            ],
            startPoint: .top,
            endPoint: .bottom
        )
    }

    private func symbolColor(index: Int) -> Color {
        let colors = [
            AppTheme.premiumEditorSecondaryAccentColor,
            AppTheme.lavenderAccent,
            AppTheme.secondaryText,
            AppTheme.premiumEditorAccentColor,
        ]
        return colors[index % colors.count]
    }
}

private struct LunarInsightTopPatternsCard: View {
    let patternNames: [String]
    let activeSignalCount: Int
    let language: AppLanguage

    private var rows: [String] {
        if patternNames.isEmpty {
            return [
                L10n.string("Cycle timing", defaultValue: "Cycle timing", language: language),
                L10n.string("Energy changes", defaultValue: "Energy changes", language: language),
                L10n.string("Symptom clusters", defaultValue: "Symptom clusters", language: language),
            ]
        }
        return patternNames
    }

    var body: some View {
        LunarInsightGlassCard(accessibilityIdentifier: "insights.lunar_dashboard.patterns_card") {
            HStack(alignment: .top, spacing: AppTheme.spacing12) {
                VStack(alignment: .leading, spacing: 10) {
                    Text(L10n.string("Top patterns", defaultValue: "Top patterns", language: language))
                        .appFont(.headline, weight: .semibold)
                        .foregroundStyle(AppTheme.primaryText)

                    ForEach(Array(rows.prefix(4).enumerated()), id: \.offset) { index, row in
                        LunarPatternRow(
                            title: row,
                            percent: patternPercent(index: index),
                            color: patternColor(index: index)
                        )
                    }
                }

                VStack(alignment: .leading, spacing: AppTheme.spacing8) {
                    Text(L10n.string("This cycle", defaultValue: "This cycle", language: language))
                        .appFont(.caption)
                        .foregroundStyle(AppTheme.secondaryText)

                    Text(
                        L10n.string(
                            "These are the signals worth watching first.",
                            defaultValue: "These are the signals worth watching first.",
                            language: language
                        )
                    )
                    .appFont(.caption)
                    .foregroundStyle(AppTheme.secondaryText)

                    Text(L10n.string("View all", defaultValue: "View all", language: language))
                        .appFont(.caption, weight: .semibold)
                        .foregroundStyle(AppTheme.premiumEditorAccentColor)
                }
                .frame(maxWidth: 124, alignment: .leading)
            }
        }
    }

    private func patternPercent(index: Int) -> Int {
        max(28, 72 - index * max(8, activeSignalCount + 6))
    }

    private func patternColor(index: Int) -> Color {
        let colors = [
            AppTheme.premiumEditorWarningAccentColor,
            AppTheme.premiumEditorSecondaryAccentColor,
            AppTheme.premiumEditorAccentColor,
            AppTheme.lavenderAccent,
        ]
        return colors[index % colors.count]
    }
}

private struct LunarPatternRow: View {
    let title: String
    let percent: Int
    let color: Color

    var body: some View {
        HStack(spacing: AppTheme.spacing8) {
            Circle()
                .fill(color)
                .frame(width: 8, height: 8)

            Text(title)
                .appFont(.caption)
                .foregroundStyle(AppTheme.primaryText)
                .lineLimit(1)
                .minimumScaleFactor(0.78)

            GeometryReader { proxy in
                ZStack(alignment: .leading) {
                    Capsule()
                        .fill(AppTheme.premiumEditorBorder.opacity(0.56))
                    Capsule()
                        .fill(
                            LinearGradient(
                                colors: [AppTheme.premiumEditorSecondaryAccentColor, AppTheme.lavenderAccent],
                                startPoint: .leading,
                                endPoint: .trailing
                            )
                        )
                        .frame(width: proxy.size.width * CGFloat(percent) / 100)
                }
            }
            .frame(height: 6)

            Text("\(percent)%")
                .appFont(.caption2, weight: .semibold)
                .foregroundStyle(AppTheme.secondaryText)
                .frame(width: 34, alignment: .trailing)
        }
    }
}

private struct LunarInsightGlassCard<Content: View>: View {
    let accessibilityIdentifier: String
    let content: Content

    init(
        accessibilityIdentifier: String,
        @ViewBuilder content: () -> Content
    ) {
        self.accessibilityIdentifier = accessibilityIdentifier
        self.content = content()
    }

    var body: some View {
        content
            .padding(AppTheme.spacing16)
            .background(
                RoundedRectangle(cornerRadius: AppTheme.largeCardCornerRadius, style: .continuous)
                    .fill(
                        LinearGradient(
                            colors: [
                                AppTheme.premiumEditorRaisedSurface.opacity(0.86),
                                AppTheme.premiumEditorSurface.opacity(0.78),
                                AppTheme.premiumEditorBackground.opacity(0.9),
                            ],
                            startPoint: .topLeading,
                            endPoint: .bottomTrailing
                        )
                    )
            )
            .overlay(
                RoundedRectangle(cornerRadius: AppTheme.largeCardCornerRadius, style: .continuous)
                    .stroke(AppTheme.premiumEditorBorder.opacity(0.68), lineWidth: 0.8)
            )
            .shadow(color: AppTheme.cardShadowColor, radius: 18, y: 12)
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

private func normalizedPoints(in rect: CGRect, values: [Double]) -> [CGPoint] {
    let resolvedValues = values.isEmpty ? [0.46, 0.72, 0.54, 0.82, 0.58, 0.76] : values
    guard resolvedValues.count > 1 else { return [] }

    let maxValue = max(resolvedValues.max() ?? 1, 0.01)
    let minValue = min(resolvedValues.min() ?? 0, maxValue - 0.01)
    let range = max(maxValue - minValue, 0.01)
    let step = rect.width / CGFloat(resolvedValues.count - 1)

    return resolvedValues.enumerated().map { index, value in
        let normalized = (value - minValue) / range
        let y = rect.maxY - CGFloat(normalized) * (rect.height * 0.72) - rect.height * 0.14
        return CGPoint(x: rect.minX + CGFloat(index) * step, y: y)
    }
}

private func normalizedPoints(in size: CGSize, values: [Double]) -> [CGPoint] {
    normalizedPoints(in: CGRect(origin: .zero, size: size), values: values)
}

struct InsightCard: View {
    @Environment(AppState.self) private var appState
    let insight: Insight
    let index: Int
    let language: AppLanguage
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
                title: L10n.string("Why this may be happening", defaultValue: "Why this may be happening", language: language),
                bodyText: displayContent,
                identifierSuffix: "content"
            )

            if InsightGuidanceCatalog.showsPhaseContext(for: insight) {
                insightSection(
                    title: L10n.string("Cycle phase context", defaultValue: "Cycle phase context", language: language),
                    bodyText: phaseContextMessage,
                    identifierSuffix: "phase_context"
                )
            }

            if !recommendedActions.isEmpty {
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
                title: L10n.string("Confidence", defaultValue: "Confidence", language: language),
                bodyText: confidenceSummary,
                identifierSuffix: "confidence_summary"
            )

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
        if appState.showScientificDetail, let scientific = insight.scientificContent {
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
        let confidencePercent = Int((insight.confidence * 100).rounded())

        if appState.showScientificDetail {
            return L10n.format(
                "%@. %lld%% confidence based on %lld data points.",
                defaultValue: "%@. %lld%% confidence based on %lld data points.",
                friendlyDataBasis,
                Int64(confidencePercent),
                Int64(insight.dataPointsUsed)
            )
        }

        return L10n.format(
            "%@. %@.",
            defaultValue: "%@. %@.",
            friendlyConfidenceLabel,
            friendlyDataBasis
        )
    }

    private var friendlyDataBasis: String {
        switch insight.insightType {
        case .cyclePattern:
            let cycleCount = max(1, insight.dataPointsUsed / 2)
            return L10n.format(
                "Based on %lld cycles",
                defaultValue: "Based on %lld cycles",
                cycleCount
            )
        default:
            let weeks = max(1, insight.dataPointsUsed / 7)
            if weeks < 2 {
                return L10n.string(
                    "Based on initial data",
                    defaultValue: "Based on initial data"
                )
            }
            return L10n.format(
                "Based on %lld weeks of data",
                defaultValue: "Based on %lld weeks of data",
                weeks
            )
        }
    }

    private var friendlyConfidenceLabel: String {
        let pct = Int(insight.confidence * 100)
        if pct >= 75 {
            return L10n.string("Strong confidence", defaultValue: "Strong confidence")
        } else if pct >= 55 {
            return L10n.string("Moderate confidence", defaultValue: "Moderate confidence")
        } else {
            return L10n.string("Growing confidence", defaultValue: "Growing confidence")
        }
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
                    "This tab looks for patterns in the cycle, symptom, meal, supplement, and daily data you log. Confidence grows as you complete more cycles.",
                    defaultValue: "This tab looks for patterns in the cycle, symptom, meal, supplement, and daily data you log. Confidence grows as you complete more cycles.",
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
