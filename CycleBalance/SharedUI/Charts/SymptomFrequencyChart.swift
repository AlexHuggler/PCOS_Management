import SwiftUI
import Charts

struct SymptomFrequencyChart: View {
    let symptoms: [(name: String, count: Int, averageSeverity: Double)]

    private var displaySymptoms: [(name: String, count: Int, averageSeverity: Double)] {
        Array(symptoms.prefix(8))
    }

    var body: some View {
        Chart(displaySymptoms, id: \.name) { item in
            BarMark(
                x: .value("Count", item.count),
                y: .value("Symptom", item.name)
            )
            .foregroundStyle(AppTheme.severityColor(for: Int(item.averageSeverity.rounded())))
            .cornerRadius(4)
        }
        .chartXAxisLabel("Occurrences")
        .frame(height: CGFloat(displaySymptoms.count) * 36)
    }
}

#Preview {
    SymptomFrequencyChart(symptoms: [
        ("Fatigue", 12, 3.2),
        ("Bloating", 10, 2.5),
        ("Cramps", 8, 4.0),
        ("Headache", 6, 2.0),
        ("Acne", 5, 3.0),
    ])
    .padding()
}
