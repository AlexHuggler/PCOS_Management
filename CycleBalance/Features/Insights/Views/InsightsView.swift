import SwiftUI
import SwiftData

struct InsightsView: View {
    @Query(sort: \Insight.generatedDate, order: .reverse)
    private var insights: [Insight]
    @State private var showingLogPeriod = false
    @State private var showingLogSymptoms = false

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
            .sheet(isPresented: $showingLogPeriod) {
                CycleLogView()
            }
            .sheet(isPresented: $showingLogSymptoms) {
                SymptomLogView()
            }
            .sensoryFeedback(.selection, trigger: showingLogPeriod)
            .sensoryFeedback(.selection, trigger: showingLogSymptoms)
        }
    }

    private var emptyState: some View {
        ContentUnavailableView {
            Label("No Insights Yet", systemImage: "chart.line.uptrend.xyaxis")
                .symbolEffect(.pulse)
        } description: {
            Text("CycleBalance identifies patterns after you've logged at least 2 complete cycles. Keep tracking — your first insights are on the way!")
        } actions: {
            HStack(spacing: AppTheme.spacing12) {
                Button {
                    showingLogPeriod = true
                } label: {
                    Label("Log Period", systemImage: "drop.fill")
                }
                .buttonStyle(.bordered)
                .tint(AppTheme.coralAccent)

                Button {
                    showingLogSymptoms = true
                } label: {
                    Label("Log Symptoms", systemImage: "list.bullet.clipboard")
                }
                .buttonStyle(.bordered)
                .tint(AppTheme.accentColor)
            }
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
        VStack(alignment: .leading, spacing: AppTheme.spacing8) {
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
        .accessibilityElement(children: .combine)
        .accessibilityLabel("\(insight.insightType.displayName): \(insight.title). \(insight.content)")
    }
}

#Preview {
    InsightsView()
        .modelContainer(for: Insight.self, inMemory: true)
}
