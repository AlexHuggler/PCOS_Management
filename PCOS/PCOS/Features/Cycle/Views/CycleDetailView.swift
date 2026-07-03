import SwiftUI
import SwiftData

struct CycleDetailView: View {
    @Environment(\.modelContext) private var modelContext
    @Environment(AppState.self) private var appState
    @State private var viewModel: CycleViewModel?
    @State private var manualOverrideEnabled = false
    @State private var manualOverrideDays = 35
    @State private var selectedOvulationStatus: OvulationStatus = .unknown
    @State private var settingsError: String?
    @State private var activeTooltip: String?
    @State private var showingPeriodEndSheet = false

    var body: some View {
        ScrollView {
            VStack(spacing: AppTheme.spacing24) {
                // Current cycle day counter
                currentCycleCard

                periodEndAction

                // Prediction card
                predictionCard

                // Prediction settings
                predictionSettingsCard

                // Statistics card
                statisticsCard

                // Cycle length trend chart
                cycleLengthChartCard

                // Recent cycles list
                recentCyclesCard
            }
            .padding()
        }
        .overlay {
            if let activeTooltip {
                Color.black.opacity(0.01)
                    .ignoresSafeArea()
                    .onTapGesture { dismissTooltip() }
                TooltipOverlay(message: activeTooltip) {
                    dismissTooltip()
                }
                .padding()
            }
        }
        .refreshable {
            await Task.yield()
            viewModel?.loadData()
        }
        .navigationTitle(L10n.string("Cycle Details", defaultValue: "Cycle Details"))
        .sheet(isPresented: $showingPeriodEndSheet, onDismiss: {
            viewModel?.loadData()
        }) {
            if let viewModel, let currentPeriodState = viewModel.currentPeriodState {
                PeriodEndSheet(
                    periodState: currentPeriodState,
                    onSave: { endDate, referenceDate in
                        try viewModel.markPeriodEnded(on: endDate, referenceDate: referenceDate)
                    },
                    onSaved: {
                        viewModel.loadData()
                    }
                )
            }
        }
        .onAppear {
            if viewModel == nil {
                let vm = CycleViewModel(modelContext: modelContext)
                vm.loadData()
                viewModel = vm
                hydratePredictionSettings(from: vm)
            } else if let viewModel {
                hydratePredictionSettings(from: viewModel)
            }
        }
    }

    // MARK: - Cards

    private var currentCycleCard: some View {
        VStack(spacing: AppTheme.spacing8) {
            if let dayCount = viewModel?.currentCycleDayCount {
                Text(L10n.format("Day %lld", defaultValue: "Day %lld", Int64(dayCount)))
                    .appFont(.largeTitle, weight: .bold)
                    .foregroundStyle(AppTheme.accentColor)
                    .contentTransition(.numericText())
                Text(L10n.string("of current cycle", defaultValue: "of current cycle"))
                    .appFont(.subheadline)
                    .foregroundStyle(.secondary)
            } else {
                Text(L10n.string("No Active Cycle", defaultValue: "No Active Cycle"))
                    .appFont(.title2)
                    .foregroundStyle(.secondary)
                Text(L10n.string("Log a period to start tracking", defaultValue: "Log a period to start tracking"))
                    .appFont(.subheadline)
                    .foregroundStyle(.tertiary)
            }

            if let endedText = currentPeriodEndedText {
                Text(endedText)
                    .appFont(.caption)
                    .foregroundStyle(AppTheme.sage)
                    .multilineTextAlignment(.center)
                    .lineLimit(2)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, AppTheme.spacing24)
        .cardStyle(cornerRadius: 16)
    }

    @ViewBuilder
    private var periodEndAction: some View {
        if canShowPeriodEndAction {
            Button {
                showingPeriodEndSheet = true
            } label: {
                Label(periodEndButtonTitle, systemImage: "calendar.badge.checkmark")
                    .appFont(.subheadline, weight: .semibold)
                    .foregroundStyle(.white)
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 12)
                    .background(Capsule().fill(AppTheme.accentColor))
            }
            .buttonStyle(.plain)
            .accessibilityIdentifier("cycle_detail.period_end_button")
        }
    }

    private var predictionCard: some View {
        Group {
            if let predictionText = viewModel?.predictionPrimaryText,
               let confidenceValue = viewModel?.predictionConfidenceValue {
                VStack(alignment: .leading, spacing: AppTheme.spacing8) {
                    Label(viewModel?.hasActionablePrediction == true ? L10n.string("Next Period Estimate", defaultValue: "Next Period Estimate") : L10n.string("Estimate Update", defaultValue: "Estimate Update"), systemImage: "sparkles")
                        .appFont(.headline)
                        .foregroundStyle(AppTheme.coralAccent)

                    Text(predictionText)
                        .appFont(.body)

                    if let secondaryText = viewModel?.predictionSecondaryText {
                        Text(secondaryText)
                            .appFont(.caption)
                            .foregroundStyle(.secondary)
                    }

                    if appState.showScientificDetail {
                        HStack {
                            Text(viewModel?.predictionConfidenceText ?? L10n.string("Confidence", defaultValue: "Confidence"))
                                .appFont(.caption)
                                .foregroundStyle(.secondary)
                            ProgressView(value: confidenceValue)
                                .tint(AppTheme.accentColor)
                        }
                    } else {
                        Text(qualitativeConfidenceLabel(confidenceValue))
                            .appFont(.caption)
                            .foregroundStyle(.secondary)
                    }
                }
                .frame(maxWidth: .infinity, alignment: .leading)
                .cardStyle()
            }
        }
    }

    private var predictionSettingsCard: some View {
        Group {
            if viewModel != nil {
                VStack(alignment: .leading, spacing: AppTheme.spacing12) {
                    HStack {
                        Text(L10n.string("Prediction Settings", defaultValue: "Prediction Settings"))
                            .appFont(.headline)
                        infoButton(L10n.string(
                            "tooltip.prediction_settings",
                            defaultValue: "These settings help CycleBalance predict your next period more accurately based on your unique cycle patterns."
                        ))
                    }

                    HStack {
                        Toggle(
                            L10n.string("Manual cycle length override", defaultValue: "Manual cycle length override"),
                            isOn: $manualOverrideEnabled
                        )
                        infoButton(L10n.string(
                            "tooltip.manual_override",
                            defaultValue: "Turn this on if you already know your typical cycle length — for example, from tracking with your provider. The app will use this instead of calculating it automatically."
                        ))
                    }

                    if manualOverrideEnabled {
                        Stepper(value: $manualOverrideDays, in: 15...120) {
                            Text(L10n.format("Expected cycle length: %lld days", defaultValue: "Expected cycle length: %lld days", Int64(manualOverrideDays)))
                                .appFont(.subheadline)
                        }
                    }

                    HStack {
                        Picker(L10n.string("Ovulation status", defaultValue: "Ovulation status"), selection: $selectedOvulationStatus) {
                            ForEach(OvulationStatus.allCases) { status in
                                Text(status.displayName).tag(status)
                            }
                        }
                        .pickerStyle(.segmented)
                        infoButton(L10n.string(
                            "tooltip.ovulation_status",
                            defaultValue: "Unknown: Default — the app predicts without assuming ovulation patterns.\n\nOvulatory: Choose if you track ovulation with OPKs or BBT and your cycles include ovulation.\n\nAnovulatory: Choose if your cycles typically don't include ovulation, which is common with PCOS."
                        ))
                    }

                    Button {
                        savePredictionSettings()
                    } label: {
                        Text(L10n.string("Apply Settings", defaultValue: "Apply Settings"))
                            .appFont(.subheadline, weight: .semibold)
                            .frame(maxWidth: .infinity)
                            .padding(.vertical, 10)
                            .background(
                                Capsule()
                                    .fill(AppTheme.accentColor)
                            )
                            .foregroundStyle(.white)
                    }
                    .buttonStyle(.plain)

                    if !appState.allowsPremiumAccess {
                        Text(L10n.string("Free tier shows cycle history for the last 30 days.", defaultValue: "Free tier shows cycle history for the last 30 days."))
                            .appFont(.caption)
                            .foregroundStyle(.secondary)
                    }

                    if let settingsError {
                        Text(settingsError)
                            .appFont(.caption)
                            .foregroundStyle(.red)
                    }
                }
                .frame(maxWidth: .infinity, alignment: .leading)
                .cardStyle()
            }
        }
    }

    private var statisticsCard: some View {
        Group {
            if let stats = viewModel?.statistics {
                VStack(alignment: .leading, spacing: AppTheme.spacing12) {
                    HStack {
                        Text(L10n.string("Cycle Statistics", defaultValue: "Cycle Statistics"))
                            .appFont(.headline)
                        infoButton(L10n.string(
                            "tooltip.cycle_statistics",
                            defaultValue: "A snapshot of your cycle history. 'Average' is your typical cycle length, 'Range' shows your shortest to longest, and 'Cycles' is how many complete cycles you've tracked."
                        ))
                    }

                    HStack(spacing: AppTheme.spacing16) {
                        StatisticItem(
                            title: L10n.string("Average", defaultValue: "Average"),
                            value: L10n.format("%@ days", defaultValue: "%@ days", stats.formattedAverage)
                        )
                        StatisticItem(
                            title: L10n.string("Range", defaultValue: "Range"),
                            value: stats.rangeDescription
                        )
                        StatisticItem(
                            title: L10n.string("Cycles", defaultValue: "Cycles"),
                            value: "\(stats.totalCycles)"
                        )
                    }
                }
                .frame(maxWidth: .infinity, alignment: .leading)
                .cardStyle()
            }
        }
    }

    private var cycleLengthChartCard: some View {
        Group {
            let completedCycles = visibleCompletedCycles
            if completedCycles.count >= 2 {
                let lengths: [(cycleNumber: Int, days: Int)] = completedCycles.enumerated().compactMap { index, cycle in
                    guard let days = cycle.manualCycleLengthOverrideDays ?? cycle.lengthDays else { return nil }
                    return (cycleNumber: index + 1, days: days)
                }
                VStack(alignment: .leading, spacing: AppTheme.spacing12) {
                    Text(L10n.string("Cycle Length Trend", defaultValue: "Cycle Length Trend"))
                        .appFont(.headline)

                    CycleLengthChart(cycleLengths: lengths)
                }
                .frame(maxWidth: .infinity, alignment: .leading)
                .cardStyle()
            }
        }
    }

    private var recentCyclesCard: some View {
        Group {
            let completedCycles = visibleCompletedCycles
            if !completedCycles.isEmpty {
                VStack(alignment: .leading, spacing: AppTheme.spacing8) {
                    Text(L10n.string("Recent Cycles", defaultValue: "Recent Cycles"))
                        .appFont(.headline)

                    ForEach(completedCycles.suffix(6).reversed()) { cycle in
                        HStack {
                            Text(formatDate(cycle.startDate))
                                .appFont(.subheadline)
                            Spacer()
                            if let length = cycle.manualCycleLengthOverrideDays ?? cycle.lengthDays {
                                Text(L10n.format("%lld days", defaultValue: "%lld days", Int64(length)))
                                    .appFont(.subheadline, weight: .medium)
                                    .foregroundStyle(AppTheme.accentColor)
                            }
                        }
                        .padding(.vertical, AppTheme.spacing4)
                        Divider()
                    }
                }
                .frame(maxWidth: .infinity, alignment: .leading)
                .cardStyle()
            }
        }
    }

    private func formatDate(_ date: Date) -> String {
        let formatter = DateFormatter()
        formatter.dateStyle = .medium
        formatter.locale = L10n.locale()
        return formatter.string(from: date)
    }

    private var visibleCompletedCycles: [Cycle] {
        let completed = viewModel?.cycles.filter { !$0.isPredicted && ($0.lengthDays != nil || $0.manualCycleLengthOverrideDays != nil) } ?? []
        guard let earliest = FreeTierPolicyService().earliestAccessibleCycleHistoryDate(now: Date(), isPremium: appState.allowsPremiumAccess) else {
            return completed
        }
        return completed.filter { $0.startDate >= earliest }
    }

    private var canShowPeriodEndAction: Bool {
        guard let viewModel else { return false }
        return viewModel.canMarkPeriodEnd && viewModel.currentPeriodState != nil
    }

    private var periodEndButtonTitle: String {
        guard viewModel?.currentPeriodState?.isActive == false else {
            return L10n.string("Mark Period End", defaultValue: "Mark Period End")
        }
        return L10n.string("Edit Period End Date", defaultValue: "Edit Period End Date")
    }

    private var currentPeriodEndedText: String? {
        guard let state = viewModel?.currentPeriodState,
              state.isActive == false,
              let endedDate = state.periodEndedDate
        else { return nil }
        return L10n.format(
            "Period ended %@",
            defaultValue: "Period ended %@",
            formatDate(endedDate)
        )
    }

    private func hydratePredictionSettings(from viewModel: CycleViewModel) {
        if let override = viewModel.currentManualCycleLengthOverride {
            manualOverrideEnabled = true
            manualOverrideDays = override
        } else {
            manualOverrideEnabled = false
        }
        selectedOvulationStatus = viewModel.currentOvulationStatus
        settingsError = nil
    }

    private func infoButton(_ message: String) -> some View {
        Button {
            withAnimation(.easeInOut(duration: 0.2)) {
                activeTooltip = (activeTooltip == message) ? nil : message
            }
        } label: {
            Image(systemName: "info.circle")
                .appFont(.subheadline)
                .foregroundStyle(.secondary)
        }
        .buttonStyle(.plain)
    }

    private func qualitativeConfidenceLabel(_ value: Double) -> String {
        let pct = Int((value * 100).rounded())
        if pct >= 75 {
            return L10n.string("Strong estimate", defaultValue: "Strong estimate")
        } else if pct >= 50 {
            return L10n.string("Moderate estimate", defaultValue: "Moderate estimate")
        } else {
            return L10n.string("Rough estimate", defaultValue: "Rough estimate")
        }
    }

    private func dismissTooltip() {
        withAnimation(.easeInOut(duration: 0.2)) {
            activeTooltip = nil
        }
    }

    private func savePredictionSettings() {
        do {
            try viewModel?.updateCurrentCycleSettings(
                manualCycleLengthOverrideDays: manualOverrideEnabled ? manualOverrideDays : nil,
                ovulationStatus: selectedOvulationStatus
            )
            settingsError = nil
        } catch {
            settingsError = String(
                localized: "Could not save prediction settings: \(error.localizedDescription)",
                comment: "Cycle detail error shown when prediction settings fail to save."
            )
        }
    }
}

struct StatisticItem: View {
    let title: String
    let value: String

    var body: some View {
        VStack(spacing: AppTheme.spacing4) {
            Text(value)
                .appFont(.title3, weight: .semibold)
            Text(title)
                .appFont(.caption)
                .foregroundStyle(.secondary)
        }
        .frame(maxWidth: .infinity)
    }
}

#Preview {
    NavigationStack {
        CycleDetailView()
    }
    .environment(AppState())
    .modelContainer(for: [CycleEntry.self, Cycle.self], inMemory: true)
}
