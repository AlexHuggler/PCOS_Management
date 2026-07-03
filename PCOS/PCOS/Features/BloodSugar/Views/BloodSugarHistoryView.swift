import SwiftUI
import SwiftData
import Charts

struct BloodSugarHistoryView: View {
    @Environment(\.modelContext) private var modelContext
    @Environment(AppState.self) private var appState
    @ScaledMetric(relativeTo: .subheadline) private var timeColumnIdealWidth: CGFloat = 70
    @State private var viewModel: BloodSugarViewModel?

    var body: some View {
        ZStack {
            if AppTheme.usesPremiumEditorStyling {
                AppTheme.premiumEditorBackground
                    .ignoresSafeArea()
            }

            Group {
                if let viewModel {
                    let readings = viewModel.fetchRecentReadings(days: 90)
                    if readings.isEmpty {
                        if AppTheme.usesPremiumEditorStyling {
                            lunarEmptyState
                        } else {
                            emptyState
                        }
                    } else {
                        if AppTheme.usesPremiumEditorStyling {
                            lunarHistoryContent(readings: readings, viewModel: viewModel)
                        } else {
                            historyContent(readings: readings, viewModel: viewModel)
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
                        .listStyle(.insetGrouped)
                    }
                }
            }
        }
        .accessibilityIdentifier("screen.blood_sugar_history")
        .background {
            if AppTheme.usesPremiumEditorStyling {
                AppTheme.premiumEditorBackground
                    .ignoresSafeArea()
            }
        }
        .navigationTitle(AppTheme.usesPremiumEditorStyling ? "" : localized("Blood Sugar History", defaultValue: "Blood Sugar History"))
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            if AppTheme.usesPremiumEditorStyling {
                ToolbarItem(placement: .principal) {
                    Text(localized("Blood sugar trends", defaultValue: "Blood sugar trends"))
                        .appFont(.headline, weight: .semibold)
                        .foregroundStyle(AppTheme.primaryText)
                }
            }
        }
        .lunarBloodSugarHistoryNavigationBackground()
        .onAppear {
            if viewModel == nil {
                viewModel = BloodSugarViewModel(modelContext: modelContext)
            }
        }
    }

    // MARK: - Subviews

    private func historyContent(readings: [BloodSugarReading], viewModel: BloodSugarViewModel) -> some View {
        let dailyAverages = viewModel.dailyGlucoseAverages(days: 30)
        let trends = viewModel.sevenDayVsThirtyDayTrend()
        let phaseAverages = viewModel.cyclePhaseComparison(days: 90)
        let spikeSamples = viewModel.postMealSpikePatterns(days: 30).sorted { $0.date > $1.date }
        let irMetrics = viewModel.insulinResistanceMetrics(days: 30)

        return List {
            Section {
                irDashboard(metrics: irMetrics)
            } header: {
                Text(localized("Insulin Resistance Indicators", defaultValue: "Insulin Resistance Indicators"))
            }

            Section {
                if dailyAverages.isEmpty {
                    Text(localized(
                        "Log readings across multiple days to see your daily trend.",
                        defaultValue: "Log readings across multiple days to see your daily trend."
                    ))
                        .appFont(.caption)
                        .foregroundStyle(.secondary)
                } else {
                    Chart {
                        ForEach(dailyAverages, id: \.date) { point in
                            LineMark(
                                x: .value(localized("Date", defaultValue: "Date"), point.date),
                                y: .value(localized("mg/dL", defaultValue: "mg/dL"), point.average)
                            )
                            .interpolationMethod(.catmullRom)
                            .foregroundStyle(AppTheme.accentColor)

                            PointMark(
                                x: .value(localized("Date", defaultValue: "Date"), point.date),
                                y: .value(localized("mg/dL", defaultValue: "mg/dL"), point.average)
                            )
                            .foregroundStyle(AppTheme.accentColor)
                        }

                        RuleMark(y: .value(localized("Elevated", defaultValue: "Elevated"), 140))
                            .foregroundStyle(.orange.opacity(0.5))
                            .lineStyle(StrokeStyle(lineWidth: 1, dash: [4, 3]))
                    }
                    .frame(height: 180)
                }
            } header: {
                Text(localized("Daily Glucose (30 days)", defaultValue: "Daily Glucose (30 days)"))
            }

            Section {
                trendComparisonView(trends: trends)
            } header: {
                Text(localized("7-day vs 30-day Trend", defaultValue: "7-day vs 30-day Trend"))
            }

            Section {
                if phaseAverages.isEmpty {
                    Text(localized(
                        "Needs blood sugar and cycle data in the same period.",
                        defaultValue: "Needs blood sugar and cycle data in the same period."
                    ))
                        .appFont(.caption)
                        .foregroundStyle(.secondary)
                } else {
                    Chart {
                        ForEach(phaseAverages) { entry in
                            BarMark(
                                x: .value(localized("Phase", defaultValue: "Phase"), entry.phase.displayName),
                                y: .value(localized("Average mg/dL", defaultValue: "Average mg/dL"), entry.average)
                            )
                            .foregroundStyle(AppTheme.sage)
                            .annotation(position: .top) {
                                Text("\(Int(entry.average.rounded()))")
                                    .appFont(.caption2)
                                    .foregroundStyle(.secondary)
                            }
                        }
                    }
                    .frame(height: 180)
                }
            } header: {
                Text(localized("Glucose by Cycle Phase", defaultValue: "Glucose by Cycle Phase"))
            }

            Section {
                if spikeSamples.isEmpty {
                    Text(localized(
                        "Log paired before-meal and after-meal readings to see spike patterns.",
                        defaultValue: "Log paired before-meal and after-meal readings to see spike patterns."
                    ))
                        .appFont(.caption)
                        .foregroundStyle(.secondary)
                } else {
                    let chartSamples = Array(spikeSamples.prefix(12)).reversed()
                    Chart {
                        ForEach(chartSamples) { sample in
                            BarMark(
                                x: .value(localized("Date", defaultValue: "Date"), sample.date),
                                y: .value(localized("Spike", defaultValue: "Spike"), sample.spike)
                            )
                            .foregroundStyle(sample.spike >= 0 ? AppTheme.coralAccent : AppTheme.sage)
                        }
                    }
                    .frame(height: 170)

                    ForEach(spikeSamples.prefix(5)) { sample in
                        HStack {
                            VStack(alignment: .leading, spacing: 2) {
                                Text(sample.mealContext.capitalized)
                                    .appFont(.subheadline)
                                    .lineLimit(2)
                                    .fixedSize(horizontal: false, vertical: true)
                                Text(sample.date, format: .dateTime.month().day())
                                    .appFont(.caption)
                                    .foregroundStyle(.secondary)
                            }
                            Spacer()
                            Text("\(Int(sample.spike.rounded())) \(localized("mg/dL", defaultValue: "mg/dL"))")
                                .appFont(.subheadline)
                                .foregroundStyle(sample.spike >= 0 ? AppTheme.coralAccent : AppTheme.sage)
                        }
                    }
                }
            } header: {
                Text(localized("Post-Meal Spike Patterns", defaultValue: "Post-Meal Spike Patterns"))
            }

            ForEach(groupedByDay(readings), id: \.key) { day, dayReadings in
                Section {
                    ForEach(dayReadings) { reading in
                        readingRow(reading)
                    }
                    .onDelete { offsets in
                        for index in offsets {
                            viewModel.deleteReading(dayReadings[index])
                        }
                    }
                } header: {
                    Text(day, style: .date)
                }
            }
        }
        .listStyle(.insetGrouped)
    }

    private var emptyState: some View {
        AppEmptyStateView(
            title: localized("No Readings Yet", defaultValue: "No Readings Yet"),
            message: localized(
                "Log your first blood sugar reading to start tracking.",
                defaultValue: "Log your first blood sugar reading to start tracking."
            ),
            systemImage: "drop.degreesign",
            animateSymbol: true
        )
    }

    private var lunarEmptyState: some View {
        VStack(spacing: AppTheme.spacing16) {
            Image(systemName: "drop.degreesign.fill")
                .font(.system(size: 42, weight: .semibold))
                .foregroundStyle(AppTheme.premiumEditorAccentGradient)
                .frame(width: 74, height: 74)
                .background(Circle().fill(AppTheme.premiumEditorRaisedSurface.opacity(0.88)))
                .overlay(Circle().stroke(AppTheme.premiumEditorBorderGradient, lineWidth: 1))

            VStack(spacing: AppTheme.spacing8) {
                Text(localized("No readings yet", defaultValue: "No readings yet"))
                    .appFont(.title3, weight: .semibold)
                    .foregroundStyle(AppTheme.primaryText)
                Text(localized(
                    "Log a few glucose readings to begin seeing gentle patterns beside meals and cycle phase.",
                    defaultValue: "Log a few glucose readings to begin seeing gentle patterns beside meals and cycle phase."
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
        .accessibilityIdentifier("blood_sugar_history.lunar.empty")
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
        .accessibilityIdentifier("blood_sugar_history.lunar.loading")
    }

    private func lunarHistoryContent(readings: [BloodSugarReading], viewModel: BloodSugarViewModel) -> some View {
        let dailyAverages = viewModel.dailyGlucoseAverages(days: 30)
        let trends = viewModel.sevenDayVsThirtyDayTrend()
        let phaseAverages = viewModel.cyclePhaseComparison(days: 90)
        let spikeSamples = viewModel.postMealSpikePatterns(days: 30).sorted { $0.date > $1.date }
        let irMetrics = viewModel.insulinResistanceMetrics(days: 30)
        let groupedReadings = Array(groupedByDay(readings).prefix(4))

        return ScrollView {
            VStack(alignment: .leading, spacing: AppTheme.spacing16) {
                lunarHistoryHeader(readings: readings, metrics: irMetrics, trends: trends)
                lunarMetricDashboard(metrics: irMetrics)
                lunarDailyTrendCard(dailyAverages: dailyAverages)
                lunarTrendComparisonCard(trends: trends)
                lunarPhaseCard(phaseAverages: phaseAverages)
                lunarSpikePatternsCard(spikeSamples: spikeSamples)
                lunarRecentReadingsCard(groupedReadings, viewModel: viewModel)
            }
            .padding(.horizontal, AppTheme.spacing16)
            .padding(.top, AppTheme.spacing12)
            .padding(.bottom, AppTheme.spacing24)
        }
        .scrollContentBackground(.hidden)
        .background(AppTheme.premiumEditorBackground)
        .accessibilityIdentifier("blood_sugar_history.lunar.surface")
    }

    private func lunarHistoryHeader(
        readings: [BloodSugarReading],
        metrics: InsulinResistanceMetrics,
        trends: (sevenDayAverage: Double?, thirtyDayAverage: Double?)
    ) -> some View {
        let latest = readings.first
        let delta: Double? = if let sevenDay = trends.sevenDayAverage, let thirtyDay = trends.thirtyDayAverage {
            sevenDay - thirtyDay
        } else {
            nil
        }

        return VStack(alignment: .leading, spacing: AppTheme.spacing16) {
            HStack(alignment: .top, spacing: AppTheme.spacing12) {
                VStack(alignment: .leading, spacing: AppTheme.spacing8) {
                    Text(localized("Find glucose patterns", defaultValue: "Find glucose patterns"))
                        .appFont(.largeTitle, weight: .semibold)
                        .foregroundStyle(AppTheme.primaryText)
                        .fixedSize(horizontal: false, vertical: true)
                    Text(localized(
                        "Review readings beside meals, cycle phase, and recent baseline shifts without over-reading a single number.",
                        defaultValue: "Review readings beside meals, cycle phase, and recent baseline shifts without over-reading a single number."
                    ))
                    .appFont(.subheadline)
                    .foregroundStyle(AppTheme.secondaryText)
                    .fixedSize(horizontal: false, vertical: true)
                }

                Spacer(minLength: AppTheme.spacing8)

                Image(systemName: "waveform.path.ecg")
                    .font(.system(size: 23, weight: .semibold))
                    .foregroundStyle(AppTheme.premiumEditorCTAForeground)
                    .frame(width: 52, height: 52)
                    .background(Circle().fill(AppTheme.premiumEditorAccentGradient))
                    .shadow(color: AppTheme.premiumEditorAccentColor.opacity(0.25), radius: 14, y: 8)
            }

            HStack(spacing: AppTheme.spacing8) {
                lunarSummaryPill(
                    title: localized("Readings", defaultValue: "Readings"),
                    value: "\(readings.count)",
                    systemImage: "drop.degreesign"
                )
                lunarSummaryPill(
                    title: localized("Latest", defaultValue: "Latest"),
                    value: latest.map { "\(Int($0.glucoseValue.rounded()))" } ?? localized("N/A", defaultValue: "N/A"),
                    systemImage: "clock"
                )
                lunarSummaryPill(
                    title: localized("Delta", defaultValue: "Delta"),
                    value: delta.map { "\($0 >= 0 ? "+" : "")\(Int($0.rounded()))" } ?? localized("N/A", defaultValue: "N/A"),
                    systemImage: "arrow.left.and.right"
                )
            }

            if let fastingAverage = metrics.fastingAverage {
                Text(String(
                    format: localized(
                        "Fasting average is tracking near %.0f mg/dL across the last month.",
                        defaultValue: "Fasting average is tracking near %.0f mg/dL across the last month."
                    ),
                    fastingAverage
                ))
                .appFont(.caption)
                .foregroundStyle(AppTheme.secondaryText)
                .fixedSize(horizontal: false, vertical: true)
            }
        }
        .padding(AppTheme.spacing16)
        .lunarBloodSugarHistoryCard()
        .accessibilityElement(children: .contain)
        .accessibilityIdentifier("blood_sugar_history.lunar.header")
    }

    private func lunarMetricDashboard(metrics: InsulinResistanceMetrics) -> some View {
        let columns = [GridItem(.flexible()), GridItem(.flexible())]

        return LazyVGrid(columns: columns, spacing: AppTheme.spacing12) {
            lunarMetricTile(
                title: localized("Fasting avg", defaultValue: "Fasting avg"),
                value: metrics.fastingAverage.map { "\(Int($0.rounded()))" } ?? localized("N/A", defaultValue: "N/A"),
                suffix: localized("mg/dL", defaultValue: "mg/dL"),
                systemImage: "sunrise.fill",
                accent: AppTheme.premiumEditorSecondaryAccentColor
            )
            lunarMetricTile(
                title: localized("Elevated rate", defaultValue: "Elevated rate"),
                value: "\(Int((metrics.elevatedReadingRate * 100).rounded()))",
                suffix: "%",
                systemImage: "chart.line.uptrend.xyaxis",
                accent: AppTheme.premiumEditorWarningAccentColor
            )
            lunarMetricTile(
                title: localized("Median spike", defaultValue: "Median spike"),
                value: metrics.medianPostMealSpike.map { "\(Int($0.rounded()))" } ?? localized("N/A", defaultValue: "N/A"),
                suffix: localized("mg/dL", defaultValue: "mg/dL"),
                systemImage: "bolt.fill",
                accent: AppTheme.softGoldAccent
            )
            lunarMetricTile(
                title: localized("Luteal shift", defaultValue: "Luteal shift"),
                value: metrics.lutealVsFollicularDelta.map { "\($0 >= 0 ? "+" : "")\(Int($0.rounded()))" } ?? localized("N/A", defaultValue: "N/A"),
                suffix: localized("mg/dL", defaultValue: "mg/dL"),
                systemImage: "moon.stars.fill",
                accent: AppTheme.lavenderAccent
            )
        }
        .accessibilityIdentifier("blood_sugar_history.lunar.dashboard")
    }

    private func lunarMetricTile(
        title: String,
        value: String,
        suffix: String,
        systemImage: String,
        accent: Color
    ) -> some View {
        VStack(alignment: .leading, spacing: AppTheme.spacing8) {
            HStack {
                Image(systemName: systemImage)
                    .font(.system(size: 14, weight: .semibold))
                    .foregroundStyle(accent)
                    .frame(width: 30, height: 30)
                    .background(Circle().fill(accent.opacity(0.14)))
                Spacer()
            }

            VStack(alignment: .leading, spacing: AppTheme.spacing4) {
                Text(title)
                    .appFont(.caption, weight: .semibold)
                    .foregroundStyle(AppTheme.secondaryText)
                    .lineLimit(2)
                HStack(alignment: .firstTextBaseline, spacing: 4) {
                    Text(value)
                        .appFont(.title2, weight: .semibold)
                        .foregroundStyle(AppTheme.primaryText)
                        .minimumScaleFactor(0.78)
                    Text(suffix)
                        .appFont(.caption)
                        .foregroundStyle(AppTheme.secondaryText)
                        .lineLimit(1)
                }
            }
        }
        .frame(maxWidth: .infinity, minHeight: 118, alignment: .leading)
        .padding(AppTheme.spacing12)
        .lunarBloodSugarHistoryCard()
    }

    private func lunarDailyTrendCard(dailyAverages: [(date: Date, average: Double)]) -> some View {
        VStack(alignment: .leading, spacing: AppTheme.spacing12) {
            lunarSectionHeader(
                title: localized("Daily glucose", defaultValue: "Daily glucose"),
                subtitle: localized("30-day average trend", defaultValue: "30-day average trend"),
                systemImage: "chart.xyaxis.line"
            )

            if dailyAverages.isEmpty {
                lunarPlaceholderText(localized(
                    "Log readings across multiple days to see your trend line.",
                    defaultValue: "Log readings across multiple days to see your trend line."
                ))
            } else {
                Chart {
                    ForEach(dailyAverages, id: \.date) { point in
                        LineMark(
                            x: .value(localized("Date", defaultValue: "Date"), point.date),
                            y: .value(localized("mg/dL", defaultValue: "mg/dL"), point.average)
                        )
                        .interpolationMethod(.catmullRom)
                        .foregroundStyle(AppTheme.premiumEditorAccentGradient)
                        .lineStyle(StrokeStyle(lineWidth: 3, lineCap: .round, lineJoin: .round))

                        PointMark(
                            x: .value(localized("Date", defaultValue: "Date"), point.date),
                            y: .value(localized("mg/dL", defaultValue: "mg/dL"), point.average)
                        )
                        .foregroundStyle(AppTheme.premiumEditorSecondaryAccentColor)
                    }

                    RuleMark(y: .value(localized("Elevated", defaultValue: "Elevated"), 140))
                        .foregroundStyle(AppTheme.premiumEditorWarningAccentColor.opacity(0.55))
                        .lineStyle(StrokeStyle(lineWidth: 1, dash: [5, 4]))
                }
                .chartYAxis {
                    AxisMarks { _ in
                        AxisGridLine().foregroundStyle(AppTheme.premiumEditorBorder.opacity(0.42))
                        AxisValueLabel().foregroundStyle(AppTheme.secondaryText)
                    }
                }
                .chartXAxis {
                    AxisMarks(values: .automatic(desiredCount: 4)) { _ in
                        AxisGridLine().foregroundStyle(AppTheme.premiumEditorBorder.opacity(0.3))
                        AxisValueLabel().foregroundStyle(AppTheme.secondaryText)
                    }
                }
                .frame(height: 190)
                .accessibilityIdentifier("blood_sugar_history.lunar.daily_chart")
            }
        }
        .padding(AppTheme.spacing16)
        .lunarBloodSugarHistoryCard()
    }

    private func lunarTrendComparisonCard(
        trends: (sevenDayAverage: Double?, thirtyDayAverage: Double?)
    ) -> some View {
        let sevenDay = trends.sevenDayAverage
        let thirtyDay = trends.thirtyDayAverage
        let delta: Double? = if let sevenDay, let thirtyDay { sevenDay - thirtyDay } else { nil }
        let insight = trendInsight(delta: delta)

        return VStack(alignment: .leading, spacing: AppTheme.spacing12) {
            lunarSectionHeader(
                title: localized("Baseline check", defaultValue: "Baseline check"),
                subtitle: localized("7 days vs. 30 days", defaultValue: "7 days vs. 30 days"),
                systemImage: "chart.line.uptrend.xyaxis"
            )

            HStack(spacing: AppTheme.spacing8) {
                lunarValueColumn(title: localized("7-day", defaultValue: "7-day"), value: sevenDay)
                lunarValueColumn(title: localized("30-day", defaultValue: "30-day"), value: thirtyDay)
                lunarDeltaColumn(delta: delta)
            }

            Text(insight)
                .appFont(.caption)
                .foregroundStyle(AppTheme.secondaryText)
                .fixedSize(horizontal: false, vertical: true)
        }
        .padding(AppTheme.spacing16)
        .lunarBloodSugarHistoryCard()
        .accessibilityElement(children: .contain)
        .accessibilityIdentifier("blood_sugar_history.lunar.trend")
    }

    private func lunarPhaseCard(phaseAverages: [CyclePhaseAverage]) -> some View {
        VStack(alignment: .leading, spacing: AppTheme.spacing12) {
            lunarSectionHeader(
                title: localized("Glucose by cycle phase", defaultValue: "Glucose by cycle phase"),
                subtitle: localized("Where patterns may shift", defaultValue: "Where patterns may shift"),
                systemImage: "moonphase.first.quarter"
            )

            if phaseAverages.isEmpty {
                lunarPlaceholderText(localized(
                    "Needs blood sugar and cycle data in the same period.",
                    defaultValue: "Needs blood sugar and cycle data in the same period."
                ))
            } else {
                Chart {
                    ForEach(phaseAverages) { entry in
                        BarMark(
                            x: .value(localized("Phase", defaultValue: "Phase"), entry.phase.displayName),
                            y: .value(localized("Average mg/dL", defaultValue: "Average mg/dL"), entry.average)
                        )
                        .cornerRadius(8)
                        .foregroundStyle(AppTheme.premiumEditorAccentGradient)
                        .annotation(position: .top) {
                            Text("\(Int(entry.average.rounded()))")
                                .appFont(.caption2, weight: .semibold)
                                .foregroundStyle(AppTheme.primaryText)
                        }
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
                .frame(height: 190)
                .accessibilityIdentifier("blood_sugar_history.lunar.phase_chart")
            }
        }
        .padding(AppTheme.spacing16)
        .lunarBloodSugarHistoryCard()
    }

    private func lunarSpikePatternsCard(spikeSamples: [PostMealSpikeSample]) -> some View {
        VStack(alignment: .leading, spacing: AppTheme.spacing12) {
            lunarSectionHeader(
                title: localized("Post-meal spike patterns", defaultValue: "Post-meal spike patterns"),
                subtitle: localized("Paired before and after readings", defaultValue: "Paired before and after readings"),
                systemImage: "fork.knife"
            )

            if spikeSamples.isEmpty {
                lunarPlaceholderText(localized(
                    "Log paired before-meal and after-meal readings to see meal response patterns.",
                    defaultValue: "Log paired before-meal and after-meal readings to see meal response patterns."
                ))
            } else {
                let chartSamples = Array(spikeSamples.prefix(8)).reversed()
                Chart {
                    ForEach(chartSamples) { sample in
                        BarMark(
                            x: .value(localized("Date", defaultValue: "Date"), sample.date),
                            y: .value(localized("Spike", defaultValue: "Spike"), sample.spike)
                        )
                        .cornerRadius(6)
                        .foregroundStyle(sample.spike >= 0 ? AppTheme.premiumEditorWarningAccentColor : AppTheme.premiumEditorAccentColor)
                    }
                }
                .chartYAxis {
                    AxisMarks { _ in
                        AxisGridLine().foregroundStyle(AppTheme.premiumEditorBorder.opacity(0.42))
                        AxisValueLabel().foregroundStyle(AppTheme.secondaryText)
                    }
                }
                .chartXAxis {
                    AxisMarks(values: .automatic(desiredCount: 3)) { _ in
                        AxisValueLabel().foregroundStyle(AppTheme.secondaryText)
                    }
                }
                .frame(height: 150)

                VStack(spacing: AppTheme.spacing8) {
                    ForEach(spikeSamples.prefix(3)) { sample in
                        HStack(spacing: AppTheme.spacing12) {
                            Image(systemName: "sparkles")
                                .foregroundStyle(AppTheme.premiumEditorSecondaryAccentColor)
                                .frame(width: 28, height: 28)
                                .background(Circle().fill(AppTheme.premiumEditorSecondaryAccentColor.opacity(0.14)))

                            VStack(alignment: .leading, spacing: 2) {
                                Text(sample.mealContext.capitalized)
                                    .appFont(.subheadline, weight: .semibold)
                                    .foregroundStyle(AppTheme.primaryText)
                                Text(sample.date, format: .dateTime.month().day())
                                    .appFont(.caption)
                                    .foregroundStyle(AppTheme.secondaryText)
                            }

                            Spacer()

                            Text("\(Int(sample.spike.rounded())) \(localized("mg/dL", defaultValue: "mg/dL"))")
                                .appFont(.subheadline, weight: .semibold)
                                .foregroundStyle(sample.spike >= 0 ? AppTheme.premiumEditorWarningAccentColor : AppTheme.premiumEditorAccentColor)
                        }
                    }
                }
            }
        }
        .padding(AppTheme.spacing16)
        .lunarBloodSugarHistoryCard()
        .accessibilityElement(children: .contain)
        .accessibilityIdentifier("blood_sugar_history.lunar.spike_patterns")
    }

    private func lunarRecentReadingsCard(
        _ groupedReadings: [(key: Date, value: [BloodSugarReading])],
        viewModel: BloodSugarViewModel
    ) -> some View {
        VStack(alignment: .leading, spacing: AppTheme.spacing12) {
            lunarSectionHeader(
                title: localized("Recent readings", defaultValue: "Recent readings"),
                subtitle: localized("Latest 90 days", defaultValue: "Latest 90 days"),
                systemImage: "clock.arrow.circlepath"
            )

            VStack(spacing: AppTheme.spacing8) {
                ForEach(groupedReadings, id: \.key) { day, readings in
                    VStack(alignment: .leading, spacing: AppTheme.spacing8) {
                        Text(day, style: .date)
                            .appFont(.caption, weight: .semibold)
                            .foregroundStyle(AppTheme.secondaryText)
                        ForEach(readings.prefix(3)) { reading in
                            lunarReadingRow(reading, viewModel: viewModel)
                        }
                    }
                }
            }
        }
        .padding(AppTheme.spacing16)
        .lunarBloodSugarHistoryCard()
        .accessibilityElement(children: .contain)
        .accessibilityIdentifier("blood_sugar_history.lunar.recent_readings")
    }

    private func lunarReadingRow(_ reading: BloodSugarReading, viewModel: BloodSugarViewModel) -> some View {
        HStack(spacing: AppTheme.spacing12) {
            VStack(alignment: .leading, spacing: 2) {
                Text(reading.timestamp, style: .time)
                    .appFont(.subheadline, weight: .semibold)
                    .foregroundStyle(AppTheme.primaryText)
                Text(reading.readingType.displayName)
                    .appFont(.caption)
                    .foregroundStyle(AppTheme.secondaryText)
                    .lineLimit(1)
            }

            Spacer()

            VStack(alignment: .trailing, spacing: 2) {
                HStack(alignment: .firstTextBaseline, spacing: 4) {
                    Text("\(Int(reading.glucoseValue.rounded()))")
                        .appFont(.headline, weight: .semibold)
                        .foregroundStyle(glucoseColor(for: reading.glucoseValue))
                    Text(localized("mg/dL", defaultValue: "mg/dL"))
                        .appFont(.caption2)
                        .foregroundStyle(AppTheme.secondaryText)
                }
                Text(glucoseRangeLabel(for: reading.glucoseValue))
                    .appFont(.caption2, weight: .semibold)
                    .foregroundStyle(glucoseColor(for: reading.glucoseValue))
            }

            Button(role: .destructive) {
                viewModel.deleteReading(reading)
            } label: {
                Image(systemName: "trash")
                    .font(.system(size: 13, weight: .semibold))
                    .foregroundStyle(AppTheme.premiumEditorWarningAccentColor)
                    .frame(width: 32, height: 32)
                    .background(Circle().fill(AppTheme.premiumEditorWarningAccentColor.opacity(0.12)))
            }
            .buttonStyle(.plain)
            .accessibilityLabel(localized("Delete reading", defaultValue: "Delete reading"))
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

    private func lunarPlaceholderText(_ text: String) -> some View {
        Text(text)
            .appFont(.subheadline)
            .foregroundStyle(AppTheme.secondaryText)
            .fixedSize(horizontal: false, vertical: true)
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(AppTheme.spacing12)
            .background(
                RoundedRectangle(cornerRadius: AppTheme.cornerRadiusSmall, style: .continuous)
                    .fill(AppTheme.premiumEditorSurface.opacity(0.64))
            )
    }

    private func lunarValueColumn(title: String, value: Double?) -> some View {
        VStack(alignment: .leading, spacing: AppTheme.spacing4) {
            Text(title)
                .appFont(.caption2, weight: .semibold)
                .foregroundStyle(AppTheme.secondaryText)
            Text(value.map { "\(Int($0.rounded()))" } ?? localized("N/A", defaultValue: "N/A"))
                .appFont(.title3, weight: .semibold)
                .foregroundStyle(AppTheme.primaryText)
            Text(localized("mg/dL", defaultValue: "mg/dL"))
                .appFont(.caption2)
                .foregroundStyle(AppTheme.secondaryText)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(AppTheme.spacing8)
        .background(
            RoundedRectangle(cornerRadius: AppTheme.cornerRadiusSmall, style: .continuous)
                .fill(AppTheme.premiumEditorSurface.opacity(0.74))
        )
        .overlay(
            RoundedRectangle(cornerRadius: AppTheme.cornerRadiusSmall, style: .continuous)
                .stroke(AppTheme.premiumEditorBorder.opacity(0.5), lineWidth: 0.8)
        )
    }

    private func lunarDeltaColumn(delta: Double?) -> some View {
        let color = (delta ?? 0) >= 0 ? AppTheme.premiumEditorWarningAccentColor : AppTheme.premiumEditorAccentColor

        return VStack(alignment: .leading, spacing: AppTheme.spacing4) {
            Text(localized("Delta", defaultValue: "Delta"))
                .appFont(.caption2, weight: .semibold)
                .foregroundStyle(AppTheme.secondaryText)
            Text(delta.map { "\($0 >= 0 ? "+" : "")\(Int($0.rounded()))" } ?? localized("N/A", defaultValue: "N/A"))
                .appFont(.title3, weight: .semibold)
                .foregroundStyle(color)
            Text(localized("mg/dL", defaultValue: "mg/dL"))
                .appFont(.caption2)
                .foregroundStyle(AppTheme.secondaryText)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(AppTheme.spacing8)
        .background(
            RoundedRectangle(cornerRadius: AppTheme.cornerRadiusSmall, style: .continuous)
                .fill(color.opacity(0.11))
        )
        .overlay(
            RoundedRectangle(cornerRadius: AppTheme.cornerRadiusSmall, style: .continuous)
                .stroke(color.opacity(0.38), lineWidth: 0.8)
        )
    }

    private func trendInsight(delta: Double?) -> String {
        guard let delta else {
            return localized(
                "More readings are needed before LunarComm compares your short-term and monthly baseline.",
                defaultValue: "More readings are needed before LunarComm compares your short-term and monthly baseline."
            )
        }

        if delta >= 0 {
            return localized(
                "Your recent average is running above your 30-day baseline. Treat this as a pattern to watch, not a diagnosis.",
                defaultValue: "Your recent average is running above your 30-day baseline. Treat this as a pattern to watch, not a diagnosis."
            )
        } else {
            return localized(
                "Your recent average is below your 30-day baseline, which may reflect meals, movement, cycle timing, or medication routines.",
                defaultValue: "Your recent average is below your 30-day baseline, which may reflect meals, movement, cycle timing, or medication routines."
            )
        }
    }

    private func irDashboard(metrics: InsulinResistanceMetrics) -> some View {
        VStack(spacing: AppTheme.spacing12) {
            HStack(spacing: AppTheme.spacing12) {
                BloodSugarMetricTile(
                    title: localized("Fasting Avg", defaultValue: "Fasting Avg"),
                    value: metrics.fastingAverage.map { "\(Int($0.rounded())) mg/dL" } ?? localized("N/A", defaultValue: "N/A")
                )
                BloodSugarMetricTile(
                    title: localized("Elevated Rate", defaultValue: "Elevated Rate"),
                    value: "\(Int((metrics.elevatedReadingRate * 100).rounded()))%"
                )
            }

            HStack(spacing: AppTheme.spacing12) {
                BloodSugarMetricTile(
                    title: localized("Median Spike", defaultValue: "Median Spike"),
                    value: metrics.medianPostMealSpike.map { "\(Int($0.rounded())) mg/dL" } ?? localized("N/A", defaultValue: "N/A")
                )
                BloodSugarMetricTile(
                    title: localized("Luteal- Follicular", defaultValue: "Luteal- Follicular"),
                    value: metrics.lutealVsFollicularDelta.map { "\(Int($0.rounded())) mg/dL" } ?? localized("N/A", defaultValue: "N/A")
                )
            }
        }
    }

    private func trendComparisonView(
        trends: (sevenDayAverage: Double?, thirtyDayAverage: Double?)
    ) -> some View {
        let sevenDay = trends.sevenDayAverage
        let thirtyDay = trends.thirtyDayAverage
        let delta: Double? = if let sevenDay, let thirtyDay { sevenDay - thirtyDay } else { nil }

        return VStack(alignment: .leading, spacing: AppTheme.spacing8) {
            HStack {
                VStack(alignment: .leading, spacing: 2) {
                    Text(localized("7-day avg", defaultValue: "7-day avg"))
                        .appFont(.caption)
                        .foregroundStyle(.secondary)
                    Text(sevenDay.map { "\(Int($0.rounded())) mg/dL" } ?? localized("N/A", defaultValue: "N/A"))
                        .appFont(.headline)
                }
                Spacer()
                VStack(alignment: .leading, spacing: 2) {
                    Text(localized("30-day avg", defaultValue: "30-day avg"))
                        .appFont(.caption)
                        .foregroundStyle(.secondary)
                    Text(thirtyDay.map { "\(Int($0.rounded())) mg/dL" } ?? localized("N/A", defaultValue: "N/A"))
                        .appFont(.headline)
                }
                Spacer()
                VStack(alignment: .leading, spacing: 2) {
                    Text(localized("Delta", defaultValue: "Delta"))
                        .appFont(.caption)
                        .foregroundStyle(.secondary)
                    Text(delta.map { "\(Int($0.rounded())) mg/dL" } ?? localized("N/A", defaultValue: "N/A"))
                        .appFont(.headline)
                        .foregroundStyle((delta ?? 0) >= 0 ? AppTheme.coralAccent : AppTheme.sage)
                }
            }

            if let delta {
                Text(
                    delta >= 0
                        ? localized(
                            "Short-term glucose is running above your 30-day baseline.",
                            defaultValue: "Short-term glucose is running above your 30-day baseline."
                        )
                        : localized(
                            "Short-term glucose is below your 30-day baseline.",
                            defaultValue: "Short-term glucose is below your 30-day baseline."
                        )
                )
                .appFont(.caption)
                .foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)
            }
        }
    }

    private func readingRow(_ reading: BloodSugarReading) -> some View {
        HStack(spacing: AppTheme.spacing12) {
            // Time
            Text(reading.timestamp, style: .time)
                .appFont(.subheadline)
                .foregroundStyle(.secondary)
                .lineLimit(1)
                .minimumScaleFactor(0.8)
                .frame(minWidth: timeColumnIdealWidth * 0.8, idealWidth: timeColumnIdealWidth, alignment: .leading)

            // Glucose value — color-coded
            Text("\(Int(reading.glucoseValue))")
                .appFont(.title3, weight: .semibold)
                .foregroundStyle(glucoseColor(for: reading.glucoseValue))

            Text(localized("mg/dL", defaultValue: "mg/dL"))
                .appFont(.caption)
                .foregroundStyle(.secondary)

            Text(glucoseRangeLabel(for: reading.glucoseValue))
                .appFont(.caption2)
                .foregroundStyle(glucoseColor(for: reading.glucoseValue))

            Spacer()

            VStack(alignment: .trailing, spacing: 4) {
                Text(reading.readingType.displayName)
                    .appFont(.caption2, weight: .medium)
                    .lineLimit(1)
                    .minimumScaleFactor(0.8)
                    .padding(.horizontal, 8)
                    .padding(.vertical, 4)
                    .background(
                        Capsule()
                            .fill(AppTheme.accentColor.opacity(AppTheme.opacityLight))
                    )
                    .foregroundStyle(AppTheme.accentColor)

                if reading.fromHealthKit {
                    Text(localized("Apple Health", defaultValue: "Apple Health"))
                        .appFont(.caption2, weight: .medium)
                        .lineLimit(1)
                        .minimumScaleFactor(0.8)
                        .padding(.horizontal, 8)
                        .padding(.vertical, 4)
                        .background(
                            Capsule()
                                .fill(AppTheme.sage.opacity(AppTheme.opacityLight))
                        )
                        .foregroundStyle(AppTheme.sage)
                }
            }
        }
        .padding(.vertical, AppTheme.spacing4)
    }

    // MARK: - Helpers

    /// Text label for glucose range so color-blind users can identify the category.
    private func glucoseRangeLabel(for value: Double) -> String {
        switch value {
        case ..<100:
            return localized("Normal", defaultValue: "Normal")
        case 100..<140:
            return localized("Borderline", defaultValue: "Borderline")
        case 140..<180:
            return localized("Elevated", defaultValue: "Elevated")
        default:
            return localized("High", defaultValue: "High")
        }
    }

    /// Color-code glucose values: green <100, sage 100-140, orange 140-180, coral >180
    private func glucoseColor(for value: Double) -> Color {
        switch value {
        case ..<100:
            return .green
        case 100..<140:
            return AppTheme.sage
        case 140..<180:
            return .orange
        default:
            return AppTheme.coralAccent
        }
    }

    /// Group readings by calendar day, sorted most recent day first.
    private func groupedByDay(_ readings: [BloodSugarReading]) -> [(key: Date, value: [BloodSugarReading])] {
        let calendar = Calendar.current
        let grouped = Dictionary(grouping: readings) { reading in
            calendar.startOfDay(for: reading.timestamp)
        }
        return grouped.sorted { $0.key > $1.key }
    }

    private var language: AppLanguage {
        appState.selectedAppLanguage
    }

    private func localized(_ key: String, defaultValue: String? = nil) -> String {
        L10n.string(key, defaultValue: defaultValue, language: language)
    }
}

private struct BloodSugarMetricTile: View {
    let title: String
    let value: String

    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(title)
                .appFont(.caption)
                .foregroundStyle(.secondary)
                .lineLimit(nil)
                .fixedSize(horizontal: false, vertical: true)
            Text(value)
                .appFont(.headline)
                .lineLimit(nil)
                .fixedSize(horizontal: false, vertical: true)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(10)
        .background(
            RoundedRectangle(cornerRadius: AppTheme.cornerRadiusSmall)
                .fill(AppTheme.cardBackground)
        )
    }
}

private extension View {
    @ViewBuilder
    func lunarBloodSugarHistoryNavigationBackground() -> some View {
        if AppTheme.usesPremiumEditorStyling {
            toolbarBackground(AppTheme.premiumEditorBackground, for: .navigationBar)
                .toolbarBackground(.visible, for: .navigationBar)
        } else {
            self
        }
    }

    func lunarBloodSugarHistoryCard() -> some View {
        background(
            RoundedRectangle(cornerRadius: AppTheme.cornerRadiusLarge, style: .continuous)
                .fill(
                    LinearGradient(
                        colors: [
                            AppTheme.premiumEditorRaisedSurface.opacity(0.9),
                            AppTheme.premiumEditorSurface.opacity(0.78),
                            AppTheme.premiumEditorBackground.opacity(0.9),
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

#Preview {
    BloodSugarHistoryView()
        .modelContainer(for: [BloodSugarReading.self, Cycle.self], inMemory: true)
}
