import SwiftUI
import SwiftData
import os

@Observable
@MainActor
final class ReportViewModel {
    enum ExportPreparationResult: Equatable {
        case existing(URL)
        case generated(URL)
    }

    private struct ConfigurationSignature: Equatable {
        let startDate: Date
        let endDate: Date
        let includeCycles: Bool
        let includeSymptoms: Bool
        let includeBloodSugar: Bool
        let includeSupplements: Bool
        let includeMeals: Bool
        let includeWeightTrend: Bool
        let includeHairPhotos: Bool
        let photoComparisonStyle: ComparisonPhotoPresentationStyle
        let includeInsights: Bool
        let includePregnancy: Bool
        let consultationConcerns: String
        let selectedNoteIDs: Set<UUID>
    }

    private let modelContext: ModelContext
    private let generatePDF: @MainActor (ReportData, PDFSections, AppLanguage, [String]) throws -> URL?
    private var lastGeneratedConfiguration: ConfigurationSignature?

    // MARK: - Configuration

    var startDate: Date = Calendar.current.date(byAdding: .month, value: -1, to: Date()) ?? Date()
    var endDate: Date = Date()

    // MARK: - Section Toggles

    var includeCycles = true
    var includeSymptoms = true
    var includeBloodSugar = true
    var includeSupplements = true
    var includeMeals = true
    var includeWeightTrend = TrackingPreferences.shared.showWeight
    var includeHairPhotos = true
    var photoComparisonStyle: ComparisonPhotoPresentationStyle = .clinical
    var includeInsights = true
    var includePregnancy = true
    var consultationConcerns = ""
    var selectedNoteIDs: Set<UUID> = []
    var availableDailyNotes: [DailyLog] {
        ((try? fetchDailyLogs()) ?? []).filter { !($0.privateNote ?? "").trimmingCharacters(in: .whitespacesAndNewlines).isEmpty }
    }

    // MARK: - State

    var isGenerating = false
    var generatedPDFURL: URL?
    var errorMessage: String?

    // MARK: - Init

    init(
        modelContext: ModelContext,
        generatePDF: @escaping @MainActor (ReportData, PDFSections, AppLanguage, [String]) throws -> URL? = { reportData, sections, appLanguage, preferredLanguages in
            let generator = PDFReportGenerator(
                appLanguage: appLanguage,
                preferredLanguages: preferredLanguages
            )
            return generator.generate(from: reportData, sections: sections)
        }
    ) {
        self.modelContext = modelContext
        self.generatePDF = generatePDF
    }

    // MARK: - Generate Report

    func generateReport(
        appLanguage: AppLanguage,
        preferredLanguages: [String] = Locale.preferredLanguages
    ) async {
        isGenerating = true
        errorMessage = nil

        do {
            let reportData = ReportData(
                cycles: try fetchCycles(),
                symptoms: try fetchSymptoms(),
                bloodSugarReadings: try fetchBloodSugarReadings(),
                supplementLogs: try fetchSupplementLogs(),
                meals: try fetchMeals(),
                dailyLogs: try fetchDailyLogs(),
                hairPhotos: try fetchHairPhotos(),
                insights: try fetchInsights(),
                pregnancyRecords: try fetchPregnancyRecords(),
                startDate: startDate,
                endDate: endDate,
                consultationConcerns: consultationConcerns.trimmingCharacters(in: .whitespacesAndNewlines),
                selectedNotes: availableDailyNotes.filter { selectedNoteIDs.contains($0.id) }.map { ReportDailyNote(date: $0.date, text: $0.privateNote ?? "") },
                sourceNames: try includedSourceNames()
            )

            let sections = PDFSections(
                cycles: includeCycles,
                symptoms: includeSymptoms,
                bloodSugar: includeBloodSugar,
                supplements: includeSupplements,
                meals: includeMeals,
                weightTrend: includeWeightTrend,
                hairPhotos: includeHairPhotos,
                photoComparisonStyle: photoComparisonStyle,
                insights: includeInsights,
                pregnancy: includePregnancy
            )

            if let url = try generatePDF(reportData, sections, appLanguage, preferredLanguages) {
                generatedPDFURL = url
                lastGeneratedConfiguration = currentConfigurationSignature
            } else {
                errorMessage = String(localized: "Failed to generate PDF report.", comment: "Error shown when a PDF report could not be created.")
            }
        } catch {
            Logger.database.error("Report generation failed: \(error.localizedDescription)")
            errorMessage = String(
                localized: "Could not generate report: \(error.localizedDescription)",
                comment: "Error shown when report generation throws an error."
            )
        }

        isGenerating = false
    }

    func prepareExport(
        appLanguage: AppLanguage,
        preferredLanguages: [String] = Locale.preferredLanguages
    ) async -> ExportPreparationResult? {
        if let generatedPDFURL, !hasPendingConfigurationChanges {
            return .existing(generatedPDFURL)
        }

        await generateReport(appLanguage: appLanguage, preferredLanguages: preferredLanguages)
        guard let generatedPDFURL else {
            return nil
        }
        return .generated(generatedPDFURL)
    }

    var hasGeneratedReport: Bool {
        generatedPDFURL != nil
    }

    var hasPendingConfigurationChanges: Bool {
        guard let lastGeneratedConfiguration else { return false }
        return currentConfigurationSignature != lastGeneratedConfiguration
    }

    var hasDataForSelectedSections: Bool {
        do {
            if !consultationConcerns.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty || availableDailyNotes.contains(where: { selectedNoteIDs.contains($0.id) }) { return true }
            if includeCycles, !(try fetchCycles().isEmpty) { return true }
            if includeSymptoms, !(try fetchSymptoms().isEmpty) { return true }
            if includeBloodSugar, !(try fetchBloodSugarReadings().isEmpty) { return true }
            if includeSupplements, !(try fetchSupplementLogs().isEmpty) { return true }
            if includeMeals, !(try fetchMeals().isEmpty) { return true }
            if includeWeightTrend, !(try fetchDailyLogs().isEmpty) { return true }
            if includeHairPhotos, !(try fetchHairPhotos().isEmpty) { return true }
            if includeInsights, !(try fetchInsights().isEmpty) { return true }
            if includePregnancy, !(try fetchPregnancyRecords().isEmpty) { return true }
            return false
        } catch {
            Logger.database.error("Report data availability check failed: \(error.localizedDescription)")
            return true
        }
    }

    private var rangeStart: Date { Calendar.current.startOfDay(for: startDate) }
    private var rangeEndExclusive: Date { Calendar.current.date(byAdding: .day, value: 1, to: Calendar.current.startOfDay(for: endDate)) ?? endDate }

    // MARK: - Private Fetchers

    private func fetchCycles() throws -> [Cycle] {
        let start = rangeStart
        let end = rangeEndExclusive
        let descriptor = FetchDescriptor<Cycle>(
            predicate: #Predicate<Cycle> { cycle in
                cycle.startDate >= start && cycle.startDate < end
            },
            sortBy: [SortDescriptor(\.startDate)]
        )
        return try modelContext.fetch(descriptor)
    }

    private func fetchSymptoms() throws -> [SymptomEntry] {
        let start = rangeStart
        let end = rangeEndExclusive
        let descriptor = FetchDescriptor<SymptomEntry>(
            predicate: #Predicate<SymptomEntry> { entry in
                entry.date >= start && entry.date < end
            },
            sortBy: [SortDescriptor(\.date)]
        )
        return try modelContext.fetch(descriptor)
    }

    private func fetchBloodSugarReadings() throws -> [BloodSugarReading] {
        let start = rangeStart
        let end = rangeEndExclusive
        let descriptor = FetchDescriptor<BloodSugarReading>(
            predicate: #Predicate<BloodSugarReading> { reading in
                reading.timestamp >= start && reading.timestamp < end
            },
            sortBy: [SortDescriptor(\.timestamp)]
        )
        return try modelContext.fetch(descriptor)
    }

    private func fetchSupplementLogs() throws -> [SupplementLog] {
        let start = rangeStart
        let end = rangeEndExclusive
        let descriptor = FetchDescriptor<SupplementLog>(
            predicate: #Predicate<SupplementLog> { log in
                log.date >= start && log.date < end
            },
            sortBy: [SortDescriptor(\.date)]
        )
        return try modelContext.fetch(descriptor)
    }

    private func fetchMeals() throws -> [MealEntry] {
        let start = rangeStart
        let end = rangeEndExclusive
        let descriptor = FetchDescriptor<MealEntry>(
            predicate: #Predicate<MealEntry> { meal in
                meal.timestamp >= start && meal.timestamp < end
            },
            sortBy: [SortDescriptor(\.timestamp)]
        )
        return try modelContext.fetch(descriptor)
    }

    private func fetchDailyLogs() throws -> [DailyLog] {
        let start = rangeStart
        let end = rangeEndExclusive
        let descriptor = FetchDescriptor<DailyLog>(
            predicate: #Predicate<DailyLog> { log in
                log.date >= start && log.date < end
            },
            sortBy: [SortDescriptor(\.date)]
        )
        return try modelContext.fetch(descriptor)
    }

    private func fetchHairPhotos() throws -> [HairPhotoEntry] {
        let start = rangeStart
        let end = rangeEndExclusive
        let descriptor = FetchDescriptor<HairPhotoEntry>(
            predicate: #Predicate<HairPhotoEntry> { photo in
                photo.date >= start && photo.date < end
            },
            sortBy: [SortDescriptor(\.date)]
        )
        return try modelContext.fetch(descriptor)
    }

    private func fetchPregnancyRecords() throws -> [PregnancyRecord] {
        let start = rangeStart
        let end = rangeEndExclusive
        let descriptor = FetchDescriptor<PregnancyRecord>(
            predicate: #Predicate<PregnancyRecord> { record in
                record.startDate >= start && record.startDate < end
            },
            sortBy: [SortDescriptor(\.startDate)]
        )
        return try modelContext.fetch(descriptor)
    }

    private func fetchInsights() throws -> [Insight] {
        let start = rangeStart
        let end = rangeEndExclusive
        let descriptor = FetchDescriptor<Insight>(
            predicate: #Predicate<Insight> { insight in
                insight.generatedDate >= start && insight.generatedDate < end
            },
            sortBy: [SortDescriptor(\.generatedDate, order: .reverse)]
        )
        return try modelContext.fetch(descriptor)
    }

    private func includedSourceNames() throws -> [String] {
        var includedIDs = Set<UUID>()
        if includeCycles { includedIDs.formUnion(try fetchCycles().flatMap { $0.entries ?? [] }.map(\.id)) }
        if includeSymptoms { includedIDs.formUnion(try fetchSymptoms().map(\.id)) }
        if includeBloodSugar { includedIDs.formUnion(try fetchBloodSugarReadings().map(\.id)) }
        let weightLogs = includeWeightTrend ? try fetchDailyLogs().filter { $0.weight != nil } : []
        let owners = try modelContext.fetch(FetchDescriptor<HealthKitFieldOwnership>())
        let importedWeightIDs = Set(weightLogs.filter { log in owners.contains { $0.recordID == log.id && $0.field == "weight" && !$0.isManual && $0.lastAppliedValue == log.weight } }.map(\.id))
        let records = try modelContext.fetch(FetchDescriptor<HealthKitImportedSampleRecord>())
        return Set(records.filter { record in
            guard let id = record.derivedRecordID else { return false }
            if record.derivedRecordKind == .dailyLog {
                return record.healthKitIdentifier == "HKQuantityTypeIdentifierBodyMass" && importedWeightIDs.contains(id)
            }
            return includedIDs.contains(id)
        }.map(\.sourceLabel)).sorted()
    }

    private var currentConfigurationSignature: ConfigurationSignature {
        ConfigurationSignature(
            startDate: startDate,
            endDate: endDate,
            includeCycles: includeCycles,
            includeSymptoms: includeSymptoms,
            includeBloodSugar: includeBloodSugar,
            includeSupplements: includeSupplements,
            includeMeals: includeMeals,
            includeWeightTrend: includeWeightTrend,
            includeHairPhotos: includeHairPhotos,
            photoComparisonStyle: photoComparisonStyle,
            includeInsights: includeInsights,
            includePregnancy: includePregnancy,
            consultationConcerns: consultationConcerns,
            selectedNoteIDs: selectedNoteIDs
        )
    }
}
