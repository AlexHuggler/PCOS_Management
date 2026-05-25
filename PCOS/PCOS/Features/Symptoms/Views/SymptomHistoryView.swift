import SwiftUI
import SwiftData

struct SymptomHistoryView: View {
    @Environment(\.modelContext) private var modelContext
    @State private var selectedRange: DateRange = .month
    @State private var entries: [SymptomEntry] = []

    private let freeTierPolicy: any FreeTierPolicyEnforcing = FreeTierPolicyService()

    private enum DateRange: Int, CaseIterable, Identifiable {
        case month = 30
        case quarter = 90

        var id: Int { rawValue }

        var title: String {
            switch self {
            case .month: "30 Days"
            case .quarter: "90 Days"
            }
        }
    }

    var body: some View {
        List {
            Section {
                Picker("Range", selection: $selectedRange) {
                    ForEach(DateRange.allCases) { range in
                        Text(range.title).tag(range)
                    }
                }
                .pickerStyle(.segmented)
            }

            if groupedEntries.isEmpty {
                Section {
                    Text("No symptom history found for the selected range.")
                        .appFont(.subheadline)
                        .foregroundStyle(.secondary)
                }
            } else {
                ForEach(groupedEntries, id: \.date) { group in
                    Section {
                        ForEach(group.entries) { entry in
                            HStack {
                                VStack(alignment: .leading, spacing: 2) {
                                    Text(entry.symptomType.displayName)
                                        .appFont(.subheadline)
                                    Text(entry.category.displayName)
                                        .appFont(.caption)
                                        .foregroundStyle(.secondary)
                                }
                                Spacer()
                                Text("\(entry.severity)/5")
                                    .appFont(.subheadline)
                                    .foregroundStyle(AppTheme.accentColor)
                            }
                        }
                    } header: {
                        Text(group.date, style: .date)
                    }
                }
            }
        }
        .navigationTitle(L10n.string("Symptom History", defaultValue: "Symptom History"))
        .navigationBarTitleDisplayMode(.inline)
        .onAppear {
            loadEntries()
        }
        .onChange(of: selectedRange) { _, newValue in
            _ = newValue
            loadEntries()
        }
    }

    private var groupedEntries: [(date: Date, entries: [SymptomEntry])] {
        let calendar = Calendar.current
        let grouped = Dictionary(grouping: entries) { entry in
            calendar.startOfDay(for: entry.date)
        }
        return grouped
            .sorted { $0.key > $1.key }
            .map { (date: $0.key, entries: $0.value.sorted { $0.date > $1.date }) }
    }

    private func loadEntries() {
        let calendar = Calendar.current
        let now = Date()
        guard let dateFromRange = calendar.date(byAdding: .day, value: -selectedRange.rawValue, to: now) else {
            entries = []
            return
        }

        let effectiveStart: Date
        if let freeTierStart = freeTierPolicy.earliestAccessibleSymptomHistoryDate(now: now, isPremium: false) {
            effectiveStart = max(dateFromRange, freeTierStart)
        } else {
            effectiveStart = dateFromRange
        }

        let descriptor = FetchDescriptor<SymptomEntry>(
            predicate: #Predicate<SymptomEntry> { entry in
                entry.date >= effectiveStart
            },
            sortBy: [SortDescriptor(\.date, order: .reverse)]
        )

        entries = (try? modelContext.fetch(descriptor)) ?? []
    }
}

#Preview {
    NavigationStack {
        SymptomHistoryView()
            .environment(AppState())
    }
    .modelContainer(for: SymptomEntry.self, inMemory: true)
}
