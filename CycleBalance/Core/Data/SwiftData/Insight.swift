import Foundation
import SwiftData

@Model
final class Insight {
    var id: UUID
    var generatedDate: Date
    var insightType: InsightType
    var title: String
    var body: String
    var confidence: Double
    var dataPointsUsed: Int
    var actionable: Bool
    var relatedSymptoms: [String]

    init(
        id: UUID = UUID(),
        generatedDate: Date = Date(),
        insightType: InsightType,
        title: String,
        body: String,
        confidence: Double,
        dataPointsUsed: Int,
        actionable: Bool = true,
        relatedSymptoms: [String] = []
    ) {
        self.id = id
        self.generatedDate = generatedDate
        self.insightType = insightType
        self.title = title
        self.body = body
        self.confidence = confidence
        self.dataPointsUsed = dataPointsUsed
        self.actionable = actionable
        self.relatedSymptoms = relatedSymptoms
    }
}
