import SwiftUI
import SwiftData

struct InsightsView: View {
    @Environment(\.modelContext) private var modelContext
    @State private var viewModel: InsightsViewModel?
    @State private var showingLogPeriod = false
    @State private var showingLogSymptoms = false

    private var insights: [Insight] {
        viewModel?.insights ?? []
    }

    private var insightErrorMessage: String? {
        viewModel?.errorMessage
    }

    var body: some View {
        NavigationStack {
            VStack(spacing: AppTheme.spacing12) {
                if let insightErrorMessage, !insightErrorMessage.isEmpty {
                    insightErrorBanner(insightErrorMessage)
                }

                Group {
                    if viewModel?.isGenerating == true {
                        ProgressView("Generating insights...")
                    } else if insights.isEmpty {
                        emptyState
                    } else {
                        insightsList
                    }
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
            .refreshable {
                await viewModel?.refreshInsights()
            }
            .background(AppTheme.warmNeutral.ignoresSafeArea())
            .onAppear {
                if viewModel == nil {
                    let vm = InsightsViewModel(modelContext: modelContext)
                    vm.fetchExistingInsights()
                    viewModel = vm
                }
            }
        }
        .premiumGated()
    }

    private func insightErrorBanner(_ message: String) -> some View {
        HStack(alignment: .top, spacing: AppTheme.spacing8) {
            Image(systemName: "exclamationmark.triangle.fill")
                .foregroundStyle(.orange)
                .font(.caption)
                .padding(.top, 2)
            Text(message)
                .font(.footnote)
                .foregroundStyle(.primary)
            Spacer(minLength: 0)
        }
        .padding(.horizontal, AppTheme.spacing12)
        .padding(.vertical, AppTheme.spacing8)
        .background(
            RoundedRectangle(cornerRadius: 12)
                .fill(Color.orange.opacity(0.15))
        )
        .overlay(
            RoundedRectangle(cornerRadius: 12)
                .stroke(Color.orange.opacity(0.3), lineWidth: 1)
        )
        .accessibilityElement(children: .combine)
        .accessibilityLabel("Insight refresh error. \(message)")
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
        .scrollContentBackground(.hidden)
        .background(AppTheme.warmNeutral)
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
        .modelContainer(for: [
            CycleEntry.self,
            Cycle.self,
            SymptomEntry.self,
            Insight.self,
            BloodSugarReading.self,
            SupplementLog.self,
            MealEntry.self,
            HairPhotoEntry.self,
            DailyLog.self,
        ], inMemory: true)
}
