import SwiftUI
import SwiftData

struct CalendarMonthView: View {
    @Environment(\.modelContext) private var modelContext
    @Environment(AppState.self) private var appState
    @State private var viewModel: CycleViewModel?
    @State private var displayedMonth = Date()
    @State private var entries: [Int: CycleEntry] = [:]
    @State private var predictedDays: Set<Int> = []
    @State private var fertileWindowDays: Set<Int> = []
    @State private var ovulationDay: Int?
    @State private var showingLogSheet = false
    @State private var showingDayLogSheet = false
    @State private var showingMonthPicker = false
    @State private var selectedDayDate: Date?
    @State private var pregnancyViewModel: PregnancyViewModel?

    private let columns = Array(repeating: GridItem(.flexible(), spacing: AppTheme.spacing4), count: 7)
    private let freeTierPolicy: any FreeTierPolicyEnforcing = FreeTierPolicyService()

    private enum CalendarGridCell: Hashable {
        case placeholder(Int)
        case day(Int)
    }

    private var calendar: Calendar {
        var localizedCalendar = Calendar.autoupdatingCurrent
        localizedCalendar.locale = L10n.locale(for: appState.selectedAppLanguage)
        return localizedCalendar
    }

    /// Locale-aware short weekday symbols starting from the calendar's first weekday
    private var orderedWeekdaySymbols: [String] {
        let symbols = calendar.shortWeekdaySymbols
        let firstIndex = calendar.firstWeekday - 1
        return Array(symbols[firstIndex...]) + Array(symbols[..<firstIndex])
    }

    var body: some View {
        NavigationStack {
            ZStack {
                BotanicalScreenBackground(style: .dashboard)

                ScrollView {
                    VStack(spacing: AppTheme.spacing16) {
                        BotanicalPosterHeader(
                            title: monthYearString,
                            subtitle: L10n.string(
                                "Notice your cycle rhythm across moons, symptoms, and flow patterns.",
                                defaultValue: "Notice your cycle rhythm across moons, symptoms, and flow patterns."
                            ),
                            emblemAssetName: "botanical-calendar-illustration",
                            dividerStyle: .moon
                        )
                        .padding(.top, AppTheme.spacing8)

                        // Month navigation header
                        monthHeader

                        // Days of week header
                        daysOfWeekHeader

                        // Calendar grid
                        calendarGrid

                        // Cycle info section
                        cycleInfoSection
                    }
                    .padding()
                    .padding(.bottom, AppTheme.botanicalScrollableBottomPadding)
                }
            }
            .accessibilityElement(children: .contain)
            .accessibilityIdentifier("screen.calendar")
            .id(appState.languageRenderKey)
            .refreshable {
                await Task.yield()
                viewModel?.loadData()
                loadMonthEntries()
            }
            .navigationTitle(
                L10n.string(
                    "Calendar",
                    defaultValue: "Calendar",
                    language: appState.selectedAppLanguage
                )
            )
            .toolbar {
                ToolbarItem(placement: .primaryAction) {
                    if appState.lifecycleMode != .pregnant {
                        Button {
                            showingLogSheet = true
                        } label: {
                            Label(L10n.string("Log Period", defaultValue: "Log Period"), systemImage: "plus")
                        }
                    }
                }
            }
            .sheet(isPresented: $showingLogSheet, onDismiss: {
                viewModel?.loadData()
                loadMonthEntries()
            }) {
                CycleLogView()
            }
            .sheet(isPresented: $showingDayLogSheet, onDismiss: {
                viewModel?.loadData()
                loadMonthEntries()
            }) {
                CycleLogView(initialDate: selectedDayDate)
            }
            .onAppear {
                if viewModel == nil {
                    let vm = CycleViewModel(modelContext: modelContext)
                    vm.loadData()
                    viewModel = vm
                }
                if pregnancyViewModel == nil {
                    let pvm = PregnancyViewModel(modelContext: modelContext)
                    pvm.loadData()
                    pregnancyViewModel = pvm
                }
                loadMonthEntries()
            }
            .onChange(of: displayedMonth) { _, _ in
                loadMonthEntries()
            }
        }
    }

    // MARK: - Subviews

    private var monthHeader: some View {
        HStack {
            Button {
                moveMonth(by: -1)
            } label: {
                Image(systemName: "chevron.left")
                    .appFont(.title3)
            }
            .accessibilityLabel(
                L10n.string("Previous month", defaultValue: "Previous month")
            )

            Spacer()

            Button {
                showingMonthPicker = true
            } label: {
                HStack(spacing: AppTheme.spacing4) {
                    Text(monthYearString)
                        .appHeadingFont(.title2, weight: .regular)
                        .foregroundStyle(AppTheme.primaryText)
                        .multilineTextAlignment(.center)
                        .lineLimit(2)
                        .minimumScaleFactor(0.85)
                        .fixedSize(horizontal: false, vertical: true)
                    Image(systemName: "chevron.down")
                        .appFont(.caption)
                        .foregroundStyle(.secondary)
                }
            }
            .buttonStyle(.plain)
            .accessibilityLabel(
                L10n.format(
                    "Jump to month, %@",
                    defaultValue: "Jump to month, %@",
                    monthYearString
                )
            )
            .accessibilityHint(
                L10n.string(
                    "Double tap to open month and year picker",
                    defaultValue: "Double tap to open month and year picker"
                )
            )

            Spacer()

            Button {
                moveMonth(by: 1)
            } label: {
                Image(systemName: "chevron.right")
                    .appFont(.title3)
            }
            .accessibilityLabel(
                L10n.string("Next month", defaultValue: "Next month")
            )
        }
        .padding(.horizontal)
        .cardStyle(cornerRadius: AppTheme.defaultCardCornerRadius)
        .sensoryFeedback(.selection, trigger: displayedMonth)
        .sensoryFeedback(.selection, trigger: showingDayLogSheet)
        .sheet(isPresented: $showingMonthPicker) {
            MonthYearPicker(
                selectedDate: $displayedMonth,
                hasPremiumAccess: appState.allowsPremiumAccess,
                freeTierPolicy: freeTierPolicy
            )
            .presentationDetents([.medium])
        }
    }

    private var daysOfWeekHeader: some View {
        LazyVGrid(columns: columns, spacing: AppTheme.spacing4) {
            ForEach(Array(orderedWeekdaySymbols.enumerated()), id: \.offset) { index, day in
                Text(day)
                    .appFont(.caption, weight: .medium)
                    .foregroundStyle(.secondary)
                    .frame(maxWidth: .infinity)
                    .lineLimit(1)
                    .minimumScaleFactor(0.75)
                    .accessibilityIdentifier("calendar.weekday.\(index)")
            }
        }
        .accessibilityIdentifier("calendar.weekdays")
    }

    private var calendarGrid: some View {
        LazyVGrid(columns: columns, spacing: AppTheme.spacing4) {
            ForEach(calendarGridCells, id: \.self) { cell in
                switch cell {
                case .placeholder:
                    Color.clear
                        .frame(minHeight: 44)
                case .day(let day):
                    Group {
                        if appState.lifecycleMode == .pregnant, isPregnancyDay(day: day) {
                            PregnancyCalendarDayCell(
                                day: day,
                                isToday: isToday(day: day),
                                isPregnancyDay: true,
                                monthDate: displayedMonth,
                                locale: appState.renderLocale
                            )
                        } else {
                            CalendarDayCell(
                                day: day,
                                isToday: isToday(day: day),
                                entry: entries[day],
                                isPredicted: predictedDays.contains(day),
                                isFertileWindow: fertileWindowDays.contains(day),
                                isOvulationDay: ovulationDay == day,
                                monthDate: displayedMonth,
                                locale: appState.renderLocale
                            )
                        }
                    }
                    .contentShape(Rectangle())
                    .onTapGesture {
                        if let date = dateForDay(day), date <= Date() {
                            guard freeTierPolicy.isCycleDateAccessible(date, now: Date(), isPremium: appState.allowsPremiumAccess) else {
                                appState.presentPremiumPaywall()
                                return
                            }
                            selectedDayDate = date
                            showingDayLogSheet = true
                        }
                    }
                }
            }
        }
        .padding(AppTheme.isBotanicalJournal ? AppTheme.spacing12 : 0)
        .cardStyle(cornerRadius: AppTheme.largeCardCornerRadius)
        .accessibilityIdentifier("calendar.grid")
    }

    private var cycleInfoSection: some View {
        NavigationLink {
            CycleDetailView()
        } label: {
            VStack(alignment: .leading, spacing: AppTheme.spacing8) {
                if let dayCount = viewModel?.currentCycleDayCount {
                    HStack {
                        Image(systemName: "calendar.badge.clock")
                            .foregroundStyle(AppTheme.accentColor)
                        Text(
                            L10n.format(
                                "Day %lld of current cycle",
                                defaultValue: "Day %lld of current cycle",
                                dayCount
                            )
                        )
                            .appFont(.subheadline)
                            .lineLimit(2)
                            .fixedSize(horizontal: false, vertical: true)
                    }
                }

                if let predictionText = viewModel?.predictionPrimaryText {
                    HStack {
                        Image(systemName: "sparkles")
                            .foregroundStyle(AppTheme.coralAccent)
                        VStack(alignment: .leading, spacing: AppTheme.spacing4) {
                            Text(predictionText)
                                .appFont(.subheadline)
                                .lineLimit(3)
                                .fixedSize(horizontal: false, vertical: true)
                            if let secondaryText = viewModel?.predictionSecondaryText {
                                Text(secondaryText)
                                    .appFont(.caption)
                                    .foregroundStyle(.secondary)
                                    .lineLimit(3)
                                    .fixedSize(horizontal: false, vertical: true)
                            }
                        }
                    }
                }

                if let avgText = viewModel?.averageCycleLengthText {
                    HStack {
                        Image(systemName: "chart.bar")
                            .foregroundStyle(.secondary)
                        Text(avgText)
                            .appFont(.caption)
                            .foregroundStyle(.secondary)
                    }
                }

                HStack {
                    Text(L10n.string("Cycle Details", defaultValue: "Cycle Details"))
                        .appFont(.caption)
                        .foregroundStyle(AppTheme.accentColor)
                        .lineLimit(2)
                        .fixedSize(horizontal: false, vertical: true)
                    Spacer()
                    Image(systemName: "chevron.right")
                        .appFont(.caption)
                        .foregroundStyle(.tertiary)
                }
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .cardStyle()
        }
        .buttonStyle(.plain)
        .accessibilityIdentifier("calendar.cycle_details.card")
    }

    // MARK: - Helpers

    private var year: Int { calendar.component(.year, from: displayedMonth) }
    private var month: Int { calendar.component(.month, from: displayedMonth) }

    private var monthYearString: String {
        displayedMonth.formatted(
            Date.FormatStyle()
                .locale(L10n.locale(for: appState.selectedAppLanguage))
                .month(.wide)
                .year()
        )
    }

    private var firstWeekdayOffset: Int {
        var components = DateComponents()
        components.year = year
        components.month = month
        components.day = 1
        guard let firstDay = calendar.date(from: components) else { return 0 }
        let weekday = calendar.component(.weekday, from: firstDay)
        // Offset relative to the calendar's configured first weekday
        return (weekday - calendar.firstWeekday + 7) % 7
    }

    private var calendarGridCells: [CalendarGridCell] {
        let placeholders = (0..<firstWeekdayOffset).map(CalendarGridCell.placeholder)
        let days = (1...daysInMonth).map(CalendarGridCell.day)
        return placeholders + days
    }

    private var daysInMonth: Int {
        var components = DateComponents()
        components.year = year
        components.month = month
        components.day = 1
        guard let date = calendar.date(from: components),
              let range = calendar.range(of: .day, in: .month, for: date) else { return 30 }
        return range.count
    }

    private func isToday(day: Int) -> Bool {
        let today = Date()
        return calendar.component(.year, from: today) == year
            && calendar.component(.month, from: today) == month
            && calendar.component(.day, from: today) == day
    }

    private func moveMonth(by value: Int) {
        if let newDate = calendar.date(byAdding: .month, value: value, to: displayedMonth) {
            if !appState.allowsPremiumAccess,
               value < 0,
               let earliestDate = freeTierPolicy.earliestAccessibleCycleHistoryDate(now: Date(), isPremium: appState.allowsPremiumAccess),
               newDate < calendar.startOfMonth(for: earliestDate) ?? earliestDate {
                appState.presentPremiumPaywall()
                return
            }
            displayedMonth = newDate
        }
    }

    private func dateForDay(_ day: Int) -> Date? {
        var components = DateComponents()
        components.year = year
        components.month = month
        components.day = day
        return calendar.date(from: components)
    }

    private func isPregnancyDay(day: Int) -> Bool {
        guard let pregnancy = pregnancyViewModel?.activePregnancy,
              let date = dateForDay(day) else { return false }
        let start = Calendar.current.startOfDay(for: pregnancy.startDate)
        let dayDate = Calendar.current.startOfDay(for: date)
        return dayDate >= start && dayDate <= Date()
    }

    private func loadMonthEntries() {
        let earliestDate = freeTierPolicy.earliestAccessibleCycleHistoryDate(now: Date(), isPremium: appState.allowsPremiumAccess)
        entries = viewModel?.entriesForMonth(year: year, month: month, earliestDate: earliestDate) ?? [:]
        loadPredictedDays()
        loadOvulationMarkers()
    }

    private func loadPredictedDays() {
        guard let prediction = viewModel?.prediction,
              viewModel?.hasActionablePrediction == true else {
            predictedDays = []
            return
        }
        var days = Set<Int>()
        var date = prediction.earliestDate
        while date <= prediction.latestDate {
            if calendar.component(.year, from: date) == year &&
               calendar.component(.month, from: date) == month {
                days.insert(calendar.component(.day, from: date))
            }
            guard let next = calendar.date(byAdding: .day, value: 1, to: date) else { break }
            date = next
        }
        predictedDays = days
    }

    private func loadOvulationMarkers() {
        fertileWindowDays = []
        ovulationDay = nil

        guard let viewModel,
              let currentCycle = viewModel.cycles.last,
              currentCycle.endDate == nil,
              let monthStart = calendar.startOfMonth(for: displayedMonth),
              let monthEnd = calendar.date(byAdding: .month, value: 1, to: monthStart)
        else {
            return
        }

        let fetchEnd = max(monthEnd, Date())
        let observationStore = OvulationObservationStore(modelContext: modelContext)
        let observations = (try? observationStore.observations(in: DateInterval(start: currentCycle.startDate, end: fetchEnd))) ?? []
        let predictionService = OvulationPredictionService(calendar: calendar)

        guard let prediction = predictionService.prediction(
            for: currentCycle,
            cycleHistory: viewModel.cycles,
            observations: observations
        ) else {
            return
        }

        var fertileDays = Set<Int>()
        var date = prediction.fertileWindowStart
        while date <= prediction.fertileWindowEnd {
            if calendar.component(.year, from: date) == year,
               calendar.component(.month, from: date) == month {
                fertileDays.insert(calendar.component(.day, from: date))
            }
            guard let next = calendar.date(byAdding: .day, value: 1, to: date) else { break }
            date = next
        }

        fertileWindowDays = fertileDays

        if calendar.component(.year, from: prediction.predictedOvulationDate) == year,
           calendar.component(.month, from: prediction.predictedOvulationDate) == month {
            ovulationDay = calendar.component(.day, from: prediction.predictedOvulationDate)
        }
    }
}

// MARK: - Calendar Day Cell

struct CalendarDayCell: View {
    let day: Int
    let isToday: Bool
    let entry: CycleEntry?
    var isPredicted: Bool = false
    var isFertileWindow: Bool = false
    var isOvulationDay: Bool = false
    let monthDate: Date
    let locale: Locale

    var body: some View {
        ZStack {
            // Background
            if let entry, entry.isPeriodDay {
                Circle()
                    .fill(colorForFlow(entry.flowIntensity))
            } else if isFertileWindow {
                Circle()
                    .fill(AppTheme.sage.opacity(AppTheme.opacityMedium))
            }

            if isPredicted {
                Circle()
                    .strokeBorder(AppTheme.coralAccent.opacity(0.5), style: StrokeStyle(lineWidth: 2, dash: [4, 3]))
            }

            if isOvulationDay {
                Circle()
                    .strokeBorder(AppTheme.accentColor, lineWidth: 2.5)
            } else if isToday {
                Circle()
                    .strokeBorder(AppTheme.accentColor, lineWidth: 2)
            }

            VStack(spacing: 0) {
                Text("\(day)")
                    .appFont(.subheadline, weight: isToday ? .bold : .regular)
                    .foregroundStyle(entry?.isPeriodDay == true ? .white : isPredicted ? AppTheme.coralAccent : .primary)
                    .lineLimit(1)
                    .minimumScaleFactor(0.8)

                if let entry, entry.isPeriodDay, let intensity = entry.flowIntensity {
                    Text(intensity.shortLabel)
                        .appFont(.caption2, weight: .bold)
                        .lineLimit(1)
                        .minimumScaleFactor(0.75)
                        .foregroundStyle(entry.isPeriodDay ? .white.opacity(0.8) : .secondary)
                } else if isOvulationDay {
                    Image(systemName: "sparkle")
                        .appFont(.caption2)
                        .foregroundStyle(AppTheme.accentColor)
                } else if isFertileWindow {
                    Circle()
                        .fill(AppTheme.sage)
                        .frame(width: 5, height: 5)
                }
            }
        }
        .frame(minHeight: 44)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(accessibilityDescription)
    }

    private var accessibilityDescription: String {
        let calendar = Calendar.current
        var components = calendar.dateComponents([.year, .month], from: monthDate)
        components.day = day
        let dateString: String
        if let date = calendar.date(from: components) {
            dateString = date.formatted(
                Date.FormatStyle(date: .long, time: .omitted)
                    .locale(locale)
            )
        } else {
            dateString = L10n.format(
                "Day %lld",
                defaultValue: "Day %lld",
                day
            )
        }

        var parts = [dateString]
        if isToday {
            parts.append(L10n.string("Today", defaultValue: "today"))
        }
        if let entry, entry.isPeriodDay {
            let flowName = entry.flowIntensity?.displayName ?? L10n.string("Period", defaultValue: "period")
            parts.append(
                L10n.format(
                    "%@ flow",
                    defaultValue: "%@ flow",
                    flowName
                )
            )
        } else {
            if isPredicted {
                parts.append(L10n.string("Predicted period", defaultValue: "predicted period"))
            }
            if isFertileWindow {
                parts.append(L10n.string("Predicted fertile window", defaultValue: "predicted fertile window"))
            }
            if isOvulationDay {
                parts.append(L10n.string("Predicted ovulation day", defaultValue: "predicted ovulation day"))
            }
        }
        return parts.joined(separator: ", ")
    }

    private func colorForFlow(_ intensity: FlowIntensity?) -> Color {
        switch intensity {
        case .some(.heavy): AppTheme.flowHeavy
        case .some(.medium): AppTheme.flowMedium
        case .some(.light): AppTheme.flowLight
        case .some(.spotting): AppTheme.flowSpotting
        case .some(.none), nil: Color.clear
        }
    }
}

// MARK: - Month/Year Quick Jump Picker

struct MonthYearPicker: View {
    @Binding var selectedDate: Date
    let hasPremiumAccess: Bool
    let freeTierPolicy: any FreeTierPolicyEnforcing
    @Environment(\.dismiss) private var dismiss

    @State private var pickerMonth: Int
    @State private var pickerYear: Int

    private let calendar = Calendar.autoupdatingCurrent

    init(selectedDate: Binding<Date>, hasPremiumAccess: Bool, freeTierPolicy: any FreeTierPolicyEnforcing) {
        self._selectedDate = selectedDate
        let cal = Calendar.autoupdatingCurrent
        self._pickerMonth = State(initialValue: cal.component(.month, from: selectedDate.wrappedValue))
        self._pickerYear = State(initialValue: cal.component(.year, from: selectedDate.wrappedValue))
        self.hasPremiumAccess = hasPremiumAccess
        self.freeTierPolicy = freeTierPolicy
    }

    private var yearRange: ClosedRange<Int> {
        let currentYear = calendar.component(.year, from: Date())
        let minYear = hasPremiumAccess ? currentYear - 5 : currentYear - 1
        return minYear...currentYear + 1
    }

    var body: some View {
        NavigationStack {
            VStack(spacing: AppTheme.spacing16) {
                HStack(spacing: 0) {
                    Picker(L10n.string("Month", defaultValue: "Month"), selection: $pickerMonth) {
                        ForEach(1...12, id: \.self) { month in
                            Text(calendar.monthSymbols[month - 1]).tag(month)
                        }
                    }
                    .pickerStyle(.wheel)

                    Picker(L10n.string("Year", defaultValue: "Year"), selection: $pickerYear) {
                        ForEach(yearRange, id: \.self) { year in
                            Text(String(year)).tag(year)
                        }
                    }
                    .pickerStyle(.wheel)
                }

                Button {
                    jumpToSelectedMonth()
                    dismiss()
                } label: {
                    Text(L10n.string("Go to Month", defaultValue: "Go to Month"))
                        .appFont(.headline)
                        .foregroundStyle(.white)
                        .frame(maxWidth: .infinity)
                        .multilineTextAlignment(.center)
                        .lineLimit(2)
                        .minimumScaleFactor(0.85)
                        .fixedSize(horizontal: false, vertical: true)
                        .padding(.vertical, 12)
                        .background(Capsule().fill(AppTheme.accentColor))
                }
                .buttonStyle(.plain)
                .padding(.horizontal)

                Button(L10n.string("Today", defaultValue: "Today")) {
                    selectedDate = Date()
                    dismiss()
                }
                .appFont(.subheadline)
                .foregroundStyle(AppTheme.accentColor)
                .lineLimit(2)
                .fixedSize(horizontal: false, vertical: true)
            }
            .padding(.vertical)
            .navigationTitle(L10n.string("Jump to Month", defaultValue: "Jump to Month"))
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button(L10n.string("Cancel", defaultValue: "Cancel")) { dismiss() }
                }
            }
        }
    }

    private func jumpToSelectedMonth() {
        var components = DateComponents()
        components.year = pickerYear
        components.month = pickerMonth
        components.day = 1
        if let date = calendar.date(from: components) {
            selectedDate = date
        }
    }
}

#Preview {
    CalendarMonthView()
        .modelContainer(for: [CycleEntry.self, Cycle.self, OvulationObservation.self], inMemory: true)
}
