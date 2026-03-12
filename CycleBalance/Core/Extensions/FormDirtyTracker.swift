import Foundation

struct FormDirtyTracker<Snapshot: Equatable> {
    private(set) var baseline: Snapshot

    init(initial: Snapshot) {
        baseline = initial
    }

    mutating func reset(to snapshot: Snapshot) {
        baseline = snapshot
    }

    func isDirty(current snapshot: Snapshot) -> Bool {
        snapshot != baseline
    }
}
