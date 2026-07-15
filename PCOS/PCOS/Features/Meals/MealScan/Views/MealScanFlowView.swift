import SwiftUI
import SwiftData
import PhotosUI
import AVFoundation
import UIKit

struct MealScanFlowView: View {
    @Environment(\.modelContext) private var modelContext
    @Environment(\.dismiss) private var dismiss
    let mealType: MealType
    var onChooseBarcode: (() -> Void)?
    var onChooseManual: (() -> Void)?

    @State private var viewModel: MealScanViewModel?

    init(
        mealType: MealType,
        onChooseBarcode: (() -> Void)? = nil,
        onChooseManual: (() -> Void)? = nil
    ) {
        self.mealType = mealType
        self.onChooseBarcode = onChooseBarcode
        self.onChooseManual = onChooseManual
    }

    var body: some View {
        NavigationStack {
            if let viewModel {
                MealScanPhaseShell(
                    title: viewModel.phase.localizedTitle,
                    closeLabel: viewModel.phase == .saved
                        ? L10n.string("Done", defaultValue: "Done")
                        : L10n.string("Close", defaultValue: "Close"),
                    onClose: { dismiss() }
                ) {
                    phaseContent(for: viewModel)
                }
            } else {
                MealScanPhaseShell(
                    title: L10n.string("Photo estimate", defaultValue: "Photo estimate"),
                    closeLabel: L10n.string("Close", defaultValue: "Close"),
                    onClose: { dismiss() }
                ) {
                    LunarMealScanLoadingView()
                }
            }
        }
        .toolbar(.hidden, for: .navigationBar)
        .onAppear {
            if viewModel == nil {
                viewModel = MealScanViewModel(mealType: mealType, modelContext: modelContext)
            }
        }
        .accessibilityIdentifier("screen.meal_scan")
    }

    @ViewBuilder
    private func phaseContent(for viewModel: MealScanViewModel) -> some View {
        switch viewModel.phase {
        case .entry:
            MealScanEntryView(viewModel: viewModel, onChooseManual: chooseManual)
        case .camera:
            MealCameraView(
                viewModel: viewModel,
                onChooseBarcode: chooseBarcode,
                onChooseManual: chooseManual
            )
        case .processing:
            MealScanProcessingView(viewModel: viewModel)
        case .repeatSuggestion:
            if let suggestion = viewModel.repeatMealSuggestion {
                RepeatMealSuggestionView(
                    suggestion: suggestion,
                    onUsePrevious: { viewModel.usePreviousMeal() },
                    onScanAsNew: {
                        Task {
                            do {
                                try await viewModel.scanPendingImageAsNew()
                            } catch {
                                viewModel.errorMessage = L10n.string(
                                    "No food was confidently detected. You can retake the photo or add the meal manually.",
                                    defaultValue: "No food was confidently detected. You can retake the photo or add the meal manually."
                                )
                                viewModel.phase = .manualFallback
                            }
                        }
                    }
                )
            } else {
                MealScanProcessingView(viewModel: viewModel)
            }
        case .remoteConsent:
            MealScanRemoteConsentView(viewModel: viewModel, onChooseManual: chooseManual)
        case .ambiguousOutcome:
            MealScanAmbiguousOutcomeView(
                viewModel: viewModel,
                onChooseBarcode: chooseBarcode,
                onChooseManual: chooseManual
            )
        case .newAttemptConfirmation:
            MealScanNewAttemptConfirmationView(
                viewModel: viewModel,
                onChooseBarcode: chooseBarcode,
                onChooseManual: chooseManual
            )
        case .review:
            MealScanReviewView(viewModel: viewModel)
        case .manualFallback:
            MealScanManualFallbackView(
                viewModel: viewModel,
                onChooseBarcode: chooseBarcode,
                onChooseManual: chooseManual
            )
        case .saved:
            MealScanSavedView(viewModel: viewModel)
        }
    }
    private func chooseBarcode() {
        onChooseBarcode?()
        dismiss()
    }

    private func chooseManual() {
        onChooseManual?()
        dismiss()
    }

}

private extension MealScanViewModel.Phase {
    var localizedTitle: String {
        switch self {
        case .entry:
            L10n.string("Photo estimate", defaultValue: "Photo estimate")
        case .camera:
            L10n.string("Meal photo", defaultValue: "Meal photo")
        case .processing:
            L10n.string("Preparing photo", defaultValue: "Preparing photo")
        case .repeatSuggestion:
            L10n.string("Looks familiar", defaultValue: "Looks familiar")
        case .remoteConsent:
            L10n.string("Review photo privacy", defaultValue: "Review photo privacy")
        case .ambiguousOutcome:
            L10n.string("Analysis status unknown", defaultValue: "Analysis status unknown")
        case .newAttemptConfirmation:
            L10n.string("Start a separate analysis?", defaultValue: "Start a separate analysis?")
        case .review:
            L10n.string("Review your estimate", defaultValue: "Review your estimate")
        case .manualFallback:
            L10n.string("Photo analysis unavailable", defaultValue: "Photo analysis unavailable")
        case .saved:
            L10n.string("Meal saved", defaultValue: "Meal saved")
        }
    }
}

struct MealScanPhaseShell<Content: View>: View {
    let title: String
    let closeLabel: String?
    let onClose: (() -> Void)?
    @ViewBuilder let content: Content
    @AccessibilityFocusState private var isHeadingFocused: Bool

    init(
        title: String,
        closeLabel: String? = nil,
        onClose: (() -> Void)? = nil,
        @ViewBuilder content: () -> Content
    ) {
        self.title = title
        self.closeLabel = closeLabel
        self.onClose = onClose
        self.content = content()
    }

    var body: some View {
        ZStack {
            BotanicalScreenBackground(style: AppTheme.usesPremiumEditorStyling ? .quiet : .dashboard)

            VStack(spacing: 0) {
                HStack(spacing: AppTheme.spacing12) {
                    Text(title)
                        .appHeadingFont(.title3, weight: .regular)
                        .foregroundStyle(AppTheme.primaryText)
                        .fixedSize(horizontal: false, vertical: true)
                        .accessibilityAddTraits(.isHeader)
                        .accessibilityHeading(.h1)
                        .accessibilityFocused($isHeadingFocused)
                        .accessibilityIdentifier("meal_scan.phase.title")

                    Spacer(minLength: AppTheme.spacing8)

                    if let closeLabel, let onClose {
                        Button(action: onClose) {
                            Text(closeLabel)
                                .appFont(.subheadline, weight: .semibold)
                                .frame(minWidth: 44, minHeight: 44)
                        }
                        .foregroundStyle(AppTheme.premiumEditorAccentColor)
                        .accessibilityLabel(closeLabel)
                        .accessibilityIdentifier("meal_scan.phase.close")
                    }
                }
                .padding(.horizontal, AppTheme.spacing20)
                .padding(.vertical, AppTheme.spacing8)
                .background(AppTheme.premiumEditorBackground.opacity(0.96))
                .overlay(alignment: .bottom) {
                    Rectangle()
                        .fill(AppTheme.premiumEditorBorder.opacity(0.7))
                        .frame(height: 1)
                }

                ScrollView {
                    content
                        .frame(maxWidth: 620, alignment: .leading)
                        .padding(.horizontal, AppTheme.spacing16)
                        .padding(.vertical, AppTheme.spacing20)
                        .frame(maxWidth: .infinity)
                }
            }
        }
        .background(AppTheme.premiumEditorBackground)
        .task(id: title) {
            isHeadingFocused = false
            await Task.yield()
            isHeadingFocused = true
        }
    }
}

struct MealScanRemoteConsentView: View {
    let viewModel: MealScanViewModel
    let onChooseManual: () -> Void
    @State private var isSubmitting = false
    @State private var isShowingTechnicalDetails = false

    private struct ConsentFact {
        let title: String
        let detail: String
        let systemImage: String
    }

    private var consentFacts: [ConsentFact] {
        [
            ConsentFact(
                title: L10n.string("What is sent", defaultValue: "What is sent"),
                detail: L10n.string(
                    "One compressed copy of this meal photo, only after you confirm.",
                    defaultValue: "One compressed copy of this meal photo, only after you confirm."
                ),
                systemImage: "photo"
            ),
            ConsentFact(
                title: L10n.string("Who processes it", defaultValue: "Who processes it"),
                detail: L10n.string(
                    "Google Gemini estimates foods, portions, and nutrition.",
                    defaultValue: "Google Gemini estimates foods, portions, and nutrition."
                ),
                systemImage: "sparkles"
            ),
            ConsentFact(
                title: L10n.string("Google retention", defaultValue: "Google retention"),
                detail: L10n.string(
                    "Google may retain the photo and response for up to 55 days for abuse monitoring and legal or regulatory requirements.",
                    defaultValue: "Google may retain the photo and response for up to 55 days for abuse monitoring and legal or regulatory requirements."
                ),
                systemImage: "clock"
            ),
            ConsentFact(
                title: L10n.string("What CycleBalance saves", defaultValue: "What CycleBalance saves"),
                detail: L10n.string(
                    "Only nutrition you review and save is added to your meal log. CycleBalance does not retain the uploaded photo on its server.",
                    defaultValue: "Only nutrition you review and save is added to your meal log. CycleBalance does not retain the uploaded photo on its server."
                ),
                systemImage: "checkmark.shield"
            ),
        ]
    }

    var body: some View {
        VStack(alignment: .leading, spacing: AppTheme.spacing20) {
            if let image = viewModel.selectedImage {
                Image(uiImage: image)
                    .resizable()
                    .scaledToFill()
                    .frame(maxWidth: .infinity)
                    .frame(height: 168)
                    .clipShape(RoundedRectangle(cornerRadius: AppTheme.cornerRadiusMedium, style: .continuous))
                    .accessibilityLabel(L10n.string("Selected meal photo", defaultValue: "Selected meal photo"))
            }

            VStack(alignment: .leading, spacing: AppTheme.spacing16) {
                Label(
                    L10n.string("Send this photo to Google Gemini?", defaultValue: "Send this photo to Google Gemini?"),
                    systemImage: "lock.shield"
                )
                .appHeadingFont(.title3, weight: .regular)
                .foregroundStyle(AppTheme.primaryText)

                ForEach(Array(consentFacts.enumerated()), id: \.offset) { _, fact in
                    HStack(alignment: .top, spacing: AppTheme.spacing12) {
                        Image(systemName: fact.systemImage)
                            .foregroundStyle(AppTheme.premiumEditorAccentColor)
                            .frame(width: 28, height: 28)
                            .accessibilityHidden(true)
                        VStack(alignment: .leading, spacing: AppTheme.spacing4) {
                            Text(fact.title)
                                .appFont(.subheadline, weight: .semibold)
                                .foregroundStyle(AppTheme.primaryText)
                            Text(fact.detail)
                                .appFont(.caption)
                                .foregroundStyle(AppTheme.secondaryText)
                                .fixedSize(horizontal: false, vertical: true)
                        }
                    }
                    .accessibilityElement(children: .combine)
                }

                DisclosureGroup(
                    isExpanded: $isShowingTechnicalDetails,
                    content: {
                        VStack(alignment: .leading, spacing: AppTheme.spacing8) {
                            technicalDetail(
                                L10n.string(
                                    "If this exact photo has not already been processed on this device, CycleBalance will send one compressed copy to Google Gemini to estimate foods, portions, and nutrients.",
                                    defaultValue: "If this exact photo has not already been processed on this device, CycleBalance will send one compressed copy to Google Gemini to estimate foods, portions, and nutrients."
                                )
                            )
                            technicalDetail(
                                L10n.string(
                                    "Google does not use paid API photos or responses to improve its products, but it may retain the photo and response for up to 55 days for abuse monitoring and legal or regulatory requirements. CycleBalance does not retain the uploaded photo on its server.",
                                    defaultValue: "Google does not use paid API photos or responses to improve its products, but it may retain the photo and response for up to 55 days for abuse monitoring and legal or regulatory requirements. CycleBalance does not retain the uploaded photo on its server."
                                )
                            )
                            technicalDetail(
                                L10n.string(
                                    "You will review and edit the estimate before anything is added to your meal log.",
                                    defaultValue: "You will review and edit the estimate before anything is added to your meal log."
                                )
                            )
                            technicalDetail(
                                L10n.string(
                                    "A structured estimate may be cached for up to 24 hours so the same request can be reused without another model call.",
                                    defaultValue: "A structured estimate may be cached for up to 24 hours so the same request can be reused without another model call."
                                )
                            )
                            technicalDetail(
                                L10n.string(
                                    "The standard paid allowance is 10 fresh AI photo analyses in any rolling 24 hours. Trial, sandbox, or temporary service-safeguard limits may be lower. Cached results do not use a fresh analysis.",
                                    defaultValue: "The standard paid allowance is 10 fresh AI photo analyses in any rolling 24 hours. Trial, sandbox, or temporary service-safeguard limits may be lower. Cached results do not use a fresh analysis."
                                )
                            )
                        }
                        .padding(.top, AppTheme.spacing8)
                    },
                    label: {
                        Text(L10n.string("Full technical details", defaultValue: "Full technical details"))
                            .appFont(.subheadline, weight: .semibold)
                    }
                )
                .tint(AppTheme.premiumEditorAccentColor)

                if viewModel.mealScanQuota?.remaining == 0 {
                    Label(
                        L10n.string(
                            "Your fresh AI photo allowance is used for the current rolling window. You can still check for an existing cached result; a cache miss will not dispatch a fresh model analysis.",
                            defaultValue: "Your fresh AI photo allowance is used for the current rolling window. You can still check for an existing cached result; a cache miss will not dispatch a fresh model analysis."
                        ),
                        systemImage: "hourglass"
                    )
                    .appFont(.caption, weight: .semibold)
                    .foregroundStyle(AppTheme.premiumEditorWarningAccentColor)

                    if let resetText = viewModel.quotaResetAtLocalText {
                        Text(L10n.format(
                            "Next rolling-window reset in your local time: %@.",
                            defaultValue: "Next rolling-window reset in your local time: %@.",
                            resetText
                        ))
                        .appFont(.caption)
                        .foregroundStyle(AppTheme.secondaryText)
                    }
                }
            }
            .padding(AppTheme.spacing16)
            .mealScanCard()

            VStack(spacing: AppTheme.spacing12) {
                Button {
                    isSubmitting = true
                    Task {
                        defer { isSubmitting = false }
                        do {
                            try await viewModel.confirmRemotePhotoEstimate()
                        } catch {
                            viewModel.errorMessage = L10n.string(
                                "The photo estimate could not start. You can try another photo or enter the meal manually.",
                                defaultValue: "The photo estimate could not start. You can try another photo or enter the meal manually."
                            )
                            viewModel.phase = .manualFallback
                        }
                    }
                } label: {
                    Label(
                        viewModel.canStartFreshAnalysis
                            ? L10n.string("Send to Google Gemini", defaultValue: "Send to Google Gemini")
                            : L10n.string("Check for cached result", defaultValue: "Check for cached result"),
                        systemImage: viewModel.canStartFreshAnalysis ? "arrow.up.circle.fill" : "clock.arrow.circlepath"
                    )
                    .frame(maxWidth: .infinity, minHeight: 44)
                }
                .buttonStyle(.borderedProminent)
                .tint(AppTheme.premiumEditorAccentColor)
                .disabled(isSubmitting)
                .accessibilityIdentifier("meal_scan.remote_consent.continue")

                Button(action: onChooseManual) {
                    Label(L10n.string("Enter Manually", defaultValue: "Enter Manually"), systemImage: "square.and.pencil")
                        .frame(maxWidth: .infinity, minHeight: 44)
                }
                .buttonStyle(.bordered)
                .disabled(isSubmitting)
                .accessibilityIdentifier("meal_scan.remote_consent.manual")

                Button {
                    viewModel.retake()
                } label: {
                    Label(L10n.string("Choose Another Photo", defaultValue: "Choose Another Photo"), systemImage: "photo.on.rectangle")
                        .frame(maxWidth: .infinity, minHeight: 44)
                }
                .buttonStyle(.plain)
                .foregroundStyle(AppTheme.secondaryText)
                .disabled(isSubmitting)
                .accessibilityIdentifier("meal_scan.remote_consent.retake")
            }
        }
        .accessibilityElement(children: .contain)
        .accessibilityIdentifier("meal_scan.remote_consent")
    }

    @ViewBuilder
    private func technicalDetail(_ text: String) -> some View {
        Text(text)
            .appFont(.caption)
            .foregroundStyle(AppTheme.secondaryText)
            .fixedSize(horizontal: false, vertical: true)
    }
}

struct MealScanEntryView: View {
    let viewModel: MealScanViewModel
    let onChooseManual: () -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: AppTheme.spacing16) {
            VStack(alignment: .leading, spacing: AppTheme.spacing16) {
                HStack(alignment: .top, spacing: AppTheme.spacing12) {
                    VStack(alignment: .leading, spacing: AppTheme.spacing8) {
                        Text(L10n.string("Start with a photo", defaultValue: "Start with a photo"))
                            .appHeadingFont(.largeTitle, weight: .regular)
                            .foregroundStyle(AppTheme.primaryText)
                            .fixedSize(horizontal: false, vertical: true)
                        Text(L10n.string(
                            "Start with a photo-based draft, then review every food and portion before anything is saved.",
                            defaultValue: "Start with a photo-based draft, then review every food and portion before anything is saved."
                        ))
                        .appFont(.subheadline)
                        .foregroundStyle(AppTheme.secondaryText)
                    }
                    Spacer(minLength: AppTheme.spacing8)
                    Image(systemName: "camera.viewfinder")
                        .font(.system(size: 22, weight: .semibold))
                        .foregroundStyle(AppTheme.premiumEditorCTAForeground)
                        .frame(width: 56, height: 56)
                        .background(Circle().fill(AppTheme.premiumEditorAccentGradient))
                        .accessibilityHidden(true)
                }

                ViewThatFits(in: .horizontal) {
                    HStack(spacing: AppTheme.spacing8) { phasePills }
                    VStack(alignment: .leading, spacing: AppTheme.spacing8) { phasePills }
                }
            }
            .padding(AppTheme.spacing16)
            .mealScanCard()
            .accessibilityIdentifier("meal_scan.lunar.header")

            MealScanPrivacyNoticeView()

            VStack(alignment: .leading, spacing: AppTheme.spacing12) {
                Label(L10n.string("Choose a starting point", defaultValue: "Choose a starting point"), systemImage: "sparkles")
                    .appHeadingFont(.headline, weight: .regular)
                    .foregroundStyle(AppTheme.primaryText)

                Button {
                    viewModel.startScan()
                } label: {
                    actionRow(
                        title: L10n.string("Choose meal photo", defaultValue: "Choose meal photo"),
                        subtitle: L10n.string("Use the camera or import a photo", defaultValue: "Use the camera or import a photo"),
                        systemImage: "camera.viewfinder",
                        accent: AppTheme.premiumEditorAccentColor,
                        isPrimary: true
                    )
                }
                .buttonStyle(.plain)
                .accessibilityIdentifier("meal_scan.scan_button")
                .accessibilityLabel(L10n.string("Choose meal photo", defaultValue: "Choose meal photo"))

                Button(action: onChooseManual) {
                    actionRow(
                        title: L10n.string("Enter manually", defaultValue: "Enter manually"),
                        subtitle: L10n.string("Build an editable estimate yourself", defaultValue: "Build an editable estimate yourself"),
                        systemImage: "square.and.pencil",
                        accent: AppTheme.premiumEditorSecondaryAccentColor,
                        isPrimary: false
                    )
                }
                .buttonStyle(.plain)
                .accessibilityIdentifier("meal_scan.manual_button")
            }
            .padding(AppTheme.spacing16)
            .mealScanCard()
            .accessibilityElement(children: .contain)
            .accessibilityIdentifier("meal_scan.lunar.actions")

            Text(L10n.string(
                "Nutrition values are estimates and can vary with preparation, ingredients, and portion size. Use them as a starting point, not a judgment.",
                defaultValue: "Nutrition values are estimates and can vary with preparation, ingredients, and portion size. Use them as a starting point, not a judgment."
            ))
            .appFont(.caption)
            .foregroundStyle(AppTheme.secondaryText)
            .fixedSize(horizontal: false, vertical: true)
        }
        .accessibilityElement(children: .contain)
        .accessibilityIdentifier("meal_scan.lunar.entry")
    }

    @ViewBuilder
    private var phasePills: some View {
        stepPill(title: L10n.string("Photo", defaultValue: "Photo"), systemImage: "camera.fill")
        stepPill(title: L10n.string("Review", defaultValue: "Review"), systemImage: "slider.horizontal.3")
        stepPill(title: L10n.string("Save", defaultValue: "Save"), systemImage: "checkmark.seal.fill")
    }

    private func stepPill(title: String, systemImage: String) -> some View {
        HStack(spacing: 6) {
            Image(systemName: systemImage)
                .font(.system(size: 11, weight: .semibold))
                .foregroundStyle(AppTheme.premiumEditorAccentColor)
            Text(title)
                .appFont(.caption2, weight: .semibold)
                .foregroundStyle(AppTheme.primaryText)
                .lineLimit(1)
                .minimumScaleFactor(0.76)
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, AppTheme.spacing8)
        .background(Capsule().fill(AppTheme.premiumEditorSurface.opacity(0.74)))
        .overlay(Capsule().stroke(AppTheme.premiumEditorBorder.opacity(0.54), lineWidth: 0.8))
    }

    private func actionRow(
        title: String,
        subtitle: String,
        systemImage: String,
        accent: Color,
        isPrimary: Bool
    ) -> some View {
        HStack(spacing: AppTheme.spacing12) {
            Image(systemName: systemImage)
                .font(.system(size: 18, weight: .semibold))
                .foregroundStyle(isPrimary ? AppTheme.premiumEditorCTAForeground : accent)
                .frame(width: 44, height: 44)
                .background(Circle().fill(isPrimary ? AnyShapeStyle(AppTheme.premiumEditorAccentGradient) : AnyShapeStyle(accent.opacity(0.14))))

            VStack(alignment: .leading, spacing: 2) {
                Text(title)
                    .appFont(.subheadline, weight: .semibold)
                    .foregroundStyle(AppTheme.primaryText)
                Text(subtitle)
                    .appFont(.caption)
                    .foregroundStyle(AppTheme.secondaryText)
                    .fixedSize(horizontal: false, vertical: true)
            }

            Spacer()

            Image(systemName: "chevron.right")
                .font(.system(size: 13, weight: .semibold))
                .foregroundStyle(AppTheme.secondaryText)
        }
        .padding(AppTheme.spacing12)
        .frame(minHeight: 56)
        .background(
            RoundedRectangle(cornerRadius: AppTheme.cornerRadiusMedium, style: .continuous)
                .fill(AppTheme.premiumEditorSurface.opacity(isPrimary ? 0.88 : 0.7))
        )
        .overlay(
            RoundedRectangle(cornerRadius: AppTheme.cornerRadiusMedium, style: .continuous)
                .stroke(isPrimary ? AppTheme.premiumEditorBorderGradient : LinearGradient(colors: [AppTheme.premiumEditorBorder.opacity(0.58)], startPoint: .leading, endPoint: .trailing), lineWidth: 0.8)
        )
    }
}

struct MealCameraView: View {
    @Environment(AppState.self) private var appState
    let viewModel: MealScanViewModel
    let onChooseBarcode: () -> Void
    let onChooseManual: () -> Void
    @State private var selectedPhotoItem: PhotosPickerItem?
    @State private var showingCamera = false
    @State private var cameraError: String?
    @State private var cameraAuthorizationStatus = AVCaptureDevice.authorizationStatus(for: .video)

    var body: some View {
        VStack(alignment: .leading, spacing: AppTheme.spacing16) {
            VStack(alignment: .leading, spacing: AppTheme.spacing12) {
                Label(
                    L10n.string("Photo quality", defaultValue: "Photo quality"),
                    systemImage: "viewfinder"
                )
                .appHeadingFont(.headline, weight: .regular)
                .foregroundStyle(AppTheme.primaryText)
                Text(L10n.string(
                    "Choose a clear photo with the whole plate visible and steady, even lighting.",
                    defaultValue: "Choose a clear photo with the whole plate visible and steady, even lighting."
                ))
                .appFont(.subheadline)
                .foregroundStyle(AppTheme.secondaryText)
                .fixedSize(horizontal: false, vertical: true)
            }
            .padding(AppTheme.spacing16)
            .mealScanCard()

            VStack(alignment: .leading, spacing: AppTheme.spacing8) {
                Label(
                    L10n.string("Camera permission", defaultValue: "Camera permission"),
                    systemImage: cameraPermissionSystemImage
                )
                .appHeadingFont(.headline, weight: .regular)
                .foregroundStyle(AppTheme.primaryText)
                Text(cameraPermissionStatusText)
                    .appFont(.subheadline, weight: .semibold)
                    .foregroundStyle(AppTheme.primaryText)
                Text(cameraPermissionDetail)
                    .appFont(.caption)
                    .foregroundStyle(AppTheme.secondaryText)
                    .fixedSize(horizontal: false, vertical: true)

                if cameraAuthorizationStatus == .denied || cameraAuthorizationStatus == .restricted {
                    Button(action: openSettings) {
                        Label(L10n.string("Open Settings", defaultValue: "Open Settings"), systemImage: "gear")
                            .frame(maxWidth: .infinity, minHeight: 44)
                    }
                    .buttonStyle(.bordered)
                    .accessibilityIdentifier("meal_scan.camera.open_settings")
                }
            }
            .padding(AppTheme.spacing16)
            .mealScanCard()
            .accessibilityElement(children: .contain)
            .accessibilityIdentifier("meal_scan.camera.permission")

            VStack(spacing: AppTheme.spacing12) {
                if appState.allowsPremiumAccess {
                    PhotosPicker(selection: $selectedPhotoItem, matching: .images) {
                        Label(L10n.string("Import meal photo", defaultValue: "Import meal photo"), systemImage: "photo.on.rectangle")
                            .frame(maxWidth: .infinity, minHeight: 44)
                    }
                    .buttonStyle(.borderedProminent)
                    .tint(AppTheme.premiumEditorAccentColor)
                    .accessibilityIdentifier("meal_scan.import_photo_button")
                } else {
                    Button {
                        presentMealScanPaywall()
                    } label: {
                        Label(L10n.string("Import meal photo", defaultValue: "Import meal photo"), systemImage: "photo.on.rectangle")
                            .frame(maxWidth: .infinity, minHeight: 44)
                    }
                    .buttonStyle(.borderedProminent)
                    .tint(AppTheme.premiumEditorAccentColor)
                    .accessibilityIdentifier("meal_scan.import_photo_button")
                }

                Button {
                    guard appState.allowsPremiumAccess else {
                        presentMealScanPaywall()
                        return
                    }
                    presentCamera()
                } label: {
                    Label(L10n.string("Take meal photo", defaultValue: "Take meal photo"), systemImage: "camera")
                        .frame(maxWidth: .infinity, minHeight: 44)
                }
                .buttonStyle(.bordered)
                .accessibilityIdentifier("meal_scan.take_photo_button")

                if MealScanFeatureFlags.current.enableMockMealScanData {
                    Button {
                        Task { await viewModel.useMockPhoto() }
                    } label: {
                        Label(L10n.string("Use sample meal", defaultValue: "Use sample meal"), systemImage: "sparkles")
                            .frame(maxWidth: .infinity, minHeight: 44)
                    }
                    .buttonStyle(.bordered)
                    .accessibilityIdentifier("meal_scan.mock_photo_button")
                }

                Button(action: onChooseBarcode) {
                    Label(L10n.string("Scan a barcode", defaultValue: "Scan a barcode"), systemImage: "barcode.viewfinder")
                        .frame(maxWidth: .infinity, minHeight: 44)
                }
                .buttonStyle(.bordered)
                .accessibilityIdentifier("meal_scan.camera.barcode")

                Button(action: onChooseManual) {
                    Label(L10n.string("Enter manually", defaultValue: "Enter manually"), systemImage: "square.and.pencil")
                        .frame(maxWidth: .infinity, minHeight: 44)
                }
                .buttonStyle(.plain)
                .accessibilityIdentifier("meal_scan.camera.manual")
            }
            .padding(AppTheme.spacing16)
            .mealScanCard()

            if let cameraError {
                VStack(alignment: .leading, spacing: AppTheme.spacing8) {
                    Label(cameraError, systemImage: "exclamationmark.triangle.fill")
                        .appFont(.subheadline, weight: .semibold)
                        .foregroundStyle(AppTheme.premiumEditorWarningAccentColor)
                    Text(L10n.string("No fresh AI photo analysis was used.", defaultValue: "No fresh AI photo analysis was used."))
                        .appFont(.caption)
                        .foregroundStyle(AppTheme.secondaryText)
                }
                .padding(AppTheme.spacing16)
                .mealScanCard()
                .accessibilityElement(children: .combine)
                .accessibilityIdentifier("meal_scan.camera.error")
            }

            Text(MealScanPrivacyNoticeView.remoteAnalysisDisclosure)
                .appFont(.caption)
                .foregroundStyle(AppTheme.secondaryText)
                .fixedSize(horizontal: false, vertical: true)
        }
        .sheet(isPresented: $showingCamera) {
            MealCameraImagePicker { image in
                Task { await viewModel.scanWithFallback(image: image) }
            }
        }
        .onChange(of: selectedPhotoItem) { _, newItem in
            guard let newItem else { return }
            guard appState.allowsPremiumAccess else {
                selectedPhotoItem = nil
                presentMealScanPaywall()
                return
            }
            Task { @MainActor in
                do {
                    guard let data = try await newItem.loadTransferable(type: Data.self),
                          let image = UIImage(data: data) else {
                        return
                    }
                    await viewModel.scanWithFallback(image: image)
                } catch {
                    cameraError = L10n.format(
                        "Could not import photo. %@",
                        defaultValue: "Could not import photo. %@",
                        error.localizedDescription
                    )
                }
            }
        }
        .onAppear {
            cameraAuthorizationStatus = AVCaptureDevice.authorizationStatus(for: .video)
        }
    }

    private var cameraPermissionSystemImage: String {
        switch cameraAuthorizationStatus {
        case .authorized: "checkmark.circle.fill"
        case .denied, .restricted: "exclamationmark.triangle.fill"
        case .notDetermined: "questionmark.circle"
        @unknown default: "questionmark.circle"
        }
    }

    private var cameraPermissionDetail: String {
        switch cameraAuthorizationStatus {
        case .authorized:
            L10n.string("The camera is available for meal photos.", defaultValue: "The camera is available for meal photos.")
        case .denied:
            L10n.string(
                "The camera permission was denied. Open Settings to allow it, or use another entry method.",
                defaultValue: "The camera permission was denied. Open Settings to allow it, or use another entry method."
            )
        case .restricted:
            L10n.string(
                "The camera is restricted on this device. You can import a photo, scan a barcode, or enter the meal manually.",
                defaultValue: "The camera is restricted on this device. You can import a photo, scan a barcode, or enter the meal manually."
            )
        case .notDetermined:
            L10n.string("The camera has not asked for access yet.", defaultValue: "The camera has not asked for access yet.")
        @unknown default:
            L10n.string("The camera has not asked for access yet.", defaultValue: "The camera has not asked for access yet.")
        }
    }

    private var cameraPermissionStatusText: String {
        switch cameraAuthorizationStatus {
        case .authorized:
            L10n.string("Allowed", defaultValue: "Allowed")
        case .denied:
            L10n.string("Denied", defaultValue: "Denied")
        case .restricted:
            L10n.string("Restricted", defaultValue: "Restricted")
        case .notDetermined:
            L10n.string("Not requested", defaultValue: "Not requested")
        @unknown default:
            L10n.string("Not requested", defaultValue: "Not requested")
        }
    }

    private func presentMealScanPaywall() {
        cameraError = L10n.string(
            "Subscribe to unlock photo estimates.",
            defaultValue: "Subscribe to unlock photo estimates."
        )
        appState.presentPremiumPaywall(reason: .mealScan)
    }

    private func presentCamera() {
        guard UIImagePickerController.isSourceTypeAvailable(.camera) else {
            cameraError = L10n.string(
                "Camera is unavailable on this device. You can import a meal photo instead.",
                defaultValue: "Camera is unavailable on this device. You can import a meal photo instead."
            )
            return
        }

        switch AVCaptureDevice.authorizationStatus(for: .video) {
        case .authorized:
            cameraAuthorizationStatus = .authorized
            showingCamera = true
        case .notDetermined:
            AVCaptureDevice.requestAccess(for: .video) { granted in
                Task { @MainActor in
                    cameraAuthorizationStatus = AVCaptureDevice.authorizationStatus(for: .video)
                    if granted {
                        showingCamera = true
                    } else {
                        cameraError = L10n.string(
                            "Camera access is needed to take a meal photo. You can import a photo instead.",
                            defaultValue: "Camera access is needed to take a meal photo. You can import a photo instead."
                        )
                    }
                }
            }
        default:
            cameraAuthorizationStatus = AVCaptureDevice.authorizationStatus(for: .video)
            cameraError = L10n.string(
                "Camera access is needed to take a meal photo. You can import a photo instead.",
                defaultValue: "Camera access is needed to take a meal photo. You can import a photo instead."
            )
        }
    }

    private func openSettings() {
        guard let settingsURL = URL(string: UIApplication.openSettingsURLString) else { return }
        UIApplication.shared.open(settingsURL)
    }
}

struct MealScanProcessingView: View {
    let viewModel: MealScanViewModel

    var body: some View {
        VStack(spacing: AppTheme.spacing16) {
            ProgressView()
                .controlSize(.large)
                .tint(AppTheme.premiumEditorAccentColor)
            Text(stageTitle)
                .appHeadingFont(.headline, weight: .regular)
                .foregroundStyle(AppTheme.primaryText)
                .multilineTextAlignment(.center)
            Text(L10n.string("You'll be able to edit everything before saving.", defaultValue: "You'll be able to edit everything before saving."))
                .appFont(.subheadline)
                .foregroundStyle(AppTheme.secondaryText)
                .multilineTextAlignment(.center)
        }
        .frame(maxWidth: .infinity)
        .padding(AppTheme.spacing24)
        .mealScanCard()
        .accessibilityElement(children: .combine)
        .accessibilityIdentifier("meal_scan.lunar.processing")
    }

    private var stageTitle: String {
        switch viewModel.processingStage {
        case .preparingPhoto, .checkingPreviousEstimate:
            L10n.string(
                "Preparing photo and checking for a previous estimate",
                defaultValue: "Preparing photo and checking for a previous estimate"
            )
        case .estimatingFoodsAndPortions:
            L10n.string("Estimating foods and portions...", defaultValue: "Estimating foods and portions...")
        }
    }
}

struct MealScanReviewView: View {
    @Bindable var viewModel: MealScanViewModel
    @State private var saveError: String?
    private let adaptiveReviewColumns = [GridItem(.adaptive(minimum: 220), spacing: AppTheme.spacing12)]

    var body: some View {
        VStack(alignment: .leading, spacing: AppTheme.spacing16) {
            LazyVGrid(columns: adaptiveReviewColumns, alignment: .leading, spacing: AppTheme.spacing12) {
                VStack(alignment: .leading, spacing: AppTheme.spacing8) {
                    Label(
                        viewModel.confidence.displayName,
                        systemImage: "checkmark.seal"
                    )
                    .appFont(.headline, weight: .semibold)
                    .foregroundStyle(AppTheme.premiumEditorAccentColor)
                    .accessibilityLabel(L10n.format(
                        "Confidence: %@",
                        defaultValue: "Confidence: %@",
                        viewModel.confidence.displayName
                    ))

                    TextField(
                        L10n.string("Meal name", defaultValue: "Meal name"),
                        text: $viewModel.mealName
                    )
                    .textFieldStyle(.plain)
                    .padding(AppTheme.spacing12)
                    .background(AppTheme.premiumEditorRaisedSurface.opacity(0.75))
                    .clipShape(RoundedRectangle(cornerRadius: AppTheme.cornerRadiusSmall, style: .continuous))
                    .accessibilityIdentifier("meal_scan.meal_name")
                }
                .padding(AppTheme.spacing16)
                .mealScanCard()

                if let image = viewModel.selectedImage {
                    Image(uiImage: image)
                        .resizable()
                        .scaledToFill()
                        .frame(maxWidth: .infinity)
                        .frame(height: 132)
                        .clipShape(RoundedRectangle(cornerRadius: AppTheme.cornerRadiusMedium, style: .continuous))
                        .accessibilityLabel(L10n.string("Selected meal photo", defaultValue: "Selected meal photo"))
                }
            }

            VStack(alignment: .leading, spacing: AppTheme.spacing12) {
                Label(L10n.string("Foods", defaultValue: "Foods"), systemImage: "fork.knife")
                    .appHeadingFont(.headline, weight: .regular)
                    .foregroundStyle(AppTheme.primaryText)

                ForEach(viewModel.draftItems) { item in
                    HStack(spacing: AppTheme.spacing8) {
                        NavigationLink {
                            MealFoodItemEditView(initialItem: item, viewModel: viewModel) { updated in
                                viewModel.replaceItem(updated)
                            }
                        } label: {
                            MealScanFoodItemRow(item: item)
                        }
                        .buttonStyle(.plain)
                        .accessibilityHint(L10n.string("Double tap to edit this food and portion.", defaultValue: "Double tap to edit this food and portion."))
                        .accessibilityIdentifier("meal_scan.edit_food_item")

                        Button {
                            viewModel.removeItem(id: item.id)
                        } label: {
                            Image(systemName: "trash")
                                .frame(width: 44, height: 44)
                        }
                        .buttonStyle(.plain)
                        .foregroundStyle(AppTheme.premiumEditorWarningAccentColor)
                        .accessibilityLabel(L10n.format(
                            "Remove %@",
                            defaultValue: "Remove %@",
                            item.displayName
                        ))
                    }
                }

                Button {
                    viewModel.addManualFood(named: L10n.string("Added food", defaultValue: "Added food"))
                } label: {
                    Label(L10n.string("Add Food", defaultValue: "Add Food"), systemImage: "plus")
                        .frame(maxWidth: .infinity, minHeight: 44)
                }
                .buttonStyle(.bordered)
            }
            .padding(AppTheme.spacing16)
            .mealScanCard()

            VStack(alignment: .leading, spacing: AppTheme.spacing12) {
                Label(L10n.string("Nutrition estimate", defaultValue: "Nutrition estimate"), systemImage: "chart.bar")
                    .appHeadingFont(.headline, weight: .regular)
                    .foregroundStyle(AppTheme.primaryText)
                MealNutritionSummaryView(nutrition: viewModel.totalNutrition)
                    .accessibilityElement(children: .ignore)
                    .accessibilityLabel(MealNutritionSummaryView.accessibilityLabel(for: viewModel.totalNutrition))
            }
            .padding(AppTheme.spacing16)
            .mealScanCard()

            VStack(alignment: .leading, spacing: AppTheme.spacing8) {
                Picker(
                    L10n.string(
                        "Was this cooked with oil, butter, dressing, or sauce?",
                        defaultValue: "Was this cooked with oil, butter, dressing, or sauce?"
                    ),
                    selection: $viewModel.hiddenIngredientEstimate
                ) {
                    ForEach(HiddenIngredientEstimate.allCases) { estimate in
                        Text(estimate.displayName).tag(estimate)
                    }
                }
                .pickerStyle(.menu)
                .onChange(of: viewModel.hiddenIngredientEstimate) { _, newValue in
                    viewModel.applyHiddenIngredientEstimate(newValue)
                }
                Text(L10n.string(
                    "Hidden oil, dressing, or sauces can change calories and fats, especially for restaurant meals and mixed dishes.",
                    defaultValue: "Hidden oil, dressing, or sauces can change calories and fats, especially for restaurant meals and mixed dishes."
                ))
                .appFont(.caption)
                .foregroundStyle(AppTheme.secondaryText)
            }
            .padding(AppTheme.spacing16)
            .mealScanCard()

            if let profile = viewModel.metabolicProfile {
                VStack(alignment: .leading, spacing: AppTheme.spacing8) {
                    Label(
                        L10n.format(
                            "Estimated glycemic context: %@",
                            defaultValue: "Estimated glycemic context: %@",
                            profile.estimatedGlycemicImpact.displayName
                        ),
                        systemImage: "chart.line.uptrend.xyaxis"
                    )
                    .appFont(.subheadline, weight: .semibold)
                    .foregroundStyle(AppTheme.premiumEditorSecondaryAccentColor)
                    Text(profile.explanation)
                        .appFont(.caption)
                        .foregroundStyle(AppTheme.secondaryText)
                    if let caution = profile.caution {
                        Text(caution)
                            .appFont(.caption2)
                            .foregroundStyle(AppTheme.secondaryText)
                    }
                }
                .padding(AppTheme.spacing16)
                .mealScanCard()
            }

            quotaCard

            if !viewModel.warnings.isEmpty {
                VStack(alignment: .leading, spacing: AppTheme.spacing8) {
                    Label(L10n.string("Estimate notes", defaultValue: "Estimate notes"), systemImage: "exclamationmark.triangle")
                        .appHeadingFont(.headline, weight: .regular)
                    ForEach(viewModel.warnings, id: \.self) { warning in
                        Text(warning)
                            .appFont(.caption)
                            .foregroundStyle(AppTheme.secondaryText)
                    }
                }
                .padding(AppTheme.spacing16)
                .mealScanCard()
            }

            VStack(alignment: .leading, spacing: AppTheme.spacing8) {
                Label(L10n.string("Estimate, not diagnosis", defaultValue: "Estimate, not diagnosis"), systemImage: "info.circle")
                    .appFont(.subheadline, weight: .semibold)
                Text(L10n.string(
                    "Review and edit before saving. Nutrition and glycemic context are estimates, not a diagnosis or medical advice.",
                    defaultValue: "Review and edit before saving. Nutrition and glycemic context are estimates, not a diagnosis or medical advice."
                ))
                .appFont(.caption)
                .foregroundStyle(AppTheme.secondaryText)
            }
            .padding(AppTheme.spacing16)
            .mealScanCard()

            VStack(spacing: AppTheme.spacing12) {
                Button {
                    Task { await save() }
                } label: {
                    Label(L10n.string("Save Meal", defaultValue: "Save Meal"), systemImage: "checkmark.circle.fill")
                        .frame(maxWidth: .infinity, minHeight: 44)
                }
                .buttonStyle(.borderedProminent)
                .tint(AppTheme.premiumEditorAccentColor)
                .accessibilityIdentifier("meal_scan.save_button")

                Button {
                    viewModel.retake()
                } label: {
                    Label(L10n.string("Retake Photo", defaultValue: "Retake Photo"), systemImage: "arrow.clockwise")
                        .frame(maxWidth: .infinity, minHeight: 44)
                }
                .buttonStyle(.bordered)
                .accessibilityIdentifier("meal_scan.retake_photo_button")

                if let saveError {
                    Label(saveError, systemImage: "exclamationmark.triangle.fill")
                        .appFont(.caption)
                        .foregroundStyle(AppTheme.premiumEditorWarningAccentColor)
                        .accessibilityLabel(saveError)
                        .accessibilityIdentifier("meal_scan.save_error")
                }
            }
            .padding(AppTheme.spacing16)
            .mealScanCard()
        }
    }

    @ViewBuilder
    private var quotaCard: some View {
        if let disposition = viewModel.mealScanCacheDisposition {
            VStack(alignment: .leading, spacing: AppTheme.spacing8) {
                Label(L10n.string("AI photo allowance", defaultValue: "AI photo allowance"), systemImage: "gauge.with.dots.needle.50percent")
                    .appHeadingFont(.headline, weight: .regular)
                if disposition == .fresh, let quota = viewModel.mealScanQuota {
                    Text(L10n.format(
                        "%lld of %lld fresh AI photo analyses remain in your rolling 24-hour %@ allowance.",
                        defaultValue: "%lld of %lld fresh AI photo analyses remain in your rolling 24-hour %@ allowance.",
                        Int64(quota.remaining),
                        Int64(quota.limit),
                        quota.localizedTierDisplayName
                    ))
                    .appFont(.subheadline, weight: .medium)

                    if let resetText = viewModel.quotaResetAtLocalText {
                        Text(L10n.format(
                            "This rolling window resets as earlier analyses age out; the next reset is shown in your local time: %@.",
                            defaultValue: "This rolling window resets as earlier analyses age out; the next reset is shown in your local time: %@.",
                            resetText
                        ))
                        .appFont(.caption)
                        .foregroundStyle(AppTheme.secondaryText)
                    }

                    if viewModel.shouldWarnAboutRemainingAnalyses {
                        Label(
                            L10n.format(
                                "Only %lld fresh AI photo analyses remain in this rolling window.",
                                defaultValue: "Only %lld fresh AI photo analyses remain in this rolling window.",
                                Int64(quota.remaining)
                            ),
                            systemImage: "exclamationmark.triangle.fill"
                        )
                        .appFont(.caption, weight: .semibold)
                        .foregroundStyle(AppTheme.premiumEditorWarningAccentColor)
                    }
                    Text(L10n.string("A fresh AI photo analysis was used.", defaultValue: "A fresh AI photo analysis was used."))
                        .appFont(.caption)
                } else {
                    Label(
                        L10n.string(
                            "Cached result — no fresh AI photo analysis was used.",
                            defaultValue: "Cached result — no fresh AI photo analysis was used."
                        ),
                        systemImage: "clock.arrow.circlepath"
                    )
                    .appFont(.subheadline, weight: .medium)
                }
            }
            .padding(AppTheme.spacing16)
            .mealScanCard()
        }
    }

    private func save() async {
        do {
            try await viewModel.save()
        } catch {
            saveError = L10n.format(
                "Could not save meal: %@",
                defaultValue: "Could not save meal: %@",
                error.localizedDescription
            )
        }
    }
}

struct MealFoodItemEditView: View {
    @Environment(\.dismiss) private var dismiss
    let initialItem: MealFoodItemDraft
    let viewModel: MealScanViewModel
    let onSave: (MealFoodItemDraft) -> Void

    @State private var query: String
    @State private var gramsText: String
    @State private var selectedFood: FoodNutritionRecord?
    @State private var validationError: String?

    init(
        initialItem: MealFoodItemDraft,
        viewModel: MealScanViewModel,
        onSave: @escaping (MealFoodItemDraft) -> Void
    ) {
        self.initialItem = initialItem
        self.viewModel = viewModel
        self.onSave = onSave
        _query = State(initialValue: initialItem.displayName)
        _gramsText = State(initialValue: MealNutritionCalculator.displayMacro(initialItem.estimatedGrams))
        _selectedFood = State(initialValue: SampleNutritionFixtures.records.first { $0.id == initialItem.canonicalFoodId })
    }

    private var matches: [FoodNutritionRecord] {
        let normalized = query.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        let records = SampleNutritionFixtures.records
        guard !normalized.isEmpty else { return Array(records.prefix(8)) }
        return records.filter {
            $0.displayName.lowercased().contains(normalized)
                || $0.canonicalName.lowercased().contains(normalized)
                || $0.aliases.contains(where: { $0.lowercased().contains(normalized) })
        }
        .prefix(8)
        .map { $0 }
    }

    var body: some View {
        MealScanPhaseShell(
            title: L10n.string("Edit food", defaultValue: "Edit food"),
            closeLabel: L10n.string("Cancel", defaultValue: "Cancel"),
            onClose: { dismiss() }
        ) {
            VStack(alignment: .leading, spacing: AppTheme.spacing16) {
                VStack(alignment: .leading, spacing: AppTheme.spacing12) {
                    Label(L10n.string("Portion", defaultValue: "Portion"), systemImage: "slider.horizontal.3")
                        .appHeadingFont(.headline, weight: .regular)
                        .foregroundStyle(AppTheme.primaryText)

                    TextField(L10n.string("Food name", defaultValue: "Food name"), text: $query)
                        .textFieldStyle(.plain)
                        .padding(AppTheme.spacing12)
                        .background(AppTheme.premiumEditorRaisedSurface.opacity(0.75))
                        .clipShape(RoundedRectangle(cornerRadius: AppTheme.cornerRadiusSmall, style: .continuous))
                        .accessibilityIdentifier("meal_scan.edit_food.name")

                    TextField(L10n.string("Grams", defaultValue: "Grams"), text: $gramsText)
                        .keyboardType(.decimalPad)
                        .textFieldStyle(.plain)
                        .padding(AppTheme.spacing12)
                        .background(AppTheme.premiumEditorRaisedSurface.opacity(0.75))
                        .clipShape(RoundedRectangle(cornerRadius: AppTheme.cornerRadiusSmall, style: .continuous))
                        .accessibilityIdentifier("meal_scan.edit_food.grams")
                }
                .padding(AppTheme.spacing16)
                .mealScanCard()

                VStack(alignment: .leading, spacing: AppTheme.spacing8) {
                    Label(L10n.string("Local foods", defaultValue: "Local foods"), systemImage: "magnifyingglass")
                        .appHeadingFont(.headline, weight: .regular)
                        .foregroundStyle(AppTheme.primaryText)

                    ForEach(matches) { food in
                        Button {
                            selectedFood = food
                            query = food.displayName
                            validationError = nil
                        } label: {
                            HStack(spacing: AppTheme.spacing8) {
                                VStack(alignment: .leading, spacing: AppTheme.spacing4) {
                                    Text(food.displayName)
                                        .appFont(.subheadline, weight: .medium)
                                        .foregroundStyle(AppTheme.primaryText)
                                    if let serving = food.servingDescription {
                                        Text(serving)
                                            .appFont(.caption)
                                            .foregroundStyle(AppTheme.secondaryText)
                                    }
                                }
                                Spacer()
                                if selectedFood?.id == food.id {
                                    Image(systemName: "checkmark.circle.fill")
                                        .foregroundStyle(AppTheme.premiumEditorAccentColor)
                                }
                            }
                            .frame(maxWidth: .infinity, minHeight: 44, alignment: .leading)
                            .contentShape(Rectangle())
                        }
                        .buttonStyle(.plain)
                    }
                }
                .padding(AppTheme.spacing16)
                .mealScanCard()

                if let validationError {
                    Label(validationError, systemImage: "exclamationmark.triangle.fill")
                        .appFont(.caption, weight: .semibold)
                        .foregroundStyle(AppTheme.premiumEditorWarningAccentColor)
                        .padding(AppTheme.spacing12)
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .mealScanCard()
                        .accessibilityLabel(validationError)
                        .accessibilityIdentifier("meal_scan.edit_food.validation_error")
                }

                Button(action: save) {
                    Label(L10n.string("Save", defaultValue: "Save"), systemImage: "checkmark.circle.fill")
                        .frame(maxWidth: .infinity, minHeight: 44)
                }
                .buttonStyle(.borderedProminent)
                .tint(AppTheme.premiumEditorAccentColor)
                .accessibilityIdentifier("meal_scan.edit_food.save")
            }
        }
        .accessibilityIdentifier("screen.meal_scan.edit_food")
    }

    private func save() {
        let trimmedName = query.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmedName.isEmpty else {
            validationError = L10n.string("Enter a food name.", defaultValue: "Enter a food name.")
            return
        }
        guard let grams = Double(gramsText), grams.isFinite, grams > 0 else {
            validationError = L10n.string(
                "Enter a portion greater than 0 grams.",
                defaultValue: "Enter a portion greater than 0 grams."
            )
            return
        }
        let updatedItem: MealFoodItemDraft
        if let selectedFood {
            var item = viewModel.draftItem(for: selectedFood, grams: grams, existingID: initialItem.id)
            item.wasPortionAdjusted = initialItem.wasPortionAdjusted
            item.recordUserEdit(previousEstimatedGrams: initialItem.estimatedGrams)
            updatedItem = item
        } else {
            var item = initialItem
            item.displayName = trimmedName
            item.estimatedGrams = grams
            item.recordUserEdit(previousEstimatedGrams: initialItem.estimatedGrams)
            updatedItem = item
        }
        onSave(updatedItem)
        dismiss()
    }
}

struct MealNutritionSummaryView: View {
    let nutrition: NutritionSnapshot
    private let columns = [GridItem(.adaptive(minimum: 112), spacing: AppTheme.spacing8)]

    private struct NutrientMetric: Identifiable {
        let label: String
        let value: String
        var id: String { label }
    }

    var body: some View {
        LazyVGrid(columns: columns, alignment: .leading, spacing: AppTheme.spacing8) {
            ForEach(Self.metrics(for: nutrition)) { metric in
                nutrient(metric.label, metric.value)
            }
        }
    }

    private func nutrient(_ label: String, _ value: String) -> some View {
        VStack(alignment: .leading, spacing: AppTheme.spacing4) {
            Text(value)
                .appFont(.subheadline, weight: .semibold)
                .foregroundStyle(AppTheme.primaryText)
            Text(label)
                .appFont(.caption2)
                .foregroundStyle(AppTheme.secondaryText)
        }
        .frame(maxWidth: .infinity, minHeight: 54, alignment: .leading)
        .padding(AppTheme.spacing8)
        .background(AppTheme.premiumEditorRaisedSurface.opacity(0.68))
        .clipShape(RoundedRectangle(cornerRadius: AppTheme.cornerRadiusSmall, style: .continuous))
        .accessibilityElement(children: .ignore)
        .accessibilityLabel("\(label), \(value)")
    }

    static func accessibilityLabel(for nutrition: NutritionSnapshot) -> String {
        metrics(for: nutrition)
            .map { "\($0.label), \($0.value)" }
            .joined(separator: ", ")
    }

    private static func metrics(for nutrition: NutritionSnapshot) -> [NutrientMetric] {
        var metrics = [
            NutrientMetric(
                label: L10n.string("Protein", defaultValue: "Protein"),
                value: "\(MealNutritionCalculator.displayMacro(nutrition.proteinGrams)) g"
            ),
            NutrientMetric(
                label: L10n.string("Fiber", defaultValue: "Fiber"),
                value: "\(MealNutritionCalculator.displayMacro(nutrition.fiberGrams)) g"
            ),
            NutrientMetric(
                label: L10n.string("Carbs", defaultValue: "Carbs"),
                value: "\(MealNutritionCalculator.displayMacro(nutrition.carbsGrams)) g"
            ),
        ]
        metrics.append(
            NutrientMetric(
                label: L10n.string("Net carbs", defaultValue: "Net carbs"),
                value: "\(MealNutritionCalculator.displayMacro(nutrition.netCarbsGrams)) g"
            )
        )
        metrics.append(contentsOf: [
            NutrientMetric(
                label: L10n.string("Sugar", defaultValue: "Sugar"),
                value: "\(MealNutritionCalculator.displayMacro(nutrition.sugarGrams)) g"
            ),
            NutrientMetric(
                label: L10n.string("Sodium", defaultValue: "Sodium"),
                value: "\(MealNutritionCalculator.displaySodium(nutrition.sodiumMg)) mg"
            ),
            NutrientMetric(
                label: L10n.string("Calories", defaultValue: "Calories"),
                value: "\(MealNutritionCalculator.displayCalories(nutrition.caloriesKcal)) kcal"
            ),
            NutrientMetric(
                label: L10n.string("Fat", defaultValue: "Fat"),
                value: "\(MealNutritionCalculator.displayMacro(nutrition.fatGrams)) g"
            ),
        ])
        return metrics
    }
}

struct MealScanFoodItemRow: View {
    let item: MealFoodItemDraft

    var body: some View {
        HStack(spacing: AppTheme.spacing8) {
            VStack(alignment: .leading, spacing: AppTheme.spacing4) {
                Text(item.displayName)
                    .appFont(.subheadline, weight: .medium)
                Text("\(MealNutritionCalculator.displayMacro(item.estimatedGrams)) g · \(MealNutritionCalculator.displayCalories(item.nutrition.caloriesKcal)) kcal")
                    .appFont(.caption)
                    .foregroundStyle(AppTheme.secondaryText)
                if let warning = item.warning {
                    Text(warning)
                        .appFont(.caption2)
                        .foregroundStyle(AppTheme.premiumEditorWarningAccentColor)
                }
            }
            Spacer()
            Text(item.confidence.displayName)
                .appFont(.caption2)
                .foregroundStyle(AppTheme.secondaryText)
        }
        .frame(maxWidth: .infinity, minHeight: 44, alignment: .leading)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(Self.accessibilityLabel(for: item))
        .accessibilityIdentifier("meal_scan.food_item_row")
    }

    static func accessibilityLabel(for item: MealFoodItemDraft) -> String {
        let context = L10n.format(
            "%@: %@ g, %@ kcal, confidence %@.",
            defaultValue: "%@: %@ g, %@ kcal, confidence %@.",
            item.displayName,
            MealNutritionCalculator.displayMacro(item.estimatedGrams),
            MealNutritionCalculator.displayCalories(item.nutrition.caloriesKcal),
            item.confidence.displayName
        )
        guard let warning = item.warning?.trimmingCharacters(in: .whitespacesAndNewlines),
              !warning.isEmpty else {
            return context
        }
        return "\(context) \(warning)"
    }
}

struct MealScanManualFallbackView: View {
    let viewModel: MealScanViewModel
    let onChooseBarcode: () -> Void
    let onChooseManual: () -> Void
    @State private var isRetryingPhoto = false

    private var title: String {
        if viewModel.mealScanQuota?.remaining == 0 {
            return L10n.string("Fresh AI photo allowance used", defaultValue: "Fresh AI photo allowance used")
        }
        return L10n.string("Photo analysis unavailable", defaultValue: "Photo analysis unavailable")
    }

    @ViewBuilder
    private var retrySamePhotoControl: some View {
        if viewModel.hasRetryablePendingPhoto {
            Text(
                L10n.string(
                    "That request stopped before AI dispatch, so no fresh analysis was used. Trying again reuses the same request.",
                    defaultValue: "That request stopped before AI dispatch, so no fresh analysis was used. Trying again reuses the same request."
                )
            )
                .appFont(.caption, weight: .medium)
                .foregroundStyle(AppTheme.secondaryText)
                .multilineTextAlignment(.center)

            if let retryTime = viewModel.pendingPhotoRetryAvailableAtLocalText {
                Text(
                    L10n.format(
                        "You can try the same photo again at %@.",
                        defaultValue: "You can try the same photo again at %@.",
                        retryTime
                    )
                )
                    .appFont(.caption)
                    .foregroundStyle(AppTheme.secondaryText)
                    .multilineTextAlignment(.center)
            }

            TimelineView(.periodic(from: .now, by: 1)) { context in
                Button {
                    isRetryingPhoto = true
                    Task {
                        defer { isRetryingPhoto = false }
                        try? await viewModel.retryPendingPhoto()
                    }
                } label: {
                    Label(
                        L10n.string("Try the same photo again", defaultValue: "Try the same photo again"),
                        systemImage: "arrow.clockwise"
                    )
                        .frame(maxWidth: .infinity)
                }
                .buttonStyle(.borderedProminent)
                .disabled(isRetryingPhoto || !viewModel.canRetryPendingPhoto(at: context.date))
                .accessibilityIdentifier("meal_scan.fallback.retry_same_photo")
            }
        }
    }

    var body: some View {
        VStack(spacing: AppTheme.spacing16) {
            Image(systemName: "fork.knife.circle.fill")
                .font(.system(size: 46, weight: .semibold))
                .foregroundStyle(AppTheme.premiumEditorAccentGradient)
                .accessibilityHidden(true)

            Text(title)
                .appHeadingFont(.title3, weight: .regular)
                .foregroundStyle(AppTheme.primaryText)
            Text(viewModel.errorMessage ?? L10n.string(
                "You can retake the photo or add the meal manually.",
                defaultValue: "You can retake the photo or add the meal manually."
            ))
            .appFont(.subheadline)
            .foregroundStyle(AppTheme.secondaryText)
            .multilineTextAlignment(.center)

            Text(freshAnalysisStatement)
                .appFont(.caption, weight: .semibold)
                .foregroundStyle(AppTheme.primaryText)
                .multilineTextAlignment(.center)

            if viewModel.mealScanQuota?.remaining == 0,
               let resetText = viewModel.quotaResetAtLocalText {
                Text(L10n.format(
                    "Next rolling-window reset in your local time: %@.",
                    defaultValue: "Next rolling-window reset in your local time: %@.",
                    resetText
                ))
                .appFont(.caption, weight: .medium)
                .foregroundStyle(AppTheme.primaryText)
                .multilineTextAlignment(.center)
            }

            retrySamePhotoControl

            Button(action: onChooseManual) {
                Label(L10n.string("Enter nutrition manually", defaultValue: "Enter nutrition manually"), systemImage: "square.and.pencil")
                    .frame(maxWidth: .infinity, minHeight: 44)
            }
            .buttonStyle(.borderedProminent)
            .tint(AppTheme.premiumEditorAccentColor)
            .accessibilityIdentifier("meal_scan.fallback.manual")

            Button(action: onChooseBarcode) {
                Label(L10n.string("Scan a barcode", defaultValue: "Scan a barcode"), systemImage: "barcode.viewfinder")
                    .frame(maxWidth: .infinity, minHeight: 44)
            }
            .buttonStyle(.bordered)
            .accessibilityIdentifier("meal_scan.fallback.barcode")

            Button {
                viewModel.retake()
            } label: {
                Label(L10n.string("Retake photo", defaultValue: "Retake photo"), systemImage: "camera")
                    .frame(maxWidth: .infinity, minHeight: 44)
            }
            .buttonStyle(.bordered)
            .accessibilityIdentifier("meal_scan.fallback.retake")
        }
        .padding(AppTheme.spacing24)
        .mealScanCard()
        .accessibilityIdentifier("meal_scan.lunar.manual_fallback")
    }

    private var freshAnalysisStatement: String {
        let noFreshStatement = L10n.string(
            "No fresh AI photo analysis was used.",
            defaultValue: "No fresh AI photo analysis was used."
        )
        if viewModel.hasRetryablePendingPhoto || viewModel.errorMessage?.contains(noFreshStatement) == true {
            return noFreshStatement
        }
        return L10n.string(
            "CycleBalance cannot confirm whether a fresh AI photo analysis was used.",
            defaultValue: "CycleBalance cannot confirm whether a fresh AI photo analysis was used."
        )
    }
}

struct MealScanAmbiguousOutcomeView: View {
    let viewModel: MealScanViewModel
    let onChooseBarcode: () -> Void
    let onChooseManual: () -> Void
    @State private var isChecking = false

    var body: some View {
        VStack(spacing: AppTheme.spacing16) {
                    Image(systemName: "questionmark.diamond.fill")
                        .font(.system(size: 46, weight: .semibold))
                        .foregroundStyle(AppTheme.premiumEditorWarningAccentColor)
                        .accessibilityHidden(true)

                    Text(viewModel.isRequestPending
                        ? L10n.string("Analysis still processing", defaultValue: "Analysis still processing")
                        : L10n.string("Analysis status unknown", defaultValue: "Analysis status unknown"))
                        .appHeadingFont(.title3, weight: .regular)
                        .foregroundStyle(AppTheme.primaryText)

                    Text(
                        viewModel.errorMessage ?? L10n.string(
                            "CycleBalance could not confirm whether the previous analysis completed.",
                            defaultValue: "CycleBalance could not confirm whether the previous analysis completed."
                        )
                    )
                        .appFont(.subheadline)
                        .foregroundStyle(AppTheme.secondaryText)
                        .multilineTextAlignment(.center)

                    Text(L10n.string(
                        "CycleBalance cannot confirm whether a fresh AI photo analysis was used.",
                        defaultValue: "CycleBalance cannot confirm whether a fresh AI photo analysis was used."
                    ))
                    .appFont(.caption, weight: .semibold)
                    .foregroundStyle(AppTheme.primaryText)
                    .multilineTextAlignment(.center)

                    Text(
                        L10n.string(
                            "Checking again uses the same request ID and cannot create a second charge for this request. Starting a new analysis uses a new request ID and may consume another fresh analysis.",
                            defaultValue: "Checking again uses the same request ID and cannot create a second charge for this request. Starting a new analysis uses a new request ID and may consume another fresh analysis."
                        )
                    )
                        .appFont(.caption, weight: .medium)
                        .foregroundStyle(AppTheme.primaryText)
                        .multilineTextAlignment(.center)

                    if let retryTime = viewModel.pendingRetryAvailableAtLocalText {
                        Text(
                            L10n.format(
                                "The server asked CycleBalance to wait before checking again. Next check: %@.",
                                defaultValue: "The server asked CycleBalance to wait before checking again. Next check: %@.",
                                retryTime
                            )
                        )
                            .appFont(.caption)
                            .foregroundStyle(AppTheme.secondaryText)
                            .multilineTextAlignment(.center)
                    }

                    TimelineView(.periodic(from: .now, by: 1)) { context in
                        Button {
                            isChecking = true
                            Task {
                                defer { isChecking = false }
                                try? await viewModel.retryAmbiguousOutcome()
                            }
                        } label: {
                            Label(
                                L10n.string("Check the same request", defaultValue: "Check the same request"),
                                systemImage: "arrow.clockwise"
                            )
                                .frame(maxWidth: .infinity, minHeight: 44)
                        }
                        .buttonStyle(.borderedProminent)
                        .disabled(isChecking || !viewModel.canRetryAmbiguousOutcome(at: context.date))
                        .accessibilityIdentifier("meal_scan.unknown.retry_same_request")
                    }

                    if !viewModel.canRetryAmbiguousOutcome,
                       viewModel.pendingRetryAvailableAtLocalText == nil {
                        Text(
                            L10n.string(
                                "The safe same-request check limit has been reached for now. Use barcode or manual entry, or return later.",
                                defaultValue: "The safe same-request check limit has been reached for now. Use barcode or manual entry, or return later."
                            )
                        )
                            .appFont(.caption)
                            .foregroundStyle(AppTheme.secondaryText)
                            .multilineTextAlignment(.center)
                    }

                    Button {
                        viewModel.requestNewAnalysisAfterAmbiguousOutcome()
                    } label: {
                        Label(
                            L10n.string("Consider a new analysis", defaultValue: "Consider a new analysis"),
                            systemImage: "plus.circle"
                        )
                            .frame(maxWidth: .infinity, minHeight: 44)
                    }
                    .buttonStyle(.bordered)
                    .disabled(isChecking || !viewModel.canStartFreshAnalysis)
                    .accessibilityIdentifier("meal_scan.unknown.request_new")

                    Button(action: onChooseBarcode) {
                        Label(
                            L10n.string("Scan a barcode", defaultValue: "Scan a barcode"),
                            systemImage: "barcode.viewfinder"
                        )
                            .frame(maxWidth: .infinity, minHeight: 44)
                    }
                    .buttonStyle(.bordered)

                    Button(action: onChooseManual) {
                        Label(
                            L10n.string("Enter manually", defaultValue: "Enter manually"),
                            systemImage: "square.and.pencil"
                        )
                            .frame(maxWidth: .infinity, minHeight: 44)
                    }
                    .buttonStyle(.plain)
        }
        .padding(AppTheme.spacing24)
        .mealScanCard()
        .accessibilityIdentifier("meal_scan.unknown_outcome")
    }
}

struct MealScanNewAttemptConfirmationView: View {
    let viewModel: MealScanViewModel
    let onChooseBarcode: () -> Void
    let onChooseManual: () -> Void
    @State private var isSubmitting = false

    var body: some View {
        VStack(spacing: AppTheme.spacing16) {
                Image(systemName: "exclamationmark.arrow.triangle.2.circlepath")
                    .font(.system(size: 42, weight: .semibold))
                    .foregroundStyle(AppTheme.premiumEditorWarningAccentColor)
                    .accessibilityHidden(true)

                Text(L10n.string("Start a separate analysis?", defaultValue: "Start a separate analysis?"))
                    .appHeadingFont(.title3, weight: .regular)
                    .foregroundStyle(AppTheme.primaryText)

                Text(
                    L10n.string(
                        "The previous outcome is still unknown. A separate request may consume another fresh AI photo analysis even if the first request completed.",
                        defaultValue: "The previous outcome is still unknown. A separate request may consume another fresh AI photo analysis even if the first request completed."
                    )
                )
                    .appFont(.subheadline)
                    .foregroundStyle(AppTheme.secondaryText)
                    .multilineTextAlignment(.center)

                Text(L10n.string(
                    "CycleBalance cannot confirm whether a fresh AI photo analysis was used.",
                    defaultValue: "CycleBalance cannot confirm whether a fresh AI photo analysis was used."
                ))
                .appFont(.caption, weight: .semibold)
                .foregroundStyle(AppTheme.primaryText)
                .multilineTextAlignment(.center)

                Button {
                    isSubmitting = true
                    Task {
                        defer { isSubmitting = false }
                        try? await viewModel.confirmNewAnalysisAfterAmbiguousOutcome()
                    }
                } label: {
                    Label(
                        L10n.string("Start a new billable analysis", defaultValue: "Start a new billable analysis"),
                        systemImage: "arrow.up.circle.fill"
                    )
                        .frame(maxWidth: .infinity, minHeight: 44)
                }
                .buttonStyle(.borderedProminent)
                .tint(AppTheme.premiumEditorWarningAccentColor)
                .disabled(isSubmitting || !viewModel.canStartFreshAnalysis)
                .accessibilityIdentifier("meal_scan.unknown.confirm_new")

                Button(action: onChooseBarcode) {
                    Label(
                        L10n.string("Scan a barcode", defaultValue: "Scan a barcode"),
                        systemImage: "barcode.viewfinder"
                    )
                        .frame(maxWidth: .infinity, minHeight: 44)
                }
                .buttonStyle(.bordered)
                .disabled(isSubmitting)

                Button(action: onChooseManual) {
                    Label(
                        L10n.string("Enter manually", defaultValue: "Enter manually"),
                        systemImage: "square.and.pencil"
                    )
                        .frame(maxWidth: .infinity, minHeight: 44)
                }
                .buttonStyle(.plain)
                .disabled(isSubmitting)

                Button(L10n.string("Go back", defaultValue: "Go back")) {
                    viewModel.cancelNewAnalysisConfirmation()
                }
                .buttonStyle(.bordered)
                .disabled(isSubmitting)
        }
        .padding(AppTheme.spacing24)
        .mealScanCard()
        .accessibilityIdentifier("meal_scan.new_attempt_confirmation")
    }
}

struct MealScanPrivacyNoticeView: View {
    static var remoteAnalysisDisclosure: String {
        L10n.string(
            "When you confirm a new photo estimate, CycleBalance may send one compressed copy to Google Gemini for analysis. Exact previous-meal reuse stays on this device. CycleBalance does not retain the uploaded photo on its server. By default, only nutrition you review and save is kept in your meal log; you can turn on Keep Saved Meal Photos in Settings to keep photos locally on this device.",
            defaultValue: "When you confirm a new photo estimate, CycleBalance may send one compressed copy to Google Gemini for analysis. Exact previous-meal reuse stays on this device. CycleBalance does not retain the uploaded photo on its server. By default, only nutrition you review and save is kept in your meal log; you can turn on Keep Saved Meal Photos in Settings to keep photos locally on this device."
        )
    }

    var body: some View {
        VStack(alignment: .leading, spacing: AppTheme.spacing8) {
            Label(L10n.string("Private by design", defaultValue: "Private by design"), systemImage: "lock.shield")
                .appFont(.subheadline, weight: .semibold)
                .foregroundStyle(AppTheme.premiumEditorAccentColor)
            Text(Self.remoteAnalysisDisclosure)
                .appFont(.caption)
                .foregroundStyle(AppTheme.secondaryText)
                .fixedSize(horizontal: false, vertical: true)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(AppTheme.spacing16)
        .mealScanCard()
        .accessibilityElement(children: .combine)
        .accessibilityIdentifier("meal_scan.lunar.privacy")
    }
}

struct MealScanSavedView: View {
    let viewModel: MealScanViewModel
    @State private var showingMealDetails = false
    @State private var showingContextEditor = false
    @State private var showingShareComposer = false
    @State private var contextError: String?

    var body: some View {
        VStack(spacing: AppTheme.spacing16) {
            VStack(spacing: AppTheme.spacing12) {
                Image(systemName: "checkmark.seal.fill")
                    .font(.system(size: 46, weight: .semibold))
                    .foregroundStyle(AppTheme.premiumEditorAccentGradient)
                    .accessibilityHidden(true)
                Text(L10n.string("Meal saved", defaultValue: "Meal saved"))
                    .appHeadingFont(.title2, weight: .regular)
                    .foregroundStyle(AppTheme.primaryText)
                Text(
                    L10n.string(
                        "Nutrition added to your CycleBalance log",
                        defaultValue: "Nutrition added to your CycleBalance log"
                    )
                )
                .appFont(.subheadline)
                .foregroundStyle(AppTheme.secondaryText)
                .multilineTextAlignment(.center)
            }
            .frame(maxWidth: .infinity)
            .padding(AppTheme.spacing24)
            .mealScanCard()
            .accessibilityElement(children: .combine)

            VStack(spacing: AppTheme.spacing8) {
                savedAction(
                    title: L10n.string("View Meal", defaultValue: "View Meal"),
                    systemImage: "doc.text.magnifyingglass",
                    identifier: "meal_scan.saved.view_meal"
                ) {
                    showingMealDetails = true
                }

                savedAction(
                    title: L10n.string("Add Context", defaultValue: "Add Context"),
                    systemImage: "text.badge.plus",
                    identifier: "meal_scan.saved.add_context"
                ) {
                    guard viewModel.savedMealID != nil else {
                        contextError = L10n.string(
                            "The saved meal could not be opened. Your meal remains saved.",
                            defaultValue: "The saved meal could not be opened. Your meal remains saved."
                        )
                        return
                    }
                    contextError = nil
                    showingContextEditor = true
                }

                savedAction(
                    title: L10n.string("Share", defaultValue: "Share"),
                    systemImage: "square.and.arrow.up",
                    identifier: "meal_scan.saved.share"
                ) {
                    showingShareComposer = true
                }
            }
            .padding(AppTheme.spacing12)
            .mealScanCard()

            if let contextError {
                Label(contextError, systemImage: "exclamationmark.triangle.fill")
                    .appFont(.caption)
                    .foregroundStyle(AppTheme.premiumEditorWarningAccentColor)
                    .accessibilityIdentifier("meal_scan.saved.context_error")
            }
        }
        .accessibilityElement(children: .contain)
        .accessibilityIdentifier("meal_scan.lunar.saved")
        .sheet(isPresented: $showingMealDetails) {
            MealScanSavedMealDetailView(viewModel: viewModel)
        }
        .sheet(isPresented: $showingContextEditor) {
            MealScanSavedContextView(viewModel: viewModel)
        }
        .sheet(isPresented: $showingShareComposer) {
            ScannerShareComposerView(viewModel: viewModel)
        }
    }

    private func savedAction(
        title: String,
        systemImage: String,
        identifier: String,
        action: @escaping () -> Void
    ) -> some View {
        Button(action: action) {
            HStack(spacing: AppTheme.spacing12) {
                Image(systemName: systemImage)
                    .frame(width: 24)
                    .accessibilityHidden(true)
                Text(title)
                    .appFont(.body, weight: .semibold)
                Spacer(minLength: AppTheme.spacing8)
                Image(systemName: "chevron.right")
                    .appFont(.caption, weight: .semibold)
                    .accessibilityHidden(true)
            }
            .frame(maxWidth: .infinity, minHeight: 44)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .foregroundStyle(AppTheme.primaryText)
        .accessibilityIdentifier(identifier)
    }
}

private struct MealScanSavedMealDetailView: View {
    @Environment(\.dismiss) private var dismiss
    let viewModel: MealScanViewModel

    var body: some View {
        MealScanPhaseShell(
            title: L10n.string("Saved meal", defaultValue: "Saved meal"),
            closeLabel: L10n.string("Done", defaultValue: "Done"),
            onClose: { dismiss() }
        ) {
            VStack(alignment: .leading, spacing: AppTheme.spacing16) {
                Text(viewModel.mealName)
                    .appHeadingFont(.title3, weight: .regular)
                    .foregroundStyle(AppTheme.primaryText)

                VStack(spacing: AppTheme.spacing8) {
                    ForEach(viewModel.draftItems) { item in
                        MealScanFoodItemRow(item: item)
                    }
                }
                .padding(AppTheme.spacing16)
                .mealScanCard()

                MealNutritionSummaryView(nutrition: viewModel.totalNutrition)
                    .accessibilityElement(children: .ignore)
                    .accessibilityLabel(MealNutritionSummaryView.accessibilityLabel(for: viewModel.totalNutrition))
                    .padding(AppTheme.spacing16)
                    .mealScanCard()
            }
        }
        .toolbar(.hidden, for: .navigationBar)
    }
}

private struct MealScanSavedContextView: View {
    @Environment(\.dismiss) private var dismiss
    let viewModel: MealScanViewModel
    @State private var mealName = ""
    @State private var severity = 0
    @State private var note = ""
    @State private var glucosePrefillContext: GlucosePrefillContext?
    @State private var errorMessage: String?
    @State private var isLoaded = false

    var body: some View {
        NavigationStack {
            MealScanPhaseShell(
                title: L10n.string("Add meal context", defaultValue: "Add meal context"),
                closeLabel: L10n.string("Cancel", defaultValue: "Cancel"),
                onClose: { dismiss() }
            ) {
                VStack(alignment: .leading, spacing: AppTheme.spacing16) {
                    if isLoaded {
                        VStack(alignment: .leading, spacing: AppTheme.spacing8) {
                            Text(mealName)
                                .appHeadingFont(.title3, weight: .regular)
                                .foregroundStyle(AppTheme.primaryText)
                                .fixedSize(horizontal: false, vertical: true)
                                .accessibilityIdentifier("meal_scan.context.meal_name")

                            Text(L10n.string(
                                "Your check-in will update this saved meal without creating another meal.",
                                defaultValue: "Your check-in will update this saved meal without creating another meal."
                            ))
                            .appFont(.caption)
                            .foregroundStyle(AppTheme.secondaryText)
                            .fixedSize(horizontal: false, vertical: true)
                        }
                        .padding(AppTheme.spacing16)
                        .mealScanCard()

                        MealAfterMealContextEditor(
                            severity: $severity,
                            note: $note,
                            accessibilityPrefix: "meal_scan.context"
                        )
                        .padding(AppTheme.spacing16)
                        .mealScanCard()

                        if let glucosePrefillContext {
                            VStack(alignment: .leading, spacing: AppTheme.spacing8) {
                                Text(L10n.string("Glucose context", defaultValue: "Glucose context"))
                                    .appHeadingFont(.headline, weight: .regular)
                                    .foregroundStyle(AppTheme.primaryText)

                                Text(L10n.string(
                                    "An after-meal glucose reading is saved separately. Opening it does not change or duplicate this meal.",
                                    defaultValue: "An after-meal glucose reading is saved separately. Opening it does not change or duplicate this meal."
                                ))
                                .appFont(.caption)
                                .foregroundStyle(AppTheme.secondaryText)
                                .fixedSize(horizontal: false, vertical: true)

                                NavigationLink {
                                    BloodSugarLogView(prefillContext: glucosePrefillContext)
                                } label: {
                                    Label(
                                        L10n.string("Log after-meal glucose", defaultValue: "Log after-meal glucose"),
                                        systemImage: "drop.fill"
                                    )
                                    .frame(maxWidth: .infinity, minHeight: 44)
                                }
                                .buttonStyle(.bordered)
                                .accessibilityIdentifier("meal_scan.context.log_glucose")
                            }
                            .padding(AppTheme.spacing16)
                            .mealScanCard()
                        }

                        Button(action: save) {
                            Label(
                                L10n.string("Save context", defaultValue: "Save context"),
                                systemImage: "checkmark.circle.fill"
                            )
                            .frame(maxWidth: .infinity, minHeight: 44)
                        }
                        .buttonStyle(.borderedProminent)
                        .tint(AppTheme.premiumEditorAccentColor)
                        .accessibilityIdentifier("meal_scan.context.save")
                    } else if errorMessage == nil {
                        ProgressView()
                            .frame(maxWidth: .infinity, minHeight: 120)
                    }

                    if let errorMessage {
                        Label(errorMessage, systemImage: "exclamationmark.triangle.fill")
                            .appFont(.subheadline, weight: .semibold)
                            .foregroundStyle(AppTheme.premiumEditorWarningAccentColor)
                            .padding(AppTheme.spacing16)
                            .mealScanCard()
                            .accessibilityIdentifier("meal_scan.context.error")
                    }
                }
            }
        }
        .accessibilityIdentifier("meal_scan.saved_context")
        .task { load() }
    }

    private func load() {
        do {
            let draft = try viewModel.savedMealContextDraft()
            mealName = draft.mealName
            severity = draft.severity
            note = draft.note
            glucosePrefillContext = try viewModel.savedMealGlucosePrefillContext()
            errorMessage = nil
            isLoaded = true
        } catch {
            errorMessage = L10n.string(
                "The saved meal could not be opened. Your meal remains saved.",
                defaultValue: "The saved meal could not be opened. Your meal remains saved."
            )
            isLoaded = false
        }
    }

    private func save() {
        do {
            try viewModel.updateSavedMealContext(severity: severity, note: note)
            dismiss()
        } catch {
            errorMessage = L10n.string(
                "Context could not be saved. Your meal remains unchanged.",
                defaultValue: "Context could not be saved. Your meal remains unchanged."
            )
        }
    }
}

private struct ScannerShareComposerView: View {
    @Environment(\.dismiss) private var dismiss
    let viewModel: MealScanViewModel
    @State private var includeFoodNames = false
    @State private var includePhoto = false
    @State private var includeMacros = false
    @State private var shareState = ScannerSharePresentationState()
    @State private var activityItems: [Any] = []

    private var card: ScannerShareCard {
        ScannerShareCard(
            items: viewModel.draftItems,
            nutrition: viewModel.totalNutrition,
            sourcePhoto: viewModel.selectedImage,
            options: ScannerShareCard.Options(
                includeFoodNames: includeFoodNames,
                includePhoto: includePhoto,
                includeMacros: includeMacros
            )
        )
    }

    var body: some View {
        MealScanPhaseShell(
            title: L10n.string("Share meal", defaultValue: "Share meal"),
            closeLabel: L10n.string("Cancel", defaultValue: "Cancel"),
            onClose: { dismiss() }
        ) {
            VStack(alignment: .leading, spacing: AppTheme.spacing16) {
                VStack(alignment: .leading, spacing: AppTheme.spacing8) {
                    Label(
                        L10n.string("Private by default", defaultValue: "Private by default"),
                        systemImage: "hand.raised.fill"
                    )
                    .appHeadingFont(.headline, weight: .regular)
                    .foregroundStyle(AppTheme.primaryText)

                    Text(
                        L10n.string(
                            "Optional details are off until you turn them on. Review this preview before sharing.",
                            defaultValue: "Optional details are off until you turn them on. Review this preview before sharing."
                        )
                    )
                    .appFont(.subheadline)
                    .foregroundStyle(AppTheme.secondaryText)
                }
                .padding(AppTheme.spacing16)
                .mealScanCard()

                Text(L10n.string("Share preview", defaultValue: "Share preview"))
                    .appHeadingFont(.headline, weight: .regular)
                    .foregroundStyle(AppTheme.primaryText)

                ScannerShareCardArtwork(card: card)
                    .frame(maxWidth: .infinity)
                    .aspectRatio(4 / 5, contentMode: .fit)
                    .accessibilityIdentifier("meal_scan.share.preview")

                VStack(spacing: 0) {
                    shareToggle(
                        L10n.string("Include food names", defaultValue: "Include food names"),
                        isOn: $includeFoodNames
                    )
                    Divider()
                    shareToggle(
                        L10n.string("Include meal photo", defaultValue: "Include meal photo"),
                        isOn: $includePhoto
                    )
                    Divider()
                    shareToggle(
                        L10n.string("Include nutrition macros", defaultValue: "Include nutrition macros"),
                        isOn: $includeMacros
                    )
                }
                .padding(.horizontal, AppTheme.spacing16)
                .mealScanCard()

                Button(action: beginShare) {
                    Label(
                        L10n.string("Share card", defaultValue: "Share card"),
                        systemImage: "square.and.arrow.up"
                    )
                    .frame(maxWidth: .infinity, minHeight: 44)
                }
                .buttonStyle(.borderedProminent)
                .tint(AppTheme.premiumEditorAccentColor)
                .accessibilityIdentifier("meal_scan.share.open_sheet")
            }
        }
        .toolbar(.hidden, for: .navigationBar)
        .sheet(
            isPresented: Binding(
                get: { shareState.isPresented },
                set: { isPresented in
                    if !isPresented {
                        shareState.finish(completed: false)
                    }
                }
            )
        ) {
            ScannerShareActivityView(activityItems: activityItems) { completed in
                shareState.finish(completed: completed)
            }
        }
    }

    private func shareToggle(_ title: String, isOn: Binding<Bool>) -> some View {
        Toggle(title, isOn: isOn)
            .tint(AppTheme.premiumEditorAccentColor)
            .frame(minHeight: 52)
    }

    private func beginShare() {
        let exportCard = card
        let renderer = ImageRenderer(
            content: ScannerShareCardArtwork(card: exportCard)
                .frame(width: 1080, height: 1350)
        )
        renderer.scale = 1
        guard let flattenedImage = renderer.uiImage else { return }
        activityItems = [flattenedImage, exportCard.destinationURL]
        shareState.begin()
    }
}

private struct ScannerShareCardArtwork: View {
    let card: ScannerShareCard

    var body: some View {
        ZStack {
            LinearGradient(
                colors: [AppTheme.premiumEditorRaisedSurface, AppTheme.premiumEditorBackground],
                startPoint: .topLeading,
                endPoint: .bottomTrailing
            )

            VStack(alignment: .leading, spacing: AppTheme.spacing16) {
                HStack {
                    Image(systemName: "fork.knife.circle.fill")
                        .font(.system(size: 36, weight: .semibold))
                        .foregroundStyle(AppTheme.premiumEditorAccentColor)
                    Spacer()
                    Text(card.brandName)
                        .appFont(.headline, weight: .bold)
                        .foregroundStyle(AppTheme.primaryText)
                }

                Text(card.headline)
                    .appHeadingFont(.title2, weight: .regular)
                    .foregroundStyle(AppTheme.primaryText)
                    .fixedSize(horizontal: false, vertical: true)

                if let data = card.flattenedPhotoPNGData, let image = UIImage(data: data) {
                    Image(uiImage: image)
                        .resizable()
                        .scaledToFill()
                        .frame(maxWidth: .infinity, maxHeight: 240)
                        .clipShape(RoundedRectangle(cornerRadius: AppTheme.cornerRadiusMedium))
                        .accessibilityLabel(L10n.string("Included meal photo", defaultValue: "Included meal photo"))
                }

                HStack(spacing: AppTheme.spacing12) {
                    shareCount(
                        value: card.reviewedFoodCount,
                        label: L10n.string("Foods reviewed", defaultValue: "Foods reviewed")
                    )
                    shareCount(
                        value: card.adjustedPortionCount,
                        label: L10n.string("Adjusted portions", defaultValue: "Adjusted portions")
                    )
                }

                if let foodNames = card.foodNames {
                    VStack(alignment: .leading, spacing: AppTheme.spacing4) {
                        ForEach(foodNames, id: \.self) { name in
                            Text("• \(name)")
                                .appFont(.subheadline)
                                .foregroundStyle(AppTheme.primaryText)
                        }
                    }
                }

                if let macros = card.macros {
                    Text(
                        L10n.format(
                            "%@ g protein • %@ g carbs • %@ g fat",
                            defaultValue: "%@ g protein • %@ g carbs • %@ g fat",
                            MealNutritionCalculator.displayMacro(macros.proteinGrams),
                            MealNutritionCalculator.displayMacro(macros.carbsGrams),
                            MealNutritionCalculator.displayMacro(macros.fatGrams)
                        )
                    )
                    .appFont(.subheadline, weight: .semibold)
                    .foregroundStyle(AppTheme.primaryText)
                }

                Spacer(minLength: 0)
            }
            .padding(AppTheme.spacing24)
        }
        .clipShape(RoundedRectangle(cornerRadius: AppTheme.cornerRadiusLarge, style: .continuous))
        .overlay {
            RoundedRectangle(cornerRadius: AppTheme.cornerRadiusLarge, style: .continuous)
                .stroke(AppTheme.premiumEditorBorder, lineWidth: 1)
        }
        .accessibilityElement(children: .combine)
        .accessibilityLabel(card.visibleText)
    }

    private func shareCount(value: Int, label: String) -> some View {
        VStack(alignment: .leading, spacing: AppTheme.spacing4) {
            Text("\(value)")
                .appFont(.title2, weight: .bold)
                .foregroundStyle(AppTheme.premiumEditorAccentColor)
            Text(label)
                .appFont(.caption, weight: .semibold)
                .foregroundStyle(AppTheme.secondaryText)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(AppTheme.spacing12)
        .background(AppTheme.premiumEditorSurface.opacity(0.75))
        .clipShape(RoundedRectangle(cornerRadius: AppTheme.cornerRadiusMedium))
    }
}

private struct ScannerShareActivityView: UIViewControllerRepresentable {
    let activityItems: [Any]
    let onFinish: (Bool) -> Void

    func makeUIViewController(context: Context) -> UIActivityViewController {
        let controller = UIActivityViewController(activityItems: activityItems, applicationActivities: nil)
        controller.completionWithItemsHandler = { _, completed, _, _ in
            onFinish(completed)
        }
        return controller
    }

    func updateUIViewController(_ uiViewController: UIActivityViewController, context: Context) {}
}

private struct LunarMealScanLoadingView: View {
    var body: some View {
        ProgressView()
            .controlSize(.large)
            .tint(AppTheme.premiumEditorAccentColor)
            .frame(maxWidth: .infinity, minHeight: 160)
            .mealScanCard()
            .accessibilityLabel(L10n.string("Loading meal scanner", defaultValue: "Loading meal scanner"))
        .accessibilityIdentifier("meal_scan.lunar.loading")
    }
}

private extension View {
    func mealScanCard() -> some View {
        background(
            RoundedRectangle(cornerRadius: AppTheme.cornerRadiusLarge, style: .continuous)
                .fill(
                    LinearGradient(
                        colors: [
                            AppTheme.premiumEditorRaisedSurface.opacity(0.92),
                            AppTheme.premiumEditorSurface.opacity(0.78),
                            AppTheme.premiumEditorBackground.opacity(0.9)
                        ],
                        startPoint: .topLeading,
                        endPoint: .bottomTrailing
                    )
                )
        )
        .overlay(
            RoundedRectangle(cornerRadius: AppTheme.cornerRadiusLarge, style: .continuous)
                .stroke(AppTheme.premiumEditorBorderGradient, lineWidth: 0.85)
        )
        .shadow(color: AppTheme.cardShadowColor, radius: 18, y: 12)
    }

    func lunarMealScanCard() -> some View {
        mealScanCard()
    }
}

private struct MealCameraImagePicker: UIViewControllerRepresentable {
    let onImage: (UIImage) -> Void
    @Environment(\.dismiss) private var dismiss

    func makeCoordinator() -> Coordinator {
        Coordinator(parent: self)
    }

    func makeUIViewController(context: Context) -> UIImagePickerController {
        let picker = UIImagePickerController()
        picker.sourceType = .camera
        picker.delegate = context.coordinator
        return picker
    }

    func updateUIViewController(_ uiViewController: UIImagePickerController, context: Context) {}

    final class Coordinator: NSObject, UINavigationControllerDelegate, UIImagePickerControllerDelegate {
        let parent: MealCameraImagePicker

        init(parent: MealCameraImagePicker) {
            self.parent = parent
        }

        func imagePickerController(
            _ picker: UIImagePickerController,
            didFinishPickingMediaWithInfo info: [UIImagePickerController.InfoKey: Any]
        ) {
            if let image = info[.originalImage] as? UIImage {
                parent.onImage(image)
            }
            parent.dismiss()
        }

        func imagePickerControllerDidCancel(_ picker: UIImagePickerController) {
            parent.dismiss()
        }
    }
}

#Preview {
    MealScanFlowView(mealType: .lunch)
        .modelContainer(for: [
            MealEntry.self,
            MealScanFoodItem.self,
            MealScanNutritionSummary.self,
            MealScanMetadata.self,
            NutritionImportRecord.self,
            MealScanRepeatCacheRecord.self,
        ], inMemory: true)
}
