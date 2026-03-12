import SwiftUI
import SwiftData
import os

@Observable
@MainActor
final class SymptomViewModel {
    private let modelContext: ModelContext

    var selectedCategory: SymptomCategory? {
        didSet {
            if let category = selectedCategory {
                UserDefaults.standard.set(category.rawValue, forKey: "symptom.selectedCategory")
            } else {
                UserDefaults.standard.removeObject(forKey: "symptom.selectedCategory")
            }
        }
    }
    var symptomSeverities: [SymptomType: Int] = [:]
    var symptomNotes: [SymptomType: String] = [:]
    var logDate: Date = Date()

    init(modelContext: ModelContext) {
        self.modelContext = modelContext
        if let raw = UserDefaults.standard.string(forKey: "symptom.selectedCategory"),
           let category = SymptomCategory(rawValue: raw) {
            self.selectedCategory = category
        } else {
            self.selectedCategory = nil
        }
    }

    /// All symptom types for the currently selected category, or all types if no category selected
    var visibleSymptomTypes: [SymptomType] {
        if let category = selectedCategory {
            return category.symptomTypes
        }
        return SymptomType.allCases.sorted { $0.displayName < $1.displayName }
    }

    /// Set severity for a symptom type. Setting to 0 removes it.
    func setSeverity(_ severity: Int, for symptomType: SymptomType) {
        if severity == 0 {
            symptomSeverities.removeValue(forKey: symptomType)
        } else {
            symptomSeverities[symptomType] = min(max(severity, 1), 5)
        }
    }

    /// Get current severity for a symptom type
    func severity(for symptomType: SymptomType) -> Int {
        symptomSeverities[symptomType] ?? 0
    }

    /// Whether any symptoms have been logged
    var hasSelections: Bool {
        !symptomSeverities.isEmpty
    }

    /// Count of logged symptoms
    var selectionCount: Int {
        symptomSeverities.count
    }

    /// Save all logged symptoms, replacing any existing entries for the same day.
    func saveSymptoms() throws {
        // Delete today's existing entries to prevent duplicates
        let existingEntries = fetchTodaysSymptoms()
        for entry in existingEntries {
            modelContext.delete(entry)
        }

        // Insert fresh entries for all selected symptoms
        for (symptomType, severity) in symptomSeverities {
            let entry = SymptomEntry(
                date: logDate,
                type: symptomType,
                severity: severity,
                notes: symptomNotes[symptomType]
            )
            modelContext.insert(entry)
        }

        try modelContext.save()
        reset()
    }

    /// Number of symptoms logged yesterday (for button label preview)
    var yesterdaySymptomCount: Int {
        fetchYesterdaysSymptoms().count
    }

    /// Copy yesterday's symptoms
    func copyYesterdaysSymptoms() {
        let yesterdaysEntries = fetchYesterdaysSymptoms()
        guard !yesterdaysEntries.isEmpty else { return }

        for entry in yesterdaysEntries {
            symptomSeverities[entry.symptomType] = entry.severity
            if let notes = entry.notes {
                symptomNotes[entry.symptomType] = notes
            }
        }
    }

    private func fetchYesterdaysSymptoms() -> [SymptomEntry] {
        let calendar = Calendar.current
        guard let yesterday = calendar.date(byAdding: .day, value: -1, to: calendar.startOfDay(for: Date())) else {
            return []
        }
        guard let endOfYesterday = calendar.date(byAdding: .day, value: 1, to: yesterday) else {
            return []
        }

        let descriptor = FetchDescriptor<SymptomEntry>(
            predicate: #Predicate<SymptomEntry> { entry in
                entry.date >= yesterday && entry.date < endOfYesterday
            }
        )

        do {
            return try modelContext.fetch(descriptor)
        } catch {
            Logger.database.error("Failed to fetch yesterday's symptoms: \(error.localizedDescription)")
            return []
        }
    }

    /// Fetch today's already-logged symptoms
    func fetchTodaysSymptoms() -> [SymptomEntry] {
        let calendar = Calendar.current
        let startOfDay = calendar.startOfDay(for: Date())
        guard let endOfDay = calendar.endOfDay(for: Date()) else { return [] }

        let descriptor = FetchDescriptor<SymptomEntry>(
            predicate: #Predicate<SymptomEntry> { entry in
                entry.date >= startOfDay && entry.date < endOfDay
            }
        )

        do {
            let entries = try modelContext.fetch(descriptor)
            return entries.sorted { lhs, rhs in
                if lhs.category.rawValue != rhs.category.rawValue {
                    return lhs.category.rawValue < rhs.category.rawValue
                }
                if lhs.symptomType.rawValue != rhs.symptomType.rawValue {
                    return lhs.symptomType.rawValue < rhs.symptomType.rawValue
                }
                if lhs.date != rhs.date {
                    return lhs.date < rhs.date
                }
                return lhs.id.uuidString < rhs.id.uuidString
            }
        } catch {
            Logger.database.error("Failed to fetch today's symptoms: \(error.localizedDescription)")
            return []
        }
    }

    /// Pre-fill the form with today's already-logged symptoms for editing
    func prefillTodaysSymptoms() {
        let todaysEntries = fetchTodaysSymptoms()
        for entry in todaysEntries {
            symptomSeverities[entry.symptomType] = entry.severity
            if let notes = entry.notes {
                symptomNotes[entry.symptomType] = notes
            }
        }
    }

    /// Top symptom types logged in the last 30 days, by frequency.
    func frequentSymptoms(limit: Int = 5) -> [SymptomType] {
        let calendar = Calendar.current
        guard let thirtyDaysAgo = calendar.date(byAdding: .day, value: -30, to: Date()) else { return [] }

        let descriptor = FetchDescriptor<SymptomEntry>(
            predicate: #Predicate<SymptomEntry> { $0.date >= thirtyDaysAgo }
        )

        let entries: [SymptomEntry]
        do {
            entries = try modelContext.fetch(descriptor)
        } catch {
            Logger.database.error("Failed to fetch frequent symptoms: \(error.localizedDescription)")
            return []
        }

        let counts = Dictionary(grouping: entries, by: \.symptomType)
            .mapValues { $0.count }
            .sorted { $0.value > $1.value }

        return Array(counts.prefix(limit).map(\.key))
    }

    func reset() {
        selectedCategory = nil
        symptomSeverities = [:]
        symptomNotes = [:]
        logDate = Date()
    }
}
