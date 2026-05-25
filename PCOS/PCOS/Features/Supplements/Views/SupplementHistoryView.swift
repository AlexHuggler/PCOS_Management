import SwiftUI
import SwiftData

struct SupplementHistoryView: View {
    @Environment(\.modelContext) private var modelContext
    @ScaledMetric(relativeTo: .title2) private var adherenceRingDiameter: CGFloat = 120
    @State private var viewModel: SupplementViewModel?
    @State private var selectedRange: DateRange = .week
    @State private var adherence: AdherenceStats = AdherenceStats(totalScheduled: 0, totalTaken: 0)
    @State private var supplementBreakdown: [SupplementBreakdown] = []
    @State private var dosageChanges: [SupplementDosageChange] = []

    private enum DateRange: Int, CaseIterable, Identifiable {
        case week = 7
        case month = 30
        case quarter = 90

        var id: Int { rawValue }

        var label: String {
            switch self {
            case .week:
                String(localized: "7 Days", comment: "Supplement history filter option for the last seven days.")
            case .month:
                String(localized: "30 Days", comment: "Supplement history filter option for the last thirty days.")
            case .quarter:
                String(localized: "90 Days", comment: "Supplement history filter option for the last ninety days.")
            }
        }
    }

    private struct SupplementBreakdown: Identifiable {
        let id = UUID()
        let name: String
        let takenCount: Int
        let missedCount: Int
        var total: Int { takenCount + missedCount }
    }

    var body: some View {
        ScrollView {
            VStack(spacing: AppTheme.spacing16) {
                // MARK: - Date Range Selector
                Picker(
                    String(localized: "Date Range", comment: "Label for the supplement history date range picker."),
                    selection: $selectedRange
                ) {
                    ForEach(DateRange.allCases) { range in
                        Text(range.label).tag(range)
                    }
                }
                .pickerStyle(.segmented)
                .padding(.horizontal)

                // MARK: - Adherence Ring
                adherenceRing

                // MARK: - Breakdown by Supplement
                supplementBreakdownSection

                // MARK: - Dosage Change Timeline
                dosageChangesSection
            }
            .padding(.vertical)
        }
        .navigationTitle(String(localized: "Supplement History", comment: "Navigation title for supplement history."))
        .navigationBarTitleDisplayMode(.inline)
        .onAppear {
            let vm = SupplementViewModel(modelContext: modelContext)
            viewModel = vm
            refreshStats()
        }
        .onChange(of: selectedRange) { _, _ in
            refreshStats()
        }
    }

    // MARK: - Adherence Ring

    private var adherenceRing: some View {
        VStack(spacing: AppTheme.spacing12) {
            ZStack {
                // Background ring
                Circle()
                    .stroke(Color(.tertiarySystemFill), lineWidth: 12)
                    .frame(width: clampedAdherenceRingDiameter, height: clampedAdherenceRingDiameter)

                // Progress ring
                Circle()
                    .trim(from: 0, to: min(adherence.percentage / 100, 1.0))
                    .stroke(
                        adherenceColor,
                        style: StrokeStyle(lineWidth: 12, lineCap: .round)
                    )
                    .frame(width: clampedAdherenceRingDiameter, height: clampedAdherenceRingDiameter)
                    .rotationEffect(.degrees(-90))
                    .animation(.easeInOut(duration: 0.5), value: adherence.percentage)

                // Percentage text
                VStack(spacing: 2) {
                    Text("\(Int(adherence.percentage))%")
                        .appFont(.title2, weight: .bold)
                        .foregroundStyle(adherenceColor)
                        .contentTransition(.numericText())

                    Text(String(localized: "adherence", comment: "Supplement adherence summary label."))
                        .appFont(.caption2)
                        .foregroundStyle(.secondary)

                    Text(adherenceStatusLabel)
                        .appFont(.caption2, weight: .medium)
                        .foregroundStyle(adherenceColor)
                }
            }

            HStack(spacing: AppTheme.spacing24) {
                statLabel(
                    value: "\(adherence.totalTaken)",
                    label: String(localized: "Taken", comment: "Supplement adherence status label for doses that were taken."),
                    color: AppTheme.sage
                )
                statLabel(
                    value: "\(adherence.totalScheduled - adherence.totalTaken)",
                    label: String(localized: "Missed", comment: "Supplement adherence status label for doses that were missed."),
                    color: AppTheme.coralAccent
                )
                statLabel(
                    value: "\(adherence.totalScheduled)",
                    label: String(localized: "Total", comment: "Supplement adherence status label for the total number of doses."),
                    color: .secondary
                )
            }
        }
        .cardStyle()
        .padding(.horizontal)
    }

    private func statLabel(value: String, label: String, color: Color) -> some View {
        VStack(spacing: AppTheme.spacing4) {
            Text(value)
                .appFont(.headline)
                .foregroundStyle(color)
            Text(label)
                .appFont(.caption)
                .foregroundStyle(.secondary)
        }
    }

    private var adherenceColor: Color {
        if adherence.percentage >= 80 {
            return AppTheme.sage
        } else if adherence.percentage >= 50 {
            return .orange
        } else {
            return AppTheme.coralAccent
        }
    }

    /// Text label for adherence status so color-blind users can identify the category.
    private var adherenceStatusLabel: String {
        if adherence.percentage >= 80 {
            return String(localized: "On Track", comment: "Adherence status label when adherence is 80% or above.")
        } else if adherence.percentage >= 50 {
            return String(localized: "Needs Improvement", comment: "Adherence status label when adherence is between 50% and 79%.")
        } else {
            return String(localized: "Low Adherence", comment: "Adherence status label when adherence is below 50%.")
        }
    }

    private var clampedAdherenceRingDiameter: CGFloat {
        min(max(adherenceRingDiameter, 96), 156)
    }

    // MARK: - Breakdown Section

    private var supplementBreakdownSection: some View {
        VStack(alignment: .leading, spacing: AppTheme.spacing12) {
            AppTheme.sectionHeader(String(localized: "By Supplement", comment: "Section title for supplement history broken down by supplement."))
                .padding(.horizontal)

            if supplementBreakdown.isEmpty {
                VStack(spacing: AppTheme.spacing8) {
                    Text(String(localized: "No supplement data", comment: "Empty state title shown when there is no supplement history."))
                        .appFont(.subheadline)
                        .foregroundStyle(.secondary)
                    Text(
                        String(
                            localized: "Start logging supplements to see your history here.",
                            comment: "Empty state message prompting the user to log supplements first."
                        )
                    )
                        .appFont(.caption)
                        .foregroundStyle(.tertiary)
                        .multilineTextAlignment(.center)
                }
                .frame(maxWidth: .infinity)
                .padding(.vertical, AppTheme.spacing24)
                .padding(.horizontal)
                .cardStyle()
                .padding(.horizontal)
            } else {
                ForEach(supplementBreakdown) { item in
                    HStack(spacing: AppTheme.spacing12) {
                        Image(systemName: "pill.fill")
                            .appFont(.body)
                            .foregroundStyle(AppTheme.sage)
                            .frame(width: 28)

                        VStack(alignment: .leading, spacing: AppTheme.spacing4) {
                            Text(item.name)
                                .appFont(.subheadline, weight: .medium)

                            // Mini progress bar
                            GeometryReader { geo in
                                ZStack(alignment: .leading) {
                                    RoundedRectangle(cornerRadius: 3)
                                        .fill(Color(.tertiarySystemFill))
                                        .frame(height: 6)

                                    RoundedRectangle(cornerRadius: 3)
                                        .fill(AppTheme.sage)
                                        .frame(
                                            width: item.total > 0
                                                ? geo.size.width * CGFloat(item.takenCount) / CGFloat(item.total)
                                                : 0,
                                            height: 6
                                        )
                                        .animation(.easeInOut(duration: 0.4), value: item.takenCount)
                                }
                            }
                            .frame(height: 6)
                        }

                        VStack(alignment: .trailing, spacing: 2) {
                            Text("\(item.takenCount)/\(item.total)")
                                .appFont(.caption, weight: .medium)
                                .foregroundStyle(.primary)

                            if item.missedCount > 0 {
                                Text(
                                    String(
                                        localized: "\(item.missedCount) missed",
                                        comment: "Supplement history label showing how many scheduled supplement doses were missed."
                                    )
                                )
                                    .appFont(.caption2)
                                    .foregroundStyle(AppTheme.coralAccent)
                            }
                        }
                    }
                    .padding(.vertical, AppTheme.spacing8)
                    .padding(.horizontal, AppTheme.spacing12)
                    .cardStyle()
                    .padding(.horizontal)
                }
            }
        }
    }

    private var dosageChangesSection: some View {
        VStack(alignment: .leading, spacing: AppTheme.spacing12) {
            AppTheme.sectionHeader("Dosage Change Timeline")
                .padding(.horizontal)

            if dosageChanges.isEmpty {
                VStack(spacing: AppTheme.spacing8) {
                    Text("No dosage changes yet")
                        .appFont(.subheadline)
                        .foregroundStyle(.secondary)
                    Text("When you log a different dosage for the same supplement, it will appear here.")
                        .appFont(.caption)
                        .foregroundStyle(.tertiary)
                        .multilineTextAlignment(.center)
                }
                .frame(maxWidth: .infinity)
                .padding(.vertical, AppTheme.spacing24)
                .padding(.horizontal)
                .cardStyle()
                .padding(.horizontal)
            } else {
                ForEach(dosageChanges) { change in
                    HStack(spacing: AppTheme.spacing12) {
                        Image(systemName: "arrow.triangle.2.circlepath")
                            .foregroundStyle(AppTheme.accentColor)
                            .frame(width: 24)

                        VStack(alignment: .leading, spacing: 2) {
                            Text(change.supplementName)
                                .appFont(.subheadline, weight: .medium)
                            Text(change.date, format: .dateTime.month(.abbreviated).day().year())
                                .appFont(.caption)
                                .foregroundStyle(.secondary)
                        }

                        Spacer()

                        Text("\(formattedDosage(change.previousDosageMg)) → \(formattedDosage(change.newDosageMg))")
                            .appFont(.caption, weight: .medium)
                            .foregroundStyle(AppTheme.coralAccent)
                    }
                    .padding(.vertical, AppTheme.spacing8)
                    .padding(.horizontal, AppTheme.spacing12)
                    .cardStyle()
                    .padding(.horizontal)
                }
            }
        }
    }

    // MARK: - Data Refresh

    private func refreshStats() {
        guard let viewModel else { return }
        let days = selectedRange.rawValue
        adherence = viewModel.calculateAdherence(days: days)
        loadBreakdown(days: days)
        loadDosageChanges(days: days)
    }

    private func loadBreakdown(days: Int) {
        guard let viewModel else { return }
        let logs = viewModel.fetchLogs(days: days)
        let grouped = Dictionary(grouping: logs, by: \.supplementName)
        supplementBreakdown = grouped.map { name, entries in
            SupplementBreakdown(
                name: name,
                takenCount: entries.filter(\.taken).count,
                missedCount: entries.filter { !$0.taken }.count
            )
        }
        .sorted { $0.name < $1.name }
    }

    private func loadDosageChanges(days: Int) {
        guard let viewModel else { return }
        dosageChanges = viewModel.dosageChanges(days: days)
    }

    private func formattedDosage(_ dosage: Double) -> String {
        let formatted = dosage.rounded(.towardZero) == dosage
            ? L10n.decimal(dosage, fractionDigits: 0)
            : L10n.decimal(dosage, fractionDigits: 1)
        return "\(formatted) mg"
    }
}

#Preview {
    NavigationStack {
        SupplementHistoryView()
    }
    .modelContainer(for: SupplementLog.self, inMemory: true)
}
