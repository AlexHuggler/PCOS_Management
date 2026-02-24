import SwiftUI
import SwiftData

struct CalendarMonthView: View {
    @Environment(\.modelContext) private var modelContext
    @State private var viewModel: CycleViewModel?
    @State private var displayedMonth = Date()
    @State private var entries: [Int: CycleEntry] = [:]
    @State private var showingLogSheet = false

    private let calendar = Calendar.current
    private let daysOfWeek = ["Sun", "Mon", "Tue", "Wed", "Thu", "Fri", "Sat"]
    private let columns = Array(repeating: GridItem(.flexible(), spacing: 4), count: 7)

    var body: some View {
        NavigationStack {
            VStack(spacing: 16) {
                // Month navigation header
                monthHeader

                // Days of week header
                daysOfWeekHeader

                // Calendar grid
                calendarGrid

                // Cycle info section
                cycleInfoSection

                Spacer()
            }
            .padding()
            .navigationTitle("Calendar")
            .toolbar {
                ToolbarItem(placement: .primaryAction) {
                    Button {
                        showingLogSheet = true
                    } label: {
                        Label("Log Period", systemImage: "plus")
                    }
                }
            }
            .sheet(isPresented: $showingLogSheet) {
                CycleLogView()
            }
            .onAppear {
                let vm = CycleViewModel(modelContext: modelContext)
                vm.loadData()
                viewModel = vm
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
                    .font(.title3)
            }

            Spacer()

            Text(monthYearString)
                .font(.title2)
                .fontWeight(.semibold)

            Spacer()

            Button {
                moveMonth(by: 1)
            } label: {
                Image(systemName: "chevron.right")
                    .font(.title3)
            }
        }
        .padding(.horizontal)
    }

    private var daysOfWeekHeader: some View {
        LazyVGrid(columns: columns, spacing: 4) {
            ForEach(daysOfWeek, id: \.self) { day in
                Text(day)
                    .font(.caption)
                    .fontWeight(.medium)
                    .foregroundStyle(.secondary)
                    .frame(maxWidth: .infinity)
            }
        }
    }

    private var calendarGrid: some View {
        LazyVGrid(columns: columns, spacing: 4) {
            // Blank cells for offset
            ForEach(0..<firstWeekdayOffset, id: \.self) { _ in
                Color.clear
                    .frame(height: 44)
            }

            // Day cells
            ForEach(1...daysInMonth, id: \.self) { day in
                CalendarDayCell(
                    day: day,
                    isToday: isToday(day: day),
                    entry: entries[day]
                )
            }
        }
    }

    private var cycleInfoSection: some View {
        VStack(alignment: .leading, spacing: 8) {
            if let dayCount = viewModel?.currentCycleDayCount {
                HStack {
                    Image(systemName: "calendar.badge.clock")
                        .foregroundStyle(AppTheme.accentColor)
                    Text("Day \(dayCount) of current cycle")
                        .font(.subheadline)
                }
            }

            if let predictionText = viewModel?.predictionRangeText {
                HStack {
                    Image(systemName: "sparkles")
                        .foregroundStyle(AppTheme.coralAccent)
                    Text(predictionText)
                        .font(.subheadline)
                }
            }

            if let avgText = viewModel?.averageCycleLengthText {
                HStack {
                    Image(systemName: "chart.bar")
                        .foregroundStyle(.secondary)
                    Text(avgText)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
            }
        }
        .padding()
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(
            RoundedRectangle(cornerRadius: 12)
                .fill(AppTheme.cardBackground)
        )
    }

    // MARK: - Helpers

    private var year: Int { calendar.component(.year, from: displayedMonth) }
    private var month: Int { calendar.component(.month, from: displayedMonth) }

    private var monthYearString: String {
        let formatter = DateFormatter()
        formatter.dateFormat = "MMMM yyyy"
        return formatter.string(from: displayedMonth)
    }

    private var firstWeekdayOffset: Int {
        var components = DateComponents()
        components.year = year
        components.month = month
        components.day = 1
        guard let firstDay = calendar.date(from: components) else { return 0 }
        return calendar.component(.weekday, from: firstDay) - 1
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
            displayedMonth = newDate
        }
    }

    private func loadMonthEntries() {
        entries = viewModel?.entriesForMonth(year: year, month: month) ?? [:]
    }
}

// MARK: - Calendar Day Cell

struct CalendarDayCell: View {
    let day: Int
    let isToday: Bool
    let entry: CycleEntry?

    var body: some View {
        ZStack {
            // Background
            if let entry, entry.isPeriodDay {
                Circle()
                    .fill(colorForFlow(entry.flowIntensity))
            } else if isToday {
                Circle()
                    .strokeBorder(AppTheme.accentColor, lineWidth: 2)
            }

            Text("\(day)")
                .font(.subheadline)
                .fontWeight(isToday ? .bold : .regular)
                .foregroundStyle(entry?.isPeriodDay == true ? .white : .primary)
        }
        .frame(height: 44)
    }

    private func colorForFlow(_ intensity: FlowIntensity?) -> Color {
        switch intensity {
        case .heavy: AppTheme.flowHeavy
        case .medium: AppTheme.flowMedium
        case .light: AppTheme.flowLight
        case .spotting: AppTheme.flowSpotting
        case .none, nil: Color.clear
        }
    }
}

#Preview {
    CalendarMonthView()
        .modelContainer(for: [CycleEntry.self, Cycle.self], inMemory: true)
}
