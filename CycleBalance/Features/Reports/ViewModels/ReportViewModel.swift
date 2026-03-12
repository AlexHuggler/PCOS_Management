import SwiftUI
import SwiftData
import os

@Observable
@MainActor
final class ReportViewModel {
    private let modelContext: ModelContext

    // MARK: - Configuration

    var startDate: Date = Calendar.current.date(byAdding: .month, value: -1, to: Date()) ?? Date()
    var endDate: Date = Date()

    // MARK: - Section Toggles

    var includeCycles = true
    var includeSymptoms = true
    var includeBloodSugar = true
    var includeSupplements = true
    var includeMeals = true
    var includeInsights = true

    // MARK: - State

    var isGenerating = false
    var generatedPDFURL: URL?
    var errorMessage: String?

    // MARK: - Init

    init(modelContext: ModelContext) {
        self.modelContext = modelContext
    }

    // MARK: - Generate Report

    func generateReport() async {
        isGenerating = true
        errorMessage = nil
        generatedPDFURL = nil

        do {
            let reportData = ReportData(
                cycles: try fetchCycles(),
                symptoms: try fetchSymptoms(),
                bloodSugarReadings: try fetchBloodSugarReadings(),
                supplementLogs: try fetchSupplementLogs(),
                meals: try fetchMeals(),
                insights: try fetchInsights(),
                startDate: startDate,
                endDate: endDate
            )

            let sections = PDFSections(
                cycles: includeCycles,
                symptoms: includeSymptoms,
                bloodSugar: includeBloodSugar,
                supplements: includeSupplements,
                meals: includeMeals,
                insights: includeInsights
            )

            let generator = PDFReportGenerator()
            if let url = generator.generate(from: reportData, sections: sections) {
                generatedPDFURL = url
            } else {
                errorMessage = "Failed to generate PDF report."
            }
        } catch {
            Logger.database.error("Report generation failed: \(error.localizedDescription)")
            errorMessage = "Could not generate report: \(error.localizedDescription)"
        }

        isGenerating = false
    }

    // MARK: - Private Fetchers

    private func fetchCycles() throws -> [Cycle] {
        let start = startDate
        let end = endDate
        let descriptor = FetchDescriptor<Cycle>(
            predicate: #Predicate<Cycle> { cycle in
                cycle.startDate >= start && cycle.startDate <= end
            },
            sortBy: [SortDescriptor(\.startDate)]
        )
        return try modelContext.fetch(descriptor)
    }

    private func fetchSymptoms() throws -> [SymptomEntry] {
        let start = startDate
        let end = endDate
        let descriptor = FetchDescriptor<SymptomEntry>(
            predicate: #Predicate<SymptomEntry> { entry in
                entry.date >= start && entry.date <= end
            },
            sortBy: [SortDescriptor(\.date)]
        )
        return try modelContext.fetch(descriptor)
    }

    private func fetchBloodSugarReadings() throws -> [BloodSugarReading] {
        let start = startDate
        let end = endDate
        let descriptor = FetchDescriptor<BloodSugarReading>(
            predicate: #Predicate<BloodSugarReading> { reading in
                reading.timestamp >= start && reading.timestamp <= end
            },
            sortBy: [SortDescriptor(\.timestamp)]
        )
        return try modelContext.fetch(descriptor)
    }

    private func fetchSupplementLogs() throws -> [SupplementLog] {
        let start = startDate
        let end = endDate
        let descriptor = FetchDescriptor<SupplementLog>(
            predicate: #Predicate<SupplementLog> { log in
                log.date >= start && log.date <= end
            },
            sortBy: [SortDescriptor(\.date)]
        )
        return try modelContext.fetch(descriptor)
    }

    private func fetchMeals() throws -> [MealEntry] {
        let start = startDate
        let end = endDate
        let descriptor = FetchDescriptor<MealEntry>(
            predicate: #Predicate<MealEntry> { meal in
                meal.timestamp >= start && meal.timestamp <= end
            },
            sortBy: [SortDescriptor(\.timestamp)]
        )
        return try modelContext.fetch(descriptor)
    }

    private func fetchInsights() throws -> [Insight] {
        let start = startDate
        let end = endDate
        let descriptor = FetchDescriptor<Insight>(
            predicate: #Predicate<Insight> { insight in
                insight.generatedDate >= start && insight.generatedDate <= end
            },
            sortBy: [SortDescriptor(\.generatedDate, order: .reverse)]
        )
        return try modelContext.fetch(descriptor)
    }
}
