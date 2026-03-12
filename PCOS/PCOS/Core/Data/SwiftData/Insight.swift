import Foundation
import SwiftData

@Model
final class Insight {
    var id: UUID = UUID()
    var generatedDate: Date = Date()
    var insightType: InsightType = InsightType.cyclePattern
    var title: String = ""
    var content: String = ""
    var confidence: Double = 0
    var dataPointsUsed: Int = 0
    var actionable: Bool = true
    var relatedSymptoms: [String] = []

    init(
        id: UUID = UUID(),
        generatedDate: Date = Date(),
        insightType: InsightType,
        title: String,
        content: String,
        confidence: Double,
        dataPointsUsed: Int,
        actionable: Bool = true,
        relatedSymptoms: [String] = []
    ) {
        self.id = id
        self.generatedDate = generatedDate
        self.insightType = insightType
        self.title = title
        self.content = content
        self.confidence = confidence
        self.dataPointsUsed = dataPointsUsed
        self.actionable = actionable
        self.relatedSymptoms = relatedSymptoms
    }
}
