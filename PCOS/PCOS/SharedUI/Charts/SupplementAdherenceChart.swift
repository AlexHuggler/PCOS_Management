import SwiftUI
import Charts

struct SupplementAdherenceChart: View {
    let taken: Int
    let missed: Int

    private var total: Int { taken + missed }
    private var takenLabel: String {
        String(localized: "Taken", comment: "Supplement adherence status label for doses that were taken.")
    }

    private var missedLabel: String {
        String(localized: "Missed", comment: "Supplement adherence status label for doses that were missed.")
    }

    private var percentage: Int {
        guard total > 0 else { return 0 }
        return Int((Double(taken) / Double(total) * 100).rounded())
    }

    private var chartData: [(label: String, count: Int, color: Color)] {
        [
            (takenLabel, taken, AppTheme.sage),
            (missedLabel, missed, Color.gray.opacity(0.4)),
        ]
    }

    var body: some View {
        VStack(spacing: AppTheme.spacing12) {
            Chart(chartData, id: \.label) { item in
                SectorMark(
                    angle: .value(
                        String(localized: "Count", comment: "Chart value label for supplement count."),
                        item.count
                    ),
                    innerRadius: .ratio(0.6),
                    angularInset: 1.5
                )
                .foregroundStyle(item.color)
                .cornerRadius(4)
            }
            .frame(height: 180)
            .chartBackground { _ in
                VStack(spacing: 2) {
                    Text("\(percentage)%")
                        .appFont(.title2, weight: .bold)
                        .foregroundStyle(.primary)
                    Text(String(localized: "adherence", comment: "Supplement adherence chart summary label."))
                        .appFont(.caption2)
                        .foregroundStyle(.secondary)
                }
            }

            // Legend
            HStack(spacing: AppTheme.spacing16) {
                legendItem(
                    color: AppTheme.sage,
                    label: String(
                        localized: "Taken (\(taken))",
                        comment: "Legend label showing how many supplement doses were taken."
                    )
                )
                legendItem(
                    color: Color.gray.opacity(0.4),
                    label: String(
                        localized: "Missed (\(missed))",
                        comment: "Legend label showing how many supplement doses were missed."
                    )
                )
            }
            .appFont(.caption)
        }
    }

    private func legendItem(color: Color, label: String) -> some View {
        HStack(spacing: AppTheme.spacing4) {
            Circle()
                .fill(color)
                .frame(width: 8, height: 8)
            Text(label)
                .foregroundStyle(.secondary)
        }
    }
}

#Preview {
    SupplementAdherenceChart(taken: 25, missed: 5)
        .padding()
}
