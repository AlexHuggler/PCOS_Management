import SwiftUI
import SwiftData
import Charts

struct MealHistoryView: View {
    @Environment(\.modelContext) private var modelContext
    @State private var viewModel: MealViewModel?
    @State private var pendingDeleteMeal: MealEntry?
    @State private var showUndoToast = false
    @State private var selectedMeal: MealEntry?

    /// Meals grouped by day, sorted most recent first.
    private var groupedMeals: [(date: Date, meals: [MealEntry])] {
        guard let viewModel else { return [] }
        let meals = viewModel.fetchRecentMeals(days: 90)
        let calendar = Calendar.current
        let grouped = Dictionary(grouping: meals) { meal in
            calendar.startOfDay(for: meal.timestamp)
        }
        return grouped
            .sorted { $0.key > $1.key }
            .map { (date: $0.key, meals: $0.value.sorted { $0.timestamp < $1.timestamp }) }
    }

    var body: some View {
        ZStack {
            if AppTheme.usesPremiumEditorStyling {
                AppTheme.premiumEditorBackground
                    .ignoresSafeArea()
            }

            Group {
                if let viewModel {
                    let groups = groupedMeals
                    if groups.isEmpty {
                        if AppTheme.usesPremiumEditorStyling {
                            lunarEmptyState
                        } else {
                            AppEmptyStateView(
                                title: L10n.string("No Meals Logged", defaultValue: "No Meals Logged"),
                                message: L10n.string("Meals you log will appear here.", defaultValue: "Meals you log will appear here."),
                                systemImage: "fork.knife"
                            )
                            .frame(maxWidth: .infinity, maxHeight: .infinity)
                        }
                    } else {
                        if AppTheme.usesPremiumEditorStyling {
                            lunarMealHistoryContent(groups: groups, viewModel: viewModel)
                        } else {
                            standardMealHistoryContent(groups: groups, viewModel: viewModel)
                        }
                    }
                } else {
                    if AppTheme.usesPremiumEditorStyling {
                        lunarLoadingContent
                    } else {
                        List {
                            ForEach(0..<5, id: \.self) { _ in
                                SkeletonListRow()
                            }
                        }
                    }
                }
            }
        }
        .accessibilityIdentifier("screen.meal_history")
        .background {
            if AppTheme.usesPremiumEditorStyling {
                AppTheme.premiumEditorBackground
                    .ignoresSafeArea()
            }
        }
        .navigationTitle(AppTheme.usesPremiumEditorStyling ? "" : L10n.string("Meal History", defaultValue: "Meal History"))
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            if AppTheme.usesPremiumEditorStyling {
                ToolbarItem(placement: .principal) {
                    Text(L10n.string("Meal patterns", defaultValue: "Meal patterns"))
                        .appFont(.headline, weight: .semibold)
                        .foregroundStyle(AppTheme.primaryText)
                }
            }
        }
        .lunarMealHistoryNavigationBackground()
        .onAppear {
            if viewModel == nil {
                viewModel = MealViewModel(modelContext: modelContext)
            }
        }
        .lunarMealHistoryItemPresentation(item: $selectedMeal) { meal in
            MealDetailView(meal: meal)
        }
    }

    private func standardMealHistoryContent(
        groups: [(date: Date, meals: [MealEntry])],
        viewModel: MealViewModel
    ) -> some View {
        List {
            ForEach(groups, id: \.date) { group in
                Section {
                    ForEach(group.meals) { meal in
                        MealRow(meal: meal)
                            .contentShape(Rectangle())
                            .onTapGesture { selectedMeal = meal }
                            .swipeActions(edge: .trailing, allowsFullSwipe: true) {
                                Button(role: .destructive) {
                                    beginDelete(meal)
                                } label: {
                                    Label("Delete", systemImage: "trash")
                                }
                            }
                    }
                } header: {
                    Text(group.date, format: .dateTime.weekday(.wide).month(.wide).day())
                }
            }
        }
        .overlay(alignment: .bottom) {
            mealUndoToast(viewModel: viewModel)
        }
    }

    private var lunarEmptyState: some View {
        VStack(spacing: AppTheme.spacing16) {
            Image(systemName: "fork.knife.circle.fill")
                .font(.system(size: 46, weight: .semibold))
                .foregroundStyle(AppTheme.premiumEditorAccentGradient)
                .frame(width: 82, height: 82)
                .background(Circle().fill(AppTheme.premiumEditorRaisedSurface.opacity(0.88)))
                .overlay(Circle().stroke(AppTheme.premiumEditorBorderGradient, lineWidth: 1))

            VStack(spacing: AppTheme.spacing8) {
                Text(L10n.string("No meals logged", defaultValue: "No meals logged"))
                    .appFont(.title3, weight: .semibold)
                    .foregroundStyle(AppTheme.primaryText)
                Text(L10n.string(
                    "Meals you log will become pattern-ready here, including glycemic impact and post-meal notes.",
                    defaultValue: "Meals you log will become pattern-ready here, including glycemic impact and post-meal notes."
                ))
                .appFont(.subheadline)
                .foregroundStyle(AppTheme.secondaryText)
                .multilineTextAlignment(.center)
                .fixedSize(horizontal: false, vertical: true)
            }
        }
        .padding(AppTheme.spacing24)
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(AppTheme.premiumEditorBackground)
        .accessibilityIdentifier("meal_history.lunar.empty")
    }

    private var lunarLoadingContent: some View {
        ScrollView {
            VStack(spacing: AppTheme.spacing16) {
                ForEach(0..<5, id: \.self) { _ in
                    RoundedRectangle(cornerRadius: AppTheme.cornerRadiusLarge, style: .continuous)
                        .fill(AppTheme.premiumEditorRaisedSurface.opacity(0.76))
                        .frame(height: 118)
                        .redacted(reason: .placeholder)
                }
            }
            .padding(AppTheme.spacing16)
        }
        .background(AppTheme.premiumEditorBackground)
        .accessibilityIdentifier("meal_history.lunar.loading")
    }

    private func lunarMealHistoryContent(
        groups: [(date: Date, meals: [MealEntry])],
        viewModel: MealViewModel
    ) -> some View {
        let meals = groups.flatMap(\.meals)
        let giCounts = viewModel.giDistribution(days: 90)

        return ScrollView {
            VStack(alignment: .leading, spacing: AppTheme.spacing16) {
                lunarMealHistoryHeader(meals: meals, giCounts: giCounts)
                lunarMealDashboard(meals: meals, giCounts: giCounts)
                lunarGlycemicChartCard(giCounts: giCounts)
                lunarMacroAveragesCard(meals: meals)
                lunarFeedbackCard(meals: meals)
                lunarRecentMealsCard(groups: Array(groups.prefix(5)), viewModel: viewModel)
            }
            .padding(.horizontal, AppTheme.spacing16)
            .padding(.top, AppTheme.spacing12)
            .padding(.bottom, AppTheme.spacing24)
        }
        .scrollContentBackground(.hidden)
        .background(AppTheme.premiumEditorBackground)
        .overlay(alignment: .bottom) {
            mealUndoToast(viewModel: viewModel)
        }
        .accessibilityIdentifier("meal_history.lunar.surface")
    }

    private func lunarMealHistoryHeader(meals: [MealEntry], giCounts: [GlycemicImpact: Int]) -> some View {
        let latestMeal = meals.first
        let lowCount = giCounts[.low, default: 0]
        let highCount = giCounts[.high, default: 0]

        return VStack(alignment: .leading, spacing: AppTheme.spacing16) {
            HStack(alignment: .top, spacing: AppTheme.spacing12) {
                VStack(alignment: .leading, spacing: AppTheme.spacing8) {
                    Text(L10n.string("Find meal patterns", defaultValue: "Find meal patterns"))
                        .appFont(.largeTitle, weight: .semibold)
                        .foregroundStyle(AppTheme.primaryText)
                        .fixedSize(horizontal: false, vertical: true)
                    Text(L10n.string(
                        "Review meals beside glycemic impact, macros, and post-meal feedback so food data becomes useful without feeling judgmental.",
                        defaultValue: "Review meals beside glycemic impact, macros, and post-meal feedback so food data becomes useful without feeling judgmental."
                    ))
                    .appFont(.subheadline)
                    .foregroundStyle(AppTheme.secondaryText)
                    .fixedSize(horizontal: false, vertical: true)
                }

                Spacer(minLength: AppTheme.spacing8)

                Image(systemName: "fork.knife")
                    .font(.system(size: 22, weight: .semibold))
                    .foregroundStyle(AppTheme.premiumEditorCTAForeground)
                    .frame(width: 54, height: 54)
                    .background(Circle().fill(AppTheme.premiumEditorAccentGradient))
                    .shadow(color: AppTheme.premiumEditorSecondaryAccentColor.opacity(0.25), radius: 14, y: 8)
            }

            HStack(spacing: AppTheme.spacing8) {
                lunarSummaryPill(
                    title: L10n.string("Meals", defaultValue: "Meals"),
                    value: "\(meals.count)",
                    systemImage: "calendar.badge.clock"
                )
                lunarSummaryPill(
                    title: L10n.string("Low GI", defaultValue: "Low GI"),
                    value: "\(lowCount)",
                    systemImage: "leaf.fill"
                )
                lunarSummaryPill(
                    title: L10n.string("High GI", defaultValue: "High GI"),
                    value: "\(highCount)",
                    systemImage: "exclamationmark.triangle.fill"
                )
            }

            if let latestMeal {
                Text(L10n.format(
                    "Most recent: %@, logged as %@.",
                    defaultValue: "Most recent: %@, logged as %@.",
                    latestMeal.mealDescription,
                    latestMeal.glycemicImpact.displayName
                ))
                .appFont(.caption)
                .foregroundStyle(AppTheme.secondaryText)
                .fixedSize(horizontal: false, vertical: true)
            }
        }
        .padding(AppTheme.spacing16)
        .lunarMealHistoryCard()
        .accessibilityElement(children: .contain)
        .accessibilityIdentifier("meal_history.lunar.header")
    }

    private func lunarMealDashboard(meals: [MealEntry], giCounts: [GlycemicImpact: Int]) -> some View {
        let columns = [GridItem(.flexible()), GridItem(.flexible())]
        let feedbackCount = meals.filter { $0.postMealSymptomSeverity != nil }.count
        let importedCount = meals.filter { $0.sourceLabel != nil || $0.barcode != nil || $0.nutritionImportID != nil }.count

        return LazyVGrid(columns: columns, spacing: AppTheme.spacing12) {
            lunarMetricTile(
                title: L10n.string("Most common", defaultValue: "Most common"),
                value: mostCommonMealType(in: meals)?.displayName ?? L10n.string("N/A", defaultValue: "N/A"),
                subtitle: L10n.string("Meal type", defaultValue: "Meal type"),
                systemImage: "clock.fill",
                accent: AppTheme.premiumEditorSecondaryAccentColor
            )
            lunarMetricTile(
                title: L10n.string("Low GI share", defaultValue: "Low GI share"),
                value: percentageString(numerator: giCounts[.low, default: 0], denominator: meals.count),
                subtitle: L10n.string("Last 90 days", defaultValue: "Last 90 days"),
                systemImage: "leaf.fill",
                accent: AppTheme.premiumEditorAccentColor
            )
            lunarMetricTile(
                title: L10n.string("Feedback", defaultValue: "Feedback"),
                value: "\(feedbackCount)",
                subtitle: L10n.string("Post-meal notes", defaultValue: "Post-meal notes"),
                systemImage: "heart.text.square.fill",
                accent: AppTheme.lavenderAccent
            )
            lunarMetricTile(
                title: L10n.string("Nutrition imports", defaultValue: "Nutrition imports"),
                value: "\(importedCount)",
                subtitle: L10n.string("Reviewed items", defaultValue: "Reviewed items"),
                systemImage: "barcode.viewfinder",
                accent: AppTheme.sage
            )
        }
        .accessibilityIdentifier("meal_history.lunar.dashboard")
    }

    private func lunarMetricTile(
        title: String,
        value: String,
        subtitle: String,
        systemImage: String,
        accent: Color
    ) -> some View {
        VStack(alignment: .leading, spacing: AppTheme.spacing8) {
            Image(systemName: systemImage)
                .font(.system(size: 14, weight: .semibold))
                .foregroundStyle(accent)
                .frame(width: 30, height: 30)
                .background(Circle().fill(accent.opacity(0.14)))

            VStack(alignment: .leading, spacing: AppTheme.spacing4) {
                Text(title)
                    .appFont(.caption, weight: .semibold)
                    .foregroundStyle(AppTheme.secondaryText)
                    .lineLimit(2)
                Text(value)
                    .appFont(.title3, weight: .semibold)
                    .foregroundStyle(AppTheme.primaryText)
                    .lineLimit(1)
                    .minimumScaleFactor(0.72)
                Text(subtitle)
                    .appFont(.caption2)
                    .foregroundStyle(AppTheme.secondaryText)
                    .lineLimit(2)
            }
        }
        .frame(maxWidth: .infinity, minHeight: 128, alignment: .leading)
        .padding(AppTheme.spacing12)
        .lunarMealHistoryCard()
    }

    private func lunarGlycemicChartCard(giCounts: [GlycemicImpact: Int]) -> some View {
        VStack(alignment: .leading, spacing: AppTheme.spacing12) {
            lunarSectionHeader(
                title: L10n.string("Glycemic impact", defaultValue: "Glycemic impact"),
                subtitle: L10n.string("Distribution across recent meals", defaultValue: "Distribution across recent meals"),
                systemImage: "chart.bar.fill"
            )

            Chart {
                ForEach(GlycemicImpact.allCases) { impact in
                    BarMark(
                        x: .value(L10n.string("Impact", defaultValue: "Impact"), shortGILabel(for: impact)),
                        y: .value(L10n.string("Meals", defaultValue: "Meals"), giCounts[impact, default: 0])
                    )
                    .cornerRadius(8)
                    .foregroundStyle(giColor(for: impact))
                }
            }
            .chartYAxis {
                AxisMarks { _ in
                    AxisGridLine().foregroundStyle(AppTheme.premiumEditorBorder.opacity(0.42))
                    AxisValueLabel().foregroundStyle(AppTheme.secondaryText)
                }
            }
            .chartXAxis {
                AxisMarks { _ in
                    AxisValueLabel().foregroundStyle(AppTheme.secondaryText)
                }
            }
            .frame(height: 178)
            .accessibilityIdentifier("meal_history.lunar.gi_chart")
        }
        .padding(AppTheme.spacing16)
        .lunarMealHistoryCard()
    }

    private func lunarMacroAveragesCard(meals: [MealEntry]) -> some View {
        let carbs = average(meals.compactMap(\.carbsGrams))
        let protein = average(meals.compactMap(\.proteinGrams))
        let fat = average(meals.compactMap(\.fatGrams))

        return VStack(alignment: .leading, spacing: AppTheme.spacing12) {
            lunarSectionHeader(
                title: L10n.string("Macro snapshot", defaultValue: "Macro snapshot"),
                subtitle: L10n.string("Average logged grams per meal", defaultValue: "Average logged grams per meal"),
                systemImage: "chart.pie.fill"
            )

            HStack(spacing: AppTheme.spacing8) {
                lunarMacroPill(title: L10n.string("Carbs", defaultValue: "Carbs"), value: carbs, accent: AppTheme.premiumEditorWarningAccentColor)
                lunarMacroPill(title: L10n.string("Protein", defaultValue: "Protein"), value: protein, accent: AppTheme.premiumEditorAccentColor)
                lunarMacroPill(title: L10n.string("Fat", defaultValue: "Fat"), value: fat, accent: AppTheme.premiumEditorSecondaryAccentColor)
            }

            Text(L10n.string(
                "Macro averages only include meals where grams were logged or imported.",
                defaultValue: "Macro averages only include meals where grams were logged or imported."
            ))
            .appFont(.caption)
            .foregroundStyle(AppTheme.secondaryText)
            .fixedSize(horizontal: false, vertical: true)
        }
        .padding(AppTheme.spacing16)
        .lunarMealHistoryCard()
        .accessibilityElement(children: .contain)
        .accessibilityIdentifier("meal_history.lunar.macro_card")
    }

    private func lunarFeedbackCard(meals: [MealEntry]) -> some View {
        let severities = meals.compactMap(\.postMealSymptomSeverity)
        let averageSeverity = average(severities.map(Double.init))

        return VStack(alignment: .leading, spacing: AppTheme.spacing12) {
            lunarSectionHeader(
                title: L10n.string("Post-meal feedback", defaultValue: "Post-meal feedback"),
                subtitle: L10n.string("Symptoms and energy after meals", defaultValue: "Symptoms and energy after meals"),
                systemImage: "sparkles"
            )

            HStack(spacing: AppTheme.spacing12) {
                VStack(alignment: .leading, spacing: AppTheme.spacing4) {
                    Text(averageSeverity.map { String(format: "%.1f", $0) } ?? L10n.string("N/A", defaultValue: "N/A"))
                        .appFont(.title2, weight: .semibold)
                        .foregroundStyle(AppTheme.primaryText)
                    Text(L10n.string("Avg. severity", defaultValue: "Avg. severity"))
                        .appFont(.caption)
                        .foregroundStyle(AppTheme.secondaryText)
                }

                Spacer()

                Text(L10n.format(
                    "%d meals with feedback",
                    defaultValue: "%d meals with feedback",
                    severities.count
                ))
                .appFont(.caption, weight: .semibold)
                .foregroundStyle(AppTheme.premiumEditorAccentColor)
                .padding(.horizontal, AppTheme.spacing12)
                .padding(.vertical, AppTheme.spacing8)
                .background(Capsule().fill(AppTheme.premiumEditorAccentColor.opacity(0.12)))
            }

            Text(feedbackInsight(averageSeverity: averageSeverity))
                .appFont(.caption)
                .foregroundStyle(AppTheme.secondaryText)
                .fixedSize(horizontal: false, vertical: true)
        }
        .padding(AppTheme.spacing16)
        .lunarMealHistoryCard()
        .accessibilityElement(children: .contain)
        .accessibilityIdentifier("meal_history.lunar.feedback")
    }

    private func lunarRecentMealsCard(
        groups: [(date: Date, meals: [MealEntry])],
        viewModel: MealViewModel
    ) -> some View {
        VStack(alignment: .leading, spacing: AppTheme.spacing12) {
            lunarSectionHeader(
                title: L10n.string("Recent meals", defaultValue: "Recent meals"),
                subtitle: L10n.string("Tap a meal for details", defaultValue: "Tap a meal for details"),
                systemImage: "clock.arrow.circlepath"
            )

            VStack(spacing: AppTheme.spacing12) {
                ForEach(groups, id: \.date) { group in
                    VStack(alignment: .leading, spacing: AppTheme.spacing8) {
                        Text(group.date, format: .dateTime.weekday(.wide).month(.wide).day())
                            .appFont(.caption, weight: .semibold)
                            .foregroundStyle(AppTheme.secondaryText)

                        ForEach(group.meals.prefix(4)) { meal in
                            lunarMealRow(meal, viewModel: viewModel)
                        }
                    }
                }
            }
        }
        .padding(AppTheme.spacing16)
        .lunarMealHistoryCard()
        .accessibilityElement(children: .contain)
        .accessibilityIdentifier("meal_history.lunar.recent_meals")
    }

    private func lunarMealRow(_ meal: MealEntry, viewModel: MealViewModel) -> some View {
        HStack(spacing: AppTheme.spacing12) {
            Image(systemName: meal.mealType.systemImage)
                .font(.system(size: 16, weight: .semibold))
                .foregroundStyle(giColor(for: meal.glycemicImpact))
                .frame(width: 36, height: 36)
                .background(Circle().fill(giColor(for: meal.glycemicImpact).opacity(0.14)))

            VStack(alignment: .leading, spacing: AppTheme.spacing4) {
                Text(meal.mealDescription)
                    .appFont(.subheadline, weight: .semibold)
                    .foregroundStyle(AppTheme.primaryText)
                    .lineLimit(2)
                HStack(spacing: AppTheme.spacing8) {
                    Text(meal.timestamp, format: .dateTime.hour().minute())
                    Text(meal.mealType.displayName)
                    if meal.sourceLabel != nil || meal.barcode != nil {
                        Text(L10n.string("Imported", defaultValue: "Imported"))
                    }
                }
                .appFont(.caption2)
                .foregroundStyle(AppTheme.secondaryText)
                .lineLimit(1)
            }

            Spacer()

            Text(shortGILabel(for: meal.glycemicImpact))
                .appFont(.caption2, weight: .semibold)
                .foregroundStyle(giColor(for: meal.glycemicImpact))
                .padding(.horizontal, AppTheme.spacing8)
                .padding(.vertical, AppTheme.spacing4)
                .background(Capsule().fill(giColor(for: meal.glycemicImpact).opacity(0.12)))

            Button(role: .destructive) {
                beginDelete(meal)
            } label: {
                Image(systemName: "trash")
                    .font(.system(size: 13, weight: .semibold))
                    .foregroundStyle(AppTheme.premiumEditorWarningAccentColor)
                    .frame(width: 32, height: 32)
                    .background(Circle().fill(AppTheme.premiumEditorWarningAccentColor.opacity(0.12)))
            }
            .buttonStyle(.plain)
            .accessibilityLabel(L10n.string("Delete meal", defaultValue: "Delete meal"))
        }
        .padding(AppTheme.spacing8)
        .background(
            RoundedRectangle(cornerRadius: AppTheme.cornerRadiusSmall, style: .continuous)
                .fill(AppTheme.premiumEditorSurface.opacity(0.74))
        )
        .overlay(
            RoundedRectangle(cornerRadius: AppTheme.cornerRadiusSmall, style: .continuous)
                .stroke(AppTheme.premiumEditorBorder.opacity(0.56), lineWidth: 0.8)
        )
        .contentShape(Rectangle())
        .onTapGesture { selectedMeal = meal }
        .accessibilityIdentifier("meal_history.lunar.row.\(meal.id.uuidString)")
    }

    private func lunarSummaryPill(title: String, value: String, systemImage: String) -> some View {
        HStack(spacing: AppTheme.spacing8) {
            Image(systemName: systemImage)
                .font(.system(size: 12, weight: .semibold))
                .foregroundStyle(AppTheme.premiumEditorAccentColor)
            VStack(alignment: .leading, spacing: 1) {
                Text(title)
                    .appFont(.caption2)
                    .foregroundStyle(AppTheme.secondaryText)
                Text(value)
                    .appFont(.caption, weight: .semibold)
                    .foregroundStyle(AppTheme.primaryText)
                    .lineLimit(1)
                    .minimumScaleFactor(0.75)
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(.horizontal, AppTheme.spacing8)
        .padding(.vertical, AppTheme.spacing8)
        .background(Capsule().fill(AppTheme.premiumEditorSurface.opacity(0.76)))
        .overlay(Capsule().stroke(AppTheme.premiumEditorBorder.opacity(0.56), lineWidth: 0.8))
    }

    private func lunarSectionHeader(title: String, subtitle: String, systemImage: String) -> some View {
        HStack(alignment: .top, spacing: AppTheme.spacing12) {
            Image(systemName: systemImage)
                .font(.system(size: 14, weight: .semibold))
                .foregroundStyle(AppTheme.premiumEditorAccentColor)
                .frame(width: 32, height: 32)
                .background(Circle().fill(AppTheme.premiumEditorAccentColor.opacity(0.12)))

            VStack(alignment: .leading, spacing: 2) {
                Text(title)
                    .appFont(.headline, weight: .semibold)
                    .foregroundStyle(AppTheme.primaryText)
                    .fixedSize(horizontal: false, vertical: true)
                Text(subtitle)
                    .appFont(.caption)
                    .foregroundStyle(AppTheme.secondaryText)
                    .fixedSize(horizontal: false, vertical: true)
            }

            Spacer(minLength: 0)
        }
    }

    private func lunarMacroPill(title: String, value: Double?, accent: Color) -> some View {
        VStack(alignment: .leading, spacing: AppTheme.spacing4) {
            Text(value.map { "\(Int($0.rounded()))g" } ?? L10n.string("N/A", defaultValue: "N/A"))
                .appFont(.headline, weight: .semibold)
                .foregroundStyle(AppTheme.primaryText)
                .lineLimit(1)
                .minimumScaleFactor(0.75)
            Text(title)
                .appFont(.caption2, weight: .semibold)
                .foregroundStyle(AppTheme.secondaryText)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(AppTheme.spacing8)
        .background(
            RoundedRectangle(cornerRadius: AppTheme.cornerRadiusSmall, style: .continuous)
                .fill(accent.opacity(0.1))
        )
        .overlay(
            RoundedRectangle(cornerRadius: AppTheme.cornerRadiusSmall, style: .continuous)
                .stroke(accent.opacity(0.34), lineWidth: 0.8)
        )
    }

    @ViewBuilder
    private func mealUndoToast(viewModel: MealViewModel) -> some View {
        if showUndoToast, pendingDeleteMeal != nil {
            UndoToast(
                message: L10n.string("Meal entry deleted", defaultValue: "Meal entry deleted"),
                onUndo: {
                    withAnimation {
                        pendingDeleteMeal = nil
                        showUndoToast = false
                    }
                },
                onExpire: {
                    if let meal = pendingDeleteMeal {
                        viewModel.deleteMeal(meal)
                    }
                    withAnimation {
                        pendingDeleteMeal = nil
                        showUndoToast = false
                    }
                }
            )
            .padding()
        }
    }

    private func beginDelete(_ meal: MealEntry) {
        pendingDeleteMeal = meal
        withAnimation {
            showUndoToast = true
        }
    }

    private func mostCommonMealType(in meals: [MealEntry]) -> MealType? {
        Dictionary(grouping: meals, by: \.mealType)
            .max { $0.value.count < $1.value.count }?
            .key
    }

    private func average(_ values: [Double]) -> Double? {
        guard !values.isEmpty else { return nil }
        return values.reduce(0, +) / Double(values.count)
    }

    private func percentageString(numerator: Int, denominator: Int) -> String {
        guard denominator > 0 else { return L10n.string("N/A", defaultValue: "N/A") }
        return "\(Int((Double(numerator) / Double(denominator) * 100).rounded()))%"
    }

    private func giColor(for impact: GlycemicImpact) -> Color {
        switch impact {
        case .low:
            AppTheme.premiumEditorAccentColor
        case .medium:
            AppTheme.premiumEditorSecondaryAccentColor
        case .high:
            AppTheme.premiumEditorWarningAccentColor
        }
    }

    private func feedbackInsight(averageSeverity: Double?) -> String {
        guard let averageSeverity else {
            return L10n.string(
                "Add quick post-meal feedback to help connect food, energy, mood, and symptoms over time.",
                defaultValue: "Add quick post-meal feedback to help connect food, energy, mood, and symptoms over time."
            )
        }

        if averageSeverity >= 3 {
            return L10n.string(
                "Post-meal symptoms are trending moderate or higher. Review meal type, timing, and macros before drawing conclusions.",
                defaultValue: "Post-meal symptoms are trending moderate or higher. Review meal type, timing, and macros before drawing conclusions."
            )
        }

        return L10n.string(
            "Post-meal feedback is currently gentle overall. Keep logging to see which meals feel most stable.",
            defaultValue: "Post-meal feedback is currently gentle overall. Keep logging to see which meals feel most stable."
        )
    }

    private func shortGILabel(for impact: GlycemicImpact) -> String {
        switch impact {
        case .low:
            L10n.string("Low", defaultValue: "Low")
        case .medium:
            L10n.string("Med", defaultValue: "Med")
        case .high:
            L10n.string("High", defaultValue: "High")
        }
    }
}

private extension View {
    @ViewBuilder
    func lunarMealHistoryItemPresentation<Item: Identifiable, Destination: View>(
        item: Binding<Item?>,
        @ViewBuilder destination: @escaping (Item) -> Destination
    ) -> some View {
        if AppTheme.usesImmersivePresentation {
            fullScreenCover(item: item, content: destination)
        } else {
            sheet(item: item, content: destination)
        }
    }

    @ViewBuilder
    func lunarMealHistoryNavigationBackground() -> some View {
        if AppTheme.usesPremiumEditorStyling {
            toolbarBackground(AppTheme.premiumEditorBackground, for: .navigationBar)
                .toolbarBackground(.visible, for: .navigationBar)
        } else {
            self
        }
    }

    func lunarMealHistoryCard() -> some View {
        background(
            RoundedRectangle(cornerRadius: AppTheme.cornerRadiusLarge, style: .continuous)
                .fill(
                    LinearGradient(
                        colors: [
                            AppTheme.premiumEditorRaisedSurface.opacity(0.9),
                            AppTheme.premiumEditorSurface.opacity(0.78),
                            AppTheme.premiumEditorBackground.opacity(0.9)
                        ],
                        startPoint: .topLeading,
                        endPoint: .bottomTrailing
                    )
                )
        )
        .overlay(
            RoundedRectangle(cornerRadius: AppTheme.cornerRadiusLarge, style: .continuous)
                .stroke(AppTheme.premiumEditorBorderGradient, lineWidth: 0.85)
        )
        .shadow(color: AppTheme.cardShadowColor, radius: 18, y: 12)
    }
}

// MARK: - Meal Row

private struct MealRow: View {
    let meal: MealEntry

    var body: some View {
        HStack(spacing: AppTheme.spacing12) {
            // Meal type icon
            Image(systemName: meal.mealType.systemImage)
                .appFont(.title3)
                .foregroundStyle(AppTheme.sage)
                .frame(width: 32, height: 32)

            // Description and time
            VStack(alignment: .leading, spacing: AppTheme.spacing4) {
                Text(meal.mealDescription)
                    .appFont(.subheadline, weight: .medium)
                    .lineLimit(2)

                Text(meal.timestamp, format: .dateTime.hour().minute())
                    .appFont(.caption)
                    .foregroundStyle(.secondary)
            }

            Spacer()

            // GI colored capsule
            Text(giLabel(for: meal.glycemicImpact))
                .appFont(.caption2, weight: .semibold)
                .padding(.horizontal, 8)
                .padding(.vertical, 4)
                .background(
                    Capsule()
                        .fill(giColor(for: meal.glycemicImpact).opacity(0.2))
                )
                .foregroundStyle(giColor(for: meal.glycemicImpact))

            // Photo thumbnail
            if let photoData = meal.photoData,
               let uiImage = UIImage(data: photoData) {
                Image(uiImage: uiImage)
                    .resizable()
                    .scaledToFill()
                    .frame(width: 40, height: 40)
                    .clipShape(RoundedRectangle(cornerRadius: 6))
            }
        }
        .padding(.vertical, AppTheme.spacing4)
    }

    private func giColor(for impact: GlycemicImpact) -> Color {
        switch impact {
        case .low: .green
        case .medium: .orange
        case .high: AppTheme.coralAccent
        }
    }

    private func giLabel(for impact: GlycemicImpact) -> String {
        switch impact {
        case .low: L10n.string("Low", defaultValue: "Low")
        case .medium: L10n.string("Med", defaultValue: "Med")
        case .high: L10n.string("High", defaultValue: "High")
        }
    }
}

#Preview {
    MealHistoryView()
        .modelContainer(for: MealEntry.self, inMemory: true)
}
