import SwiftUI
import SwiftData

struct TodayView: View {
    @Environment(\.modelContext) private var modelContext
    @Environment(AppState.self) private var appState
    @State private var viewModel: CycleViewModel?
    @State private var showingLogPeriod = false
    @State private var showingLogSymptoms = false
    @State private var todaysSymptoms: [SymptomEntry] = []
    @State private var activeHint: String?
    @State private var quickLogFlow: FlowIntensity?
    @State private var showQuickLogSaved = false
    @State private var quickLogResetTask: Task<Void, Never>?
    @State private var fetchError: String?

    var body: some View {
        NavigationStack {
            ZStack {
                ScrollView {
                    VStack(spacing: AppTheme.spacing16) {
                        // Cycle status card
                        cycleStatusCard

                        // Quick period log inline
                        quickPeriodLogRow

                        // Quick actions
                        quickActionsSection

                        // Today's logged symptoms
                        todaysSymptomsSection

                        // Prediction card
                        predictionSection
                    }
                    .padding()
                }

                // Post-onboarding contextual hint
                if let hint = activeHint {
                    VStack {
                        Spacer()
                        TooltipOverlay(message: hint) {
                            dismissActiveHint()
                        }
                        .padding(.horizontal, AppTheme.spacing24)
                        .padding(.bottom, AppTheme.spacing32)
                    }
                }
            }
            .navigationTitle("Today")
            .sheet(isPresented: $showingLogPeriod, onDismiss: {
                viewModel?.loadData()
            }) {
                CycleLogView()
            }
            .sheet(isPresented: $showingLogSymptoms, onDismiss: {
                refreshTodaysSymptoms()
            }) {
                SymptomLogView()
            }
            .onAppear {
                if viewModel == nil {
                    let vm = CycleViewModel(modelContext: modelContext)
                    vm.loadData()
                    viewModel = vm
                }
                refreshTodaysSymptoms()
                showNextHintIfNeeded()
            }
        }
    }

    private func refreshTodaysSymptoms() {
        let calendar = Calendar.current
        let startOfDay = calendar.startOfDay(for: Date())
        let endOfDay = calendar.date(byAdding: .day, value: 1, to: startOfDay)!

        let descriptor = FetchDescriptor<SymptomEntry>(
            predicate: #Predicate<SymptomEntry> { entry in
                entry.date >= startOfDay && entry.date < endOfDay
            },
            sortBy: [SortDescriptor(\.date, order: .reverse)]
        )
        do {
            todaysSymptoms = try modelContext.fetch(descriptor)
            fetchError = nil
        } catch {
            todaysSymptoms = []
            fetchError = "Could not load today's symptoms."
        }
    }

    // MARK: - Subviews

    private var cycleStatusCard: some View {
        VStack(spacing: 12) {
            if let dayCount = viewModel?.currentCycleDayCount {
                Text("Day \(dayCount)")
                    .font(.system(.largeTitle, design: .rounded, weight: .bold))
                    .foregroundStyle(AppTheme.accentColor)
                    .contentTransition(.numericText())
                Text("of current cycle")
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
            } else {
                Text("Welcome")
                    .font(.title)
                    .fontWeight(.semibold)
                Text(personalizedWelcomeText)
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
        .animation(.easeInOut(duration: 0.3), value: viewModel?.currentCycleDayCount)
    }

    private var quickActionsSection: some View {
        HStack(spacing: AppTheme.spacing12) {
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
            if let fetchError {
                HStack {
                    Image(systemName: "exclamationmark.triangle")
                    Text(fetchError)
                }
                .font(.caption)
                .foregroundStyle(.orange)
                .padding()
            }

            if !todaysSymptoms.isEmpty {
                VStack(alignment: .leading, spacing: 8) {
                    Text("Today's Symptoms")
                        .font(.headline)

                    FlowLayout(spacing: 8) {
                        ForEach(todaysSymptoms) { symptom in
                            SymptomChip(
                                name: symptom.symptomType.displayName,
                                severity: symptom.severity
                            )
                        }
                    }
                }
                .frame(maxWidth: .infinity, alignment: .leading)
                .cardStyle()
            }
        }
    }

    private var personalizedWelcomeText: String {
        switch appState.onboardingProfile.primaryGoal {
        case .trackCycles:
            "Log your period to start tracking your cycle"
        case .understandSymptoms:
            "Log symptoms to start finding patterns"
        case nil:
            "Start tracking by logging your period"
        }
    }

    private func showNextHintIfNeeded() {
        let profile = appState.onboardingProfile
        guard appState.hasCompletedOnboarding else { return }

        if profile.shouldShowHint(OnboardingProfile.hintCalendarTab) {
            withAnimation(.easeInOut(duration: 0.3)) {
                activeHint = "Check the Calendar tab to see your cycle at a glance"
            }
        } else if todaysSymptoms.isEmpty,
                  profile.shouldShowHint(OnboardingProfile.hintLogSymptoms) {
            withAnimation(.easeInOut(duration: 0.3)) {
                activeHint = "Logging symptoms helps find patterns with your cycle"
            }
        }
    }

    private func dismissActiveHint() {
        let profile = appState.onboardingProfile
        if activeHint != nil {
            if profile.shouldShowHint(OnboardingProfile.hintCalendarTab) {
                profile.dismissHint(OnboardingProfile.hintCalendarTab)
            } else if profile.shouldShowHint(OnboardingProfile.hintLogSymptoms) {
                profile.dismissHint(OnboardingProfile.hintLogSymptoms)
            }
        }
        withAnimation(.easeInOut(duration: 0.2)) {
            activeHint = nil
        }
    }

    private var quickPeriodLogRow: some View {
        HStack(spacing: AppTheme.spacing12) {
            Image(systemName: "drop.fill")
                .font(.subheadline)
                .foregroundStyle(AppTheme.coralAccent)

            Text("Period today?")
                .font(.subheadline)
                .foregroundStyle(.secondary)

            Spacer()

            ForEach([FlowIntensity.light, .medium, .heavy], id: \.self) { intensity in
                Button {
                    quickLogPeriod(intensity: intensity)
                } label: {
                    Text(intensity.displayName)
                        .font(.caption)
                        .fontWeight(.medium)
                        .padding(.horizontal, 10)
                        .padding(.vertical, 6)
                        .background(
                            Capsule()
                                .fill(quickLogFlow == intensity
                                      ? AppTheme.coralAccent
                                      : AppTheme.coralAccent.opacity(0.12))
                        )
                        .foregroundStyle(quickLogFlow == intensity ? .white : AppTheme.coralAccent)
                }
                .buttonStyle(.plain)
            }
        }
        .cardStyle()
        .sensoryFeedback(.success, trigger: showQuickLogSaved)
    }

    private func quickLogPeriod(intensity: FlowIntensity) {
        guard let viewModel else { return }
        viewModel.selectedDate = Date()
        viewModel.selectedFlowIntensity = intensity
        viewModel.periodNotes = ""

        do {
            try viewModel.logPeriodDay()
            UserDefaults.standard.set(intensity.rawValue, forKey: "cycle.lastFlowIntensity")
            quickLogFlow = intensity
            showQuickLogSaved.toggle()
            quickLogResetTask?.cancel()
            quickLogResetTask = Task {
                try? await Task.sleep(for: .seconds(1.5))
                guard !Task.isCancelled else { return }
                quickLogFlow = nil
            }
        } catch {
            // Quick log is best-effort; full form available via sheet
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
                .cardStyle()
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
        .accessibilityLabel(title)
        .accessibilityAddTraits(.isButton)
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
            Text(severityLabel)
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
        .accessibilityLabel("\(name), severity \(severity) of 5, \(severityLabel)")
    }

    private var severityLabel: String {
        guard severity >= 1 && severity <= 5 else { return "" }
        return SeverityPicker.labels[severity - 1]
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
        .environment(AppState())
        .modelContainer(for: [
            CycleEntry.self,
            Cycle.self,
            SymptomEntry.self,
        ], inMemory: true)
}
