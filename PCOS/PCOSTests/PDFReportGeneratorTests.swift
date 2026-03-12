import Testing
import Foundation
import SwiftData
@testable import PCOS

@Suite("PDF Report Generator", .serialized)
@MainActor
struct PDFReportGeneratorTests {

    private func makeContainer() throws -> ModelContainer {
        let schema = Schema([
            Cycle.self,
            CycleEntry.self,
            SymptomEntry.self,
            BloodSugarReading.self,
            SupplementLog.self,
            MealEntry.self,
            Insight.self,
        ])
        let config = ModelConfiguration(
            schema: schema,
            isStoredInMemoryOnly: true,
            cloudKitDatabase: .none
        )
        return try ModelContainer(for: schema, configurations: [config])
    }

    private func makeEmptyReportData() -> ReportData {
        ReportData(
            cycles: [],
            symptoms: [],
            bloodSugarReadings: [],
            supplementLogs: [],
            meals: [],
            insights: [],
            startDate: Calendar.current.date(byAdding: .month, value: -1, to: Date()) ?? Date(),
            endDate: Date()
        )
    }

    private func makeAllSections(enabled: Bool) -> PDFSections {
        PDFSections(
            cycles: enabled,
            symptoms: enabled,
            bloodSugar: enabled,
            supplements: enabled,
            meals: enabled,
            insights: enabled
        )
    }

    // MARK: - Tests

    @Test("Empty data generates PDF with non-nil URL")
    func emptyDataGeneratesPDF() throws {
        _ = try makeContainer()
        let generator = PDFReportGenerator()
        let data = makeEmptyReportData()
        let sections = makeAllSections(enabled: true)

        let url = generator.generate(from: data, sections: sections)
        #expect(url != nil)
    }

    @Test("PDF file exists at returned URL")
    func pdfFileExistsAtURL() throws {
        _ = try makeContainer()
        let generator = PDFReportGenerator()
        let data = makeEmptyReportData()
        let sections = makeAllSections(enabled: true)

        let url = generator.generate(from: data, sections: sections)
        #expect(url != nil)

        if let url {
            #expect(FileManager.default.fileExists(atPath: url.path))
        }
    }

    @Test("Report with all sections and populated data generates PDF")
    func allSectionsPopulatedGenerates() throws {
        let container = try makeContainer()
        let context = container.mainContext

        // Create sample data
        let cycle = Cycle(startDate: Date(), endDate: Date(), lengthDays: 28)
        context.insert(cycle)

        let symptom = SymptomEntry(date: Date(), type: .fatigue, severity: 3)
        context.insert(symptom)

        let reading = BloodSugarReading(
            timestamp: Date(),
            glucoseValue: 95.0,
            readingType: .fasting
        )
        context.insert(reading)

        let supplement = SupplementLog(
            date: Date(),
            supplementName: "Inositol",
            dosageMg: 2000,
            timeTaken: Date(),
            taken: true
        )
        context.insert(supplement)

        let meal = MealEntry(
            timestamp: Date(),
            mealType: .lunch,
            mealDescription: "Grilled chicken salad",
            glycemicImpact: .low
        )
        context.insert(meal)

        let insight = Insight(
            insightType: .cyclePattern,
            title: "Regular Cycles",
            content: "Your cycles have been consistent.",
            confidence: 0.85,
            dataPointsUsed: 10
        )
        context.insert(insight)

        try context.save()

        let data = ReportData(
            cycles: [cycle],
            symptoms: [symptom],
            bloodSugarReadings: [reading],
            supplementLogs: [supplement],
            meals: [meal],
            insights: [insight],
            startDate: Calendar.current.date(byAdding: .month, value: -1, to: Date()) ?? Date(),
            endDate: Date()
        )

        let generator = PDFReportGenerator()
        let sections = makeAllSections(enabled: true)

        let url = generator.generate(from: data, sections: sections)
        #expect(url != nil)

        if let url {
            #expect(FileManager.default.fileExists(atPath: url.path))
            let fileData = try Data(contentsOf: url)
            #expect(fileData.count > 0)
        }
    }

    @Test("Report with no sections still generates cover page")
    func noSectionsStillGeneratesCoverPage() throws {
        _ = try makeContainer()
        let generator = PDFReportGenerator()
        let data = makeEmptyReportData()
        let sections = makeAllSections(enabled: false)

        let url = generator.generate(from: data, sections: sections)
        #expect(url != nil)

        if let url {
            #expect(FileManager.default.fileExists(atPath: url.path))
            let fileData = try Data(contentsOf: url)
            #expect(fileData.count > 0)
        }
    }
}
