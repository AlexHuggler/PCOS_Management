import Testing
import Foundation

@Suite("Delayed Dismiss Safety")
struct TaskCancellationTests {
    @Test("Task cancellation prevents stale execution")
    func cancelledTaskDoesNotExecute() async {
        var didExecute = false
        let task = Task {
            try? await Task.sleep(for: .seconds(0.1))
            guard !Task.isCancelled else { return }
            didExecute = true
        }
        task.cancel()
        try? await Task.sleep(for: .seconds(0.2))
        #expect(!didExecute, "Cancelled task should not mutate state")
    }

    @Test("Non-cancelled task does execute")
    func nonCancelledTaskExecutes() async {
        var didExecute = false
        let task = Task {
            try? await Task.sleep(for: .seconds(0.05))
            guard !Task.isCancelled else { return }
            didExecute = true
        }
        _ = await task.result
        #expect(didExecute, "Non-cancelled task should complete normally")
    }
}
