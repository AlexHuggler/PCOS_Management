import SwiftUI
import SwiftData

struct BloodSugarHistoryView: View {
    @Environment(\.modelContext) private var modelContext
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
                        readingsList(readings: readings, viewModel: viewModel)
                    }
                } else {
                    ProgressView()
                        .frame(maxWidth: .infinity, maxHeight: .infinity)
                }
            }
            .navigationTitle("Blood Sugar History")
            .navigationBarTitleDisplayMode(.inline)
            .onAppear {
                if viewModel == nil {
                    viewModel = BloodSugarViewModel(modelContext: modelContext)
                }
            }
        }
    }

    // MARK: - Subviews

    private var emptyState: some View {
        ContentUnavailableView {
            Label("No Readings Yet", systemImage: "drop.degreesign")
                .symbolEffect(.pulse)
        } description: {
            Text("Log your first blood sugar reading to start tracking.")
        }
    }

    private func readingsList(readings: [BloodSugarReading], viewModel: BloodSugarViewModel) -> some View {
        List {
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

    private func readingRow(_ reading: BloodSugarReading) -> some View {
        HStack(spacing: AppTheme.spacing12) {
            // Time
            Text(reading.timestamp, style: .time)
                .font(.subheadline)
                .foregroundStyle(.secondary)
                .lineLimit(1)
                .minimumScaleFactor(0.8)
                .frame(minWidth: timeColumnIdealWidth * 0.8, idealWidth: timeColumnIdealWidth, alignment: .leading)

            // Glucose value — color-coded
            Text("\(Int(reading.glucoseValue))")
                .font(.title3)
                .fontWeight(.semibold)
                .foregroundStyle(glucoseColor(for: reading.glucoseValue))

            Text("mg/dL")
                .font(.caption)
                .foregroundStyle(.secondary)

            Spacer()

            // Reading type badge
            Text(reading.readingType.displayName)
                .font(.caption2)
                .fontWeight(.medium)
                .padding(.horizontal, 8)
                .padding(.vertical, 4)
                .background(
                    Capsule()
                        .fill(AppTheme.accentColor.opacity(0.12))
                )
                .foregroundStyle(AppTheme.accentColor)
        }
        .padding(.vertical, AppTheme.spacing4)
    }

    // MARK: - Helpers

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
}

#Preview {
    BloodSugarHistoryView()
        .modelContainer(for: BloodSugarReading.self, inMemory: true)
}
