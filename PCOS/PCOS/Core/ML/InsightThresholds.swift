import Foundation

/// Single source of truth for the data thresholds that unlock insights. Shared by the analyzers
/// and by every piece of copy that promises when a pattern will appear, so they cannot drift.
enum InsightThresholds {
    /// Completed (non-predicted) cycles needed before cycle-pattern insights are generated.
    static let completedCyclesForCyclePatterns = 3
    /// Distinct days with symptom logs needed before symptom-correlation insights are generated.
    static let trackedSymptomDaysForCorrelations = 14
}
