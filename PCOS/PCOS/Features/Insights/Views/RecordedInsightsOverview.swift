import SwiftUI
import Charts

struct RecordedInsightsOverview: View {
    let snapshot: InsightObservationSnapshot
    let language: AppLanguage
    let onOpenReport: () -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: AppTheme.spacing16) {
            VStack(alignment: .leading, spacing: AppTheme.spacing8) {
                Text(L10n.string("Your patterns, with context", defaultValue: "Your patterns, with context", language: language))
                    .appFont(.title2, weight: .semibold)
                Text(L10n.string("Small observations from the days you recorded.", defaultValue: "Small observations from the days you recorded.", language: language))
                    .appFont(.subheadline)
                    .foregroundStyle(.secondary)
                Text(snapshot.window.start.formatted(date: .abbreviated, time: .omitted) + " – " + snapshot.window.end.addingTimeInterval(-1).formatted(date: .abbreviated, time: .omitted))
                    .appFont(.caption)
                    .foregroundStyle(.secondary)
            }
            metric(title: L10n.string("Symptoms", defaultValue: "Symptoms", language: language), points: snapshot.symptoms, unit: L10n.string("Severity / 5", defaultValue: "Severity / 5", language: language), domain: 0...5)
            metric(title: L10n.string("Sleep", defaultValue: "Sleep", language: language), points: snapshot.sleep, unit: L10n.string("Hours · waking day", defaultValue: "Hours · waking day", language: language), domain: 0...max(12, snapshot.sleep.map(\.value).max() ?? 12))
            VStack(alignment: .leading, spacing: AppTheme.spacing8) {
                Label(L10n.string("Data receipt", defaultValue: "Data receipt", language: language), systemImage: "doc.text.magnifyingglass")
                    .appFont(.subheadline, weight: .semibold)
                Text(L10n.format("%lld completed cycles in your history", defaultValue: "%lld completed cycles in your history", snapshot.completedCycles))
                Text(L10n.string("Charts use saved symptom entries and daily sleep logs. Imported and manual entries may be combined. Each dot is a recorded day's average; gaps stay empty.", defaultValue: "Charts use saved symptom entries and daily sleep logs. Imported and manual entries may be combined. Each dot is a recorded day's average; gaps stay empty.", language: language))
                if !snapshot.sourceNames.isEmpty {
                    Text(L10n.format("Connected sources with records in this window: %@", defaultValue: "Connected sources with records in this window: %@", snapshot.sourceNames.joined(separator: ", ")))
                }
                Text(L10n.format("Coverage checked %@", defaultValue: "Coverage checked %@", snapshot.updatedAt.formatted(date: .abbreviated, time: .shortened)))
            }
            .appFont(.caption)
            .foregroundStyle(.secondary)
            .accessibilityIdentifier("insights.data_receipt")
            Button(action: onOpenReport) {
                Label(L10n.string("Prepare a report", defaultValue: "Prepare a report", language: language), systemImage: "doc.richtext")
                    .appFont(.subheadline, weight: .semibold)
            }
            .buttonStyle(.bordered)
            .tint(AppTheme.accentColor)
            .accessibilityIdentifier("insights.overview.report")
        }
        .padding(.vertical, AppTheme.spacing8)
    }

    private func metric(title: String, points: [InsightObservationPoint], unit: String, domain: ClosedRange<Double>) -> some View {
        VStack(alignment: .leading, spacing: AppTheme.spacing12) {
            Text(title).appFont(.headline)
            Text(unit).appFont(.caption).foregroundStyle(.secondary)
            if points.isEmpty {
                Label(L10n.string("No records in these 14 days", defaultValue: "No records in these 14 days", language: language), systemImage: "chart.xyaxis.line")
                    .appFont(.subheadline)
                    .foregroundStyle(.secondary)
                    .frame(maxWidth: .infinity, minHeight: 70, alignment: .leading)
            } else {
                Chart(points) { point in
                    PointMark(x: .value(L10n.string("Date", defaultValue: "Date"), point.date), y: .value(unit, point.value))
                        .foregroundStyle(AppTheme.accentColor)
                        .symbolSize(50)
                        .accessibilityLabel(point.date.formatted(date: .abbreviated, time: .omitted))
                        .accessibilityValue(L10n.decimal(point.value) + " · " + unit)
                }
                .chartXScale(domain: snapshot.window.start...snapshot.window.end)
                .chartYScale(domain: domain)
                .chartXAxis { AxisMarks(values: .stride(by: .day, count: 4)) { _ in AxisGridLine(); AxisValueLabel(format: .dateTime.month(.abbreviated).day()) } }
                .frame(height: 140)
            }
            Text(L10n.format("%lld of 14 days recorded · %lld missing · %lld records", defaultValue: "%lld of 14 days recorded · %lld missing · %lld records", points.count, max(0, 14 - points.count), points.reduce(0) { $0 + $1.recordCount }))
                .appFont(.caption)
                .foregroundStyle(.secondary)
        }
        .cardStyle()
    }
}
