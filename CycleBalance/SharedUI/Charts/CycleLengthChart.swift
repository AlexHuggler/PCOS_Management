import SwiftUI
import Charts

struct CycleLengthChart: View {
    let cycleLengths: [(cycleNumber: Int, days: Int)]

    private var averageDays: Double {
        guard !cycleLengths.isEmpty else { return 0 }
        let total = cycleLengths.reduce(0) { $0 + $1.days }
        return Double(total) / Double(cycleLengths.count)
    }

    var body: some View {
        Chart {
            ForEach(cycleLengths, id: \.cycleNumber) { item in
                LineMark(
                    x: .value("Cycle", item.cycleNumber),
                    y: .value("Days", item.days)
                )
                .foregroundStyle(AppTheme.accentColor)
                .interpolationMethod(.catmullRom)

                PointMark(
                    x: .value("Cycle", item.cycleNumber),
                    y: .value("Days", item.days)
                )
                .foregroundStyle(AppTheme.accentColor)
                .symbolSize(40)
            }

            RuleMark(y: .value("Average", averageDays))
                .foregroundStyle(AppTheme.coralAccent)
                .lineStyle(StrokeStyle(lineWidth: 1.5, dash: [6, 4]))
                .annotation(position: .top, alignment: .trailing) {
                    Text("Avg: \(String(format: "%.0f", averageDays))d")
                        .font(.caption2)
                        .foregroundStyle(AppTheme.coralAccent)
                }
        }
        .chartYAxisLabel("Days")
        .chartXAxisLabel("Cycle")
        .frame(height: 200)
    }
}

#Preview {
    CycleLengthChart(cycleLengths: [
        (1, 28), (2, 30), (3, 27), (4, 31), (5, 29)
    ])
    .padding()
}
