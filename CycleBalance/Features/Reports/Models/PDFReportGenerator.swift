import UIKit
import os

struct ReportData {
    let cycles: [Cycle]
    let symptoms: [SymptomEntry]
    let bloodSugarReadings: [BloodSugarReading]
    let supplementLogs: [SupplementLog]
    let meals: [MealEntry]
    let insights: [Insight]
    let startDate: Date
    let endDate: Date
}

struct PDFSections {
    var cycles: Bool
    var symptoms: Bool
    var bloodSugar: Bool
    var supplements: Bool
    var meals: Bool
    var insights: Bool
}

@MainActor
struct PDFReportGenerator {

    // MARK: - Layout Constants

    private let pageSize = CGSize(width: 595.28, height: 841.89) // A4
    private let margin: CGFloat = 50
    private let headerColor = UIColor(red: 0.384, green: 0.498, blue: 0.478, alpha: 1) // #627F7A sage green
    private let bodyFont = UIFont.systemFont(ofSize: 11)
    private let bodyBoldFont = UIFont.boldSystemFont(ofSize: 11)
    private let sectionTitleFont = UIFont.boldSystemFont(ofSize: 16)
    private let coverTitleFont = UIFont.boldSystemFont(ofSize: 28)
    private let coverSubtitleFont = UIFont.systemFont(ofSize: 14)
    private let lineSpacing: CGFloat = 18

    private var contentWidth: CGFloat { pageSize.width - margin * 2 }

    // MARK: - Public

    func generate(from data: ReportData, sections: PDFSections) -> URL? {
        let renderer = UIGraphicsPDFRenderer(bounds: CGRect(origin: .zero, size: pageSize))

        let pdfData = renderer.pdfData { context in
            var cursor = DrawCursor(context: context, pageSize: pageSize, margin: margin)

            // Cover page
            drawCoverPage(data: data, cursor: &cursor)

            // Cycle Summary
            if sections.cycles {
                drawCycleSummary(data: data, cursor: &cursor)
            }

            // Symptom Summary
            if sections.symptoms {
                drawSymptomSummary(data: data, cursor: &cursor)
            }

            // Blood Sugar
            if sections.bloodSugar {
                drawBloodSugarSummary(data: data, cursor: &cursor)
            }

            // Supplement Adherence
            if sections.supplements {
                drawSupplementAdherence(data: data, cursor: &cursor)
            }

            // Meal GI Distribution
            if sections.meals {
                drawMealDistribution(data: data, cursor: &cursor)
            }

            // Insights
            if sections.insights {
                drawInsights(data: data, cursor: &cursor)
            }
        }

        let fileName = "CycleBalance_Report_\(Self.filenameDateFormatter.string(from: Date())).pdf"
        let tempURL = FileManager.default.temporaryDirectory.appendingPathComponent(fileName)
        do {
            try pdfData.write(to: tempURL)
            return tempURL
        } catch {
            Logger.database.error("Failed to write PDF report: \(error.localizedDescription)")
            return nil
        }
    }

    // MARK: - Cover Page

    private func drawCoverPage(data: ReportData, cursor: inout DrawCursor) {
        cursor.beginPage()

        let centerX = pageSize.width / 2

        // Title
        let titleY: CGFloat = 260
        let titleAttrs: [NSAttributedString.Key: Any] = [
            .font: coverTitleFont,
            .foregroundColor: headerColor,
            .paragraphStyle: centeredParagraph()
        ]
        let titleString = "CycleBalance Health Report"
        let titleRect = CGRect(x: margin, y: titleY, width: contentWidth, height: 40)
        (titleString as NSString).draw(in: titleRect, withAttributes: titleAttrs)

        // Date range
        let rangeText = "\(Self.displayDateFormatter.string(from: data.startDate)) - \(Self.displayDateFormatter.string(from: data.endDate))"
        let rangeAttrs: [NSAttributedString.Key: Any] = [
            .font: coverSubtitleFont,
            .foregroundColor: UIColor.darkGray,
            .paragraphStyle: centeredParagraph()
        ]
        let rangeRect = CGRect(x: margin, y: titleY + 50, width: contentWidth, height: 22)
        (rangeText as NSString).draw(in: rangeRect, withAttributes: rangeAttrs)

        // Generation date
        let genText = "Generated on \(Self.displayDateFormatter.string(from: Date()))"
        let genAttrs: [NSAttributedString.Key: Any] = [
            .font: UIFont.systemFont(ofSize: 10),
            .foregroundColor: UIColor.gray,
            .paragraphStyle: centeredParagraph()
        ]
        let genRect = CGRect(x: margin, y: titleY + 78, width: contentWidth, height: 16)
        (genText as NSString).draw(in: genRect, withAttributes: genAttrs)

        // Decorative line
        let lineY = titleY + 110
        let lineInset: CGFloat = 120
        let linePath = UIBezierPath()
        linePath.move(to: CGPoint(x: centerX - lineInset, y: lineY))
        linePath.addLine(to: CGPoint(x: centerX + lineInset, y: lineY))
        headerColor.setStroke()
        linePath.lineWidth = 1.5
        linePath.stroke()

        // Disclaimer
        let disclaimerText = "This report is for informational purposes only and is not a substitute for professional medical advice."
        let disclaimerAttrs: [NSAttributedString.Key: Any] = [
            .font: UIFont.italicSystemFont(ofSize: 9),
            .foregroundColor: UIColor.gray,
            .paragraphStyle: centeredParagraph()
        ]
        let disclaimerRect = CGRect(x: margin, y: pageSize.height - margin - 30, width: contentWidth, height: 30)
        (disclaimerText as NSString).draw(in: disclaimerRect, withAttributes: disclaimerAttrs)
    }

    // MARK: - Cycle Summary

    private func drawCycleSummary(data: ReportData, cursor: inout DrawCursor) {
        cursor.beginPage()
        cursor.y = margin

        drawSectionHeader("Cycle Summary", cursor: &cursor)

        let cycles = data.cycles
        if cycles.isEmpty {
            drawBodyText("No cycle data recorded in this period.", cursor: &cursor)
            return
        }

        let count = cycles.count
        let lengths = cycles.compactMap(\.lengthDays)
        let avgLength: String
        let rangeStr: String
        if lengths.isEmpty {
            avgLength = "N/A"
            rangeStr = "N/A"
        } else {
            let avg = Double(lengths.reduce(0, +)) / Double(lengths.count)
            avgLength = String(format: "%.1f days", avg)
            let minL = lengths.min() ?? 0
            let maxL = lengths.max() ?? 0
            rangeStr = "\(minL) - \(maxL) days"
        }

        drawBodyText("Total cycles: \(count)", cursor: &cursor)
        drawBodyText("Average length: \(avgLength)", cursor: &cursor)
        drawBodyText("Length range: \(rangeStr)", cursor: &cursor)
        cursor.y += lineSpacing / 2

        drawSubheader("Cycle Dates", cursor: &cursor)
        for cycle in cycles {
            let start = Self.displayDateFormatter.string(from: cycle.startDate)
            let end = cycle.endDate.map { Self.displayDateFormatter.string(from: $0) } ?? "ongoing"
            let lengthNote = cycle.lengthDays.map { " (\($0) days)" } ?? ""
            drawBodyText("\(start) - \(end)\(lengthNote)", cursor: &cursor)
        }
    }

    // MARK: - Symptom Summary

    private func drawSymptomSummary(data: ReportData, cursor: inout DrawCursor) {
        cursor.beginPage()
        cursor.y = margin

        drawSectionHeader("Symptom Summary", cursor: &cursor)

        let symptoms = data.symptoms
        if symptoms.isEmpty {
            drawBodyText("No symptom data recorded in this period.", cursor: &cursor)
            return
        }

        // Top symptoms by frequency
        let grouped = Dictionary(grouping: symptoms, by: \.symptomType)
        let sorted = grouped.sorted { $0.value.count > $1.value.count }

        drawSubheader("Top Symptoms by Frequency", cursor: &cursor)
        for (type, entries) in sorted.prefix(10) {
            let avgSev = Double(entries.map(\.severity).reduce(0, +)) / Double(entries.count)
            drawBodyText("\(type.displayName): \(entries.count) occurrences, avg severity \(String(format: "%.1f", avgSev))/5", cursor: &cursor)
        }

        cursor.y += lineSpacing / 2

        drawSubheader("Average Severity per Symptom", cursor: &cursor)
        for (type, entries) in sorted {
            let avgSev = Double(entries.map(\.severity).reduce(0, +)) / Double(entries.count)
            drawBodyText("\(type.displayName): \(String(format: "%.1f", avgSev))/5", cursor: &cursor)
        }
    }

    // MARK: - Blood Sugar Summary

    private func drawBloodSugarSummary(data: ReportData, cursor: inout DrawCursor) {
        cursor.beginPage()
        cursor.y = margin

        drawSectionHeader("Blood Sugar", cursor: &cursor)

        let readings = data.bloodSugarReadings
        if readings.isEmpty {
            drawBodyText("No blood sugar data recorded in this period.", cursor: &cursor)
            return
        }

        let allValues = readings.map(\.glucoseValue)
        let overallAvg = allValues.reduce(0, +) / Double(allValues.count)

        drawBodyText("Total readings: \(readings.count)", cursor: &cursor)
        drawBodyText("Overall average: \(String(format: "%.1f", overallAvg)) mg/dL", cursor: &cursor)
        cursor.y += lineSpacing / 2

        drawSubheader("Average by Reading Type", cursor: &cursor)
        let byType = Dictionary(grouping: readings, by: \.readingType)
        for readingType in GlucoseReadingType.allCases {
            if let entries = byType[readingType], !entries.isEmpty {
                let avg = entries.map(\.glucoseValue).reduce(0, +) / Double(entries.count)
                drawBodyText("\(readingType.displayName): \(String(format: "%.1f", avg)) mg/dL (\(entries.count) readings)", cursor: &cursor)
            }
        }
    }

    // MARK: - Supplement Adherence

    private func drawSupplementAdherence(data: ReportData, cursor: inout DrawCursor) {
        cursor.beginPage()
        cursor.y = margin

        drawSectionHeader("Supplement Adherence", cursor: &cursor)

        let logs = data.supplementLogs
        if logs.isEmpty {
            drawBodyText("No supplement data recorded in this period.", cursor: &cursor)
            return
        }

        let bySupplement = Dictionary(grouping: logs, by: \.supplementName)
        var totalTaken = 0
        var totalLogs = 0

        drawSubheader("Per-Supplement Breakdown", cursor: &cursor)
        for (name, entries) in bySupplement.sorted(by: { $0.key < $1.key }) {
            let taken = entries.filter(\.taken).count
            let missed = entries.count - taken
            totalTaken += taken
            totalLogs += entries.count
            let pct = entries.isEmpty ? 0 : Int(Double(taken) / Double(entries.count) * 100)
            drawBodyText("\(name): \(taken) taken, \(missed) missed (\(pct)% adherence)", cursor: &cursor)
        }

        cursor.y += lineSpacing / 2
        let overallPct = totalLogs == 0 ? 0 : Int(Double(totalTaken) / Double(totalLogs) * 100)
        drawBodyText("Overall adherence: \(overallPct)%", bold: true, cursor: &cursor)
    }

    // MARK: - Meal GI Distribution

    private func drawMealDistribution(data: ReportData, cursor: inout DrawCursor) {
        cursor.beginPage()
        cursor.y = margin

        drawSectionHeader("Meal GI Distribution", cursor: &cursor)

        let meals = data.meals
        if meals.isEmpty {
            drawBodyText("No meal data recorded in this period.", cursor: &cursor)
            return
        }

        let byImpact = Dictionary(grouping: meals, by: \.glycemicImpact)
        let lowCount = byImpact[.low]?.count ?? 0
        let medCount = byImpact[.medium]?.count ?? 0
        let highCount = byImpact[.high]?.count ?? 0

        drawBodyText("Total meals logged: \(meals.count)", cursor: &cursor)
        cursor.y += lineSpacing / 2
        drawBodyText("Low GI: \(lowCount) meals", cursor: &cursor)
        drawBodyText("Medium GI: \(medCount) meals", cursor: &cursor)
        drawBodyText("High GI: \(highCount) meals", cursor: &cursor)

        if !meals.isEmpty {
            cursor.y += lineSpacing / 2
            let lowPct = Int(Double(lowCount) / Double(meals.count) * 100)
            let medPct = Int(Double(medCount) / Double(meals.count) * 100)
            let highPct = Int(Double(highCount) / Double(meals.count) * 100)
            drawBodyText("Distribution: \(lowPct)% Low, \(medPct)% Medium, \(highPct)% High", bold: true, cursor: &cursor)
        }
    }

    // MARK: - Insights

    private func drawInsights(data: ReportData, cursor: inout DrawCursor) {
        cursor.beginPage()
        cursor.y = margin

        drawSectionHeader("Insights", cursor: &cursor)

        let insights = data.insights
        if insights.isEmpty {
            drawBodyText("No insights generated in this period.", cursor: &cursor)
            return
        }

        for insight in insights {
            ensureSpace(needed: lineSpacing * 4, cursor: &cursor)

            drawSubheader(insight.title, cursor: &cursor)

            let typeLabel = "[\(insight.insightType.displayName)] "
            drawBodyText(typeLabel + insight.content, cursor: &cursor)
            cursor.y += lineSpacing / 2
        }
    }

    // MARK: - Drawing Helpers

    private func drawSectionHeader(_ text: String, cursor: inout DrawCursor) {
        ensureSpace(needed: lineSpacing * 3, cursor: &cursor)

        let attrs: [NSAttributedString.Key: Any] = [
            .font: sectionTitleFont,
            .foregroundColor: headerColor
        ]
        let rect = CGRect(x: cursor.margin, y: cursor.y, width: contentWidth, height: 24)
        (text as NSString).draw(in: rect, withAttributes: attrs)
        cursor.y += 28

        // Underline
        let path = UIBezierPath()
        path.move(to: CGPoint(x: cursor.margin, y: cursor.y))
        path.addLine(to: CGPoint(x: cursor.margin + contentWidth, y: cursor.y))
        headerColor.setStroke()
        path.lineWidth = 1
        path.stroke()
        cursor.y += lineSpacing / 2
    }

    private func drawSubheader(_ text: String, cursor: inout DrawCursor) {
        ensureSpace(needed: lineSpacing * 2, cursor: &cursor)

        let attrs: [NSAttributedString.Key: Any] = [
            .font: bodyBoldFont,
            .foregroundColor: UIColor.darkGray
        ]
        let size = (text as NSString).boundingRect(
            with: CGSize(width: contentWidth, height: .greatestFiniteMagnitude),
            options: [.usesLineFragmentOrigin],
            attributes: attrs,
            context: nil
        )
        let rect = CGRect(x: cursor.margin, y: cursor.y, width: contentWidth, height: size.height + 4)
        (text as NSString).draw(in: rect, withAttributes: attrs)
        cursor.y += rect.height + 4
    }

    private func drawBodyText(_ text: String, bold: Bool = false, cursor: inout DrawCursor) {
        let font = bold ? bodyBoldFont : bodyFont
        let attrs: [NSAttributedString.Key: Any] = [
            .font: font,
            .foregroundColor: UIColor.darkText
        ]
        let size = (text as NSString).boundingRect(
            with: CGSize(width: contentWidth, height: .greatestFiniteMagnitude),
            options: [.usesLineFragmentOrigin],
            attributes: attrs,
            context: nil
        )
        let height = max(size.height + 4, lineSpacing)

        ensureSpace(needed: height, cursor: &cursor)

        let rect = CGRect(x: cursor.margin, y: cursor.y, width: contentWidth, height: height)
        (text as NSString).draw(in: rect, withAttributes: attrs)
        cursor.y += height
    }

    private func ensureSpace(needed: CGFloat, cursor: inout DrawCursor) {
        if cursor.y + needed > cursor.pageSize.height - cursor.margin {
            cursor.beginPage()
            cursor.y = cursor.margin
        }
    }

    private func centeredParagraph() -> NSMutableParagraphStyle {
        let style = NSMutableParagraphStyle()
        style.alignment = .center
        return style
    }

    // MARK: - Date Formatters

    private static let displayDateFormatter: DateFormatter = {
        let f = DateFormatter()
        f.dateStyle = .medium
        f.timeStyle = .none
        return f
    }()

    private static let filenameDateFormatter: DateFormatter = {
        let f = DateFormatter()
        f.dateFormat = "yyyy-MM-dd_HHmmss"
        return f
    }()
}

// MARK: - Draw Cursor

private struct DrawCursor {
    let context: UIGraphicsPDFRendererContext
    let pageSize: CGSize
    let margin: CGFloat
    var y: CGFloat = 0

    mutating func beginPage() {
        context.beginPage()
        y = margin
    }
}
