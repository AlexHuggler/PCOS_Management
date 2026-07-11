import SwiftUI
import SwiftData
import PhotosUI
import AVFoundation

struct MealScanFlowView: View {
    @Environment(\.modelContext) private var modelContext
    @Environment(\.dismiss) private var dismiss
    let mealType: MealType

    @State private var viewModel: MealScanViewModel?

    var body: some View {
        NavigationStack {
            Group {
                if let viewModel {
                    switch viewModel.phase {
                    case .entry:
                        MealScanEntryView(viewModel: viewModel)
                    case .camera:
                        MealCameraView(viewModel: viewModel)
                    case .processing:
                        MealScanProcessingView()
                    case .repeatSuggestion:
                        MealScanProcessingView()
                    case .review:
                        MealScanReviewView(viewModel: viewModel)
                    case .manualFallback:
                        MealScanManualFallbackView(viewModel: viewModel)
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
}

struct MealScanEntryView: View {
    let viewModel: MealScanViewModel

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

                        Button {
                            viewModel.addManualFood(named: "Manual food")
                        } label: {
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

                        Button {
                            viewModel.addManualFood(named: "Manual food")
                        } label: {
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

    var body: some View {
        if AppTheme.usesPremiumEditorStyling {
            ZStack {
                BotanicalScreenBackground(style: .quiet)
                VStack(spacing: AppTheme.spacing16) {
                    Image(systemName: "fork.knife.circle.fill")
                        .font(.system(size: 46, weight: .semibold))
                        .foregroundStyle(AppTheme.premiumEditorAccentGradient)

                    VStack(spacing: AppTheme.spacing8) {
                        Text(L10n.string("No food confidently detected", defaultValue: "No food confidently detected"))
                            .appFont(.title3, weight: .semibold)
                            .foregroundStyle(AppTheme.primaryText)
                        Text(viewModel.errorMessage ?? L10n.string("You can retake the photo or add the meal manually.", defaultValue: "You can retake the photo or add the meal manually."))
                            .appFont(.subheadline)
                            .foregroundStyle(AppTheme.secondaryText)
                            .multilineTextAlignment(.center)
                    }

                    Button {
                        viewModel.addManualFood(named: "Manual food")
                    } label: {
                        Label(L10n.string("Add manually", defaultValue: "Add manually"), systemImage: "plus")
                            .frame(maxWidth: .infinity)
                    }
                    .buttonStyle(.borderedProminent)
                    .tint(AppTheme.premiumEditorAccentColor)

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
                    title: "No food confidently detected",
                    message: viewModel.errorMessage ?? "You can retake the photo or add the meal manually.",
                    systemImage: "fork.knife.circle"
                )
                Button {
                    viewModel.addManualFood(named: "Manual food")
                } label: {
                    Label("Add manually", systemImage: "plus")
                }
                .buttonStyle(.borderedProminent)
                .tint(AppTheme.sage)

                Button {
                    viewModel.retake()
                } label: {
                    Label("Retake photo", systemImage: "camera")
                }
            }
            .padding()
        }
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
