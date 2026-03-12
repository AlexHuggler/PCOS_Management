import Foundation
import Observation
import UIKit

@MainActor
@Observable
final class SaveInteractionCoordinator {
    var isShowingSavedFeedback = false

    private var feedbackTask: Task<Void, Never>?

    func cancelPending() {
        feedbackTask?.cancel()
        feedbackTask = nil
    }

    func showSuccessAndDismiss(after seconds: TimeInterval = 0.8, dismiss: @escaping @MainActor () -> Void) {
        emit(.success)
        isShowingSavedFeedback = true
        cancelPending()
        feedbackTask = Task { [weak self] in
            try? await Task.sleep(nanoseconds: UInt64(seconds * 1_000_000_000))
            guard !Task.isCancelled else { return }
            dismiss()
            self?.isShowingSavedFeedback = false
        }
    }

    func showSuccessTransient(after seconds: TimeInterval = 0.8) {
        emit(.success)
        isShowingSavedFeedback = true
        cancelPending()
        feedbackTask = Task { [weak self] in
            try? await Task.sleep(nanoseconds: UInt64(seconds * 1_000_000_000))
            guard !Task.isCancelled else { return }
            self?.isShowingSavedFeedback = false
        }
    }

    func showErrorHaptic() {
        emit(.error)
    }

    private func emit(_ type: UINotificationFeedbackGenerator.FeedbackType) {
        let generator = UINotificationFeedbackGenerator()
        generator.notificationOccurred(type)
    }
}
