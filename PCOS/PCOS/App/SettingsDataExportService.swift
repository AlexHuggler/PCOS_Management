import Foundation
import SwiftData
import os

@MainActor
struct SettingsDataExportService {
    typealias FileWriter = (_ contents: String, _ url: URL) throws -> Void

    private static let isoFormatter = ISO8601DateFormatter()

    private let modelContext: ModelContext
    private let fileWriter: FileWriter

    init(
        modelContext: ModelContext,
        fileWriter: @escaping FileWriter = { contents, url in
            try contents.write(to: url, atomically: true, encoding: .utf8)
        }
    ) {
        self.modelContext = modelContext
        self.fileWriter = fileWriter
    }

    func generateCSVExport() throws -> URL {
        var csv = "Type,Date,Detail,Value,Notes\n"

        do {
            let cycleDescriptor = FetchDescriptor<Cycle>(sortBy: [SortDescriptor(\.startDate)])
            let cycles = try modelContext.fetch(cycleDescriptor)
            for cycle in cycles {
                let dateStr = Self.isoFormatter.string(from: cycle.startDate)
                let length = cycle.lengthDays.map(String.init) ?? "ongoing"
                csv += "Cycle,\(dateStr),Length,\(length),\n"
            }
        } catch {
            Logger.database.error("Failed to export cycles: \(error.localizedDescription)")
        }

        do {
            let entryDescriptor = FetchDescriptor<CycleEntry>(sortBy: [SortDescriptor(\.date)])
            let entries = try modelContext.fetch(entryDescriptor)
            for entry in entries {
                let dateStr = Self.isoFormatter.string(from: entry.date)
                let flow = entry.flowIntensity?.displayName ?? "none"
                let notes = entry.notes?.replacingOccurrences(of: ",", with: ";") ?? ""
                csv += "Period,\(dateStr),\(flow),\(entry.isPeriodDay ? "yes" : "no"),\(notes)\n"
            }
        } catch {
            Logger.database.error("Failed to export cycle entries: \(error.localizedDescription)")
        }

        do {
            let symptomDescriptor = FetchDescriptor<SymptomEntry>(sortBy: [SortDescriptor(\.date)])
            let symptoms = try modelContext.fetch(symptomDescriptor)
            for symptom in symptoms {
                let dateStr = Self.isoFormatter.string(from: symptom.date)
                let notes = symptom.notes?.replacingOccurrences(of: ",", with: ";") ?? ""
                csv += "Symptom,\(dateStr),\(symptom.symptomType.displayName),\(symptom.severity),\(notes)\n"
            }
        } catch {
            Logger.database.error("Failed to export symptoms: \(error.localizedDescription)")
        }

        do {
            let bsDescriptor = FetchDescriptor<BloodSugarReading>(sortBy: [SortDescriptor(\.timestamp)])
            let readings = try modelContext.fetch(bsDescriptor)
            for reading in readings {
                let dateStr = Self.isoFormatter.string(from: reading.timestamp)
                let notes = reading.notes?.replacingOccurrences(of: ",", with: ";") ?? ""
                csv += "BloodSugar,\(dateStr),\(reading.readingType.displayName),\(reading.glucoseValue),\(notes)\n"
            }
        } catch {
            Logger.database.error("Failed to export blood sugar readings: \(error.localizedDescription)")
        }

        do {
            let suppDescriptor = FetchDescriptor<SupplementLog>(sortBy: [SortDescriptor(\.date)])
            let logs = try modelContext.fetch(suppDescriptor)
            for log in logs {
                let dateStr = Self.isoFormatter.string(from: log.date)
                let dosage = log.dosageMg.map { String(format: "%.0f mg", $0) } ?? ""
                csv += "Supplement,\(dateStr),\(log.supplementName),\(log.taken ? "taken" : "missed"),\(dosage)\n"
            }
        } catch {
            Logger.database.error("Failed to export supplement logs: \(error.localizedDescription)")
        }

        do {
            let mealDescriptor = FetchDescriptor<MealEntry>(sortBy: [SortDescriptor(\.timestamp)])
            let meals = try modelContext.fetch(mealDescriptor)
            for meal in meals {
                let dateStr = Self.isoFormatter.string(from: meal.timestamp)
                let desc = meal.mealDescription.replacingOccurrences(of: ",", with: ";")
                csv += "Meal,\(dateStr),\(meal.mealType.displayName),\(meal.glycemicImpact.displayName),\(desc)\n"
            }
        } catch {
            Logger.database.error("Failed to export meals: \(error.localizedDescription)")
        }

        let tempURL = FileManager.default.temporaryDirectory.appendingPathComponent("CycleBalance_Export.csv")
        try fileWriter(csv, tempURL)
        return tempURL
    }
}
