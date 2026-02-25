import SwiftUI
import SwiftData

struct CycleDetailView: View {
    @Environment(\.modelContext) private var modelContext
    @State private var viewModel: CycleViewModel?

    var body: some View {
        ScrollView {
            VStack(spacing: AppTheme.spacing24) {
                // Current cycle day counter
                currentCycleCard

                // Prediction card
                predictionCard

                // Statistics card
                statisticsCard

                // Recent cycles list
                recentCyclesCard
            }
            .padding()
        }
        .refreshable {
            await Task.yield()
            viewModel?.loadData()
        }
        .navigationTitle("Cycle Details")
        .onAppear {
            if viewModel == nil {
                let vm = CycleViewModel(modelContext: modelContext)
                vm.loadData()
                viewModel = vm
            }
        }
    }

    // MARK: - Cards

    private var currentCycleCard: some View {
        VStack(spacing: AppTheme.spacing8) {
            if let dayCount = viewModel?.currentCycleDayCount {
                Text("Day \(dayCount)")
                    .font(.system(.largeTitle, design: .rounded, weight: .bold))
                    .foregroundStyle(AppTheme.accentColor)
                    .contentTransition(.numericText())
                Text("of current cycle")
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
            } else {
                Text("No Active Cycle")
                    .font(.title2)
                    .foregroundStyle(.secondary)
                Text("Log a period to start tracking")
                    .font(.subheadline)
                    .foregroundStyle(.tertiary)
            }
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, AppTheme.spacing24)
        .cardStyle(cornerRadius: 16)
    }

    private var predictionCard: some View {
        Group {
            if let predictionText = viewModel?.predictionRangeText,
               let prediction = viewModel?.prediction {
                VStack(alignment: .leading, spacing: AppTheme.spacing8) {
                    Label("Next Period Estimate", systemImage: "sparkles")
                        .font(.headline)
                        .foregroundStyle(AppTheme.coralAccent)

                    Text(predictionText)
                        .font(.body)

                    HStack {
                        Text("Confidence")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                        ProgressView(value: prediction.confidence)
                            .tint(AppTheme.accentColor)
                    }
                }
                .frame(maxWidth: .infinity, alignment: .leading)
                .cardStyle()
            }
        }
    }

    private var statisticsCard: some View {
        Group {
            if let stats = viewModel?.statistics {
                VStack(alignment: .leading, spacing: AppTheme.spacing12) {
                    Text("Cycle Statistics")
                        .font(.headline)

                    HStack(spacing: AppTheme.spacing16) {
                        StatisticItem(
                            title: "Average",
                            value: "\(stats.formattedAverage) days"
                        )
                        StatisticItem(
                            title: "Range",
                            value: stats.rangeDescription
                        )
                        StatisticItem(
                            title: "Cycles",
                            value: "\(stats.totalCycles)"
                        )
                    }
                }
                .frame(maxWidth: .infinity, alignment: .leading)
                .cardStyle()
            }
        }
    }

    private var recentCyclesCard: some View {
        Group {
            let completedCycles = viewModel?.cycles.filter { $0.lengthDays != nil } ?? []
            if !completedCycles.isEmpty {
                VStack(alignment: .leading, spacing: AppTheme.spacing8) {
                    Text("Recent Cycles")
                        .font(.headline)

                    ForEach(completedCycles.suffix(6).reversed()) { cycle in
                        HStack {
                            Text(formatDate(cycle.startDate))
                                .font(.subheadline)
                            Spacer()
                            if let length = cycle.lengthDays {
                                Text("\(length) days")
                                    .font(.subheadline)
                                    .fontWeight(.medium)
                                    .foregroundStyle(AppTheme.accentColor)
                            }
                        }
                        .padding(.vertical, AppTheme.spacing4)
                        Divider()
                    }
                }
                .frame(maxWidth: .infinity, alignment: .leading)
                .cardStyle()
            }
        }
    }

    private static let mediumDateFormatter: DateFormatter = {
        let formatter = DateFormatter()
        formatter.dateStyle = .medium
        return formatter
    }()

    private func formatDate(_ date: Date) -> String {
        Self.mediumDateFormatter.string(from: date)
    }
}

struct StatisticItem: View {
    let title: String
    let value: String

    var body: some View {
        VStack(spacing: AppTheme.spacing4) {
            Text(value)
                .font(.title3)
                .fontWeight(.semibold)
            Text(title)
                .font(.caption)
                .foregroundStyle(.secondary)
        }
        .frame(maxWidth: .infinity)
    }
}

#Preview {
    NavigationStack {
        CycleDetailView()
    }
    .modelContainer(for: [CycleEntry.self, Cycle.self], inMemory: true)
}
