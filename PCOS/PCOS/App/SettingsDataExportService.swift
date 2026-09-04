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
                let length = (cycle.manualCycleLengthOverrideDays ?? cycle.lengthDays).map(String.init)
                    ?? String(localized: "Ongoing", comment: "CSV export value for a cycle that has not ended yet.")
                csv += "\(localizedRowType(.cycle)),\(dateStr),\(String(localized: "Length", comment: "CSV export detail value for cycle length.")),\(length),\n"
            }
        } catch {
            Logger.database.error("Failed to export cycles: \(error.localizedDescription)")
        }

        do {
            let entryDescriptor = FetchDescriptor<CycleEntry>(sortBy: [SortDescriptor(\.date)])
            let entries = try modelContext.fetch(entryDescriptor)
            for entry in entries {
                let dateStr = Self.isoFormatter.string(from: entry.date)
                let flow = entry.flowIntensity?.displayName
                    ?? String(localized: "None", comment: "CSV export value meaning no period flow was logged.")
                let notes = entry.notes?.replacingOccurrences(of: ",", with: ";") ?? ""
                let periodValue = entry.isPeriodDay
                    ? String(localized: "Yes", comment: "CSV export boolean value.")
                    : String(localized: "No", comment: "CSV export boolean value.")
                csv += "\(localizedRowType(.period)),\(dateStr),\(flow),\(periodValue),\(notes)\n"
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
                csv += "\(localizedRowType(.symptom)),\(dateStr),\(symptom.symptomType.displayName),\(symptom.severity),\(notes)\n"
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
                csv += "\(localizedRowType(.bloodSugar)),\(dateStr),\(reading.readingType.displayName),\(reading.glucoseValue),\(notes)\n"
            }
        } catch {
            Logger.database.error("Failed to export blood sugar readings: \(error.localizedDescription)")
        }

        do {
            let suppDescriptor = FetchDescriptor<SupplementLog>(sortBy: [SortDescriptor(\.date)])
            let logs = try modelContext.fetch(suppDescriptor)
            for log in logs {
                let dateStr = Self.isoFormatter.string(from: log.date)
                let dosage = log.dosageMg.map { DosageUnit.formatted($0, unit: log.dosageUnit) } ?? ""
                let status = log.taken
                    ? String(localized: "Taken", comment: "CSV export supplement status value.")
                    : String(localized: "Missed", comment: "CSV export supplement status value.")
                csv += "\(localizedRowType(.supplement)),\(dateStr),\(log.supplementName),\(status),\(dosage)\n"
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
                csv += "\(localizedRowType(.meal)),\(dateStr),\(meal.mealType.displayName),\(meal.glycemicImpact.displayName),\(desc)\n"
            }
        } catch {
            Logger.database.error("Failed to export meals: \(error.localizedDescription)")
        }

        do {
            let nutritionDescriptor = FetchDescriptor<NutritionImportRecord>(sortBy: [SortDescriptor(\.startDate)])
            let imports = try modelContext.fetch(nutritionDescriptor)
            for nutritionImport in imports {
                let dateStr = Self.isoFormatter.string(from: nutritionImport.startDate)
                let product = nutritionImport.displayProductName.replacingOccurrences(of: ",", with: ";")
                let value = nutritionImport.calories.map { "\($0.formatted()) kcal" } ?? nutritionImport.sourceKind.displayName
                let notes = nutritionImport.notes?.replacingOccurrences(of: ",", with: ";") ?? nutritionImport.sourceLabel
                csv += "\(localizedRowType(.nutritionImport)),\(dateStr),\(product),\(value),\(notes)\n"
            }
        } catch {
            Logger.database.error("Failed to export nutrition imports: \(error.localizedDescription)")
        }

        do {
            let pregnancyDescriptor = FetchDescriptor<PregnancyRecord>(sortBy: [SortDescriptor(\.startDate)])
            let pregnancies = try modelContext.fetch(pregnancyDescriptor)
            for pregnancy in pregnancies {
                let startStr = Self.isoFormatter.string(from: pregnancy.startDate)
                let endStr = pregnancy.endDate.map { Self.isoFormatter.string(from: $0) } ?? ""
                let reason = pregnancy.endReason?.rawValue ?? ""
                let dueDate = pregnancy.estimatedDueDate.map { Self.isoFormatter.string(from: $0) } ?? ""
                let notes = pregnancy.notes?.replacingOccurrences(of: ",", with: ";") ?? ""
                csv += "\(localizedRowType(.pregnancy)),\(startStr),\(reason),\(dueDate),\(endStr),\(notes)\n"
            }
        } catch {
            Logger.database.error("Failed to export pregnancy records: \(error.localizedDescription)")
        }

        let tempURL = FileManager.default.temporaryDirectory.appendingPathComponent("CycleBalance_Export.csv")
        try fileWriter(csv, tempURL)
        return tempURL
    }

    private enum ExportRowType {
        case cycle
        case period
        case symptom
        case bloodSugar
        case supplement
        case meal
        case nutritionImport
        case pregnancy
    }

    private func localizedRowType(_ type: ExportRowType) -> String {
        switch type {
        case .cycle:
            String(localized: "Cycle", comment: "CSV export row type value.")
        case .period:
            String(localized: "Period", comment: "CSV export row type value.")
        case .symptom:
            String(localized: "Symptom", comment: "CSV export row type value.")
        case .bloodSugar:
            String(localized: "Blood Sugar", comment: "CSV export row type value.")
        case .supplement:
            String(localized: "Supplement", comment: "CSV export row type value.")
        case .meal:
            String(localized: "Meal", comment: "CSV export row type value.")
        case .nutritionImport:
            String(localized: "Nutrition Import", comment: "CSV export row type value.")
        case .pregnancy:
            String(localized: "Pregnancy", comment: "CSV export row type value.")
        }
    }
}
