import SwiftUI
import SwiftData

struct SupplementHistoryView: View {
    @Environment(\.modelContext) private var modelContext
    @ScaledMetric(relativeTo: .title2) private var adherenceRingDiameter: CGFloat = 120
    @State private var viewModel: SupplementViewModel?
    @State private var selectedRange: DateRange = .week
    @State private var adherence: AdherenceStats = AdherenceStats(totalScheduled: 0, totalTaken: 0)
    @State private var supplementBreakdown: [SupplementBreakdown] = []

    private enum DateRange: Int, CaseIterable, Identifiable {
        case week = 7
        case month = 30
        case quarter = 90

        var id: Int { rawValue }

        var label: String {
            switch self {
            case .week: "7 Days"
            case .month: "30 Days"
            case .quarter: "90 Days"
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
                Picker("Date Range", selection: $selectedRange) {
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
            }
            .padding(.vertical)
        }
        .navigationTitle("Supplement History")
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
                        .font(.title2)
                        .fontWeight(.bold)
                        .foregroundStyle(adherenceColor)
                        .contentTransition(.numericText())

                    Text("adherence")
                        .font(.caption2)
                        .foregroundStyle(.secondary)
                }
            }

            HStack(spacing: AppTheme.spacing24) {
                statLabel(value: "\(adherence.totalTaken)", label: "Taken", color: AppTheme.sage)
                statLabel(
                    value: "\(adherence.totalScheduled - adherence.totalTaken)",
                    label: "Missed",
                    color: AppTheme.coralAccent
                )
                statLabel(value: "\(adherence.totalScheduled)", label: "Total", color: .secondary)
            }
        }
        .cardStyle()
        .padding(.horizontal)
    }

    private func statLabel(value: String, label: String, color: Color) -> some View {
        VStack(spacing: AppTheme.spacing4) {
            Text(value)
                .font(.headline)
                .foregroundStyle(color)
            Text(label)
                .font(.caption)
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

    private var clampedAdherenceRingDiameter: CGFloat {
        min(max(adherenceRingDiameter, 96), 156)
    }

    // MARK: - Breakdown Section

    private var supplementBreakdownSection: some View {
        VStack(alignment: .leading, spacing: AppTheme.spacing12) {
            AppTheme.sectionHeader("By Supplement")
                .padding(.horizontal)

            if supplementBreakdown.isEmpty {
                VStack(spacing: AppTheme.spacing8) {
                    Text("No supplement data")
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                    Text("Start logging supplements to see your history here.")
                        .font(.caption)
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
                            .font(.body)
                            .foregroundStyle(AppTheme.sage)
                            .frame(width: 28)

                        VStack(alignment: .leading, spacing: AppTheme.spacing4) {
                            Text(item.name)
                                .font(.subheadline)
                                .fontWeight(.medium)

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
                                .font(.caption)
                                .fontWeight(.medium)
                                .foregroundStyle(.primary)

                            if item.missedCount > 0 {
                                Text("\(item.missedCount) missed")
                                    .font(.caption2)
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

    // MARK: - Data Refresh

    private func refreshStats() {
        guard let viewModel else { return }
        let days = selectedRange.rawValue
        adherence = viewModel.calculateAdherence(days: days)
        loadBreakdown(days: days)
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
}

#Preview {
    NavigationStack {
        SupplementHistoryView()
    }
    .modelContainer(for: SupplementLog.self, inMemory: true)
}
