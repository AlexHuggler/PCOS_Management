import Testing
import Foundation
@testable import PCOS

@Suite("Insight dashboard data")
@MainActor
struct InsightDashboardDataTests {
    private var utcCalendar: Calendar {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(identifier: "UTC")!
        return calendar
    }

    private func date(_ year: Int, _ month: Int, _ day: Int) -> Date {
        utcCalendar.date(from: DateComponents(year: year, month: month, day: day, hour: 12))!
    }

    private func insight(_ confidence: Double, on date: Date, symptoms: [String] = []) -> Insight {
        Insight(
            generatedDate: date,
            insightType: .cyclePattern,
            title: "title",
            content: "content",
            confidence: confidence,
            dataPointsUsed: 5,
            relatedSymptoms: symptoms
        )
    }

    @Test("Trend is nil below three real insights so no chart is drawn from placeholder values")
    func trendIsNilBelowThreshold() {
        let insights = [insight(0.5, on: date(2026, 1, 15)), insight(0.6, on: date(2026, 2, 15))]
        #expect(InsightDashboardTrend.make(from: insights, locale: Locale(identifier: "en_US"), calendar: utcCalendar) == nil)
        #expect(InsightDashboardTrend.remainingInsightCount(currentCount: 2) == 1)
        #expect(InsightDashboardTrend.remainingInsightCount(currentCount: 7) == 0)
    }

    @Test("Trend uses real confidences oldest to newest with month labels from generatedDate")
    func trendUsesRealValuesAndLabels() throws {
        let insights = [
            insight(0.9, on: date(2026, 3, 15)),
            insight(0.1, on: date(2026, 1, 15)),
            insight(0.99, on: date(2026, 2, 15)),
        ]
        let trend = try #require(InsightDashboardTrend.make(from: insights, locale: Locale(identifier: "en_US"), calendar: utcCalendar))
        #expect(trend.labels == ["Jan", "Feb", "Mar"])
        #expect(trend.values == [0.22, 0.96, 0.9])
    }

    @Test("Trend keeps only the six newest insights")
    func trendKeepsSixNewest() throws {
        let insights = (1...8).map { insight(Double($0) / 10, on: date(2026, $0, 10)) }
        let trend = try #require(InsightDashboardTrend.make(from: insights, locale: Locale(identifier: "en_US"), calendar: utcCalendar))
        #expect(trend.points.count == 6)
        #expect(trend.labels.first == "Mar")
        #expect(trend.labels.last == "Aug")
    }

    @Test("Patterns report the real share of insights naming each symptom, most frequent first, at most four")
    func patternsUseRealShares() {
        let insights = [
            insight(0.5, on: date(2026, 1, 1), symptoms: ["Fatigue", "Bloating"]),
            insight(0.5, on: date(2026, 1, 2), symptoms: ["Fatigue", " Cravings "]),
            insight(0.5, on: date(2026, 1, 3), symptoms: ["Fatigue", "Acne", "Headache", "Cramps"]),
            insight(0.5, on: date(2026, 1, 4), symptoms: ["Bloating", "Fatigue"]),
        ]
        let patterns = InsightDashboardPatterns.make(from: insights)
        #expect(patterns.count == 4)
        #expect(patterns.first == InsightDashboardPattern(name: "Fatigue", percent: 100))
        #expect(patterns[1] == InsightDashboardPattern(name: "Bloating", percent: 50))
        #expect(patterns[2].percent == 25)
        #expect(patterns.map(\.name).contains("Cravings"))
    }

    @Test("Patterns are empty when no insight names a symptom; no fabricated rows")
    func patternsEmptyWithoutSymptoms() {
        let insights = [insight(0.8, on: date(2026, 1, 1)), insight(0.7, on: date(2026, 1, 2))]
        #expect(InsightDashboardPatterns.make(from: insights).isEmpty)
        #expect(InsightDashboardPatterns.make(from: []).isEmpty)
    }

    @Test("Snapshot mood and energy read as not logged when nothing was logged")
    func snapshotTextDoesNotInventValues() {
        #expect(TodaySnapshotText.mood(hasMoodSymptomToday: false) == "Not logged")
        #expect(TodaySnapshotText.mood(hasMoodSymptomToday: true) == "Tender")
        #expect(TodaySnapshotText.energy(level: nil) == "Not logged")
        #expect(TodaySnapshotText.energy(level: 5) == "High")
        #expect(TodaySnapshotText.energy(level: 3) == "Medium")
        #expect(TodaySnapshotText.energy(level: 1) == "Low")
    }

    @Test("Insights dashboard and Today snapshot sources no longer contain placeholder data")
    func viewsDoNotContainPlaceholderData() throws {
        let projectRoot = try TestHelpers.projectRoot(from: #filePath)
        let insightsSource = try String(
            contentsOf: projectRoot.appendingPathComponent("PCOS/PCOS/Features/Insights/Views/InsightsView.swift"),
            encoding: .utf8
        )
        #expect(!insightsSource.contains("[0.46, 0.72"))
        #expect(!insightsSource.contains("[\"Feb\", \"Mar\""))
        #expect(!insightsSource.contains("max(28, 72"))
        #expect(!insightsSource.contains("[0.54, 0.62"))
        #expect(insightsSource.contains("InsightDashboardTrend.make("))
        #expect(insightsSource.contains("InsightDashboardPatterns.make("))

        let todaySource = try String(
            contentsOf: projectRoot.appendingPathComponent("PCOS/PCOS/Features/Cycle/Views/TodayView.swift"),
            encoding: .utf8
        )
        #expect(todaySource.contains("TodaySnapshotText.mood("))
        #expect(todaySource.contains("TodaySnapshotText.energy("))
        #expect(!todaySource.contains("return L10n.string(\"Calm\", defaultValue: \"Calm\")"))
    }
}
