import Foundation
import SwiftData

@Model
final class Insight {
    #if swift(>=6.0)
    @available(iOS 18, *)
    #Index<Insight>([\.generatedDate])
    #endif

    var id: UUID = UUID()
    var generatedDate: Date = Date()
    var insightType: InsightType = InsightType.cyclePattern
    var title: String = ""
    var content: String = ""
    var scientificContent: String?
    var confidence: Double = 0
    var dataPointsUsed: Int = 0
    var actionable: Bool = true
    var relatedSymptoms: [String] = []
    var phaseContext: CyclePhase?
    var recommendedActions: [String] = []
    var learnMoreTopic: String?

    init(
        id: UUID = UUID(),
        generatedDate: Date = Date(),
        insightType: InsightType,
        title: String,
        content: String,
        scientificContent: String? = nil,
        confidence: Double,
        dataPointsUsed: Int,
        actionable: Bool = true,
        relatedSymptoms: [String] = [],
        phaseContext: CyclePhase? = nil,
        recommendedActions: [String] = [],
        learnMoreTopic: String? = nil
    ) {
        self.id = id
        self.generatedDate = generatedDate
        self.insightType = insightType
        self.title = title
        self.content = content
        self.scientificContent = scientificContent
        self.confidence = confidence
        self.dataPointsUsed = dataPointsUsed
        self.actionable = actionable
        self.relatedSymptoms = relatedSymptoms
        self.phaseContext = phaseContext
        self.recommendedActions = recommendedActions
        self.learnMoreTopic = learnMoreTopic
    }
}
