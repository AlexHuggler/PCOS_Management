import SwiftUI
import SwiftData

struct InsightsView: View {
    @Query(sort: \Insight.generatedDate, order: .reverse)
    private var insights: [Insight]

    var body: some View {
        NavigationStack {
            Group {
                if insights.isEmpty {
                    emptyState
                } else {
                    insightsList
                }
            }
            .navigationTitle("Insights")
        }
    }

    private var emptyState: some View {
        ContentUnavailableView {
            Label("No Insights Yet", systemImage: "chart.line.uptrend.xyaxis")
        } description: {
            Text("Keep logging your symptoms, meals, and supplements. CycleBalance will identify patterns and correlations as your data grows.")
        }
    }

    private var insightsList: some View {
        List {
            ForEach(insights) { insight in
                InsightCard(insight: insight)
            }
        }
        .listStyle(.insetGrouped)
    }
}

struct InsightCard: View {
    let insight: Insight

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack {
                Image(systemName: insight.insightType.systemImage)
                    .foregroundStyle(AppTheme.accentColor)
                Text(insight.insightType.displayName)
                    .font(.caption)
                    .foregroundStyle(.secondary)
                Spacer()
                if insight.actionable {
                    Image(systemName: "lightbulb.fill")
                        .font(.caption)
                        .foregroundStyle(.yellow)
                }
            }

            Text(insight.title)
                .font(.headline)

            Text(insight.content)
                .font(.subheadline)
                .foregroundStyle(.secondary)

            HStack {
                Text("Based on \(insight.dataPointsUsed) data points")
                    .font(.caption2)
                    .foregroundStyle(.tertiary)

                Spacer()

                Text("\(Int(insight.confidence * 100))% confidence")
                    .font(.caption2)
                    .foregroundStyle(.tertiary)
            }
        }
        .padding(.vertical, 4)
    }
}

#Preview {
    InsightsView()
        .modelContainer(for: Insight.self, inMemory: true)
}
