import Foundation

/// One plotted point of the Insights trend chart: a real insight confidence and the month it was generated.
struct InsightDashboardTrendPoint: Equatable, Sendable {
    let value: Double
    let label: String
}

/// Real-data-only model behind the Insights dashboard trend chart.
struct InsightDashboardTrend: Equatable, Sendable {
    static let minimumInsightCount = 3
    static let maximumPointCount = 6

    let points: [InsightDashboardTrendPoint]

    var values: [Double] { points.map(\.value) }
    var labels: [String] { points.map(\.label) }

    /// Builds the trend from real insights only. Returns nil below `minimumInsightCount` so the
    /// view shows an honest placeholder instead of a chart drawn from invented values.
    static func make(from insights: [Insight], locale: Locale, calendar: Calendar = .current) -> InsightDashboardTrend? {
        guard insights.count >= minimumInsightCount else { return nil }

        let formatter = DateFormatter()
        formatter.locale = locale
        formatter.calendar = calendar
        formatter.timeZone = calendar.timeZone
        formatter.setLocalizedDateFormatFromTemplate("MMM")

        let ordered = insights
            .sorted { $0.generatedDate < $1.generatedDate }
            .suffix(maximumPointCount)

        let points = ordered.map { insight in
            InsightDashboardTrendPoint(
                value: min(max(insight.confidence, 0.22), 0.96),
                label: formatter.string(from: insight.generatedDate)
            )
        }
        return InsightDashboardTrend(points: points)
    }

    static func remainingInsightCount(currentCount: Int) -> Int {
        max(0, minimumInsightCount - currentCount)
    }
}

struct InsightDashboardPattern: Equatable, Identifiable, Sendable {
    let name: String
    /// Share (0...100) of current insights that reference this symptom.
    let percent: Int

    var id: String { name }
}

enum InsightDashboardPatterns {
    static let maximumRowCount = 4

    /// Real share of the current insights that name each symptom, most frequent first.
    /// Returns an empty array (never placeholder rows) when no insight names a symptom.
    static func make(from insights: [Insight]) -> [InsightDashboardPattern] {
        guard !insights.isEmpty else { return [] }

        var counts: [String: Int] = [:]
        var firstSeenOrder: [String] = []
        for insight in insights {
            var seenInInsight = Set<String>()
            for rawName in insight.relatedSymptoms {
                let name = rawName.trimmingCharacters(in: .whitespacesAndNewlines)
                guard !name.isEmpty, seenInInsight.insert(name).inserted else { continue }
                if counts[name] == nil {
                    firstSeenOrder.append(name)
                }
                counts[name, default: 0] += 1
            }
        }

        let total = Double(insights.count)
        return firstSeenOrder
            .map { name in
                InsightDashboardPattern(
                    name: name,
                    percent: Int((Double(counts[name] ?? 0) / total * 100).rounded())
                )
            }
            .sorted { lhs, rhs in
                if lhs.percent != rhs.percent {
                    return lhs.percent > rhs.percent
                }
                return (firstSeenOrder.firstIndex(of: lhs.name) ?? 0) < (firstSeenOrder.firstIndex(of: rhs.name) ?? 0)
            }
            .prefix(maximumRowCount)
            .map { $0 }
    }
}
