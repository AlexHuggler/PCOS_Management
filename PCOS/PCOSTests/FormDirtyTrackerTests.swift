import Testing
@testable import PCOS

@Suite("FormDirtyTracker")
struct FormDirtyTrackerTests {
    private struct Snapshot: Equatable {
        var value: String
        var count: Int
    }

    @Test("Tracker starts clean and marks changes as dirty")
    func dirtyTracking() {
        var tracker = FormDirtyTracker(initial: Snapshot(value: "A", count: 1))
        #expect(!tracker.isDirty(current: Snapshot(value: "A", count: 1)))
        #expect(tracker.isDirty(current: Snapshot(value: "B", count: 1)))

        tracker.reset(to: Snapshot(value: "B", count: 1))
        #expect(!tracker.isDirty(current: Snapshot(value: "B", count: 1)))
    }
}
