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
                .safeAreaInset(edge: .bottom, spacing: 0) {
                    if viewModel.phase == .review {
                        MealScanReviewActionPanel(viewModel: viewModel)
                    }
                }
                .alert(
                    L10n.string("Start another scan?", defaultValue: "Start another scan?"),
                    isPresented: Binding(
                        get: { viewModel.isShowingNewAnalysisConfirmation },
                        set: { isPresented in
                            if !isPresented { viewModel.cancelNewAnalysisConfirmation() }
                        }
                    )
                ) {
                    Button(L10n.string("Start another scan", defaultValue: "Start another scan")) {
                        Task { try? await viewModel.confirmNewAnalysisAfterAmbiguousOutcome() }
                    }
                    Button(L10n.string("Cancel", defaultValue: "Cancel"), role: .cancel) {
                        viewModel.cancelNewAnalysisConfirmation()
                    }
                } message: {
                    Text(L10n.string(
                        "CycleBalance still cannot confirm the earlier scan. Starting another one may use an additional scan.",
                        defaultValue: "CycleBalance still cannot confirm the earlier scan. Starting another one may use an additional scan."
                    ))
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
        .tint(AppTheme.mealScannerActionBackground)
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
        case .photoChoice:
            MealPhotoChoiceView(
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
                            try? await viewModel.scanPendingImageAsNew()
                        }
                    }
                )
            } else {
                MealScanProcessingView(viewModel: viewModel)
            }
        case .remoteConsent:
            MealScanRemoteConsentView(viewModel: viewModel, onChooseManual: chooseManual)
        case .failure:
            MealScanFailureView(
                viewModel: viewModel,
                onChooseBarcode: chooseBarcode,
                onChooseManual: chooseManual
            )
        case .review:
            MealScanReviewView(viewModel: viewModel)
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
        case .photoChoice:
            L10n.string("Meal photo", defaultValue: "Meal photo")
        case .processing:
            L10n.string("Preparing photo", defaultValue: "Preparing photo")
        case .repeatSuggestion:
            L10n.string("Looks familiar", defaultValue: "Looks familiar")
        case .remoteConsent:
            L10n.string("Confirm analysis", defaultValue: "Confirm analysis")
        case .failure:
            L10n.string("CycleBalance AI scanner", defaultValue: "CycleBalance AI scanner")
        case .review:
            L10n.string("Review your estimate", defaultValue: "Review your estimate")
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
    @Environment(\.dynamicTypeSize) private var dynamicTypeSize

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
                HStack(alignment: .firstTextBaseline, spacing: AppTheme.spacing8) {
                    Text(title)
                        .appHeadingFont(dynamicTypeSize.isAccessibilitySize ? .caption2 : .title3, weight: .regular)
                        .foregroundStyle(AppTheme.primaryText)
                        .fixedSize(horizontal: false, vertical: true)
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .layoutPriority(1)
                        .accessibilityAddTraits(.isHeader)
                        .accessibilityHeading(.h1)
                        .accessibilityFocused($isHeadingFocused)
                        .accessibilityIdentifier("meal_scan.phase.title")

                    if let closeLabel, let onClose {
                        Button(action: onClose) {
                            Text(closeLabel)
                                .appFont(dynamicTypeSize.isAccessibilitySize ? .caption2 : .subheadline, weight: .semibold)
                                .frame(minWidth: 44, minHeight: 44)
                        }
                        .foregroundStyle(AppTheme.mealScannerActionBackground)
                        .fixedSize()
                        .accessibilityLabel(closeLabel)
                        .accessibilityIdentifier("meal_scan.phase.close")
                    }
                }
                .padding(.horizontal, dynamicTypeSize.isAccessibilitySize ? AppTheme.spacing12 : AppTheme.spacing20)
                .padding(.vertical, dynamicTypeSize.isAccessibilitySize ? 0 : AppTheme.spacing8)
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
                        .padding(.vertical, dynamicTypeSize.isAccessibilitySize ? AppTheme.spacing4 : AppTheme.spacing20)
                        .frame(maxWidth: .infinity)
                }
                .scrollDismissesKeyboard(.interactively)
                .id(title)
                .accessibilityIdentifier("meal_scan.phase.scroll")
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

    var body: some View {
        VStack(alignment: .leading, spacing: AppTheme.spacing16) {
            if let image = viewModel.selectedImage {
                Image(uiImage: image)
                    .resizable()
                    .scaledToFill()
                    .frame(maxWidth: .infinity)
                    .frame(height: 176)
                    .clipShape(RoundedRectangle(cornerRadius: AppTheme.cornerRadiusMedium, style: .continuous))
                    .accessibilityLabel(L10n.string("Selected meal photo", defaultValue: "Selected meal photo"))
            }

            VStack(alignment: .leading, spacing: AppTheme.spacing12) {
                Label(
                    L10n.string("Analyze this meal photo?", defaultValue: "Analyze this meal photo?"),
                    systemImage: "sparkles"
                )
                .appHeadingFont(.title3, weight: .regular)
                .foregroundStyle(AppTheme.primaryText)

                Text(L10n.string(
                    "CycleBalance uses AI to create an editable estimate of foods, portions, and nutrition.",
                    defaultValue: "CycleBalance uses AI to create an editable estimate of foods, portions, and nutrition."
                ))
                .appFont(.subheadline)
                .foregroundStyle(AppTheme.mealScannerBodyText)
                .fixedSize(horizontal: false, vertical: true)

                consentLine(
                    L10n.string(
                        "Google Gemini receives one compressed copy and may retain the photo and response for up to 55 days.",
                        defaultValue: "Google Gemini receives one compressed copy and may retain the photo and response for up to 55 days."
                    ),
                    systemImage: "clock"
                )
                consentLine(
                    L10n.string(
                        "CycleBalance does not retain the uploaded photo on its servers.",
                        defaultValue: "CycleBalance does not retain the uploaded photo on its servers."
                    ),
                    systemImage: "lock.shield"
                )
                consentLine(
                    L10n.string(
                        "Your edited estimate is added to the meal log only after you choose Save meal.",
                        defaultValue: "Your edited estimate is added to the meal log only after you choose Save meal."
                    ),
                    systemImage: "checkmark.circle"
                )
                consentLine(
                    L10n.string(
                        "The photo is saved locally only when Keep Saved Meal Photos is enabled.",
                        defaultValue: "The photo is saved locally only when Keep Saved Meal Photos is enabled."
                    ),
                    systemImage: "iphone"
                )

                DisclosureGroup(
                    isExpanded: $isShowingTechnicalDetails,
                    content: {
                        VStack(alignment: .leading, spacing: AppTheme.spacing8) {
                            technicalDetail(
                                L10n.string(
                                    "Google does not use paid API photos or responses to improve its products. Retention may still apply for abuse monitoring and legal or regulatory requirements.",
                                    defaultValue: "Google does not use paid API photos or responses to improve its products. Retention may still apply for abuse monitoring and legal or regulatory requirements."
                                )
                            )
                            technicalDetail(
                                L10n.string(
                                    "CycleBalance may keep a structured estimate for up to 24 hours so the exact photo can be reused without another upload.",
                                    defaultValue: "CycleBalance may keep a structured estimate for up to 24 hours so the exact photo can be reused without another upload."
                                )
                            )
                            technicalDetail(
                                L10n.string(
                                    "Scan limits depend on your access. Reusing a cached estimate does not use a scan.",
                                    defaultValue: "Scan limits depend on your access. Reusing a cached estimate does not use a scan."
                                )
                            )
                        }
                        .padding(.top, AppTheme.spacing8)
                    },
                    label: {
                        Text(L10n.string("Privacy details", defaultValue: "Privacy details"))
                            .appFont(.subheadline, weight: .semibold)
                    }
                )
                .tint(AppTheme.mealScannerActionBackground)
                .accessibilityIdentifier("meal_scan.remote_consent.privacy_details")
            }
            .padding(AppTheme.spacing16)
            .mealScanCard()

            VStack(spacing: AppTheme.spacing12) {
                Button {
                    isSubmitting = true
                    Task {
                        defer { isSubmitting = false }
                        try? await viewModel.confirmRemotePhotoEstimate()
                    }
                } label: {
                    Label(
                        L10n.string("Analyze photo", defaultValue: "Analyze photo"),
                        systemImage: "sparkles"
                    )
                    .frame(maxWidth: .infinity, minHeight: 44)
                }
                .mealScanPrimaryActionStyle()
                .disabled(isSubmitting)
                .accessibilityIdentifier("meal_scan.remote_consent.continue")

                Button {
                    viewModel.retake()
                } label: {
                    Label(L10n.string("Choose another photo", defaultValue: "Choose another photo"), systemImage: "photo.on.rectangle")
                        .frame(maxWidth: .infinity, minHeight: 44)
                }
                .buttonStyle(.bordered)
                .disabled(isSubmitting)
                .accessibilityIdentifier("meal_scan.remote_consent.retake")

                Button(action: onChooseManual) {
                    Label(L10n.string("Enter manually", defaultValue: "Enter manually"), systemImage: "square.and.pencil")
                        .frame(maxWidth: .infinity, minHeight: 44)
                }
                .buttonStyle(.plain)
                .foregroundStyle(AppTheme.secondaryText)
                .disabled(isSubmitting)
                .accessibilityIdentifier("meal_scan.remote_consent.manual")
            }
        }
        .accessibilityElement(children: .contain)
        .accessibilityIdentifier("meal_scan.remote_consent")
    }

    @ViewBuilder
    private func technicalDetail(_ text: String) -> some View {
        Text(text)
            .appFont(.caption)
            .foregroundStyle(AppTheme.mealScannerBodyText)
            .fixedSize(horizontal: false, vertical: true)
    }

    private func consentLine(_ text: String, systemImage: String) -> some View {
        Label(text, systemImage: systemImage)
            .appFont(.caption)
            .foregroundStyle(AppTheme.mealScannerBodyText)
            .fixedSize(horizontal: false, vertical: true)
    }
}

struct MealPhotoChoiceView: View {
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
                    L10n.string("Choose a meal photo", defaultValue: "Choose a meal photo"),
                    systemImage: "viewfinder"
                )
                .appHeadingFont(.headline, weight: .regular)
                .foregroundStyle(AppTheme.primaryText)
                Text(L10n.string(
                    "For the clearest estimate, show the whole plate in good light.",
                    defaultValue: "For the clearest estimate, show the whole plate in good light."
                ))
                .appFont(.subheadline)
                .foregroundStyle(AppTheme.mealScannerBodyText)
                .fixedSize(horizontal: false, vertical: true)
            }
            .padding(AppTheme.spacing16)
            .mealScanCard()

            if shouldShowCameraPermissionHelp {
                VStack(alignment: .leading, spacing: AppTheme.spacing8) {
                    Label(
                        L10n.string("Camera needs attention", defaultValue: "Camera needs attention"),
                        systemImage: cameraPermissionSystemImage
                    )
                    .appHeadingFont(.headline, weight: .regular)
                    .foregroundStyle(AppTheme.primaryText)
                    Text(cameraPermissionDetail)
                        .appFont(.subheadline)
                        .foregroundStyle(AppTheme.mealScannerBodyText)
                        .fixedSize(horizontal: false, vertical: true)

                    if cameraAuthorizationStatus == .denied {
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
            }

            VStack(spacing: AppTheme.spacing12) {
                Button {
                    guard appState.allowsPremiumAccess else {
                        presentMealScanPaywall()
                        return
                    }
                    presentCamera()
                } label: {
                    Label(L10n.string("Take Photo", defaultValue: "Take Photo"), systemImage: "camera.fill")
                        .frame(maxWidth: .infinity, minHeight: 44)
                }
                .mealScanPrimaryActionStyle()
                .accessibilityIdentifier("meal_scan.take_photo_button")

                if appState.allowsPremiumAccess {
                    PhotosPicker(selection: $selectedPhotoItem, matching: .images) {
                        Label(L10n.string("Choose from Library", defaultValue: "Choose from Library"), systemImage: "photo.on.rectangle")
                            .frame(maxWidth: .infinity, minHeight: 44)
                    }
                    .buttonStyle(.bordered)
                    .accessibilityIdentifier("meal_scan.import_photo_button")
                } else {
                    Button {
                        presentMealScanPaywall()
                    } label: {
                        Label(L10n.string("Choose from Library", defaultValue: "Choose from Library"), systemImage: "photo.on.rectangle")
                            .frame(maxWidth: .infinity, minHeight: 44)
                    }
                    .buttonStyle(.bordered)
                    .accessibilityIdentifier("meal_scan.import_photo_button")
                }

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

                ViewThatFits(in: .horizontal) {
                    HStack(spacing: AppTheme.spacing8) { compactAlternatives }
                    VStack(spacing: AppTheme.spacing8) { compactAlternatives }
                }
            }
            .padding(AppTheme.spacing16)
            .mealScanCard()

            if let cameraError {
                VStack(alignment: .leading, spacing: AppTheme.spacing8) {
                    Label(cameraError, systemImage: "exclamationmark.triangle.fill")
                        .appFont(.subheadline, weight: .semibold)
                        .foregroundStyle(AppTheme.mealScannerErrorText)
                    Text(L10n.string("No scan was used.", defaultValue: "No scan was used."))
                        .appFont(.caption)
                        .foregroundStyle(AppTheme.mealScannerBodyText)
                }
                .padding(AppTheme.spacing16)
                .mealScanCard()
                .accessibilityElement(children: .combine)
                .accessibilityIdentifier("meal_scan.camera.error")
            }
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
                        viewModel.rejectUnreadableSelectedPhoto()
                        return
                    }
                    await viewModel.scanWithFallback(image: image)
                } catch {
                    viewModel.rejectUnreadableSelectedPhoto()
                }
            }
        }
        .onAppear {
            cameraAuthorizationStatus = initialCameraAuthorizationStatus
        }
        .accessibilityElement(children: .contain)
        .accessibilityIdentifier("meal_scan.photo_choice")
    }

    @ViewBuilder
    private var compactAlternatives: some View {
        Button(action: onChooseBarcode) {
            Label(L10n.string("Barcode", defaultValue: "Barcode"), systemImage: "barcode.viewfinder")
                .frame(maxWidth: .infinity, minHeight: 44)
        }
        .buttonStyle(.bordered)
        .accessibilityLabel(L10n.string("Scan a barcode", defaultValue: "Scan a barcode"))
        .accessibilityIdentifier("meal_scan.camera.barcode")

        Button(action: onChooseManual) {
            Label(L10n.string("Enter manually", defaultValue: "Enter manually"), systemImage: "square.and.pencil")
                .frame(maxWidth: .infinity, minHeight: 44)
        }
        .buttonStyle(.plain)
        .accessibilityIdentifier("meal_scan.camera.manual")
    }

    private var cameraPermissionSystemImage: String {
        switch cameraAuthorizationStatus {
        case .authorized: "checkmark.circle.fill"
        case .denied, .restricted: "exclamationmark.triangle.fill"
        case .notDetermined: "questionmark.circle"
        @unknown default: "questionmark.circle"
        }
    }

    private var shouldShowCameraPermissionHelp: Bool {
        cameraAuthorizationStatus == .denied || cameraAuthorizationStatus == .restricted
    }

    private var initialCameraAuthorizationStatus: AVAuthorizationStatus {
        #if DEBUG
        let arguments = ProcessInfo.processInfo.arguments
        if arguments.contains("UITestMode"),
           let fixtureIndex = arguments.firstIndex(of: "-mealScan.fixture"),
           arguments.indices.contains(fixtureIndex + 1) {
            return arguments[fixtureIndex + 1] == "permissionDenied" ? .denied : .authorized
        }
        #endif
        return AVCaptureDevice.authorizationStatus(for: .video)
    }

    private var cameraPermissionDetail: String {
        switch cameraAuthorizationStatus {
        case .denied:
            L10n.string(
                "The camera permission was denied. Open Settings to allow it, or use another entry method.",
                defaultValue: "The camera permission was denied. Open Settings to allow it, or use another entry method."
            )
        case .restricted:
            L10n.string(
                "The camera is restricted on this device. Choose a photo from your library, scan a barcode, or enter the meal manually.",
                defaultValue: "The camera is restricted on this device. Choose a photo from your library, scan a barcode, or enter the meal manually."
            )
        case .authorized, .notDetermined:
            ""
        @unknown default:
            ""
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
                .tint(AppTheme.mealScannerActionBackground)
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
    @State private var isShowingMoreDetails = false
    @Environment(\.dynamicTypeSize) private var dynamicTypeSize

    var body: some View {
        VStack(alignment: .leading, spacing: dynamicTypeSize.isAccessibilitySize ? AppTheme.spacing12 : AppTheme.spacing16) {
            VStack(alignment: .leading, spacing: dynamicTypeSize.isAccessibilitySize ? AppTheme.spacing8 : AppTheme.spacing12) {
                if !dynamicTypeSize.isAccessibilitySize {
                    Label(L10n.string("Meal and portions", defaultValue: "Meal and portions"), systemImage: "fork.knife")
                        .appHeadingFont(.headline, weight: .regular)
                        .foregroundStyle(AppTheme.primaryText)
                }

                TextField(
                    L10n.string("Meal name", defaultValue: "Meal name"),
                    text: $viewModel.mealName
                )
                .textFieldStyle(.plain)
                .padding(dynamicTypeSize.isAccessibilitySize ? AppTheme.spacing8 : AppTheme.spacing12)
                .background(AppTheme.premiumEditorRaisedSurface.opacity(0.75))
                .clipShape(RoundedRectangle(cornerRadius: AppTheme.cornerRadiusSmall, style: .continuous))
                .accessibilityIdentifier("meal_scan.meal_name")

                ForEach(viewModel.draftItems) { item in
                    VStack(alignment: .leading, spacing: dynamicTypeSize.isAccessibilitySize ? AppTheme.spacing4 : AppTheme.spacing8) {
                        HStack(spacing: AppTheme.spacing8) {
                            NavigationLink {
                                MealFoodItemEditView(initialItem: item, viewModel: viewModel) { updated in
                                    viewModel.replaceItem(updated)
                                }
                            } label: {
                                MealScanFoodItemRow(item: item)
                                    .frame(maxWidth: .infinity, minHeight: 44, alignment: .leading)
                                    .contentShape(Rectangle())
                            }
                            .buttonStyle(.plain)
                            .accessibilityHint(L10n.string(
                                "Double tap to edit this food or enter an exact portion.",
                                defaultValue: "Double tap to edit this food or enter an exact portion."
                            ))
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

                        HStack(spacing: AppTheme.spacing12) {
                            portionButton(
                                systemImage: "minus",
                                label: L10n.format(
                                    "Decrease %@ portion",
                                    defaultValue: "Decrease %@ portion",
                                    item.displayName
                                ),
                                value: item.estimatedGrams
                            ) {
                                viewModel.adjustPortion(id: item.id, byGrams: -25)
                            }

                            Text(dynamicTypeSize.isAccessibilitySize
                                ? "\(MealNutritionCalculator.displayMacro(item.estimatedGrams)) g"
                                : L10n.format(
                                    "%@ grams",
                                    defaultValue: "%@ grams",
                                    MealNutritionCalculator.displayMacro(item.estimatedGrams)
                                ))
                            .appFont(.subheadline, weight: .semibold)
                            .foregroundStyle(AppTheme.primaryText)
                            .frame(maxWidth: .infinity)
                            .accessibilityIdentifier("meal_scan.portion.value")

                            portionButton(
                                systemImage: "plus",
                                label: L10n.format(
                                    "Increase %@ portion",
                                    defaultValue: "Increase %@ portion",
                                    item.displayName
                                ),
                                value: item.estimatedGrams
                            ) {
                                viewModel.adjustPortion(id: item.id, byGrams: 25)
                            }
                        }
                    }
                    .padding(dynamicTypeSize.isAccessibilitySize ? AppTheme.spacing8 : AppTheme.spacing12)
                    .background(AppTheme.premiumEditorSurface.opacity(0.54))
                    .clipShape(RoundedRectangle(cornerRadius: AppTheme.cornerRadiusMedium, style: .continuous))
                }

                NavigationLink {
                    MealFoodItemEditView(initialItem: viewModel.newManualFoodDraft(), viewModel: viewModel) { newItem in
                        viewModel.appendItem(newItem)
                    }
                } label: {
                    Label(L10n.string("Add food", defaultValue: "Add food"), systemImage: "plus")
                        .frame(maxWidth: .infinity, minHeight: 44)
                }
                .buttonStyle(.bordered)
                .accessibilityIdentifier("meal_scan.add_food")
            }
            .padding(dynamicTypeSize.isAccessibilitySize ? AppTheme.spacing8 : AppTheme.spacing16)
            .mealScanCard()

            VStack(alignment: .leading, spacing: AppTheme.spacing12) {
                Label(L10n.string("Nutrition estimate", defaultValue: "Nutrition estimate"), systemImage: "chart.bar")
                    .appHeadingFont(.headline, weight: .regular)
                    .foregroundStyle(AppTheme.primaryText)
                MealNutritionSummaryView(nutrition: viewModel.totalNutrition, mode: .core)
                    .accessibilityElement(children: .ignore)
                    .accessibilityLabel(MealNutritionSummaryView.accessibilityLabel(
                        for: viewModel.totalNutrition,
                        mode: .core
                    ))
                    .accessibilityIdentifier("meal_scan.core_nutrition")
            }
            .padding(AppTheme.spacing16)
            .mealScanCard()

            DisclosureGroup(isExpanded: $isShowingMoreDetails) {
                VStack(alignment: .leading, spacing: AppTheme.spacing16) {
                    MealNutritionSummaryView(nutrition: viewModel.totalNutrition, mode: .advanced)

                    Label(
                        L10n.format(
                            "Confidence: %@",
                            defaultValue: "Confidence: %@",
                            viewModel.confidence.displayName
                        ),
                        systemImage: "checkmark.seal"
                    )
                    .appFont(.subheadline, weight: .semibold)

                    Picker(
                        L10n.string(
                            "Oil, butter, dressing, or sauce",
                            defaultValue: "Oil, butter, dressing, or sauce"
                        ),
                        selection: $viewModel.hiddenIngredientEstimate
                    ) {
                        ForEach(HiddenIngredientEstimate.allCases) { estimate in
                            Text(estimate.displayName).tag(estimate)
                        }
                    }
                    .pickerStyle(.menu)
                    .onChange(of: viewModel.hiddenIngredientEstimate) { _, value in
                        viewModel.applyHiddenIngredientEstimate(value)
                    }

                    if let profile = viewModel.metabolicProfile {
                        VStack(alignment: .leading, spacing: AppTheme.spacing4) {
                            Text(L10n.format(
                                "Estimated glycemic context: %@",
                                defaultValue: "Estimated glycemic context: %@",
                                profile.estimatedGlycemicImpact.displayName
                            ))
                            .appFont(.subheadline, weight: .semibold)
                            Text(profile.explanation)
                                .appFont(.caption)
                                .foregroundStyle(AppTheme.secondaryText)
                        }
                    }

                    quotaDetails

                    if !reviewWarnings.isEmpty {
                        VStack(alignment: .leading, spacing: AppTheme.spacing4) {
                            Text(L10n.string("Estimate notes", defaultValue: "Estimate notes"))
                                .appFont(.subheadline, weight: .semibold)
                            ForEach(reviewWarnings, id: \.self) { warning in
                                Text(warning)
                                    .appFont(.caption)
                                    .foregroundStyle(AppTheme.mealScannerErrorText)
                            }
                        }
                    }

                    Text(L10n.string(
                        "Review and edit before saving. Nutrition and glycemic context are estimates, not a diagnosis or medical advice.",
                        defaultValue: "Review and edit before saving. Nutrition and glycemic context are estimates, not a diagnosis or medical advice."
                    ))
                    .appFont(.caption)
                    .foregroundStyle(AppTheme.secondaryText)
                }
                .padding(.top, AppTheme.spacing12)
            } label: {
                Label(L10n.string("More details", defaultValue: "More details"), systemImage: "ellipsis.circle")
                    .appHeadingFont(.headline, weight: .regular)
            }
            .tint(AppTheme.mealScannerActionBackground)
            .padding(AppTheme.spacing16)
            .mealScanCard()
            .accessibilityIdentifier("meal_scan.more_details")

            Button {
                viewModel.retake()
            } label: {
                Label(L10n.string("Retake", defaultValue: "Retake"), systemImage: "arrow.clockwise")
                    .frame(maxWidth: .infinity, minHeight: 44)
            }
            .buttonStyle(.bordered)
            .accessibilityHint(L10n.string(
                "Returns to photo choices without saving this estimate.",
                defaultValue: "Returns to photo choices without saving this estimate."
            ))
            .accessibilityIdentifier("meal_scan.retake_photo_button")
        }
        .accessibilityElement(children: .contain)
        .accessibilityIdentifier("meal_scan.review")
    }

    private func portionButton(
        systemImage: String,
        label: String,
        value: Double,
        action: @escaping () -> Void
    ) -> some View {
        Button(action: action) {
            Image(systemName: systemImage)
                .frame(width: 44, height: 44)
        }
        .buttonStyle(.bordered)
        .accessibilityLabel(label)
        .accessibilityValue(L10n.format(
            "%@ grams",
            defaultValue: "%@ grams",
            MealNutritionCalculator.displayMacro(value)
        ))
        .accessibilityHint(L10n.string(
            "Changes the portion by 25 grams.",
            defaultValue: "Changes the portion by 25 grams."
        ))
        .accessibilityIdentifier(systemImage == "minus" ? "meal_scan.portion.decrease" : "meal_scan.portion.increase")
    }

    private var reviewWarnings: [String] {
        var seen = Set<String>()
        return (viewModel.warnings + viewModel.draftItems.compactMap(\.warning)).compactMap { warning in
            let trimmed = warning.trimmingCharacters(in: .whitespacesAndNewlines)
            guard !trimmed.isEmpty, seen.insert(trimmed).inserted else { return nil }
            return trimmed
        }
    }

    @ViewBuilder
    private var quotaDetails: some View {
        if let disposition = viewModel.mealScanCacheDisposition {
            if disposition == .fresh, let quota = viewModel.mealScanQuota {
                Text(L10n.format(
                    "%lld of %lld scans remain in the current rolling window.",
                    defaultValue: "%lld of %lld scans remain in the current rolling window.",
                    Int64(quota.remaining),
                    Int64(quota.limit)
                ))
                .appFont(.caption)
                .foregroundStyle(AppTheme.secondaryText)
            } else {
                Text(L10n.string(
                    "This estimate was reused from cache. No scan was used.",
                    defaultValue: "This estimate was reused from cache. No scan was used."
                ))
                .appFont(.caption)
                .foregroundStyle(AppTheme.secondaryText)
            }
        }
    }
}

struct MealScanReviewActionPanel: View {
    let viewModel: MealScanViewModel
    @State private var isSaving = false
    @AccessibilityFocusState private var isSaveErrorFocused: Bool
    @Environment(\.dynamicTypeSize) private var dynamicTypeSize

    var body: some View {
        VStack(spacing: AppTheme.spacing8) {
            if viewModel.failure?.kind == .saveFailed {
                VStack(alignment: .leading, spacing: AppTheme.spacing4) {
                    Label(
                        L10n.string(
                            "Your edits are still here. Try saving again.",
                            defaultValue: "Your edits are still here. Try saving again."
                        ),
                        systemImage: "exclamationmark.triangle.fill"
                    )
                    .appFont(.caption, weight: .semibold)
                    .foregroundStyle(AppTheme.mealScannerErrorText)
                    .accessibilityFocused($isSaveErrorFocused)
                    .accessibilityIdentifier("meal_scan.save_error")

                    Text(consumptionStatus)
                        .appFont(.caption)
                        .foregroundStyle(AppTheme.mealScannerBodyText)
                }
                .frame(maxWidth: .infinity, alignment: .leading)
            } else if let validationMessage = viewModel.saveValidationMessage {
                Text(validationMessage)
                    .appFont(.caption, weight: .semibold)
                    .foregroundStyle(AppTheme.mealScannerErrorText)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .accessibilityIdentifier("meal_scan.save_validation")
            }

            Button {
                isSaving = true
                Task {
                    defer { isSaving = false }
                    try? await viewModel.save()
                }
            } label: {
                Label(
                    viewModel.failure?.kind == .saveFailed
                        ? L10n.string("Try saving again", defaultValue: "Try saving again")
                        : L10n.string("Save meal", defaultValue: "Save meal"),
                    systemImage: "checkmark.circle.fill"
                )
                .appFont(dynamicTypeSize.isAccessibilitySize ? .caption : .body, weight: .semibold)
                .frame(maxWidth: .infinity, minHeight: 44)
            }
            .mealScanPrimaryActionStyle()
            .disabled(isSaving || !viewModel.canSaveMeal)
            .accessibilityHint(L10n.string(
                "Saves the edited meal estimate to your meal log.",
                defaultValue: "Saves the edited meal estimate to your meal log."
            ))
            .accessibilityIdentifier("meal_scan.save_button")
        }
        .frame(maxWidth: .infinity)
        .padding(.horizontal, AppTheme.spacing16)
        .padding(.vertical, dynamicTypeSize.isAccessibilitySize ? AppTheme.spacing4 : AppTheme.spacing12)
        .background(AppTheme.premiumEditorBackground.opacity(0.98))
        .overlay(alignment: .top) {
            Rectangle()
                .fill(AppTheme.premiumEditorBorder.opacity(0.75))
                .frame(height: 1)
        }
        .accessibilityElement(children: .contain)
        .accessibilityIdentifier("meal_scan.save_action_panel")
        .task(id: viewModel.failureOccurrence) {
            guard viewModel.failure?.kind == .saveFailed else { return }
            isSaveErrorFocused = false
            await Task.yield()
            isSaveErrorFocused = true
        }
    }

    private var consumptionStatus: String {
        switch viewModel.failure?.consumption ?? viewModel.scanConsumption {
        case .notUsed:
            L10n.string("No scan was used.", defaultValue: "No scan was used.")
        case .used:
            L10n.string("A scan was used.", defaultValue: "A scan was used.")
        case .unknown:
            L10n.string("Scan status is still unknown.", defaultValue: "Scan status is still unknown.")
        }
    }
}

struct MealFoodItemEditView: View {
    private enum FocusedField: Hashable {
        case name
        case grams
    }

    @Environment(\.dismiss) private var dismiss
    let initialItem: MealFoodItemDraft
    let viewModel: MealScanViewModel
    let onSave: (MealFoodItemDraft) -> Void

    @State private var query: String
    @State private var gramsText: String
    @State private var selectedFood: FoodNutritionRecord?
    @State private var validationError: String?
    @FocusState private var focusedField: FocusedField?

    init(
        initialItem: MealFoodItemDraft,
        viewModel: MealScanViewModel,
        onSave: @escaping (MealFoodItemDraft) -> Void
    ) {
        self.initialItem = initialItem
        self.viewModel = viewModel
        self.onSave = onSave
        _query = State(initialValue: initialItem.displayName)
        _gramsText = State(initialValue: Self.formatGrams(initialItem.estimatedGrams, locale: .current))
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
                        .focused($focusedField, equals: .name)
                        .accessibilityIdentifier("meal_scan.edit_food.name")

                    TextField(L10n.string("Grams", defaultValue: "Grams"), text: $gramsText)
                        .keyboardType(.decimalPad)
                        .textFieldStyle(.plain)
                        .padding(AppTheme.spacing12)
                        .background(AppTheme.premiumEditorRaisedSurface.opacity(0.75))
                        .clipShape(RoundedRectangle(cornerRadius: AppTheme.cornerRadiusSmall, style: .continuous))
                        .focused($focusedField, equals: .grams)
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
                                        .foregroundStyle(AppTheme.mealScannerActionBackground)
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
                        .foregroundStyle(AppTheme.mealScannerErrorText)
                        .padding(AppTheme.spacing12)
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .mealScanCard()
                        .accessibilityLabel(validationError)
                        .accessibilityIdentifier("meal_scan.edit_food.validation_error")
                }

            }
        }
        .safeAreaInset(edge: .bottom, spacing: 0) {
            if focusedField == nil {
                Button(action: save) {
                    Label(L10n.string("Save", defaultValue: "Save"), systemImage: "checkmark.circle.fill")
                        .frame(maxWidth: .infinity, minHeight: 44)
                }
                .mealScanPrimaryActionStyle()
                .padding(.horizontal, AppTheme.spacing16)
                .padding(.vertical, AppTheme.spacing12)
                .background(AppTheme.premiumEditorBackground.opacity(0.98))
                .accessibilityIdentifier("meal_scan.edit_food.save")
            }
        }
        .toolbar {
            ToolbarItemGroup(placement: .keyboard) {
                if focusedField == .name {
                    Button(L10n.string("Next", defaultValue: "Next")) {
                        focusedField = .grams
                    }
                    .accessibilityIdentifier("meal_scan.keyboard.next")
                }
                Spacer()
                Button(L10n.string("Done", defaultValue: "Done")) {
                    focusedField = nil
                }
                .accessibilityIdentifier("meal_scan.keyboard.done")
            }
        }
        .accessibilityElement(children: .contain)
        .accessibilityIdentifier("screen.meal_scan.edit_food")
    }

    private func save() {
        let trimmedName = query.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmedName.isEmpty else {
            validationError = L10n.string("Enter a food name.", defaultValue: "Enter a food name.")
            return
        }
        guard let grams = Self.parseGrams(gramsText, locale: .current),
              grams.isFinite,
              grams > 0 else {
            validationError = L10n.string(
                "Enter a portion greater than 0 grams.",
                defaultValue: "Enter a portion greater than 0 grams."
            )
            return
        }
        let updatedItem: MealFoodItemDraft
        if let selectedFood {
            var item = viewModel.draftItem(for: selectedFood, grams: grams, existingID: initialItem.id)
            item = Self.editedItem(item, displayName: trimmedName, grams: grams)
            item.wasPortionAdjusted = initialItem.wasPortionAdjusted
            item.recordUserEdit(previousEstimatedGrams: initialItem.estimatedGrams)
            updatedItem = item
        } else {
            var item = Self.editedItem(initialItem, displayName: trimmedName, grams: grams)
            item.recordUserEdit(previousEstimatedGrams: initialItem.estimatedGrams)
            updatedItem = item
        }
        onSave(updatedItem)
        dismiss()
    }

    static func parseGrams(_ text: String, locale: Locale) -> Double? {
        gramsFormatter(locale: locale).number(
            from: text.trimmingCharacters(in: .whitespacesAndNewlines)
        )?.doubleValue
    }

    static func formatGrams(_ grams: Double, locale: Locale) -> String {
        gramsFormatter(locale: locale).string(from: NSNumber(value: grams)) ?? "\(grams)"
    }

    private static func gramsFormatter(locale: Locale) -> NumberFormatter {
        let formatter = NumberFormatter()
        formatter.locale = locale
        formatter.numberStyle = .decimal
        formatter.isLenient = false
        formatter.usesGroupingSeparator = false
        formatter.minimumFractionDigits = 0
        formatter.maximumFractionDigits = 1
        return formatter
    }

    static func editedItem(
        _ item: MealFoodItemDraft,
        displayName: String,
        grams: Double
    ) -> MealFoodItemDraft {
        var edited = item
        let priorGrams = item.estimatedGrams
        edited.displayName = displayName
        edited.estimatedGrams = grams
        if priorGrams.isFinite, priorGrams > 0, grams.isFinite, grams >= 0 {
            edited.nutrition = item.nutrition.scaled(by: grams / priorGrams)
        }
        return edited
    }
}

struct MealNutritionSummaryView: View {
    enum Mode {
        case core
        case advanced
        case all
    }

    let nutrition: NutritionSnapshot
    var mode: Mode = .all
    private let columns = [GridItem(.adaptive(minimum: 112), spacing: AppTheme.spacing8)]

    private struct NutrientMetric: Identifiable {
        let label: String
        let value: String
        var id: String { label }
    }

    var body: some View {
        LazyVGrid(columns: columns, alignment: .leading, spacing: AppTheme.spacing8) {
            ForEach(Self.metrics(for: nutrition, mode: mode)) { metric in
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

    static func accessibilityLabel(for nutrition: NutritionSnapshot, mode: Mode = .all) -> String {
        metrics(for: nutrition, mode: mode)
            .map { "\($0.label), \($0.value)" }
            .joined(separator: ", ")
    }

    private static func metrics(for nutrition: NutritionSnapshot, mode: Mode) -> [NutrientMetric] {
        let core = [
            NutrientMetric(
                label: L10n.string("Calories", defaultValue: "Calories"),
                value: "\(MealNutritionCalculator.displayCalories(nutrition.caloriesKcal)) kcal"
            ),
            NutrientMetric(
                label: L10n.string("Protein", defaultValue: "Protein"),
                value: "\(MealNutritionCalculator.displayMacro(nutrition.proteinGrams)) g"
            ),
            NutrientMetric(
                label: L10n.string("Carbs", defaultValue: "Carbs"),
                value: "\(MealNutritionCalculator.displayMacro(nutrition.carbsGrams)) g"
            ),
            NutrientMetric(
                label: L10n.string("Fat", defaultValue: "Fat"),
                value: "\(MealNutritionCalculator.displayMacro(nutrition.fatGrams)) g"
            ),
        ]

        let advanced = [
            NutrientMetric(
                label: L10n.string("Fiber", defaultValue: "Fiber"),
                value: "\(MealNutritionCalculator.displayMacro(nutrition.fiberGrams)) g"
            ),
            NutrientMetric(
                label: L10n.string("Net carbs", defaultValue: "Net carbs"),
                value: "\(MealNutritionCalculator.displayMacro(nutrition.netCarbsGrams)) g"
            ),
            NutrientMetric(
                label: L10n.string("Sugar", defaultValue: "Sugar"),
                value: "\(MealNutritionCalculator.displayMacro(nutrition.sugarGrams)) g"
            ),
            NutrientMetric(
                label: L10n.string("Sodium", defaultValue: "Sodium"),
                value: "\(MealNutritionCalculator.displaySodium(nutrition.sodiumMg)) mg"
            ),
        ]

        switch mode {
        case .core:
            return core
        case .advanced:
            return advanced
        case .all:
            return core + advanced
        }
    }
}

struct MealScanFoodItemRow: View {
    let item: MealFoodItemDraft
    @Environment(\.dynamicTypeSize) private var dynamicTypeSize

    var body: some View {
        HStack(spacing: AppTheme.spacing8) {
            VStack(alignment: .leading, spacing: AppTheme.spacing4) {
                Text(item.displayName)
                    .appFont(.subheadline, weight: .medium)
                if !dynamicTypeSize.isAccessibilitySize {
                    Text("\(MealNutritionCalculator.displayMacro(item.estimatedGrams)) g · \(MealNutritionCalculator.displayCalories(item.nutrition.caloriesKcal)) kcal")
                        .appFont(.caption)
                        .foregroundStyle(AppTheme.secondaryText)
                }
            }
            Spacer()
            if !dynamicTypeSize.isAccessibilitySize {
                Text(item.confidence.displayName)
                    .appFont(.caption2)
                    .foregroundStyle(AppTheme.secondaryText)
            }
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
        return context
    }
}

struct MealScanFailureView: View {
    let viewModel: MealScanViewModel
    let onChooseBarcode: () -> Void
    let onChooseManual: () -> Void
    @State private var isRetryingPhoto = false

    private var title: String {
        switch viewModel.failure?.kind {
        case .serviceDisabled:
            L10n.string("Scanner unavailable", defaultValue: "Scanner unavailable")
        case .offlineBeforeDispatch:
            L10n.string("You're offline", defaultValue: "You're offline")
        case .connectionInterruptedAfterDispatch:
            L10n.string("Connection interrupted", defaultValue: "Connection interrupted")
        case .appIntegrity:
            L10n.string("App verification needed", defaultValue: "App verification needed")
        case .entitlement:
            L10n.string("Check your subscription", defaultValue: "Check your subscription")
        case .quotaExhausted:
            L10n.string("Scan limit reached", defaultValue: "Scan limit reached")
        case .unreadableMeal:
            L10n.string("We couldn't read this meal", defaultValue: "We couldn't read this meal")
        case .ambiguousResult:
            L10n.string("We couldn't confirm the result", defaultValue: "We couldn't confirm the result")
        case .saveFailed:
            L10n.string("Meal not saved", defaultValue: "Meal not saved")
        case nil:
            L10n.string("Scanner unavailable", defaultValue: "Scanner unavailable")
        }
    }

    private var detail: String {
        Self.detail(for: viewModel.failure)
    }

    static func detail(for failure: MealScanFailure?) -> String {
        switch failure?.kind {
        case .serviceDisabled:
            L10n.string(
                "The CycleBalance AI scanner is unavailable right now. Enter the meal manually or scan a barcode.",
                defaultValue: "The CycleBalance AI scanner is unavailable right now. Enter the meal manually or scan a barcode."
            )
        case .offlineBeforeDispatch:
            L10n.string(
                "Reconnect, then try this same photo again. Your photo is still ready.",
                defaultValue: "Reconnect, then try this same photo again. Your photo is still ready."
            )
        case .connectionInterruptedAfterDispatch:
            L10n.string(
                "The connection was lost after the scan started. Check again before starting another scan.",
                defaultValue: "The connection was lost after the scan started. Check again before starting another scan."
            )
        case .appIntegrity:
            L10n.string(
                "Update CycleBalance if an update is available, reopen the app, then try this photo again.",
                defaultValue: "Update CycleBalance if an update is available, reopen the app, then try this photo again."
            )
        case .entitlement:
            L10n.string(
                "Check Subscription in Settings, then try this photo again, or enter the meal manually.",
                defaultValue: "Check Subscription in Settings, then try this photo again, or enter the meal manually."
            )
        case .quotaExhausted:
            L10n.string(
                "Your current scan allowance is used. Enter the meal manually or scan a barcode while it resets.",
                defaultValue: "Your current scan allowance is used. Enter the meal manually or scan a barcode while it resets."
            )
        case .unreadableMeal:
            L10n.string(
                "Try a brighter, closer photo with the whole plate visible, or enter the foods manually.",
                defaultValue: "Try a brighter, closer photo with the whole plate visible, or enter the foods manually."
            )
        case .ambiguousResult:
            if failure?.retryBehavior == .checkSameRequest {
                L10n.string(
                    "CycleBalance could not confidently identify the result. Check again, choose another photo, or enter it manually.",
                    defaultValue: "CycleBalance could not confidently identify the result. Check again, choose another photo, or enter it manually."
                )
            } else {
                L10n.string(
                    "We couldn't finish this estimate. Choose another photo or enter the meal manually.",
                    defaultValue: "We couldn't finish this estimate. Choose another photo or enter the meal manually."
                )
            }
        case .saveFailed:
            L10n.string(
                "Your edits are still available in Review. Try saving again.",
                defaultValue: "Your edits are still available in Review. Try saving again."
            )
        case nil:
            L10n.string(
                "Choose another photo, scan a barcode, or enter the meal manually.",
                defaultValue: "Choose another photo, scan a barcode, or enter the meal manually."
            )
        }
    }

    private var consumptionStatus: String {
        switch viewModel.failure?.consumption ?? .unknown {
        case .notUsed:
            L10n.string("No scan was used.", defaultValue: "No scan was used.")
        case .used:
            L10n.string("A scan was used.", defaultValue: "A scan was used.")
        case .unknown:
            L10n.string("Scan status is still unknown.", defaultValue: "Scan status is still unknown.")
        }
    }

    @ViewBuilder
    private var recoveryControl: some View {
        switch viewModel.failure?.retryBehavior {
        case .retrySameRequest:
            TimelineView(.periodic(from: .now, by: 1)) { context in
                let guidance = retryAvailabilityGuidance(at: context.date, for: .retrySameRequest)
                VStack(spacing: AppTheme.spacing4) {
                    Button {
                        isRetryingPhoto = true
                        Task {
                            defer { isRetryingPhoto = false }
                            try? await viewModel.retryPendingPhoto()
                        }
                    } label: {
                        Label(L10n.string("Try again", defaultValue: "Try again"), systemImage: "arrow.clockwise")
                            .frame(maxWidth: .infinity, minHeight: 44)
                    }
                    .mealScanPrimaryActionStyle()
                    .disabled(isRetryingPhoto || !viewModel.canRetryPendingPhoto(at: context.date))
                    .accessibilityHint(L10n.string(
                        "Retries this photo without starting a separate scan.",
                        defaultValue: "Retries this photo without starting a separate scan."
                    ))
                    .accessibilityValue(retryAvailabilityGuidance(at: context.date, for: .retrySameRequest))
                    .accessibilityIdentifier("meal_scan.failure.retry")

                    if !guidance.isEmpty {
                        Text(guidance)
                            .appFont(.caption)
                            .foregroundStyle(AppTheme.mealScannerBodyText)
                    }
                }
            }
        case .checkSameRequest:
            TimelineView(.periodic(from: .now, by: 1)) { context in
                let guidance = retryAvailabilityGuidance(at: context.date, for: .checkSameRequest)
                VStack(spacing: AppTheme.spacing4) {
                    Button {
                        isRetryingPhoto = true
                        Task {
                            defer { isRetryingPhoto = false }
                            try? await viewModel.retryAmbiguousOutcome()
                        }
                    } label: {
                        Label(L10n.string("Check again", defaultValue: "Check again"), systemImage: "arrow.clockwise")
                            .frame(maxWidth: .infinity, minHeight: 44)
                    }
                    .mealScanPrimaryActionStyle()
                    .disabled(isRetryingPhoto || !viewModel.canRetryAmbiguousOutcome(at: context.date))
                    .accessibilityHint(L10n.string(
                        "Checks the same scan without starting another one.",
                        defaultValue: "Checks the same scan without starting another one."
                    ))
                    .accessibilityValue(retryAvailabilityGuidance(at: context.date, for: .checkSameRequest))
                    .accessibilityIdentifier("meal_scan.failure.check_again")

                    if !guidance.isEmpty {
                        Text(guidance)
                            .appFont(.caption)
                            .foregroundStyle(AppTheme.mealScannerBodyText)
                    }
                }
            }
        case .some(.none), .some(.retrySave), nil:
            EmptyView()
        }
    }

    private func retryAvailabilityGuidance(
        at date: Date,
        for behavior: MealScanRetryBehavior
    ) -> String {
        let remainingSeconds: Int?
        let format: String
        switch behavior {
        case .retrySameRequest:
            remainingSeconds = viewModel.pendingPhotoRetryRemainingSeconds(at: date)
            format = L10n.string("Try again in %@.", defaultValue: "Try again in %@.")
        case .checkSameRequest:
            remainingSeconds = viewModel.pendingRetryRemainingSeconds(at: date)
            format = L10n.string("Check again in %@.", defaultValue: "Check again in %@.")
        case .none, .retrySave:
            return ""
        }
        guard let remainingSeconds, remainingSeconds > 0 else { return "" }

        let formatter = DateComponentsFormatter()
        formatter.allowedUnits = remainingSeconds >= 60 ? [.minute, .second] : [.second]
        formatter.unitsStyle = .full
        formatter.maximumUnitCount = 1
        let duration = formatter.string(from: TimeInterval(remainingSeconds)) ?? "\(remainingSeconds)"
        return String(format: format, locale: .current, duration)
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
            Text(detail)
            .appFont(.subheadline)
            .foregroundStyle(AppTheme.mealScannerBodyText)
            .multilineTextAlignment(.center)

            Text(consumptionStatus)
                .appFont(.caption, weight: .semibold)
                .foregroundStyle(AppTheme.mealScannerBodyText)
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

            recoveryControl

            if viewModel.failure?.retryBehavior == .checkSameRequest,
               viewModel.canStartFreshAnalysis {
                Button {
                    viewModel.requestNewAnalysisAfterAmbiguousOutcome()
                } label: {
                    Label(L10n.string("Start another scan", defaultValue: "Start another scan"), systemImage: "plus.circle")
                        .frame(maxWidth: .infinity, minHeight: 44)
                }
                .buttonStyle(.bordered)
                .accessibilityIdentifier("meal_scan.failure.start_another")
            }

            Button(action: onChooseManual) {
                Label(L10n.string("Enter manually", defaultValue: "Enter manually"), systemImage: "square.and.pencil")
                    .frame(maxWidth: .infinity, minHeight: 44)
            }
            .mealScanPrimaryActionStyle()
            .accessibilityIdentifier("meal_scan.failure.manual")

            Button(action: onChooseBarcode) {
                Label(L10n.string("Scan a barcode", defaultValue: "Scan a barcode"), systemImage: "barcode.viewfinder")
                    .frame(maxWidth: .infinity, minHeight: 44)
            }
            .buttonStyle(.bordered)
            .accessibilityIdentifier("meal_scan.failure.barcode")

            Button {
                viewModel.retake()
            } label: {
                Label(L10n.string("Choose another photo", defaultValue: "Choose another photo"), systemImage: "camera")
                    .frame(maxWidth: .infinity, minHeight: 44)
            }
            .buttonStyle(.bordered)
            .accessibilityIdentifier("meal_scan.failure.choose_photo")
        }
        .padding(AppTheme.spacing24)
        .mealScanCard()
        .accessibilityElement(children: .contain)
        .accessibilityIdentifier("meal_scan.failure")
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
                        .mealScanPrimaryActionStyle()
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
                .mealScanPrimaryActionStyle()
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
            .tint(AppTheme.mealScannerActionBackground)
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
                        .foregroundStyle(AppTheme.mealScannerActionBackground)
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
                .foregroundStyle(AppTheme.mealScannerActionBackground)
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
            .tint(AppTheme.mealScannerActionBackground)
            .frame(maxWidth: .infinity, minHeight: 160)
            .mealScanCard()
            .accessibilityLabel(L10n.string("Loading meal scanner", defaultValue: "Loading meal scanner"))
        .accessibilityIdentifier("meal_scan.lunar.loading")
    }
}

private extension View {
    func mealScanPrimaryActionStyle() -> some View {
        self.buttonStyle(.borderedProminent)
            .tint(AppTheme.mealScannerActionBackground)
            .foregroundStyle(AppTheme.mealScannerActionForeground)
    }

    func mealScanCard() -> some View {
        background(
            RoundedRectangle(cornerRadius: AppTheme.cornerRadiusLarge, style: .continuous)
                .fill(AppTheme.mealScannerSurface)
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
