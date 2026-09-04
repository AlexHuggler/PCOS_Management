import SwiftUI
import SwiftData

struct SupplementHistoryView: View {
    @Environment(\.modelContext) private var modelContext
    @ScaledMetric(relativeTo: .title2) private var adherenceRingDiameter: CGFloat = 120
    @State private var viewModel: SupplementViewModel?
    @State private var selectedRange: DateRange = .week
    @State private var adherence: AdherenceStats = AdherenceStats(totalScheduled: 0, totalTaken: 0)
    @State private var supplementBreakdown: [SupplementBreakdown] = []
    @State private var dosageChanges: [SupplementDosageChange] = []

    private enum DateRange: Int, CaseIterable, Identifiable {
        case week = 7
        case month = 30
        case quarter = 90

        var id: Int { rawValue }

        var label: String {
            switch self {
            case .week:
                String(localized: "7 Days", comment: "Supplement history filter option for the last seven days.")
            case .month:
                String(localized: "30 Days", comment: "Supplement history filter option for the last thirty days.")
            case .quarter:
                String(localized: "90 Days", comment: "Supplement history filter option for the last ninety days.")
            }
        }
    }

    private struct SupplementBreakdown: Identifiable {
        let id = UUID()
        let name: String
        let takenCount: Int
        let missedCount: Int
        var total: Int { takenCount + missedCount }
    }

    var body: some View {
        ScrollView {
            VStack(spacing: AppTheme.spacing16) {
                // MARK: - Date Range Selector
                Picker(
                    String(localized: "Date Range", comment: "Label for the supplement history date range picker."),
                    selection: $selectedRange
                ) {
                    ForEach(DateRange.allCases) { range in
                        Text(range.label).tag(range)
                    }
                }
                .pickerStyle(.segmented)
                .padding(.horizontal)

                // MARK: - Adherence Ring
                adherenceRing

                // MARK: - Breakdown by Supplement
                supplementBreakdownSection

                // MARK: - Dosage Change Timeline
                dosageChangesSection
            }
            .padding(.vertical)
        }
        .scrollContentBackground(.hidden)
        .background(AppTheme.usesPremiumEditorStyling ? AppTheme.premiumEditorBackground : Color.clear)
        .navigationTitle(AppTheme.usesPremiumEditorStyling ? "" : String(localized: "Supplement History", comment: "Navigation title for supplement history."))
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            if AppTheme.usesPremiumEditorStyling {
                ToolbarItem(placement: .principal) {
                    Text(String(localized: "Supplement patterns", comment: "Navigation title for Lunar Calm supplement history."))
                        .appFont(.headline, weight: .semibold)
                        .foregroundStyle(AppTheme.primaryText)
                }
            }
        }
        .lunarSupplementHistoryNavigationBackground()
        .accessibilityIdentifier("screen.supplement_history")
        .onAppear {
            let vm = SupplementViewModel(modelContext: modelContext)
            viewModel = vm
            refreshStats()
        }
        .onChange(of: selectedRange) { _, _ in
            refreshStats()
        }
    }

    // MARK: - Adherence Ring

    private var adherenceRing: some View {
        VStack(spacing: AppTheme.spacing12) {
            ZStack {
                // Background ring
                Circle()
                    .stroke(AppTheme.usesPremiumEditorStyling ? AppTheme.premiumEditorBorder.opacity(0.72) : Color(.tertiarySystemFill), lineWidth: 12)
                    .frame(width: clampedAdherenceRingDiameter, height: clampedAdherenceRingDiameter)

                // Progress ring
                Circle()
                    .trim(from: 0, to: min(adherence.percentage / 100, 1.0))
                    .stroke(
                        adherenceColor,
                        style: StrokeStyle(lineWidth: 12, lineCap: .round)
                    )
                    .frame(width: clampedAdherenceRingDiameter, height: clampedAdherenceRingDiameter)
                    .rotationEffect(.degrees(-90))
                    .animation(.easeInOut(duration: 0.5), value: adherence.percentage)

                // Percentage text
                VStack(spacing: 2) {
                    Text("\(Int(adherence.percentage))%")
                        .appFont(.title2, weight: .bold)
                        .foregroundStyle(adherenceColor)
                        .contentTransition(.numericText())

                    Text(String(localized: "adherence", comment: "Supplement adherence summary label."))
                        .appFont(.caption2)
                        .foregroundStyle(AppTheme.secondaryText)

                    Text(adherenceStatusLabel)
                        .appFont(.caption2, weight: .medium)
                        .foregroundStyle(adherenceColor)
                        .lineLimit(1)
                        .minimumScaleFactor(0.66)
                }
                .frame(width: clampedAdherenceRingDiameter * 0.72)
            }

            HStack(spacing: AppTheme.spacing16) {
                statLabel(
                    value: "\(adherence.totalTaken)",
                    label: String(localized: "Taken", comment: "Supplement adherence status label for doses that were taken."),
                    color: AppTheme.sage
                )
                statLabel(
                    value: "\(adherence.totalScheduled - adherence.totalTaken)",
                    label: String(localized: "Missed", comment: "Supplement adherence status label for doses that were missed."),
                    color: AppTheme.coralAccent
                )
                statLabel(
                    value: "\(adherence.totalScheduled)",
                    label: String(localized: "Total", comment: "Supplement adherence status label for the total number of doses."),
                    color: .secondary
                )
            }
            .frame(maxWidth: .infinity)
        }
        .frame(maxWidth: .infinity)
        .lunarSupplementHistoryCard()
        .padding(.horizontal)
        .accessibilityElement(children: .contain)
        .accessibilityIdentifier("supplement_history.lunar.adherence")
    }

    private func statLabel(value: String, label: String, color: Color) -> some View {
        VStack(spacing: AppTheme.spacing4) {
            Text(value)
                .appFont(.headline)
                .foregroundStyle(color)
            Text(label)
                .appFont(.caption)
                .foregroundStyle(.secondary)
        }
    }

    private var adherenceColor: Color {
        if AppTheme.usesPremiumEditorStyling {
            if adherence.percentage >= 80 {
                return AppTheme.premiumEditorAccentColor
            } else if adherence.percentage >= 50 {
                return AppTheme.premiumEditorSecondaryAccentColor
            } else {
                return AppTheme.premiumEditorWarningAccentColor
            }
        }

        if adherence.percentage >= 80 {
            return AppTheme.sage
        } else if adherence.percentage >= 50 {
            return .orange
        } else {
            return AppTheme.coralAccent
        }
    }

    /// Text label for adherence status so color-blind users can identify the category.
    private var adherenceStatusLabel: String {
        if adherence.percentage >= 80 {
            return String(localized: "On Track", comment: "Adherence status label when adherence is 80% or above.")
        } else if adherence.percentage >= 50 {
            return String(localized: "Needs Improvement", comment: "Adherence status label when adherence is between 50% and 79%.")
        } else {
            return String(localized: "Low Adherence", comment: "Adherence status label when adherence is below 50%.")
        }
    }

    private var clampedAdherenceRingDiameter: CGFloat {
        min(max(adherenceRingDiameter, 96), 156)
    }

    // MARK: - Breakdown Section

    private var supplementBreakdownSection: some View {
        VStack(alignment: .leading, spacing: AppTheme.spacing12) {
            if AppTheme.usesPremiumEditorStyling {
                lunarHistorySectionHeader(
                    title: String(localized: "By supplement", comment: "Lunar Calm supplement history breakdown section title."),
                    subtitle: String(localized: "Taken and missed doses by item", comment: "Lunar Calm supplement history breakdown section subtitle."),
                    systemImage: "pills.fill"
                )
                .padding(.horizontal)
            } else {
                AppTheme.sectionHeader(String(localized: "By Supplement", comment: "Section title for supplement history broken down by supplement."))
                    .padding(.horizontal)
            }

            if supplementBreakdown.isEmpty {
                VStack(spacing: AppTheme.spacing8) {
                    Text(String(localized: "No supplement data", comment: "Empty state title shown when there is no supplement history."))
                        .appFont(.subheadline)
                        .foregroundStyle(.secondary)
                    Text(
                        String(
                            localized: "Start logging supplements to see your history here.",
                            comment: "Empty state message prompting the user to log supplements first."
                        )
                    )
                        .appFont(.caption)
                        .foregroundStyle(.tertiary)
                        .multilineTextAlignment(.center)
                }
                .frame(maxWidth: .infinity)
                .padding(.vertical, AppTheme.spacing24)
                .padding(.horizontal)
                .lunarSupplementHistoryCard()
                .padding(.horizontal)
            } else {
                ForEach(supplementBreakdown) { item in
                    HStack(spacing: AppTheme.spacing12) {
                        Image(systemName: "pill.fill")
                            .appFont(.body)
                            .foregroundStyle(historyAccent)
                            .frame(width: 28)

                        VStack(alignment: .leading, spacing: AppTheme.spacing4) {
                            Text(item.name)
                                .appFont(.subheadline, weight: .medium)

                            // Mini progress bar
                            GeometryReader { geo in
                                ZStack(alignment: .leading) {
                                    RoundedRectangle(cornerRadius: 3)
                                        .fill(AppTheme.usesPremiumEditorStyling ? AppTheme.premiumEditorBorder.opacity(0.6) : Color(.tertiarySystemFill))
                                        .frame(height: 6)

                                    RoundedRectangle(cornerRadius: 3)
                                        .fill(historyAccent)
                                        .frame(
                                            width: item.total > 0
                                                ? geo.size.width * CGFloat(item.takenCount) / CGFloat(item.total)
                                                : 0,
                                            height: 6
                                        )
                                        .animation(.easeInOut(duration: 0.4), value: item.takenCount)
                                }
                            }
                            .frame(height: 6)
                        }

                        VStack(alignment: .trailing, spacing: 2) {
                            Text("\(item.takenCount)/\(item.total)")
                                .appFont(.caption, weight: .medium)
                                .foregroundStyle(AppTheme.primaryText)

                            if item.missedCount > 0 {
                                Text(
                                    String(
                                        localized: "\(item.missedCount) missed",
                                        comment: "Supplement history label showing how many scheduled supplement doses were missed."
                                    )
                                )
                                    .appFont(.caption2)
                                    .foregroundStyle(AppTheme.coralAccent)
                            }
                        }
                    }
                    .padding(.vertical, AppTheme.spacing8)
                    .padding(.horizontal, AppTheme.spacing12)
                    .lunarSupplementHistoryCard(cornerRadius: AppTheme.cornerRadiusMedium)
                    .padding(.horizontal)
                }
            }
        }
    }

    private var dosageChangesSection: some View {
        VStack(alignment: .leading, spacing: AppTheme.spacing12) {
            if AppTheme.usesPremiumEditorStyling {
                lunarHistorySectionHeader(
                    title: String(localized: "Dosage timeline", comment: "Lunar Calm supplement history dosage timeline section title."),
                    subtitle: String(localized: "Changes appear here when doses shift", comment: "Lunar Calm supplement history dosage timeline section subtitle."),
                    systemImage: "arrow.triangle.2.circlepath"
                )
                .padding(.horizontal)
            } else {
                AppTheme.sectionHeader("Dosage Change Timeline")
                    .padding(.horizontal)
            }

            if dosageChanges.isEmpty {
                VStack(spacing: AppTheme.spacing8) {
                    Text("No dosage changes yet")
                        .appFont(.subheadline)
                        .foregroundStyle(.secondary)
                    Text("When you log a different dosage for the same supplement, it will appear here.")
                        .appFont(.caption)
                        .foregroundStyle(.tertiary)
                        .multilineTextAlignment(.center)
                }
                .frame(maxWidth: .infinity)
                .padding(.vertical, AppTheme.spacing24)
                .padding(.horizontal)
                .lunarSupplementHistoryCard()
                .padding(.horizontal)
            } else {
                ForEach(dosageChanges) { change in
                    HStack(spacing: AppTheme.spacing12) {
                        Image(systemName: "arrow.triangle.2.circlepath")
                            .foregroundStyle(historyAccent)
                            .frame(width: 24)

                        VStack(alignment: .leading, spacing: 2) {
                            Text(change.supplementName)
                                .appFont(.subheadline, weight: .medium)
                            Text(change.date, format: .dateTime.month(.abbreviated).day().year())
                                .appFont(.caption)
                                .foregroundStyle(.secondary)
                        }

                        Spacer()

                        Text("\(formattedDosage(change.previousDosageMg, unit: change.dosageUnit)) → \(formattedDosage(change.newDosageMg, unit: change.dosageUnit))")
                            .appFont(.caption, weight: .medium)
                            .foregroundStyle(AppTheme.coralAccent)
                    }
                    .padding(.vertical, AppTheme.spacing8)
                    .padding(.horizontal, AppTheme.spacing12)
                    .lunarSupplementHistoryCard(cornerRadius: AppTheme.cornerRadiusMedium)
                    .padding(.horizontal)
                }
            }
        }
    }

    private var historyAccent: Color {
        AppTheme.usesPremiumEditorStyling ? AppTheme.premiumEditorAccentColor : AppTheme.sage
    }

    private func lunarHistorySectionHeader(title: String, subtitle: String, systemImage: String) -> some View {
        HStack(alignment: .top, spacing: AppTheme.spacing12) {
            Image(systemName: systemImage)
                .font(.system(size: 14, weight: .semibold))
                .foregroundStyle(AppTheme.premiumEditorAccentGradient)
                .frame(width: 32, height: 32)
                .background(Circle().fill(historyAccent.opacity(0.12)))

            VStack(alignment: .leading, spacing: 2) {
                Text(title)
                    .appFont(.headline, weight: .semibold)
                    .foregroundStyle(AppTheme.primaryText)
                Text(subtitle)
                    .appFont(.caption)
                    .foregroundStyle(AppTheme.secondaryText)
            }

            Spacer(minLength: 0)
        }
    }

    // MARK: - Data Refresh

    private func refreshStats() {
        guard let viewModel else { return }
        let days = selectedRange.rawValue
        adherence = viewModel.calculateAdherence(days: days)
        loadBreakdown(days: days)
        loadDosageChanges(days: days)
    }

    private func loadBreakdown(days: Int) {
        guard let viewModel else { return }
        let logs = viewModel.fetchLogs(days: days)
        let grouped = Dictionary(grouping: logs, by: \.supplementName)
        supplementBreakdown = grouped.map { name, entries in
            SupplementBreakdown(
                name: name,
                takenCount: entries.filter(\.taken).count,
                missedCount: entries.filter { !$0.taken }.count
            )
        }
        .sorted { $0.name < $1.name }
    }

    private func loadDosageChanges(days: Int) {
        guard let viewModel else { return }
        dosageChanges = viewModel.dosageChanges(days: days)
    }

    private func formattedDosage(_ dosage: Double, unit: DosageUnit) -> String {
        DosageUnit.formatted(dosage, unit: unit)
    }
}

private extension View {
    @ViewBuilder
    func lunarSupplementHistoryNavigationBackground() -> some View {
        if AppTheme.usesPremiumEditorStyling {
            toolbarBackground(AppTheme.premiumEditorBackground, for: .navigationBar)
                .toolbarBackground(.visible, for: .navigationBar)
        } else {
            self
        }
    }

    @ViewBuilder
    func lunarSupplementHistoryCard(cornerRadius: CGFloat = AppTheme.cornerRadiusLarge) -> some View {
        if AppTheme.usesPremiumEditorStyling {
            background(
                RoundedRectangle(cornerRadius: cornerRadius, style: .continuous)
                    .fill(
                        LinearGradient(
                            colors: [
                                AppTheme.premiumEditorRaisedSurface.opacity(0.92),
                                AppTheme.premiumEditorSurface.opacity(0.78),
                                AppTheme.premiumEditorBackground.opacity(0.9)
                            ],
                            startPoint: .topLeading,
                            endPoint: .bottomTrailing
                        )
                    )
            )
            .overlay(
                RoundedRectangle(cornerRadius: cornerRadius, style: .continuous)
                    .stroke(AppTheme.premiumEditorBorderGradient, lineWidth: 0.85)
            )
            .shadow(color: AppTheme.cardShadowColor, radius: 18, y: 12)
        } else {
            cardStyle(cornerRadius: cornerRadius)
        }
    }
}

#Preview {
    NavigationStack {
        SupplementHistoryView()
    }
    .modelContainer(for: SupplementLog.self, inMemory: true)
}
