import Foundation
import SwiftUI
import AVFoundation
import os

enum OnboardingPermissionStatus: Equatable {
    case notDetermined
    case granted
    case denied
}

enum OnboardingPermissionAction: Equatable {
    case requestCamera
    case requestHealthKit
    case continueOnboarding
}

enum OnboardingPermissionRequestPhase: Equatable {
    case idle
    case requestingCamera
    case waitingForSceneActive
    case requestingHealthKit

    var isInteractionDisabled: Bool {
        self != .idle
    }
}

struct OnboardingPermissionFlowState: Equatable {
    var cameraStatus: OnboardingPermissionStatus = .notDetermined
    var healthKitStatus: OnboardingPermissionStatus = .notDetermined
    var queuedHealthKitRequest = false
    var requestPhase: OnboardingPermissionRequestPhase = .idle

    var allResolved: Bool {
        cameraStatus != .notDetermined && healthKitStatus != .notDetermined
    }

    var isInteractionDisabled: Bool {
        requestPhase.isInteractionDisabled
    }

    mutating func nextPrimaryAction() -> OnboardingPermissionAction {
        if allResolved {
            return .continueOnboarding
        }

        if cameraStatus == .notDetermined {
            queuedHealthKitRequest = healthKitStatus == .notDetermined
            return .requestCamera
        }

        if healthKitStatus == .notDetermined {
            return .requestHealthKit
        }

        return .continueOnboarding
    }

    mutating func nextCardAction(for action: OnboardingPermissionAction) -> OnboardingPermissionAction? {
        switch action {
        case .requestCamera:
            return cameraStatus == .notDetermined ? .requestCamera : nil
        case .requestHealthKit:
            queuedHealthKitRequest = false
            return healthKitStatus == .notDetermined ? .requestHealthKit : nil
        case .continueOnboarding:
            return allResolved ? .continueOnboarding : nil
        }
    }

    mutating func beginRequest(_ action: OnboardingPermissionAction) -> Bool {
        guard requestPhase == .idle else { return false }

        switch action {
        case .requestCamera:
            guard cameraStatus == .notDetermined else { return false }
            requestPhase = .requestingCamera
            return true
        case .requestHealthKit:
            guard healthKitStatus == .notDetermined else { return false }
            queuedHealthKitRequest = false
            requestPhase = .requestingHealthKit
            return true
        case .continueOnboarding:
            return allResolved
        }
    }

    mutating func nextQueuedSceneActiveAction() -> OnboardingPermissionAction? {
        guard
            requestPhase == .waitingForSceneActive,
            queuedHealthKitRequest,
            healthKitStatus == .notDetermined
        else { return nil }
        queuedHealthKitRequest = false
        requestPhase = .requestingHealthKit
        return .requestHealthKit
    }

    mutating func markHealthKitRecoverableFailure() {
        healthKitStatus = .notDetermined
        queuedHealthKitRequest = false
        requestPhase = .idle
    }

    mutating func markCameraStatus(_ status: OnboardingPermissionStatus) {
        cameraStatus = status

        if queuedHealthKitRequest, healthKitStatus == .notDetermined {
            requestPhase = .waitingForSceneActive
        } else if requestPhase == .requestingCamera {
            requestPhase = .idle
        }
    }

    mutating func markHealthKitStatus(_ status: OnboardingPermissionStatus) {
        healthKitStatus = status
        if status != .notDetermined {
            queuedHealthKitRequest = false
        }

        if requestPhase == .requestingHealthKit
            || (requestPhase == .waitingForSceneActive && status != .notDetermined) {
            requestPhase = .idle
        }
    }
}

/// Pre-permission step in onboarding that explains why the app needs camera
/// and HealthKit access, then requests them with a single tap.
struct PermissionsStepView: View {
    @Environment(\.scenePhase) private var scenePhase

    let onContinue: () -> Void
    let onSkip: () -> Void

    @State private var permissionState = OnboardingPermissionFlowState()
    @State private var healthKitManager = HealthKitManager()
    @State private var healthKitErrorMessage: String?
    @State private var queuedHealthKitWaitStartedAt: Date?

    @ScaledMetric(relativeTo: .largeTitle) private var iconSize: CGFloat = 48

    private var allResolved: Bool {
        permissionState.allResolved
    }

    private var primaryButtonTitle: String {
        switch permissionState.requestPhase {
        case .idle:
            return L10n.string(
                allResolved ? "Continue" : "Allow Permissions",
                defaultValue: allResolved ? "Continue" : "Allow Permissions"
            )
        case .requestingCamera:
            return L10n.string("Requesting Camera...", defaultValue: "Requesting Camera...")
        case .waitingForSceneActive, .requestingHealthKit:
            return L10n.string("Opening Apple Health...", defaultValue: "Opening Apple Health...")
        }
    }

    var body: some View {
        VStack(spacing: AppTheme.spacing24) {
            Spacer()

            Image(systemName: "lock.shield")
                .font(.system(size: iconSize))
                .foregroundStyle(AppTheme.accentColor)
                .accessibilityHidden(true)

            VStack(spacing: AppTheme.spacing12) {
                Text(L10n.string("Help CycleBalance work better", defaultValue: "Help CycleBalance work better"))
                    .appHeadingFont(.title2, weight: .regular)
                    .foregroundStyle(AppTheme.primaryText)
                    .multilineTextAlignment(.center)

                Text(
                    L10n.string(
                        "These permissions are optional. You can change them anytime in Settings.",
                        defaultValue: "These permissions are optional. You can change them anytime in Settings."
                    )
                )
                .appFont(.body)
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)
            }
            .padding(.horizontal, AppTheme.spacing24)

            HStack(spacing: AppTheme.spacing8) {
                Image(systemName: "lock.shield.fill")
                    .appFont(.caption)
                    .foregroundStyle(AppTheme.accentColor)
                Text(
                    L10n.string(
                        "Your data stays on your device. No accounts, no servers, no exceptions.",
                        defaultValue: "Your data stays on your device. No accounts, no servers, no exceptions."
                    )
                )
                .appFont(.caption)
                .foregroundStyle(.secondary)
            }
            .padding(.horizontal, AppTheme.spacing24)

            VStack(spacing: AppTheme.spacing12) {
                permissionCard(
                    icon: "camera.fill",
                    title: L10n.string("Camera", defaultValue: "Camera"),
                    description: L10n.string(
                        "Take photos for your hair & skin journal to track changes over time.",
                        defaultValue: "Take photos for your hair & skin journal to track changes over time."
                    ),
                    benefit: L10n.string(
                        "See skin and hair changes side by side over months.",
                        defaultValue: "See skin and hair changes side by side over months."
                    ),
                    status: permissionState.cameraStatus,
                    action: .requestCamera
                )

                permissionCard(
                    icon: "heart.fill",
                    title: L10n.string("Apple Health", defaultValue: "Apple Health"),
                    description: L10n.string(
                        "Sync weight, sleep, steps, blood glucose, activity, and heart rate for richer insights.",
                        defaultValue: "Sync weight, sleep, steps, blood glucose, activity, and heart rate for richer insights."
                    ),
                    benefit: L10n.string(
                        "Get deeper insights when health data is connected.",
                        defaultValue: "Get deeper insights when health data is connected."
                    ),
                    status: permissionState.healthKitStatus,
                    action: .requestHealthKit
                )
            }
            .padding(.horizontal, AppTheme.spacing24)

            if let healthKitErrorMessage {
                healthKitRecoveryNotice(message: healthKitErrorMessage)
                    .padding(.horizontal, AppTheme.spacing24)
            }

            Spacer()

            VStack(spacing: AppTheme.spacing12) {
                Button(action: handlePrimaryButtonTap) {
                    HStack(spacing: AppTheme.spacing8) {
                        if permissionState.isInteractionDisabled {
                            ProgressView()
                                .controlSize(.small)
                                .tint(.white)
                        }

                        Text(primaryButtonTitle)
                            .appFont(.headline)
                    }
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, AppTheme.spacing12)
                    .background(
                        RoundedRectangle(cornerRadius: AppTheme.cornerRadiusMedium)
                            .fill(
                                permissionState.isInteractionDisabled
                                    ? AppTheme.accentColor.opacity(0.85)
                                    : AppTheme.accentColor
                            )
                    )
                    .foregroundStyle(.white)
                }
                .buttonStyle(.plain)
                .disabled(permissionState.isInteractionDisabled)
                .accessibilityIdentifier("onboarding.permissions.allow")

                Button(action: onSkip) {
                    Text(L10n.string("Skip for now", defaultValue: "Skip for now"))
                }
                .appFont(.subheadline)
                .foregroundStyle(.secondary)
                .disabled(permissionState.isInteractionDisabled)
                .accessibilityHint(
                    Text(
                        L10n.string(
                            "Skip permissions and continue setup",
                            defaultValue: "Skip permissions and continue setup"
                        )
                    )
                )
                .accessibilityIdentifier("onboarding.permissions.skip")
            }
            .padding(.horizontal, AppTheme.spacing24)
            .padding(.bottom, AppTheme.spacing32)
        }
        .background(BotanicalScreenBackground(style: .dense))
        .accessibilityElement(children: .contain)
        .accessibilityIdentifier("screen.onboarding.permissions")
        .task {
            await refreshPermissionState()
        }
        .onChange(of: scenePhase) { _, newPhase in
            guard newPhase == .active else { return }
            Task {
                await handleSceneDidBecomeActive()
            }
        }
    }

    // MARK: - Permission Card

    private func permissionCard(
        icon: String,
        title: String,
        description: String,
        benefit: String,
        status: OnboardingPermissionStatus,
        action: OnboardingPermissionAction
    ) -> some View {
        let isRequestingThisAction = isRequestInFlight(for: action)

        return HStack(spacing: AppTheme.spacing16) {
            Image(systemName: icon)
                .appFont(.title2)
                .foregroundStyle(status == .granted ? AppTheme.accentColor : .secondary)
                .frame(width: 44)

            VStack(alignment: .leading, spacing: AppTheme.spacing4) {
                Text(title)
                    .appFont(.body, weight: .semibold)
                Text(description)
                    .appFont(.caption)
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
                Text(benefit)
                    .appFont(.caption2)
                    .foregroundStyle(.tertiary)
                    .fixedSize(horizontal: false, vertical: true)
            }

            Spacer()

            Group {
                if isRequestingThisAction {
                    ProgressView()
                        .controlSize(.small)
                        .tint(AppTheme.accentColor)
                } else {
                    switch status {
                    case .granted:
                        Image(systemName: "checkmark.circle.fill")
                            .foregroundStyle(AppTheme.accentColor)
                    case .denied:
                        Image(systemName: "xmark.circle.fill")
                            .foregroundStyle(.secondary)
                    case .notDetermined:
                        Image(systemName: "circle")
                            .foregroundStyle(.tertiary)
                    }
                }
            }
            .transition(.scale.combined(with: .opacity))
        }
        .padding(AppTheme.spacing16)
        .background(
            RoundedRectangle(cornerRadius: AppTheme.cornerRadiusMedium)
                .fill(cardBackground(for: status, isRequesting: isRequestingThisAction))
        )
        .overlay(
            RoundedRectangle(cornerRadius: AppTheme.cornerRadiusMedium)
                .strokeBorder(
                    cardBorderColor(for: status, isRequesting: isRequestingThisAction),
                    lineWidth: 1.5
                )
        )
        .contentShape(Rectangle())
        .opacity(permissionState.isInteractionDisabled && !isRequestingThisAction ? 0.72 : 1)
        .allowsHitTesting(!permissionState.isInteractionDisabled)
        .onTapGesture {
            guard let nextAction = permissionState.nextCardAction(for: action) else { return }
            Task {
                await perform(nextAction, source: "card")
            }
        }
        .animation(.easeInOut(duration: 0.2), value: status)
        .animation(.easeInOut(duration: 0.2), value: permissionState.requestPhase)
        .sensoryFeedback(.selection, trigger: status)
    }

    private func healthKitRecoveryNotice(message: String) -> some View {
        VStack(alignment: .leading, spacing: AppTheme.spacing8) {
            Label(
                L10n.string(
                    "Apple Health needs another try",
                    defaultValue: "Apple Health needs another try"
                ),
                systemImage: "exclamationmark.triangle.fill"
            )
            .appFont(.subheadline, weight: .semibold)
            .foregroundStyle(AppTheme.coralAccent)

            Text(message)
                .appFont(.caption)
                .foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)

            Button {
                Task {
                    await perform(.requestHealthKit, source: "retry")
                }
            } label: {
                Text(
                    L10n.string(
                        "Try Apple Health Again",
                        defaultValue: "Try Apple Health Again"
                    )
                )
                .appFont(.caption, weight: .semibold)
            }
            .buttonStyle(.plain)
            .foregroundStyle(AppTheme.accentColor)
            .disabled(permissionState.isInteractionDisabled)
        }
        .padding(AppTheme.spacing16)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(
            RoundedRectangle(cornerRadius: AppTheme.cornerRadiusMedium)
                .fill(AppTheme.cardBackground)
        )
        .overlay(
            RoundedRectangle(cornerRadius: AppTheme.cornerRadiusMedium)
                .stroke(Color.primary.opacity(0.06), lineWidth: 1)
        )
    }

    // MARK: - Actions

    private func handlePrimaryButtonTap() {
        guard !permissionState.isInteractionDisabled else { return }
        let action = permissionState.nextPrimaryAction()
        Task {
            await perform(action, source: "primary")
        }
    }

    private func perform(_ action: OnboardingPermissionAction, source: String) async {
        switch action {
        case .requestCamera:
            guard permissionState.beginRequest(.requestCamera) else { return }
            await requestCamera(source: source)
        case .requestHealthKit:
            guard permissionState.beginRequest(.requestHealthKit) else { return }
            await requestHealthKit(source: source)
        case .continueOnboarding:
            guard !permissionState.isInteractionDisabled else { return }
            onContinue()
        }
    }

    private func handleSceneDidBecomeActive() async {
        let wasWaitingForQueuedHealthKit = permissionState.requestPhase == .waitingForSceneActive
        await refreshPermissionState()

        guard wasWaitingForQueuedHealthKit else { return }
        guard let queuedAction = permissionState.nextQueuedSceneActiveAction() else {
            queuedHealthKitWaitStartedAt = nil
            Logger.onboarding.info("Queued onboarding HealthKit request resolved without another prompt after scene activation.")
            return
        }

        let waitDuration = queuedHealthKitWaitStartedAt.map { elapsedTimeString(since: $0) } ?? "0.00"
        queuedHealthKitWaitStartedAt = nil
        Logger.onboarding.info(
            "Processing queued onboarding HealthKit request after scene activation. wait=\(waitDuration, privacy: .public)s"
        )
        await perform(queuedAction, source: "sceneActive")
    }

    private func refreshPermissionState() async {
        refreshCameraStatus()

        let authorizationState = await healthKitManager.refreshAuthorizationState()
        syncHealthKitStatus(with: authorizationState, treatNeedsAuthorizationAsDenied: false)
    }

    private func requestCamera(source: String) async {
        let requestStartedAt = Date()
        Logger.onboarding.info("Requesting onboarding camera permission via \(source, privacy: .public).")
        healthKitErrorMessage = nil

        let granted = await AVCaptureDevice.requestAccess(for: .video)
        withAnimation {
            permissionState.markCameraStatus(granted ? .granted : .denied)
        }

        if permissionState.requestPhase == .waitingForSceneActive {
            queuedHealthKitWaitStartedAt = Date()
            Logger.onboarding.info("Queued onboarding HealthKit request after camera permission. Awaiting the next active scene cycle.")
        } else {
            queuedHealthKitWaitStartedAt = nil
        }

        Logger.onboarding.info(
            "Onboarding camera permission completed after \(elapsedTimeString(since: requestStartedAt), privacy: .public)s with status \(statusLogValue(permissionState.cameraStatus), privacy: .public)"
        )
    }

    private func requestHealthKit(source: String) async {
        let requestStartedAt = Date()
        Logger.onboarding.info("Requesting onboarding HealthKit permission via \(source, privacy: .public).")
        healthKitErrorMessage = nil
        queuedHealthKitWaitStartedAt = nil

        do {
            let authorizationState = try await healthKitManager.requestAuthorization()
            syncHealthKitStatus(with: authorizationState, treatNeedsAuthorizationAsDenied: true)
            Logger.onboarding.info(
                "Onboarding HealthKit authorization finished after \(elapsedTimeString(since: requestStartedAt), privacy: .public)s with status \(statusLogValue(permissionState.healthKitStatus), privacy: .public)"
            )
        } catch {
            Logger.onboarding.error(
                "Onboarding HealthKit authorization failed after \(elapsedTimeString(since: requestStartedAt), privacy: .public)s: \(error.localizedDescription, privacy: .public)"
            )
            permissionState.markHealthKitRecoverableFailure()
            healthKitErrorMessage = L10n.string(
                "Apple Health authorization timed out or did not finish. You can try again now or skip and connect later in Settings.",
                defaultValue: "Apple Health authorization timed out or did not finish. You can try again now or skip and connect later in Settings."
            )
        }
    }

    private func syncHealthKitStatus(
        with authorizationState: HealthKitManager.AuthorizationState,
        treatNeedsAuthorizationAsDenied: Bool
    ) {
        let nextStatus: OnboardingPermissionStatus
        switch authorizationState {
        case .configured:
            nextStatus = .granted
        case .needsAuthorization:
            if treatNeedsAuthorizationAsDenied || permissionState.healthKitStatus == .denied {
                nextStatus = .denied
            } else {
                nextStatus = .notDetermined
            }
        case .unavailable:
            nextStatus = .denied
        }

        withAnimation {
            permissionState.markHealthKitStatus(nextStatus)
        }

        if nextStatus != .notDetermined {
            healthKitErrorMessage = nil
        }
    }

    private func refreshCameraStatus() {
        switch AVCaptureDevice.authorizationStatus(for: .video) {
        case .authorized:
            permissionState.cameraStatus = .granted
        case .denied, .restricted:
            permissionState.cameraStatus = .denied
        default:
            permissionState.cameraStatus = .notDetermined
        }
    }

    private func isRequestInFlight(for action: OnboardingPermissionAction) -> Bool {
        switch (permissionState.requestPhase, action) {
        case (.requestingCamera, .requestCamera):
            return true
        case (.waitingForSceneActive, .requestHealthKit), (.requestingHealthKit, .requestHealthKit):
            return true
        default:
            return false
        }
    }

    private func cardBackground(
        for status: OnboardingPermissionStatus,
        isRequesting: Bool
    ) -> Color {
        if isRequesting {
            return AppTheme.accentColor.opacity(AppTheme.opacitySubtle)
        }

        if status == .granted {
            return AppTheme.accentColor.opacity(AppTheme.opacitySubtle)
        }

        return AppTheme.cardBackground
    }

    private func cardBorderColor(
        for status: OnboardingPermissionStatus,
        isRequesting: Bool
    ) -> Color {
        if isRequesting || status == .granted {
            return AppTheme.accentColor.opacity(0.4)
        }

        return Color.clear
    }

    private func elapsedTimeString(since startDate: Date) -> String {
        String(format: "%.2f", Date().timeIntervalSince(startDate))
    }

    private func statusLogValue(_ status: OnboardingPermissionStatus) -> String {
        switch status {
        case .notDetermined:
            return "notDetermined"
        case .granted:
            return "granted"
        case .denied:
            return "denied"
        }
    }
}

#Preview {
    PermissionsStepView(onContinue: {}, onSkip: {})
}
