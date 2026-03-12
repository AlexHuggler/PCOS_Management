import Testing
import Foundation

@Suite("Delayed Dismiss Safety")
struct TaskCancellationTests {
    private actor ExecutionFlag {
        private var didExecute = false

        func markExecuted() {
            didExecute = true
        }

        func value() -> Bool {
            didExecute
        }
    }

    @Test("Task cancellation prevents stale execution")
    func cancelledTaskDoesNotExecute() async {
        let flag = ExecutionFlag()
        let task = Task {
            try? await Task.sleep(for: .seconds(0.1))
            guard !Task.isCancelled else { return }
            await flag.markExecuted()
        }
        task.cancel()
        try? await Task.sleep(for: .seconds(0.2))
        let didExecute = await flag.value()
        #expect(!didExecute, "Cancelled task should not mutate state")
    }

    @Test("Non-cancelled task does execute")
    func nonCancelledTaskExecutes() async {
        let flag = ExecutionFlag()
        let task = Task {
            try? await Task.sleep(for: .seconds(0.05))
            guard !Task.isCancelled else { return }
            await flag.markExecuted()
        }
        _ = await task.result
        let didExecute = await flag.value()
        #expect(didExecute, "Non-cancelled task should complete normally")
    }
}
