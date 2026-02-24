import SwiftUI
import SwiftData

struct TodayView: View {
    @Environment(\.modelContext) private var modelContext
    @State private var viewModel: CycleViewModel?
    @State private var showingLogPeriod = false
    @State private var showingLogSymptoms = false

    @Query(
        filter: #Predicate<SymptomEntry> { entry in
            entry.date >= Date().addingTimeInterval(-86400)
        },
        sort: \SymptomEntry.date,
        order: .reverse
    )
    private var todaysSymptoms: [SymptomEntry]

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(spacing: 16) {
                    // Cycle status card
                    cycleStatusCard

                    // Quick actions
                    quickActionsSection

                    // Today's logged symptoms
                    todaysSymptomsSection

                    // Prediction card
                    predictionSection
                }
                .padding()
            }
            .navigationTitle("Today")
            .sheet(isPresented: $showingLogPeriod) {
                CycleLogView()
            }
            .sheet(isPresented: $showingLogSymptoms) {
                SymptomLogView()
            }
            .onAppear {
                let vm = CycleViewModel(modelContext: modelContext)
                vm.loadData()
                viewModel = vm
            }
        }
    }

    // MARK: - Subviews

    private var cycleStatusCard: some View {
        VStack(spacing: 12) {
            if let dayCount = viewModel?.currentCycleDayCount {
                Text("Day \(dayCount)")
                    .font(.system(size: 56, weight: .bold, design: .rounded))
                    .foregroundStyle(AppTheme.accentColor)
                Text("of current cycle")
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
            } else {
                Text("Welcome")
                    .font(.title)
                    .fontWeight(.semibold)
                Text("Start tracking by logging your period")
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
            }
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, 32)
        .background(
            RoundedRectangle(cornerRadius: 20)
                .fill(AppTheme.cardBackground)
        )
    }

    private var quickActionsSection: some View {
        HStack(spacing: 12) {
            QuickActionButton(
                title: "Log Period",
                systemImage: "drop.fill",
                color: AppTheme.coralAccent
            ) {
                showingLogPeriod = true
            }

            QuickActionButton(
                title: "Log Symptoms",
                systemImage: "list.bullet.clipboard",
                color: AppTheme.accentColor
            ) {
                showingLogSymptoms = true
            }
        }
    }

    private var todaysSymptomsSection: some View {
        Group {
            if !todaysSymptoms.isEmpty {
                VStack(alignment: .leading, spacing: 8) {
                    Text("Today's Symptoms")
                        .font(.headline)

                    FlowLayout(spacing: 8) {
                        ForEach(todaysSymptoms, id: \.id) { symptom in
                            SymptomChip(
                                name: SymptomType(rawValue: symptom.symptomType)?.displayName ?? symptom.symptomType,
                                severity: symptom.severity
                            )
                        }
                    }
                }
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding()
                .background(
                    RoundedRectangle(cornerRadius: 12)
                        .fill(AppTheme.cardBackground)
                )
            }
        }
    }

    private var predictionSection: some View {
        Group {
            if let predictionText = viewModel?.predictionRangeText {
                VStack(alignment: .leading, spacing: 8) {
                    Label("Period Estimate", systemImage: "sparkles")
                        .font(.headline)
                        .foregroundStyle(AppTheme.coralAccent)
                    Text(predictionText)
                        .font(.subheadline)
                }
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding()
                .background(
                    RoundedRectangle(cornerRadius: 12)
                        .fill(AppTheme.cardBackground)
                )
            }
        }
    }
}

// MARK: - Quick Action Button

struct QuickActionButton: View {
    let title: String
    let systemImage: String
    let color: Color
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            VStack(spacing: 8) {
                Image(systemName: systemImage)
                    .font(.title2)
                Text(title)
                    .font(.caption)
                    .fontWeight(.medium)
            }
            .frame(maxWidth: .infinity)
            .padding(.vertical, 16)
            .background(
                RoundedRectangle(cornerRadius: 12)
                    .fill(color.opacity(0.12))
            )
            .foregroundStyle(color)
        }
        .buttonStyle(.plain)
    }
}

// MARK: - Symptom Chip

struct SymptomChip: View {
    let name: String
    let severity: Int

    var body: some View {
        HStack(spacing: 4) {
            Text(name)
                .font(.caption)
            Text("(\(severity))")
                .font(.caption2)
                .foregroundStyle(.secondary)
        }
        .padding(.horizontal, 10)
        .padding(.vertical, 6)
        .background(
            Capsule()
                .fill(severityColor.opacity(0.15))
        )
        .foregroundStyle(severityColor)
    }

    private var severityColor: Color {
        switch severity {
        case 1: .green
        case 2: AppTheme.accentColor
        case 3: .orange
        case 4, 5: AppTheme.coralAccent
        default: .secondary
        }
    }
}

// MARK: - Flow Layout

struct FlowLayout: Layout {
    var spacing: CGFloat = 8

    func sizeThatFits(proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) -> CGSize {
        let result = arrangeSubviews(proposal: proposal, subviews: subviews)
        return result.size
    }

    func placeSubviews(in bounds: CGRect, proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) {
        let result = arrangeSubviews(proposal: proposal, subviews: subviews)
        for (index, position) in result.positions.enumerated() {
            subviews[index].place(
                at: CGPoint(x: bounds.minX + position.x, y: bounds.minY + position.y),
                proposal: .unspecified
            )
        }
    }

    private func arrangeSubviews(proposal: ProposedViewSize, subviews: Subviews) -> (positions: [CGPoint], size: CGSize) {
        let maxWidth = proposal.width ?? .infinity
        var positions: [CGPoint] = []
        var currentX: CGFloat = 0
        var currentY: CGFloat = 0
        var lineHeight: CGFloat = 0
        var totalHeight: CGFloat = 0

        for subview in subviews {
            let size = subview.sizeThatFits(.unspecified)
            if currentX + size.width > maxWidth && currentX > 0 {
                currentX = 0
                currentY += lineHeight + spacing
                lineHeight = 0
            }
            positions.append(CGPoint(x: currentX, y: currentY))
            lineHeight = max(lineHeight, size.height)
            currentX += size.width + spacing
            totalHeight = max(totalHeight, currentY + lineHeight)
        }

        return (positions, CGSize(width: maxWidth, height: totalHeight))
    }
}

#Preview {
    TodayView()
        .modelContainer(for: [
            CycleEntry.self,
            Cycle.self,
            SymptomEntry.self,
        ], inMemory: true)
}
