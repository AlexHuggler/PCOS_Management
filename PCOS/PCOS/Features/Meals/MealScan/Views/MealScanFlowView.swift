import SwiftUI
import SwiftData
import PhotosUI
import AVFoundation

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
            Group {
                if let viewModel {
                    switch viewModel.phase {
                    case .entry:
                        MealScanEntryView(viewModel: viewModel, onChooseManual: chooseManual)
                    case .camera:
                        MealCameraView(viewModel: viewModel)
                    case .processing:
                        MealScanProcessingView()
                    case .repeatSuggestion:
                        if let suggestion = viewModel.repeatMealSuggestion {
                            RepeatMealSuggestionView(
                                suggestion: suggestion,
                                onUsePrevious: {
                                    viewModel.usePreviousMeal()
                                },
                                onScanAsNew: {
                                    Task {
                                        do {
                                            try await viewModel.scanPendingImageAsNew()
                                        } catch {
                                            viewModel.errorMessage = "No food was confidently detected. You can retake the photo or add the meal manually."
                                            viewModel.phase = .manualFallback
                                        }
                                    }
                                }
                            )
                        } else {
                            MealScanProcessingView()
                        }
                    case .remoteConsent:
                        MealScanRemoteConsentView(
                            viewModel: viewModel,
                            onChooseManual: chooseManual
                        )
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
                        MealScanSavedView()
                    }
                } else {
                    if AppTheme.usesPremiumEditorStyling {
                        LunarMealScanLoadingView()
                    } else {
                        ProgressView()
                    }
                }
            }
            .navigationTitle(AppTheme.usesPremiumEditorStyling ? "" : L10n.string("AI meal estimate", defaultValue: "AI meal estimate"))
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                if AppTheme.usesPremiumEditorStyling {
                    ToolbarItem(placement: .principal) {
                        Text(L10n.string("Meal estimate", defaultValue: "Meal estimate"))
                            .appFont(.headline, weight: .semibold)
                            .foregroundStyle(AppTheme.primaryText)
                    }
                }
                ToolbarItem(placement: .cancellationAction) {
                    Button(viewModel?.phase == .saved ? L10n.string("Done", defaultValue: "Done") : L10n.string("Close", defaultValue: "Close")) {
                        dismiss()
                    }
                }
            }
            .lunarMealScanNavigationBackground()
            .onAppear {
                if viewModel == nil {
                    viewModel = MealScanViewModel(mealType: mealType, modelContext: modelContext)
                }
            }
        }
        .accessibilityIdentifier("screen.meal_scan")
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

struct MealScanRemoteConsentView: View {
    let viewModel: MealScanViewModel
    let onChooseManual: () -> Void
    @State private var isSubmitting = false

    var body: some View {
        ZStack {
            BotanicalScreenBackground(style: AppTheme.usesPremiumEditorStyling ? .quiet : .dashboard)

            ScrollView {
                VStack(alignment: .leading, spacing: AppTheme.spacing20) {
                    if let image = viewModel.selectedImage {
                        Image(uiImage: image)
                            .resizable()
                            .scaledToFill()
                            .frame(maxWidth: .infinity)
                            .frame(height: 168)
                            .clipShape(RoundedRectangle(cornerRadius: AppTheme.cornerRadiusMedium, style: .continuous))
                            .accessibilityHidden(true)
                    }

                    VStack(alignment: .leading, spacing: AppTheme.spacing12) {
                        Label(
                            L10n.string("Photo estimate", defaultValue: "Photo estimate"),
                            systemImage: "lock.shield"
                        )
                        .appFont(.subheadline, weight: .semibold)
                        .foregroundStyle(AppTheme.premiumEditorAccentColor)

                        Text(L10n.string(
                            "Send this photo to Google Gemini?",
                            defaultValue: "Send this photo to Google Gemini?"
                        ))
                        .appFont(.title2, weight: .semibold)
                        .foregroundStyle(AppTheme.primaryText)
                        .fixedSize(horizontal: false, vertical: true)

                        Text(L10n.string(
                            "If this exact photo has not already been processed on this device, CycleBalance will send one compressed copy to Google Gemini to estimate foods, portions, and nutrients.",
                            defaultValue: "If this exact photo has not already been processed on this device, CycleBalance will send one compressed copy to Google Gemini to estimate foods, portions, and nutrients."
                        ))
                        .appFont(.body)
                        .foregroundStyle(AppTheme.secondaryText)
                        .fixedSize(horizontal: false, vertical: true)

                        Text(L10n.string(
                            "Google does not use paid API photos or responses to improve its products, but it may retain the photo and response for up to 55 days for abuse monitoring and legal or regulatory requirements. CycleBalance does not retain the uploaded photo on its server.",
                            defaultValue: "Google does not use paid API photos or responses to improve its products, but it may retain the photo and response for up to 55 days for abuse monitoring and legal or regulatory requirements. CycleBalance does not retain the uploaded photo on its server."
                        ))
                        .appFont(.caption)
                        .foregroundStyle(AppTheme.secondaryText)
                        .fixedSize(horizontal: false, vertical: true)

                        Text(L10n.string(
                            "You will review and edit the estimate before anything is added to your meal log.",
                            defaultValue: "You will review and edit the estimate before anything is added to your meal log."
                        ))
                        .appFont(.caption, weight: .medium)
                        .foregroundStyle(AppTheme.primaryText)
                        .fixedSize(horizontal: false, vertical: true)

                        Text(L10n.string(
                            "A structured estimate may be cached for up to 24 hours so the same request can be reused without another model call.",
                            defaultValue: "A structured estimate may be cached for up to 24 hours so the same request can be reused without another model call."
                        ))
                        .appFont(.caption)
                        .foregroundStyle(AppTheme.secondaryText)
                        .fixedSize(horizontal: false, vertical: true)

                        Text(L10n.string(
                            "The standard paid allowance is 10 fresh AI photo analyses in any rolling 24 hours. Trial, sandbox, or temporary service-safeguard limits may be lower. Cached results do not use a fresh analysis.",
                            defaultValue: "The standard paid allowance is 10 fresh AI photo analyses in any rolling 24 hours. Trial, sandbox, or temporary service-safeguard limits may be lower. Cached results do not use a fresh analysis."
                        ))
                        .appFont(.caption, weight: .medium)
                        .foregroundStyle(AppTheme.primaryText)
                        .fixedSize(horizontal: false, vertical: true)

                        if viewModel.mealScanQuota?.remaining == 0 {
                            Label(
                                L10n.string(
                                    "Your fresh AI photo allowance is used for the current rolling window. You can still check for an existing cached result; a cache miss will not dispatch a fresh model analysis.",
                                    defaultValue: "Your fresh AI photo allowance is used for the current rolling window. You can still check for an existing cached result; a cache miss will not dispatch a fresh model analysis."
                                ),
                                systemImage: "hourglass"
                            )
                            .appFont(.caption, weight: .semibold)
                            .foregroundStyle(.orange)
                            .fixedSize(horizontal: false, vertical: true)

                            if let resetText = viewModel.quotaResetAtLocalText {
                                Text(
                                    L10n.format(
                                        "Next rolling-window reset in your local time: %@.",
                                        defaultValue: "Next rolling-window reset in your local time: %@.",
                                        resetText
                                    )
                                )
                                    .appFont(.caption)
                                    .foregroundStyle(AppTheme.secondaryText)
                            }
                        }
                    }

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
                            .frame(maxWidth: .infinity)
                        }
                        .buttonStyle(.borderedProminent)
                        .tint(AppTheme.premiumEditorAccentColor)
                        .disabled(isSubmitting)
                        .accessibilityIdentifier("meal_scan.remote_consent.continue")

                        Button(action: onChooseManual) {
                            Label(
                                L10n.string("Enter Manually", defaultValue: "Enter Manually"),
                                systemImage: "square.and.pencil"
                            )
                            .frame(maxWidth: .infinity)
                        }
                        .buttonStyle(.bordered)
                        .tint(AppTheme.accentColor)
                        .disabled(isSubmitting)
                        .accessibilityIdentifier("meal_scan.remote_consent.manual")

                        Button {
                            viewModel.retake()
                        } label: {
                            Label(
                                L10n.string("Choose Another Photo", defaultValue: "Choose Another Photo"),
                                systemImage: "photo.on.rectangle"
                            )
                            .frame(maxWidth: .infinity)
                        }
                        .buttonStyle(.plain)
                        .foregroundStyle(AppTheme.secondaryText)
                        .disabled(isSubmitting)
                        .accessibilityIdentifier("meal_scan.remote_consent.retake")
                    }
                }
                .frame(maxWidth: 560, alignment: .leading)
                .padding(AppTheme.spacing20)
                .frame(maxWidth: .infinity)
            }
        }
        .accessibilityIdentifier("meal_scan.remote_consent")
    }
}

struct MealScanEntryView: View {
    let viewModel: MealScanViewModel
    let onChooseManual: () -> Void

    var body: some View {
        if AppTheme.usesPremiumEditorStyling {
            lunarEntryBody
        } else {
            standardEntryBody
        }
    }

    private var standardEntryBody: some View {
        ZStack {
            BotanicalScreenBackground()
            ScrollView {
                VStack(alignment: .leading, spacing: AppTheme.spacing20) {
                    BotanicalPosterHeader(
                        title: L10n.string("AI meal estimate", defaultValue: "AI meal estimate"),
                        subtitle: L10n.string(
                            "Snap a meal, review the estimated foods and portions, then save carbs, protein, fats, calories, and fiber to your CycleBalance log.",
                            defaultValue: "Snap a meal, review the estimated foods and portions, then save carbs, protein, fats, calories, and fiber to your CycleBalance log."
                        ),
                        dividerStyle: .ornamental
                    )

                    MealScanPrivacyNoticeView()

                    VStack(spacing: AppTheme.spacing12) {
                        Button {
                            viewModel.startScan()
                        } label: {
                            Label(L10n.string("Scan meal", defaultValue: "Scan meal"), systemImage: "camera.viewfinder")
                                .appFont(.headline)
                                .frame(maxWidth: .infinity)
                        }
                        .buttonStyle(.borderedProminent)
                        .tint(AppTheme.sage)
                        .accessibilityIdentifier("meal_scan.scan_button")
                        .accessibilityLabel("Scan meal")

                        Button(action: onChooseManual) {
                            Label(L10n.string("Enter manually", defaultValue: "Enter manually"), systemImage: "square.and.pencil")
                                .frame(maxWidth: .infinity)
                        }
                        .buttonStyle(.bordered)
                        .tint(AppTheme.accentColor)
                        .accessibilityIdentifier("meal_scan.manual_button")
                    }

                    Text(L10n.string(
                        "Nutrition values are estimates and can vary based on preparation, ingredients, and portion size. CycleBalance is not a medical device.",
                        defaultValue: "Nutrition values are estimates and can vary based on preparation, ingredients, and portion size. CycleBalance is not a medical device."
                    ))
                        .appFont(.caption)
                        .foregroundStyle(AppTheme.secondaryText)
                        .fixedSize(horizontal: false, vertical: true)
                }
                .padding()
            }
        }
    }

    private var lunarEntryBody: some View {
        ZStack {
            BotanicalScreenBackground(style: .quiet)

            ScrollView {
                VStack(alignment: .leading, spacing: AppTheme.spacing16) {
                    VStack(alignment: .leading, spacing: AppTheme.spacing16) {
                        HStack(alignment: .top, spacing: AppTheme.spacing12) {
                            VStack(alignment: .leading, spacing: AppTheme.spacing8) {
                                Text(L10n.string("Estimate meals gently", defaultValue: "Estimate meals gently"))
                                    .appFont(.largeTitle, weight: .semibold)
                                    .foregroundStyle(AppTheme.primaryText)
                                    .fixedSize(horizontal: false, vertical: true)

                                Text(L10n.string(
                                    "Start with a photo-based draft, then review every food and portion before anything is saved.",
                                    defaultValue: "Start with a photo-based draft, then review every food and portion before anything is saved."
                                ))
                                .appFont(.subheadline)
                                .foregroundStyle(AppTheme.secondaryText)
                                .fixedSize(horizontal: false, vertical: true)
                            }

                            Spacer(minLength: AppTheme.spacing8)

                            Image(systemName: "camera.viewfinder")
                                .font(.system(size: 22, weight: .semibold))
                                .foregroundStyle(AppTheme.premiumEditorCTAForeground)
                                .frame(width: 56, height: 56)
                                .background(Circle().fill(AppTheme.premiumEditorAccentGradient))
                                .shadow(color: AppTheme.premiumEditorSecondaryAccentColor.opacity(0.24), radius: 16, y: 8)
                        }

                        HStack(spacing: AppTheme.spacing8) {
                            lunarStepPill(title: L10n.string("Photo", defaultValue: "Photo"), systemImage: "camera.fill")
                            lunarStepPill(title: L10n.string("Review", defaultValue: "Review"), systemImage: "slider.horizontal.3")
                            lunarStepPill(title: L10n.string("Save", defaultValue: "Save"), systemImage: "checkmark.seal.fill")
                        }
                    }
                    .padding(AppTheme.spacing16)
                    .lunarMealScanCard()
                    .accessibilityElement(children: .contain)
                    .accessibilityIdentifier("meal_scan.lunar.header")

                    MealScanPrivacyNoticeView()

                    VStack(alignment: .leading, spacing: AppTheme.spacing12) {
                        Label(L10n.string("Choose a starting point", defaultValue: "Choose a starting point"), systemImage: "sparkles")
                            .appFont(.headline, weight: .semibold)
                            .foregroundStyle(AppTheme.primaryText)

                        Button {
                            viewModel.startScan()
                        } label: {
                            lunarActionRow(
                                title: L10n.string("Scan meal", defaultValue: "Scan meal"),
                                subtitle: L10n.string("Use the camera or import a photo", defaultValue: "Use the camera or import a photo"),
                                systemImage: "camera.viewfinder",
                                accent: AppTheme.premiumEditorAccentColor,
                                isPrimary: true
                            )
                        }
                        .buttonStyle(.plain)
                        .accessibilityIdentifier("meal_scan.scan_button")
                        .accessibilityLabel(L10n.string("Scan meal", defaultValue: "Scan meal"))

                        Button(action: onChooseManual) {
                            lunarActionRow(
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
                    .lunarMealScanCard()
                    .accessibilityElement(children: .contain)
                    .accessibilityIdentifier("meal_scan.lunar.actions")

                    Text(L10n.string(
                        "Nutrition values are estimates and can vary with preparation, ingredients, and portion size. Use them as a starting point, not a judgment.",
                        defaultValue: "Nutrition values are estimates and can vary with preparation, ingredients, and portion size. Use them as a starting point, not a judgment."
                    ))
                    .appFont(.caption)
                    .foregroundStyle(AppTheme.secondaryText)
                    .fixedSize(horizontal: false, vertical: true)
                    .padding(.horizontal, AppTheme.spacing4)
                }
                .padding(.horizontal, AppTheme.spacing16)
                .padding(.top, AppTheme.spacing12)
                .padding(.bottom, AppTheme.spacing24)
            }
        }
        .background(AppTheme.premiumEditorBackground)
        .accessibilityIdentifier("meal_scan.lunar.entry")
    }

    private func lunarStepPill(title: String, systemImage: String) -> some View {
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

    private func lunarActionRow(
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
    @State private var selectedPhotoItem: PhotosPickerItem?
    @State private var showingCamera = false
    @State private var cameraError: String?

    var body: some View {
        Form {
            Section {
                Text("Use good lighting, include the whole plate, and remember you can edit everything before saving.")
                    .appFont(.subheadline)
                    .foregroundStyle(.secondary)

                if appState.allowsPremiumAccess {
                    PhotosPicker(selection: $selectedPhotoItem, matching: .images) {
                        Label("Import meal photo", systemImage: "photo.on.rectangle")
                    }
                    .accessibilityIdentifier("meal_scan.import_photo_button")
                } else {
                    Button {
                        presentMealScanPaywall()
                    } label: {
                        Label("Import meal photo", systemImage: "photo.on.rectangle")
                    }
                    .accessibilityIdentifier("meal_scan.import_photo_button")
                }

                Button {
                    guard appState.allowsPremiumAccess else {
                        presentMealScanPaywall()
                        return
                    }
                    presentCamera()
                } label: {
                    Label("Take meal photo", systemImage: "camera")
                }
                .accessibilityIdentifier("meal_scan.take_photo_button")

                if MealScanFeatureFlags.current.enableMockMealScanData {
                    Button {
                        Task { await viewModel.useMockPhoto() }
                    } label: {
                        Label("Use sample meal", systemImage: "sparkles")
                    }
                    .accessibilityIdentifier("meal_scan.mock_photo_button")
                }

                if let cameraError {
                    Label(cameraError, systemImage: "exclamationmark.triangle.fill")
                        .appFont(.caption)
                        .foregroundStyle(.orange)
                }
            } header: {
                Text("Meal photo")
            } footer: {
                Text(MealScanPrivacyNoticeView.remoteAnalysisDisclosure)
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
                        return
                    }
                    await viewModel.scanWithFallback(image: image)
                } catch {
                    cameraError = "Could not import photo: \(error.localizedDescription)"
                }
            }
        }
    }

    private func presentMealScanPaywall() {
        cameraError = "Subscribe to unlock real photo estimates."
        appState.presentPremiumPaywall(reason: .mealScan)
    }

    private func presentCamera() {
        guard UIImagePickerController.isSourceTypeAvailable(.camera) else {
            cameraError = "Camera is unavailable on this device. You can import a meal photo instead."
            return
        }

        switch AVCaptureDevice.authorizationStatus(for: .video) {
        case .authorized:
            showingCamera = true
        case .notDetermined:
            AVCaptureDevice.requestAccess(for: .video) { granted in
                Task { @MainActor in
                    if granted {
                        showingCamera = true
                    } else {
                        cameraError = "Camera access is needed to take a meal photo. You can import a photo instead."
                    }
                }
            }
        default:
            cameraError = "Camera access is needed to take a meal photo. You can import a photo instead."
        }
    }
}

struct MealScanProcessingView: View {
    var body: some View {
        if AppTheme.usesPremiumEditorStyling {
            ZStack {
                BotanicalScreenBackground(style: .quiet)
                VStack(spacing: AppTheme.spacing16) {
                    ProgressView()
                        .controlSize(.large)
                        .tint(AppTheme.premiumEditorAccentColor)
                    Text(L10n.string("Estimating foods and portions...", defaultValue: "Estimating foods and portions..."))
                        .appFont(.headline, weight: .semibold)
                        .foregroundStyle(AppTheme.primaryText)
                    Text(L10n.string("You'll be able to edit everything before saving.", defaultValue: "You'll be able to edit everything before saving."))
                        .appFont(.subheadline)
                        .foregroundStyle(AppTheme.secondaryText)
                        .multilineTextAlignment(.center)
                }
                .padding(AppTheme.spacing24)
                .lunarMealScanCard()
                .padding(AppTheme.spacing16)
            }
            .background(AppTheme.premiumEditorBackground)
            .accessibilityIdentifier("meal_scan.lunar.processing")
        } else {
            VStack(spacing: AppTheme.spacing16) {
                ProgressView()
                    .controlSize(.large)
                Text("Estimating foods and portions...")
                    .appFont(.headline)
                Text("You'll be able to edit everything before saving.")
                    .appFont(.subheadline)
                    .foregroundStyle(.secondary)
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            .background(AppTheme.groupedBackground)
        }
    }
}

struct MealScanReviewView: View {
    @Bindable var viewModel: MealScanViewModel
    @State private var editingItem: MealFoodItemDraft?
    @State private var saveError: String?

    var body: some View {
        Form {
            Section {
                TextField("Meal name", text: $viewModel.mealName)
                    .accessibilityIdentifier("meal_scan.meal_name")

                MealNutritionSummaryView(nutrition: viewModel.totalNutrition)
                    .accessibilityElement(children: .combine)
                    .accessibilityLabel("Nutrient summary")

                if let profile = viewModel.metabolicProfile {
                    VStack(alignment: .leading, spacing: AppTheme.spacing8) {
                        Label(profile.estimatedGlycemicImpact.displayName, systemImage: "chart.line.uptrend.xyaxis")
                            .appFont(.subheadline, weight: .semibold)
                            .foregroundStyle(AppTheme.sage)
                        Text(profile.explanation)
                            .appFont(.caption)
                            .foregroundStyle(.secondary)
                        if let caution = profile.caution {
                            Text(caution)
                                .appFont(.caption2)
                                .foregroundStyle(.secondary)
                        }
                    }
                }

                Label(viewModel.confidence.displayName, systemImage: "checkmark.seal")
                    .accessibilityLabel("Confidence \(viewModel.confidence.displayName)")
            } header: {
                Text("Review estimate")
            }

            if let disposition = viewModel.mealScanCacheDisposition {
                Section {
                    if disposition == .fresh, let quota = viewModel.mealScanQuota {
                        Text(
                            L10n.format(
                                "%lld of %lld fresh AI photo analyses remain in your rolling 24-hour %@ allowance.",
                                defaultValue: "%lld of %lld fresh AI photo analyses remain in your rolling 24-hour %@ allowance.",
                                Int64(quota.remaining),
                                Int64(quota.limit),
                                quota.localizedTierDisplayName
                            )
                        )
                            .appFont(.subheadline, weight: .medium)

                        if let resetText = viewModel.quotaResetAtLocalText {
                            Text(
                                L10n.format(
                                    "This rolling window resets as earlier analyses age out; the next reset is shown in your local time: %@.",
                                    defaultValue: "This rolling window resets as earlier analyses age out; the next reset is shown in your local time: %@.",
                                    resetText
                                )
                            )
                                .appFont(.caption)
                                .foregroundStyle(.secondary)
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
                            .foregroundStyle(.orange)
                        }
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
                } header: {
                    Text(L10n.string("AI photo allowance", defaultValue: "AI photo allowance"))
                }
            }

            Section {
                Picker("Was this cooked with oil, butter, dressing, or sauce?", selection: $viewModel.hiddenIngredientEstimate) {
                    ForEach(HiddenIngredientEstimate.allCases) { estimate in
                        Text(estimate.displayName).tag(estimate)
                    }
                }
                .pickerStyle(.menu)
                .onChange(of: viewModel.hiddenIngredientEstimate) { _, newValue in
                    viewModel.applyHiddenIngredientEstimate(newValue)
                }
            } footer: {
                Text("Hidden oil, dressing, or sauces can change calories and fats, especially for restaurant meals and mixed dishes.")
            }

            Section {
                ForEach(viewModel.draftItems) { item in
                    Button {
                        editingItem = item
                    } label: {
                        MealScanFoodItemRow(item: item)
                    }
                    .buttonStyle(.plain)
                    .accessibilityLabel("Edit food item \(item.displayName)")
                }
                .onDelete { offsets in
                    for index in offsets {
                        viewModel.removeItem(id: viewModel.draftItems[index].id)
                    }
                }

                Button {
                    viewModel.addManualFood(named: "Added food")
                } label: {
                    Label("Add Food", systemImage: "plus")
                }
            } header: {
                Text("Foods")
            }

            if !viewModel.warnings.isEmpty {
                Section {
                    ForEach(viewModel.warnings, id: \.self) { warning in
                        Label(warning, systemImage: "exclamationmark.triangle")
                            .appFont(.caption)
                    }
                } header: {
                    Text("Estimate notes")
                }
            }

            Section {
                Button {
                    Task { await save() }
                } label: {
                    Label("Save Meal", systemImage: "checkmark.circle.fill")
                        .frame(maxWidth: .infinity)
                }
                .buttonStyle(.borderedProminent)
                .tint(AppTheme.sage)
                .accessibilityIdentifier("meal_scan.save_button")

                Button {
                    editingItem = viewModel.draftItems.first
                } label: {
                    Label("Edit Portions", systemImage: "slider.horizontal.3")
                }

                Button {
                    viewModel.retake()
                } label: {
                    Label("Retake Photo", systemImage: "arrow.clockwise")
                }
                .accessibilityIdentifier("meal_scan.retake_photo_button")

                if let saveError {
                    Label(saveError, systemImage: "exclamationmark.triangle.fill")
                        .appFont(.caption)
                        .foregroundStyle(.orange)
                }
            }
        }
        .sheet(item: $editingItem) { item in
            MealFoodItemEditView(initialItem: item, viewModel: viewModel) { updated in
                viewModel.replaceItem(updated)
                editingItem = nil
            }
        }
    }

    private func save() async {
        do {
            try await viewModel.save()
        } catch {
            saveError = "Could not save meal: \(error.localizedDescription)"
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
        NavigationStack {
            Form {
                Section {
                    TextField("Food name", text: $query)
                    TextField("Grams", text: $gramsText)
                        .keyboardType(.decimalPad)
                } header: {
                    Text("Portion")
                }

                Section {
                    ForEach(matches) { food in
                        Button {
                            selectedFood = food
                            query = food.displayName
                        } label: {
                            HStack {
                                VStack(alignment: .leading) {
                                    Text(food.displayName)
                                    if let serving = food.servingDescription {
                                        Text(serving)
                                            .appFont(.caption)
                                            .foregroundStyle(.secondary)
                                    }
                                }
                                Spacer()
                                if selectedFood?.id == food.id {
                                    Image(systemName: "checkmark")
                                }
                            }
                        }
                    }
                } header: {
                    Text("Local foods")
                }
            }
            .navigationTitle("Edit food")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") { dismiss() }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Save") {
                        save()
                    }
                }
            }
        }
    }

    private func save() {
        let grams = Double(gramsText) ?? initialItem.estimatedGrams
        if let selectedFood {
            onSave(viewModel.draftItem(for: selectedFood, grams: grams, existingID: initialItem.id))
        } else {
            var item = initialItem
            item.displayName = query
            item.estimatedGrams = grams
            item.wasUserEdited = true
            onSave(item)
        }
    }
}

struct MealNutritionSummaryView: View {
    let nutrition: NutritionSnapshot

    var body: some View {
        VStack(spacing: AppTheme.spacing12) {
            HStack {
                nutrient("Calories", MealNutritionCalculator.displayCalories(nutrition.caloriesKcal))
                nutrient("Carbs", "\(MealNutritionCalculator.displayMacro(nutrition.carbsGrams))g")
                nutrient("Protein", "\(MealNutritionCalculator.displayMacro(nutrition.proteinGrams))g")
                nutrient("Fat", "\(MealNutritionCalculator.displayMacro(nutrition.fatGrams))g")
            }
            HStack {
                nutrient("Fiber", "\(MealNutritionCalculator.displayMacro(nutrition.fiberGrams))g")
                nutrient("Sugar", "\(MealNutritionCalculator.displayMacro(nutrition.sugarGrams))g")
                nutrient("Sodium", "\(MealNutritionCalculator.displaySodium(nutrition.sodiumMg))mg")
                nutrient("Net carbs", "\(MealNutritionCalculator.displayMacro(nutrition.netCarbsGrams))g")
            }
        }
    }

    private func nutrient(_ label: String, _ value: String) -> some View {
        VStack(spacing: 2) {
            Text(value)
                .appFont(.caption, weight: .semibold)
            Text(label)
                .appFont(.caption2)
                .foregroundStyle(.secondary)
        }
        .frame(maxWidth: .infinity)
    }
}

private struct MealScanFoodItemRow: View {
    let item: MealFoodItemDraft

    var body: some View {
        HStack {
            VStack(alignment: .leading, spacing: AppTheme.spacing4) {
                Text(item.displayName)
                    .appFont(.subheadline, weight: .medium)
                Text("\(MealNutritionCalculator.displayMacro(item.estimatedGrams))g · \(MealNutritionCalculator.displayCalories(item.nutrition.caloriesKcal)) kcal")
                    .appFont(.caption)
                    .foregroundStyle(.secondary)
                if let warning = item.warning {
                    Text(warning)
                        .appFont(.caption2)
                        .foregroundStyle(.orange)
                }
            }
            Spacer()
            Text(item.confidence.displayName)
                .appFont(.caption2)
                .foregroundStyle(.secondary)
        }
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
        if AppTheme.usesPremiumEditorStyling {
            ZStack {
                BotanicalScreenBackground(style: .quiet)
                VStack(spacing: AppTheme.spacing16) {
                    Image(systemName: "fork.knife.circle.fill")
                        .font(.system(size: 46, weight: .semibold))
                        .foregroundStyle(AppTheme.premiumEditorAccentGradient)

                    VStack(spacing: AppTheme.spacing8) {
                        Text(title)
                            .appFont(.title3, weight: .semibold)
                            .foregroundStyle(AppTheme.primaryText)
                        Text(viewModel.errorMessage ?? L10n.string("You can retake the photo or add the meal manually.", defaultValue: "You can retake the photo or add the meal manually."))
                            .appFont(.subheadline)
                            .foregroundStyle(AppTheme.secondaryText)
                            .multilineTextAlignment(.center)

                        if viewModel.mealScanQuota?.remaining == 0,
                           let resetText = viewModel.quotaResetAtLocalText {
                            Text(
                                L10n.format(
                                    "Next rolling-window reset in your local time: %@.",
                                    defaultValue: "Next rolling-window reset in your local time: %@.",
                                    resetText
                                )
                            )
                                .appFont(.caption, weight: .medium)
                                .foregroundStyle(AppTheme.primaryText)
                                .multilineTextAlignment(.center)
                        }
                    }

                    retrySamePhotoControl

                    Button(action: onChooseManual) {
                        Label(L10n.string("Enter nutrition manually", defaultValue: "Enter nutrition manually"), systemImage: "square.and.pencil")
                            .frame(maxWidth: .infinity)
                    }
                    .buttonStyle(.borderedProminent)
                    .tint(AppTheme.premiumEditorAccentColor)

                    Button(action: onChooseBarcode) {
                        Label(L10n.string("Scan a barcode", defaultValue: "Scan a barcode"), systemImage: "barcode.viewfinder")
                            .frame(maxWidth: .infinity)
                    }
                    .buttonStyle(.bordered)
                    .tint(AppTheme.premiumEditorSecondaryAccentColor)
                    .accessibilityIdentifier("meal_scan.fallback.barcode")

                    Button {
                        viewModel.retake()
                    } label: {
                        Label(L10n.string("Retake photo", defaultValue: "Retake photo"), systemImage: "camera")
                            .frame(maxWidth: .infinity)
                    }
                    .buttonStyle(.bordered)
                    .tint(AppTheme.premiumEditorSecondaryAccentColor)
                }
                .padding(AppTheme.spacing24)
                .lunarMealScanCard()
                .padding(AppTheme.spacing16)
            }
            .background(AppTheme.premiumEditorBackground)
            .accessibilityIdentifier("meal_scan.lunar.manual_fallback")
        } else {
            VStack(spacing: AppTheme.spacing16) {
                AppEmptyStateView(
                    title: title,
                    message: viewModel.errorMessage ?? L10n.string("You can retake the photo or add the meal manually.", defaultValue: "You can retake the photo or add the meal manually."),
                    systemImage: "fork.knife.circle"
                )
                if viewModel.mealScanQuota?.remaining == 0,
                   let resetText = viewModel.quotaResetAtLocalText {
                    Text(
                        L10n.format(
                            "Next rolling-window reset in your local time: %@.",
                            defaultValue: "Next rolling-window reset in your local time: %@.",
                            resetText
                        )
                    )
                        .appFont(.caption, weight: .medium)
                        .multilineTextAlignment(.center)
                }
                retrySamePhotoControl
                Button(action: onChooseManual) {
                    Label(L10n.string("Enter nutrition manually", defaultValue: "Enter nutrition manually"), systemImage: "square.and.pencil")
                }
                .buttonStyle(.borderedProminent)
                .tint(AppTheme.sage)

                Button(action: onChooseBarcode) {
                    Label(L10n.string("Scan a barcode", defaultValue: "Scan a barcode"), systemImage: "barcode.viewfinder")
                }
                .buttonStyle(.bordered)
                .accessibilityIdentifier("meal_scan.fallback.barcode")

                Button {
                    viewModel.retake()
                } label: {
                    Label(L10n.string("Retake photo", defaultValue: "Retake photo"), systemImage: "camera")
                }
            }
            .padding()
        }
    }
}

struct MealScanAmbiguousOutcomeView: View {
    let viewModel: MealScanViewModel
    let onChooseBarcode: () -> Void
    let onChooseManual: () -> Void
    @State private var isChecking = false

    var body: some View {
        ZStack {
            BotanicalScreenBackground(style: AppTheme.usesPremiumEditorStyling ? .quiet : .dashboard)
            ScrollView {
                VStack(spacing: AppTheme.spacing16) {
                    Image(systemName: "questionmark.diamond.fill")
                        .font(.system(size: 46, weight: .semibold))
                        .foregroundStyle(.orange)

                    Text(viewModel.isRequestPending
                        ? L10n.string("Analysis still processing", defaultValue: "Analysis still processing")
                        : L10n.string("Analysis status unknown", defaultValue: "Analysis status unknown"))
                        .appFont(.title3, weight: .semibold)
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
                                .frame(maxWidth: .infinity)
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
                            .frame(maxWidth: .infinity)
                    }
                    .buttonStyle(.bordered)
                    .disabled(isChecking || !viewModel.canStartFreshAnalysis)
                    .accessibilityIdentifier("meal_scan.unknown.request_new")

                    Button(action: onChooseBarcode) {
                        Label(
                            L10n.string("Scan a barcode", defaultValue: "Scan a barcode"),
                            systemImage: "barcode.viewfinder"
                        )
                            .frame(maxWidth: .infinity)
                    }
                    .buttonStyle(.bordered)

                    Button(action: onChooseManual) {
                        Label(
                            L10n.string("Enter manually", defaultValue: "Enter manually"),
                            systemImage: "square.and.pencil"
                        )
                            .frame(maxWidth: .infinity)
                    }
                    .buttonStyle(.plain)
                }
                .padding(AppTheme.spacing24)
                .frame(maxWidth: 560)
            }
        }
        .accessibilityIdentifier("meal_scan.unknown_outcome")
    }
}

struct MealScanNewAttemptConfirmationView: View {
    let viewModel: MealScanViewModel
    let onChooseBarcode: () -> Void
    let onChooseManual: () -> Void
    @State private var isSubmitting = false

    var body: some View {
        ZStack {
            BotanicalScreenBackground(style: AppTheme.usesPremiumEditorStyling ? .quiet : .dashboard)
            VStack(spacing: AppTheme.spacing16) {
                Image(systemName: "exclamationmark.arrow.triangle.2.circlepath")
                    .font(.system(size: 42, weight: .semibold))
                    .foregroundStyle(.orange)

                Text(L10n.string("Start a separate analysis?", defaultValue: "Start a separate analysis?"))
                    .appFont(.title3, weight: .semibold)
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
                        .frame(maxWidth: .infinity)
                }
                .buttonStyle(.borderedProminent)
                .tint(.orange)
                .disabled(isSubmitting || !viewModel.canStartFreshAnalysis)
                .accessibilityIdentifier("meal_scan.unknown.confirm_new")

                Button(action: onChooseBarcode) {
                    Label(
                        L10n.string("Scan a barcode", defaultValue: "Scan a barcode"),
                        systemImage: "barcode.viewfinder"
                    )
                        .frame(maxWidth: .infinity)
                }
                .buttonStyle(.bordered)
                .disabled(isSubmitting)

                Button(action: onChooseManual) {
                    Label(
                        L10n.string("Enter manually", defaultValue: "Enter manually"),
                        systemImage: "square.and.pencil"
                    )
                        .frame(maxWidth: .infinity)
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
            .frame(maxWidth: 560)
        }
        .accessibilityIdentifier("meal_scan.new_attempt_confirmation")
    }
}

struct MealScanPrivacyNoticeView: View {
    static var remoteAnalysisDisclosure: String {
        L10n.string(
            "When you choose a photo estimate, a compressed copy is sent securely to our AI service for analysis. CycleBalance does not retain the uploaded photo on its server. By default, only nutrition you review and save is kept in your meal log; you can turn on Keep Saved Meal Photos in Settings to keep photos locally on this device.",
            defaultValue: "When you choose a photo estimate, a compressed copy is sent securely to our AI service for analysis. CycleBalance does not retain the uploaded photo on its server. By default, only nutrition you review and save is kept in your meal log; you can turn on Keep Saved Meal Photos in Settings to keep photos locally on this device."
        )
    }

    var body: some View {
        if AppTheme.usesPremiumEditorStyling {
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
            .lunarMealScanCard()
            .accessibilityElement(children: .combine)
            .accessibilityIdentifier("meal_scan.lunar.privacy")
        } else {
            VStack(alignment: .leading, spacing: AppTheme.spacing8) {
                Label("Private by design", systemImage: "lock.shield")
                    .appFont(.subheadline, weight: .semibold)
                    .foregroundStyle(AppTheme.sage)
                Text(Self.remoteAnalysisDisclosure)
                    .appFont(.caption)
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .cardStyle(cornerRadius: AppTheme.cornerRadiusMedium)
        }
    }
}

struct MealScanSavedView: View {
    var body: some View {
        if AppTheme.usesPremiumEditorStyling {
            ZStack {
                BotanicalScreenBackground(style: .quiet)
                VStack(spacing: AppTheme.spacing16) {
                    Image(systemName: "checkmark.seal.fill")
                        .font(.system(size: 46, weight: .semibold))
                        .foregroundStyle(AppTheme.premiumEditorAccentGradient)
                    Text(L10n.string("Meal saved", defaultValue: "Meal saved"))
                        .appFont(.title2, weight: .semibold)
                        .foregroundStyle(AppTheme.primaryText)
                    Text(L10n.string("Nutrition added to your CycleBalance log", defaultValue: "Nutrition added to your CycleBalance log"))
                        .appFont(.subheadline)
                        .foregroundStyle(AppTheme.secondaryText)
                        .multilineTextAlignment(.center)
                }
                .padding(AppTheme.spacing24)
                .lunarMealScanCard()
                .padding(AppTheme.spacing16)
            }
            .background(AppTheme.premiumEditorBackground)
            .accessibilityIdentifier("meal_scan.lunar.saved")
        } else {
            VStack(spacing: AppTheme.spacing16) {
                Image(systemName: "checkmark.seal.fill")
                    .appFont(.largeTitle)
                    .foregroundStyle(AppTheme.sage)
                Text("Meal saved")
                    .appFont(.title2, weight: .semibold)
                Text("Nutrition added to your CycleBalance log")
                    .appFont(.subheadline)
                    .foregroundStyle(.secondary)
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            .background(AppTheme.groupedBackground)
        }
    }
}

private struct LunarMealScanLoadingView: View {
    var body: some View {
        ZStack {
            BotanicalScreenBackground(style: .quiet)
            ProgressView()
                .controlSize(.large)
                .tint(AppTheme.premiumEditorAccentColor)
                .padding(AppTheme.spacing24)
                .lunarMealScanCard()
        }
        .background(AppTheme.premiumEditorBackground)
        .accessibilityIdentifier("meal_scan.lunar.loading")
    }
}

private extension View {
    @ViewBuilder
    func lunarMealScanNavigationBackground() -> some View {
        if AppTheme.usesPremiumEditorStyling {
            toolbarBackground(AppTheme.premiumEditorBackground, for: .navigationBar)
                .toolbarBackground(.visible, for: .navigationBar)
        } else {
            self
        }
    }

    func lunarMealScanCard() -> some View {
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
        ], inMemory: true)
}
