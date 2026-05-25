import SwiftUI
import SwiftData
import Charts

struct BloodSugarHistoryView: View {
    @Environment(\.modelContext) private var modelContext
    @Environment(AppState.self) private var appState
    @ScaledMetric(relativeTo: .subheadline) private var timeColumnIdealWidth: CGFloat = 70
    @State private var viewModel: BloodSugarViewModel?

    var body: some View {
        NavigationStack {
            Group {
                if let viewModel {
                    let readings = viewModel.fetchRecentReadings(days: 90)
                    if readings.isEmpty {
                        emptyState
                    } else {
                        historyContent(readings: readings, viewModel: viewModel)
                    }
                } else {
                    List {
                        ForEach(0..<5, id: \.self) { _ in
                            SkeletonListRow()
                        }
                    }
                    .listStyle(.insetGrouped)
                }
            }
            .navigationTitle(localized("Blood Sugar History", defaultValue: "Blood Sugar History"))
            .navigationBarTitleDisplayMode(.inline)
            .onAppear {
                if viewModel == nil {
                    viewModel = BloodSugarViewModel(modelContext: modelContext)
                }
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

#Preview {
    BloodSugarHistoryView()
        .modelContainer(for: [BloodSugarReading.self, Cycle.self], inMemory: true)
}
