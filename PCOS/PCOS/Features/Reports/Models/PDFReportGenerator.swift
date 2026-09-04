import UIKit
import os

enum ComparisonPhotoPresentationStyle: String, CaseIterable, Identifiable, Sendable {
    case standard
    case clinical

    var id: String { rawValue }
}

struct ComparisonPhotoPresentation {
    let style: ComparisonPhotoPresentationStyle

    static let columnSpacing: CGFloat = 12
    static let captionSpacing: CGFloat = 6
    static let captionHeight: CGFloat = 14

    var slotAspectRatio: CGFloat {
        switch style {
        case .standard:
            return 1.35
        case .clinical:
            return 0.75
        }
    }

    var slotPadding: CGFloat {
        switch style {
        case .standard:
            return 8
        case .clinical:
            return 12
        }
    }

    var cornerRadius: CGFloat {
        switch style {
        case .standard:
            return 8
        case .clinical:
            return 12
        }
    }

    var slotBackgroundColor: UIColor { UIColor.secondarySystemBackground }

    var slotBorderColor: UIColor {
        UIColor.secondaryLabel.withAlphaComponent(style == .clinical ? 0.22 : 0.14)
    }

    var slotBorderWidth: CGFloat { 1 }

    var captionFont: UIFont {
        UIFont.systemFont(ofSize: style == .clinical ? 9 : 8.5)
    }

    var placeholderFont: UIFont {
        UIFont.systemFont(ofSize: style == .clinical ? 10 : 9, weight: .medium)
    }

    func slotHeight(for width: CGFloat) -> CGFloat {
        width / max(slotAspectRatio, 0.01)
    }

    func imageRect(for imageSize: CGSize, in slotRect: CGRect) -> CGRect {
        Self.aspectFitRect(
            for: imageSize,
            in: slotRect.insetBy(dx: slotPadding, dy: slotPadding)
        )
    }

    static func aspectFitRect(for imageSize: CGSize, in bounds: CGRect) -> CGRect {
        guard imageSize.width > 0, imageSize.height > 0, bounds.width > 0, bounds.height > 0 else {
            return bounds
        }

        let widthScale = bounds.width / imageSize.width
        let heightScale = bounds.height / imageSize.height
        let scale = min(widthScale, heightScale)

        let fittedSize = CGSize(
            width: imageSize.width * scale,
            height: imageSize.height * scale
        )

        return CGRect(
            x: bounds.midX - fittedSize.width / 2,
            y: bounds.midY - fittedSize.height / 2,
            width: fittedSize.width,
            height: fittedSize.height
        ).integral
    }
}

struct ReportData {
    let cycles: [Cycle]
    let symptoms: [SymptomEntry]
    let bloodSugarReadings: [BloodSugarReading]
    let supplementLogs: [SupplementLog]
    let meals: [MealEntry]
    let dailyLogs: [DailyLog]
    let hairPhotos: [HairPhotoEntry]
    let insights: [Insight]
    let pregnancyRecords: [PregnancyRecord]
    let startDate: Date
    let endDate: Date
}

struct PDFSections {
    var cycles: Bool
    var symptoms: Bool
    var bloodSugar: Bool
    var supplements: Bool
    var meals: Bool
    var weightTrend: Bool
    var hairPhotos: Bool
    var photoComparisonStyle: ComparisonPhotoPresentationStyle
    var insights: Bool
    var pregnancy: Bool
}

@MainActor
struct PDFReportGenerator {
    private let appLanguage: AppLanguage
    private let preferredLanguages: [String]

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

    init(
        appLanguage: AppLanguage = .system,
        preferredLanguages: [String] = Locale.preferredLanguages
    ) {
        self.appLanguage = appLanguage
        self.preferredLanguages = preferredLanguages
    }

    // MARK: - Public

    func generate(from data: ReportData, sections: PDFSections) -> URL? {
        L10n.withOverrides(appLanguage: appLanguage, preferredLanguages: preferredLanguages) {
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

                // Weight trend
                if sections.weightTrend {
                    drawWeightTrend(data: data, cursor: &cursor)
                }

                // Hair photo comparison
                if sections.hairPhotos {
                    drawHairPhotoGrid(
                        data: data,
                        cursor: &cursor,
                        style: sections.photoComparisonStyle
                    )
                }

                // Insights
                if sections.insights {
                    drawInsights(data: data, cursor: &cursor)
                }

                // Pregnancy
                if sections.pregnancy {
                    drawPregnancySummary(data: data, cursor: &cursor)
                }
            }

            let fileName = "CycleBalance_Report_\(Self.filenameDateFormatter.string(from: Date()))_\(UUID().uuidString).pdf"
            let tempURL = FileManager.default.temporaryDirectory.appendingPathComponent(fileName)
            do {
                try pdfData.write(to: tempURL)
                return tempURL
            } catch {
                Logger.database.error("Failed to write PDF report: \(error.localizedDescription)")
                return nil
            }
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
        let titleString = localized(
            "CycleBalance Health Report",
            defaultValue: "CycleBalance Health Report"
        )
        let titleRect = CGRect(x: margin, y: titleY, width: contentWidth, height: 40)
        (titleString as NSString).draw(in: titleRect, withAttributes: titleAttrs)

        // Date range
        let rangeText = "\(displayDate(data.startDate)) - \(displayDate(data.endDate))"
        let rangeAttrs: [NSAttributedString.Key: Any] = [
            .font: coverSubtitleFont,
            .foregroundColor: UIColor.darkGray,
            .paragraphStyle: centeredParagraph()
        ]
        let rangeRect = CGRect(x: margin, y: titleY + 50, width: contentWidth, height: 22)
        (rangeText as NSString).draw(in: rangeRect, withAttributes: rangeAttrs)

        // Generation date
        let genText = format(
            "Generated on %@",
            defaultValue: "Generated on %@",
            displayDate(Date())
        )
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
        let disclaimerText = localized(
            "This report is for informational purposes only and is not a substitute for professional medical advice.",
            defaultValue: "This report is for informational purposes only and is not a substitute for professional medical advice."
        )
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

        drawSectionHeader(
            localized("Cycle Summary", defaultValue: "Cycle Summary"),
            cursor: &cursor
        )

        let cycles = data.cycles
        if cycles.isEmpty {
            drawBodyText(
                localized(
                    "No cycle data recorded in this period.",
                    defaultValue: "No cycle data recorded in this period."
                ),
                cursor: &cursor
            )
            return
        }

        let count = cycles.count
        let lengths = cycles.compactMap(\.lengthDays)
        let avgLength: String
        let rangeStr: String
        if lengths.isEmpty {
            avgLength = localized("N/A", defaultValue: "N/A")
            rangeStr = localized("N/A", defaultValue: "N/A")
        } else {
            let avg = Double(lengths.reduce(0, +)) / Double(lengths.count)
            avgLength = format(
                "%@ days",
                defaultValue: "%@ days",
                decimal(avg)
            )
            let minL = lengths.min() ?? 0
            let maxL = lengths.max() ?? 0
            rangeStr = format(
                "%@ - %@ days",
                defaultValue: "%@ - %@ days",
                integer(minL),
                integer(maxL)
            )
        }

        drawBodyText(
            format(
                "Total cycles: %@",
                defaultValue: "Total cycles: %@",
                integer(count)
            ),
            cursor: &cursor
        )
        drawBodyText(
            format(
                "Average length: %@",
                defaultValue: "Average length: %@",
                avgLength
            ),
            cursor: &cursor
        )
        drawBodyText(
            format(
                "Length range: %@",
                defaultValue: "Length range: %@",
                rangeStr
            ),
            cursor: &cursor
        )
        cursor.y += lineSpacing / 2

        drawSubheader(
            localized("Cycle Dates", defaultValue: "Cycle Dates"),
            cursor: &cursor
        )
        for cycle in cycles {
            let start = displayDate(cycle.startDate)
            let end = cycle.endDate.map(displayDate)
                ?? localized("ongoing", defaultValue: "ongoing")
            let lengthNote = cycle.lengthDays.map {
                format(
                    " (%@ days)",
                    defaultValue: " (%@ days)",
                    integer($0)
                )
            } ?? ""
            drawBodyText("\(start) - \(end)\(lengthNote)", cursor: &cursor)
        }
    }

    // MARK: - Symptom Summary

    private func drawSymptomSummary(data: ReportData, cursor: inout DrawCursor) {
        cursor.beginPage()
        cursor.y = margin

        drawSectionHeader(
            localized("Symptom Summary", defaultValue: "Symptom Summary"),
            cursor: &cursor
        )

        let symptoms = data.symptoms
        if symptoms.isEmpty {
            drawBodyText(
                localized(
                    "No symptom data recorded in this period.",
                    defaultValue: "No symptom data recorded in this period."
                ),
                cursor: &cursor
            )
            return
        }

        // Top symptoms by frequency
        let grouped = Dictionary(grouping: symptoms, by: \.symptomType)
        let sorted = grouped.sorted { $0.value.count > $1.value.count }

        drawSubheader(
            localized("Top Symptoms by Frequency", defaultValue: "Top Symptoms by Frequency"),
            cursor: &cursor
        )
        for (type, entries) in sorted.prefix(10) {
            let avgSev = Double(entries.map(\.severity).reduce(0, +)) / Double(entries.count)
            drawBodyText(
                format(
                    "%@: %@ occurrences, avg severity %@/5",
                    defaultValue: "%@: %@ occurrences, avg severity %@/5",
                    type.displayName,
                    integer(entries.count),
                    decimal(avgSev)
                ),
                cursor: &cursor
            )
        }

        cursor.y += lineSpacing / 2

        drawSubheader(
            localized("Average Severity per Symptom", defaultValue: "Average Severity per Symptom"),
            cursor: &cursor
        )
        for (type, entries) in sorted {
            let avgSev = Double(entries.map(\.severity).reduce(0, +)) / Double(entries.count)
            drawBodyText(
                format(
                    "%@: %@/5",
                    defaultValue: "%@: %@/5",
                    type.displayName,
                    decimal(avgSev)
                ),
                cursor: &cursor
            )
        }
    }

    // MARK: - Blood Sugar Summary

    private func drawBloodSugarSummary(data: ReportData, cursor: inout DrawCursor) {
        cursor.beginPage()
        cursor.y = margin

        drawSectionHeader(
            localized("Blood Sugar", defaultValue: "Blood Sugar"),
            cursor: &cursor
        )

        let readings = data.bloodSugarReadings
        if readings.isEmpty {
            drawBodyText(
                localized(
                    "No blood sugar data recorded in this period.",
                    defaultValue: "No blood sugar data recorded in this period."
                ),
                cursor: &cursor
            )
            return
        }

        let allValues = readings.map(\.glucoseValue)
        let overallAvg = allValues.reduce(0, +) / Double(allValues.count)

        drawBodyText(
            format(
                "Total readings: %@",
                defaultValue: "Total readings: %@",
                integer(readings.count)
            ),
            cursor: &cursor
        )
        drawBodyText(
            format(
                "Overall average: %@ mg/dL",
                defaultValue: "Overall average: %@ mg/dL",
                decimal(overallAvg)
            ),
            cursor: &cursor
        )
        cursor.y += lineSpacing / 2

        drawSubheader(
            localized("Average by Reading Type", defaultValue: "Average by Reading Type"),
            cursor: &cursor
        )
        let byType = Dictionary(grouping: readings, by: \.readingType)
        for readingType in GlucoseReadingType.allCases {
            if let entries = byType[readingType], !entries.isEmpty {
                let avg = entries.map(\.glucoseValue).reduce(0, +) / Double(entries.count)
                drawBodyText(
                    format(
                        "%@: %@ mg/dL (%@ readings)",
                        defaultValue: "%@: %@ mg/dL (%@ readings)",
                        readingType.displayName,
                        decimal(avg),
                        integer(entries.count)
                    ),
                    cursor: &cursor
                )
            }
        }
    }

    // MARK: - Supplement Adherence

    private func drawSupplementAdherence(data: ReportData, cursor: inout DrawCursor) {
        cursor.beginPage()
        cursor.y = margin

        drawSectionHeader(
            localized("Supplement Adherence", defaultValue: "Supplement Adherence"),
            cursor: &cursor
        )

        let logs = data.supplementLogs
        if logs.isEmpty {
            drawBodyText(
                localized(
                    "No supplement data recorded in this period.",
                    defaultValue: "No supplement data recorded in this period."
                ),
                cursor: &cursor
            )
            return
        }

        let bySupplement = Dictionary(grouping: logs, by: \.supplementName)
        var totalTaken = 0
        var totalLogs = 0

        drawSubheader(
            localized("Per-Supplement Breakdown", defaultValue: "Per-Supplement Breakdown"),
            cursor: &cursor
        )
        for (name, entries) in bySupplement.sorted(by: { $0.key < $1.key }) {
            let taken = entries.filter(\.taken).count
            let missed = entries.count - taken
            totalTaken += taken
            totalLogs += entries.count
            let pct = entries.isEmpty ? 0 : Int(Double(taken) / Double(entries.count) * 100)
            drawBodyText(
                format(
                    "%@: %@ taken, %@ missed (%@%% adherence)",
                    defaultValue: "%@: %@ taken, %@ missed (%@%% adherence)",
                    name,
                    integer(taken),
                    integer(missed),
                    integer(pct)
                ),
                cursor: &cursor
            )
        }

        cursor.y += lineSpacing / 2
        let overallPct = totalLogs == 0 ? 0 : Int(Double(totalTaken) / Double(totalLogs) * 100)
        drawBodyText(
            format(
                "Overall adherence: %@%%",
                defaultValue: "Overall adherence: %@%%",
                integer(overallPct)
            ),
            bold: true,
            cursor: &cursor
        )
    }

    // MARK: - Meal GI Distribution

    private func drawMealDistribution(data: ReportData, cursor: inout DrawCursor) {
        cursor.beginPage()
        cursor.y = margin

        drawSectionHeader(
            localized("Meal GI Distribution", defaultValue: "Meal GI Distribution"),
            cursor: &cursor
        )

        let meals = data.meals
        if meals.isEmpty {
            drawBodyText(
                localized(
                    "No meal data recorded in this period.",
                    defaultValue: "No meal data recorded in this period."
                ),
                cursor: &cursor
            )
            return
        }

        let byImpact = Dictionary(grouping: meals, by: \.glycemicImpact)
        let lowCount = byImpact[.low]?.count ?? 0
        let medCount = byImpact[.medium]?.count ?? 0
        let highCount = byImpact[.high]?.count ?? 0

        drawBodyText(
            format(
                "Total meals logged: %@",
                defaultValue: "Total meals logged: %@",
                integer(meals.count)
            ),
            cursor: &cursor
        )
        cursor.y += lineSpacing / 2
        drawBodyText(
            format("Low GI: %@ meals", defaultValue: "Low GI: %@ meals", integer(lowCount)),
            cursor: &cursor
        )
        drawBodyText(
            format("Medium GI: %@ meals", defaultValue: "Medium GI: %@ meals", integer(medCount)),
            cursor: &cursor
        )
        drawBodyText(
            format("High GI: %@ meals", defaultValue: "High GI: %@ meals", integer(highCount)),
            cursor: &cursor
        )

        if !meals.isEmpty {
            cursor.y += lineSpacing / 2
            let lowPct = Int(Double(lowCount) / Double(meals.count) * 100)
            let medPct = Int(Double(medCount) / Double(meals.count) * 100)
            let highPct = Int(Double(highCount) / Double(meals.count) * 100)
            drawBodyText(
                format(
                    "Distribution: %@%% Low, %@%% Medium, %@%% High",
                    defaultValue: "Distribution: %@%% Low, %@%% Medium, %@%% High",
                    integer(lowPct),
                    integer(medPct),
                    integer(highPct)
                ),
                bold: true,
                cursor: &cursor
            )
        }
    }

    // MARK: - Weight Trend

    private func drawWeightTrend(data: ReportData, cursor: inout DrawCursor) {
        cursor.beginPage()
        cursor.y = margin

        drawSectionHeader(
            localized("Weight Trend", defaultValue: "Weight Trend"),
            cursor: &cursor
        )

        let weightedLogs = data.dailyLogs
            .compactMap { log -> (date: Date, weight: Double)? in
                guard let weight = log.weight else { return nil }
                return (date: log.date, weight: weight)
            }
            .sorted { $0.date < $1.date }

        guard !weightedLogs.isEmpty else {
            drawBodyText(
                localized(
                    "No weight data recorded in this period.",
                    defaultValue: "No weight data recorded in this period."
                ),
                cursor: &cursor
            )
            return
        }

        let startWeight = weightedLogs.first?.weight ?? 0
        let endWeight = weightedLogs.last?.weight ?? 0
        let delta = endWeight - startWeight
        let average = weightedLogs.map(\.weight).reduce(0, +) / Double(weightedLogs.count)

        drawBodyText(
            format(
                "Weight entries: %@",
                defaultValue: "Weight entries: %@",
                integer(weightedLogs.count)
            ),
            cursor: &cursor
        )
        drawBodyText(
            format(
                "Average weight: %@",
                defaultValue: "Average weight: %@",
                WeightDisplay.formatted(kilograms: average, locale: locale)
            ),
            cursor: &cursor
        )
        drawBodyText(
            format(
                "Start to end change: %@ %@",
                defaultValue: "Start to end change: %@ %@",
                WeightDisplay.formatted(kilograms: abs(delta), locale: locale),
                localized(delta >= 0 ? "increase" : "decrease", defaultValue: delta >= 0 ? "increase" : "decrease")
            ),
            cursor: &cursor
        )

        cursor.y += lineSpacing / 2
        drawSubheader(
            localized("Recent Measurements", defaultValue: "Recent Measurements"),
            cursor: &cursor
        )

        for entry in weightedLogs.suffix(10) {
            drawBodyText(
                "\(displayDate(entry.date)): \(WeightDisplay.formatted(kilograms: entry.weight, locale: locale))",
                cursor: &cursor
            )
        }
    }

    // MARK: - Hair Photo Grid

    private func drawHairPhotoGrid(
        data: ReportData,
        cursor: inout DrawCursor,
        style: ComparisonPhotoPresentationStyle
    ) {
        cursor.beginPage()
        cursor.y = margin

        drawSectionHeader(
            localized("Hair Photo Comparison Grid", defaultValue: "Hair Photo Comparison Grid"),
            cursor: &cursor
        )

        guard !data.hairPhotos.isEmpty else {
            drawBodyText(
                localized(
                    "No hair photos recorded in this period.",
                    defaultValue: "No hair photos recorded in this period."
                ),
                cursor: &cursor
            )
            return
        }

        let decryptor = PhotoEncryptionService()
        let grouped = Dictionary(grouping: data.hairPhotos, by: \.photoType)
        let comparisons = HairPhotoType.allCases.compactMap { type -> (type: HairPhotoType, before: HairPhotoEntry, after: HairPhotoEntry)? in
            guard let entries = grouped[type]?.sorted(by: { $0.date < $1.date }),
                  entries.count >= 2,
                  let before = entries.first,
                  let after = entries.last
            else {
                return nil
            }
            return (type, before, after)
        }

        guard !comparisons.isEmpty else {
            drawBodyText(
                localized(
                    "Add at least one photo type to generate comparison thumbnails.",
                    defaultValue: "Add at least one photo type to generate comparison thumbnails."
                ),
                cursor: &cursor
            )
            return
        }

        let presentation = ComparisonPhotoPresentation(style: style)
        let imageWidth = (contentWidth - ComparisonPhotoPresentation.columnSpacing) / 2
        let imageHeight = presentation.slotHeight(for: imageWidth)
        let rowHeight = imageHeight + ComparisonPhotoPresentation.captionSpacing + ComparisonPhotoPresentation.captionHeight
        let rowSpacing: CGFloat = style == .clinical ? 22 : 18

        for comparison in comparisons {
            ensureSpace(needed: rowHeight + 32, cursor: &cursor)

            drawSubheader(comparison.type.displayName, cursor: &cursor)

            let beforeRect = CGRect(x: cursor.margin, y: cursor.y, width: imageWidth, height: imageHeight)
            let afterRect = CGRect(
                x: cursor.margin + imageWidth + ComparisonPhotoPresentation.columnSpacing,
                y: cursor.y,
                width: imageWidth,
                height: imageHeight
            )

            drawPhotoThumbnail(
                entry: comparison.before,
                targetRect: beforeRect,
                label: localized("Before", defaultValue: "Before"),
                decryptor: decryptor,
                presentation: presentation
            )
            drawPhotoThumbnail(
                entry: comparison.after,
                targetRect: afterRect,
                label: localized("After", defaultValue: "After"),
                decryptor: decryptor,
                presentation: presentation
            )

            cursor.y += rowHeight + rowSpacing
        }
    }

    private func drawPhotoThumbnail(
        entry: HairPhotoEntry,
        targetRect: CGRect,
        label: String,
        decryptor: PhotoEncryptionService,
        presentation: ComparisonPhotoPresentation
    ) {
        let borderPath = UIBezierPath(roundedRect: targetRect, cornerRadius: presentation.cornerRadius)
        presentation.slotBackgroundColor.setFill()
        borderPath.fill()
        presentation.slotBorderColor.setStroke()
        borderPath.lineWidth = presentation.slotBorderWidth
        borderPath.stroke()

        if let decrypted = decryptor.decrypt(entry.photoData),
           let image = UIImage(data: decrypted) {
            image.draw(in: presentation.imageRect(for: image.size, in: targetRect))
        } else {
            let placeholderAttrs: [NSAttributedString.Key: Any] = [
                .font: presentation.placeholderFont,
                .foregroundColor: UIColor.secondaryLabel,
                .paragraphStyle: centeredParagraph()
            ]
            let placeholderRect = CGRect(
                x: targetRect.minX + presentation.slotPadding,
                y: targetRect.midY - 8,
                width: targetRect.width - presentation.slotPadding * 2,
                height: 16
            )
            (localized("No Photo", defaultValue: "No Photo") as NSString)
                .draw(in: placeholderRect, withAttributes: placeholderAttrs)
        }

        let caption = "\(label) • \(displayDate(entry.date))"
        let captionAttrs: [NSAttributedString.Key: Any] = [
            .font: presentation.captionFont,
            .foregroundColor: UIColor.darkGray
        ]
        let captionRect = CGRect(
            x: targetRect.minX + 4,
            y: targetRect.maxY + ComparisonPhotoPresentation.captionSpacing,
            width: targetRect.width - 8,
            height: ComparisonPhotoPresentation.captionHeight
        )
        (caption as NSString).draw(in: captionRect, withAttributes: captionAttrs)
    }

    // MARK: - Insights

    private func drawInsights(data: ReportData, cursor: inout DrawCursor) {
        cursor.beginPage()
        cursor.y = margin

        drawSectionHeader(
            localized("Insights", defaultValue: "Insights"),
            cursor: &cursor
        )

        let insights = data.insights
        if insights.isEmpty {
            drawBodyText(
                localized(
                    "No insights generated in this period.",
                    defaultValue: "No insights generated in this period."
                ),
                cursor: &cursor
            )
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

    // MARK: - Pregnancy Summary

    private func drawPregnancySummary(data: ReportData, cursor: inout DrawCursor) {
        let pregnancies = data.pregnancyRecords
        guard !pregnancies.isEmpty else { return }

        cursor.beginPage()
        cursor.y = margin

        drawSectionHeader(
            localized("Pregnancy", defaultValue: "Pregnancy"),
            cursor: &cursor
        )

        for pregnancy in pregnancies {
            let startStr = displayDate(pregnancy.startDate)
            let endStr = pregnancy.endDate.map(displayDate)
                ?? localized("ongoing", defaultValue: "ongoing")
            let reasonStr = pregnancy.endReason.map { " (\($0.displayName))" } ?? ""

            drawBodyText(
                "\(startStr) - \(endStr)\(reasonStr)",
                cursor: &cursor
            )

            if let dueDate = pregnancy.estimatedDueDate {
                drawBodyText(
                    format(
                        "Estimated due date: %@",
                        defaultValue: "Estimated due date: %@",
                        displayDate(dueDate)
                    ),
                    cursor: &cursor
                )
            }

            if let endDate = pregnancy.endDate {
                let days = Calendar.current.dateComponents([.day], from: pregnancy.startDate, to: endDate).day ?? 0
                let weeks = days / 7
                drawBodyText(
                    format(
                        "Duration: %@ weeks (%@ days)",
                        defaultValue: "Duration: %@ weeks (%@ days)",
                        integer(weeks),
                        integer(days)
                    ),
                    cursor: &cursor
                )
            }

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

    // MARK: - Localization

    private var locale: Locale {
        L10n.locale(for: appLanguage, preferredLanguages: preferredLanguages)
    }

    private func localized(_ key: String, defaultValue: String) -> String {
        L10n.string(
            key,
            defaultValue: defaultValue,
            language: appLanguage,
            preferredLanguages: preferredLanguages
        )
    }

    private func format(
        _ key: String,
        defaultValue: String,
        _ arguments: CVarArg...
    ) -> String {
        let format = L10n.string(
            key,
            defaultValue: defaultValue,
            language: appLanguage,
            preferredLanguages: preferredLanguages
        )

        return String(format: format, locale: locale, arguments: arguments)
    }

    private func decimal(_ value: Double, fractionDigits: Int = 1) -> String {
        L10n.decimal(
            value,
            fractionDigits: fractionDigits,
            language: appLanguage,
            preferredLanguages: preferredLanguages
        )
    }

    private func integer(_ value: Int) -> String {
        L10n.integer(
            value,
            language: appLanguage,
            preferredLanguages: preferredLanguages
        )
    }

    private func displayDate(_ date: Date) -> String {
        date.formatted(
            Date.FormatStyle(date: .abbreviated, time: .omitted)
                .locale(locale)
        )
    }

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
