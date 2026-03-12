import SwiftUI
import Charts

struct GlycemicImpactChart: View {
    let distribution: [(label: String, count: Int)]

    private func barColor(for label: String) -> Color {
        switch label.lowercased() {
        case "low": .green
        case "medium": .orange
        case "high": AppTheme.coralAccent
        default: .secondary
        }
    }

    var body: some View {
        Chart(distribution, id: \.label) { item in
            BarMark(
                x: .value("Impact", item.label),
                y: .value("Count", item.count)
            )
            .foregroundStyle(barColor(for: item.label))
            .cornerRadius(6)
        }
        .chartYAxisLabel("Meals")
        .frame(height: 200)
    }
}

#Preview {
    GlycemicImpactChart(distribution: [
        ("Low", 10),
        ("Medium", 5),
        ("High", 3),
    ])
    .padding()
}
