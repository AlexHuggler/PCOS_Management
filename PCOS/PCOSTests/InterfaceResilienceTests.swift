import Testing
import Foundation
@testable import PCOS

#if canImport(PCOS)
private let paywallSourceRelativePath = "../PCOS/Core/StoreKit/PaywallView.swift"
private let calendarSourceRelativePath = "../PCOS/Features/Cycle/Views/CalendarMonthView.swift"
private let supplementHistorySourceRelativePath = "../PCOS/Features/Supplements/Views/SupplementHistoryView.swift"
private let bloodSugarHistorySourceRelativePath = "../PCOS/Features/BloodSugar/Views/BloodSugarHistoryView.swift"
#else
private let paywallSourceRelativePath = "../CycleBalance/Core/StoreKit/PaywallView.swift"
private let calendarSourceRelativePath = "../CycleBalance/Features/Cycle/Views/CalendarMonthView.swift"
private let supplementHistorySourceRelativePath = "../CycleBalance/Features/Supplements/Views/SupplementHistoryView.swift"
private let bloodSugarHistorySourceRelativePath = "../CycleBalance/Features/BloodSugar/Views/BloodSugarHistoryView.swift"
#endif

@Suite("Interface Resilience", .serialized)
struct InterfaceResilienceTests {
    private func loadSource(relativePath: String) throws -> String {
        let testFileURL = URL(fileURLWithPath: #filePath)
        let sourceURL = testFileURL
            .deletingLastPathComponent()
            .appendingPathComponent(relativePath)
            .standardizedFileURL
        return try String(contentsOf: sourceURL, encoding: .utf8)
    }

    @Test("PaywallView uses adaptive typography and column widths")
    func paywallViewUsesAdaptiveLayoutPrimitives() throws {
        let source = try loadSource(relativePath: paywallSourceRelativePath)

        #expect(source.contains("@ScaledMetric(relativeTo: .largeTitle)"))
        #expect(source.contains(".font(.system(size: heroSymbolSize))"))
        #expect(!source.contains(".font(.system(size: 48))"))

        #expect(source.contains("@ScaledMetric(relativeTo: .caption) private var freeColumnWidth"))
        #expect(source.contains("@ScaledMetric(relativeTo: .caption) private var premiumColumnWidth"))
        #expect(source.contains(".frame(minWidth: freeColumnWidth * 0.8, idealWidth: freeColumnWidth, alignment: .center)"))
        #expect(source.contains(".frame(minWidth: premiumColumnWidth * 0.8, idealWidth: premiumColumnWidth, alignment: .center)"))
        #expect(!source.contains(".frame(width: 50)"))
        #expect(!source.contains(".frame(width: 70)"))

        #expect(source.contains(".lineLimit(1)"))
        #expect(source.contains(".minimumScaleFactor(0.8)"))
    }

    @Test("Calendar day cell avoids fixed micro-font and rigid height")
    func calendarDayCellUsesAdaptiveTextAndHeight() throws {
        let source = try loadSource(relativePath: calendarSourceRelativePath)

        #expect(!source.contains(".font(.system(size: 7, weight: .bold))"))
        #expect(source.contains(".font(.caption2)"))
        #expect(source.contains(".minimumScaleFactor(0.75)"))
        #expect(source.contains(".frame(minHeight: 44)"))
        #expect(!source.contains(".frame(height: 44)"))
    }

    @Test("Supplement history ring uses scaled metric sizing without fixed 120x120 frames")
    func supplementHistoryRingUsesAdaptiveSizing() throws {
        let source = try loadSource(relativePath: supplementHistorySourceRelativePath)

        #expect(source.contains("@ScaledMetric(relativeTo: .title2) private var adherenceRingDiameter"))
        #expect(source.contains("private var clampedAdherenceRingDiameter: CGFloat"))
        #expect(source.contains(".frame(width: clampedAdherenceRingDiameter, height: clampedAdherenceRingDiameter)"))
        #expect(!source.contains(".frame(width: 120, height: 120)"))
    }

    @Test("Blood sugar time column uses adaptive single-line width")
    func bloodSugarTimeColumnUsesAdaptiveSingleLineWidth() throws {
        let source = try loadSource(relativePath: bloodSugarHistorySourceRelativePath)

        #expect(source.contains("@ScaledMetric(relativeTo: .subheadline) private var timeColumnIdealWidth: CGFloat"))
        #expect(source.contains(".frame(minWidth: timeColumnIdealWidth * 0.8, idealWidth: timeColumnIdealWidth, alignment: .leading)"))
        #expect(source.contains(".lineLimit(1)"))
        #expect(source.contains(".minimumScaleFactor(0.8)"))
        #expect(!source.contains(".frame(width: 70, alignment: .leading)"))
    }
}
