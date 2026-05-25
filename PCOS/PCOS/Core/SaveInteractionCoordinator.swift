import Foundation
import Observation
import UIKit
import os

enum SaveFeedbackEvent: String {
    case success
    case error
}

@MainActor
@Observable
final class SaveInteractionCoordinator {
    var isShowingSavedFeedback = false

    private let generator = UINotificationFeedbackGenerator()
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

    func showErrorFeedback() {
        emit(.error)
    }

    func emit(_ event: SaveFeedbackEvent) {
#if targetEnvironment(simulator)
        Logger.haptics.debug("Skipping haptic feedback on simulator for event \(event.rawValue, privacy: .public)")
        return
#else
        let feedbackType: UINotificationFeedbackGenerator.FeedbackType
        switch event {
        case .success:
            feedbackType = .success
        case .error:
            feedbackType = .error
        }

        generator.prepare()
        generator.notificationOccurred(feedbackType)
        Logger.haptics.debug("Dispatched haptic feedback event \(event.rawValue, privacy: .public)")
#endif
    }
}
