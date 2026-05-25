import Testing
import Foundation
import SwiftData
import CoreGraphics
import PDFKit
import UIKit
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
            DailyLog.self,
            HairPhotoEntry.self,
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
            dailyLogs: [],
            hairPhotos: [],
            insights: [],
            pregnancyRecords: [],
            startDate: Calendar.current.date(byAdding: .month, value: -1, to: Date()) ?? Date(),
            endDate: Date()
        )
    }

    private func makeAllSections(
        enabled: Bool,
        photoComparisonStyle: ComparisonPhotoPresentationStyle = .clinical
    ) -> PDFSections {
        PDFSections(
            cycles: enabled,
            symptoms: enabled,
            bloodSugar: enabled,
            supplements: enabled,
            meals: enabled,
            weightTrend: enabled,
            hairPhotos: enabled,
            photoComparisonStyle: photoComparisonStyle,
            insights: enabled,
            pregnancy: enabled
        )
    }

    private func makeImageData(
        size: CGSize = CGSize(width: 240, height: 320),
        color: UIColor = .systemBlue
    ) -> Data {
        let renderer = UIGraphicsImageRenderer(size: size)
        let image = renderer.image { context in
            color.setFill()
            context.fill(CGRect(origin: .zero, size: size))
            UIColor.white.setFill()
            context.fill(
                CGRect(
                    x: size.width * 0.22,
                    y: size.height * 0.2,
                    width: size.width * 0.56,
                    height: size.height * 0.6
                )
            )
        }
        return image.jpegData(compressionQuality: 0.9) ?? Data()
    }

    private func pdfPageCount(at url: URL) -> Int? {
        guard let document = CGPDFDocument(url as CFURL) else { return nil }
        return document.numberOfPages
    }

    private func pdfText(at url: URL) -> String? {
        PDFDocument(url: url)?.string
    }

    private func makeComparisonReportData() -> ReportData {
        let now = Date()
        let hairPhotos = HairPhotoType.allCases.enumerated().flatMap { index, type in
            [
                HairPhotoEntry(
                    date: now.addingTimeInterval(-Double((index + 7) * 86_400)),
                    photoType: type,
                    photoData: makeImageData(size: CGSize(width: 900, height: 1_400), color: .systemTeal)
                ),
                HairPhotoEntry(
                    date: now.addingTimeInterval(-Double(index * 86_400)),
                    photoType: type,
                    photoData: makeImageData(size: CGSize(width: 1_400, height: 900), color: .systemPink)
                ),
            ]
        }

        return ReportData(
            cycles: [],
            symptoms: [],
            bloodSugarReadings: [],
            supplementLogs: [],
            meals: [],
            dailyLogs: [],
            hairPhotos: hairPhotos,
            insights: [],
            pregnancyRecords: [],
            startDate: Calendar.current.date(byAdding: .month, value: -3, to: now) ?? now,
            endDate: now
        )
    }

    // MARK: - Tests

    @Test("Comparison photo aspect-fit math preserves image proportions inside the slot")
    func comparisonPhotoAspectFitPreservesProportions() {
        let bounds = CGRect(x: 0, y: 0, width: 240, height: 320)
        let rect = ComparisonPhotoPresentation.aspectFitRect(
            for: CGSize(width: 1_200, height: 800),
            in: bounds
        )

        #expect(rect.minX >= bounds.minX)
        #expect(rect.maxX <= bounds.maxX)
        #expect(rect.minY >= bounds.minY)
        #expect(rect.maxY <= bounds.maxY)
        #expect(abs((rect.width / rect.height) - 1.5) < 0.01)
    }

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

        let dailyLog = DailyLog(
            date: Date(),
            weight: 74.2,
            sleepHours: 7.2,
            activeMinutes: 42
        )
        context.insert(dailyLog)

        let hairPhoto = HairPhotoEntry(
            date: Date(),
            photoType: .hairline,
            photoData: Data([0xFF, 0xD8, 0xFF])
        )
        context.insert(hairPhoto)

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
            dailyLogs: [dailyLog],
            hairPhotos: [hairPhoto],
            insights: [insight],
            pregnancyRecords: [],
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

    @Test("Clinical comparison layout paginates multiple photo comparison rows")
    func clinicalComparisonLayoutPaginatesRows() throws {
        _ = try makeContainer()
        let generator = PDFReportGenerator()
        let data = makeComparisonReportData()
        var sections = makeAllSections(enabled: false)
        sections.hairPhotos = true
        sections.photoComparisonStyle = .clinical

        let url = try #require(generator.generate(from: data, sections: sections))
        let pageCount = try #require(pdfPageCount(at: url))
        #expect(pageCount > 1)
    }

    @Test("Standard and clinical comparison layouts both generate distinct export output")
    func comparisonLayoutsGenerateDistinctOutput() throws {
        _ = try makeContainer()
        let generator = PDFReportGenerator()
        let data = makeComparisonReportData()

        var standardSections = makeAllSections(enabled: false, photoComparisonStyle: .standard)
        standardSections.hairPhotos = true

        var clinicalSections = makeAllSections(enabled: false, photoComparisonStyle: .clinical)
        clinicalSections.hairPhotos = true

        let standardURL = try #require(generator.generate(from: data, sections: standardSections))
        let clinicalURL = try #require(generator.generate(from: data, sections: clinicalSections))
        let standardPages = try #require(pdfPageCount(at: standardURL))
        let clinicalPages = try #require(pdfPageCount(at: clinicalURL))
        let standardData = try Data(contentsOf: standardURL)
        let clinicalData = try Data(contentsOf: clinicalURL)

        #expect(standardPages >= 1)
        #expect(clinicalPages >= 1)
        #expect(standardData != clinicalData)
    }

    @Test("Report content follows the explicitly selected app language")
    func reportContentFollowsExplicitAppLanguage() throws {
        _ = try makeContainer()
        let calendar = Calendar(identifier: .gregorian)
        let startDate = try #require(calendar.date(from: DateComponents(year: 2026, month: 3, day: 1)))
        let endDate = try #require(calendar.date(from: DateComponents(year: 2026, month: 3, day: 31)))
        let generator = PDFReportGenerator(appLanguage: .fr, preferredLanguages: ["en-US"])
        let data = ReportData(
            cycles: [],
            symptoms: [],
            bloodSugarReadings: [],
            supplementLogs: [],
            meals: [],
            dailyLogs: [],
            hairPhotos: [],
            insights: [],
            pregnancyRecords: [],
            startDate: startDate,
            endDate: endDate
        )

        let url = try #require(generator.generate(from: data, sections: makeAllSections(enabled: false)))
        let text = try #require(pdfText(at: url))
        let locale = Locale(identifier: "fr_FR")
        let expectedRange = "\(startDate.formatted(Date.FormatStyle(date: .abbreviated, time: .omitted).locale(locale))) - \(endDate.formatted(Date.FormatStyle(date: .abbreviated, time: .omitted).locale(locale)))"

        #expect(text.contains("CycleBalance Rapport de santé"))
        #expect(text.contains("Généré le"))
        #expect(text.contains(expectedRange))
        #expect(!text.contains("CycleBalance Health Report"))
    }
}
