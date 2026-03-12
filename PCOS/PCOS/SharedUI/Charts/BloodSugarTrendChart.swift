import SwiftUI
import Charts

struct BloodSugarTrendChart: View {
    let readings: [(date: Date, value: Double, type: String)]

    private var sortedReadings: [(date: Date, value: Double, type: String)] {
        readings.sorted { $0.date < $1.date }
    }

    var body: some View {
        Chart {
            ForEach(sortedReadings.indices, id: \.self) { index in
                let reading = sortedReadings[index]

                LineMark(
                    x: .value("Date", reading.date),
                    y: .value("mg/dL", reading.value)
                )
                .foregroundStyle(AppTheme.accentColor)
                .interpolationMethod(.catmullRom)

                PointMark(
                    x: .value("Date", reading.date),
                    y: .value("mg/dL", reading.value)
                )
                .foregroundStyle(by: .value("Type", reading.type))
                .symbolSize(30)
            }

            RuleMark(y: .value("Normal", 100))
                .foregroundStyle(.green.opacity(0.6))
                .lineStyle(StrokeStyle(lineWidth: 1, dash: [5, 3]))
                .annotation(position: .leading, alignment: .leading) {
                    Text("Normal")
                        .font(.caption2)
                        .foregroundStyle(.green)
                }

            RuleMark(y: .value("Elevated", 140))
                .foregroundStyle(.orange.opacity(0.6))
                .lineStyle(StrokeStyle(lineWidth: 1, dash: [5, 3]))
                .annotation(position: .leading, alignment: .leading) {
                    Text("Elevated")
                        .font(.caption2)
                        .foregroundStyle(.orange)
                }
        }
        .chartYAxisLabel("mg/dL")
        .frame(height: 220)
    }
}

#Preview {
    BloodSugarTrendChart(readings: [
        (.now.addingTimeInterval(-86400 * 3), 95, "Fasting"),
        (.now.addingTimeInterval(-86400 * 2), 130, "After Meal"),
        (.now.addingTimeInterval(-86400), 105, "Random"),
        (.now, 110, "Before Meal"),
    ])
    .padding()
}
