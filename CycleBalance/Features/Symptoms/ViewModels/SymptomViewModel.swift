import SwiftUI
import SwiftData
import os

@Observable
@MainActor
final class SymptomViewModel {
    private let modelContext: ModelContext

    var selectedCategory: SymptomCategory? = nil
    var symptomSeverities: [SymptomType: Int] = [:]
    var symptomNotes: [SymptomType: String] = [:]
    var logDate: Date = Date()

    init(modelContext: ModelContext) {
        self.modelContext = modelContext
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

    /// Copy yesterday's symptoms
    func copyYesterdaysSymptoms() {
        let calendar = Calendar.current
        guard let yesterday = calendar.date(byAdding: .day, value: -1, to: calendar.startOfDay(for: Date())) else {
            return
        }
        let endOfYesterday = calendar.date(byAdding: .day, value: 1, to: yesterday)!

        let descriptor = FetchDescriptor<SymptomEntry>(
            predicate: #Predicate<SymptomEntry> { entry in
                entry.date >= yesterday && entry.date < endOfYesterday
            }
        )

        let yesterdaysEntries: [SymptomEntry]
        do {
            yesterdaysEntries = try modelContext.fetch(descriptor)
        } catch {
            Logger.database.error("Failed to fetch yesterday's symptoms: \(error.localizedDescription)")
            return
        }
        guard !yesterdaysEntries.isEmpty else { return }

        for entry in yesterdaysEntries {
            if let type = SymptomType(rawValue: entry.symptomType) {
                symptomSeverities[type] = entry.severity
                if let notes = entry.notes {
                    symptomNotes[type] = notes
                }
            }
        }
    }

    /// Fetch today's already-logged symptoms
    func fetchTodaysSymptoms() -> [SymptomEntry] {
        let calendar = Calendar.current
        let startOfDay = calendar.startOfDay(for: Date())
        let endOfDay = calendar.date(byAdding: .day, value: 1, to: startOfDay)!

        let descriptor = FetchDescriptor<SymptomEntry>(
            predicate: #Predicate<SymptomEntry> { entry in
                entry.date >= startOfDay && entry.date < endOfDay
            },
            sortBy: [SortDescriptor(\.category.rawValue)]
        )

        do {
            return try modelContext.fetch(descriptor)
        } catch {
            Logger.database.error("Failed to fetch today's symptoms: \(error.localizedDescription)")
            return []
        }
    }

    /// Pre-fill the form with today's already-logged symptoms for editing
    func prefillTodaysSymptoms() {
        let todaysEntries = fetchTodaysSymptoms()
        for entry in todaysEntries {
            if let type = SymptomType(rawValue: entry.symptomType) {
                symptomSeverities[type] = entry.severity
                if let notes = entry.notes {
                    symptomNotes[type] = notes
                }
            }
        }
    }

    func reset() {
        symptomSeverities = [:]
        symptomNotes = [:]
        selectedCategory = nil
        logDate = Date()
    }
}
