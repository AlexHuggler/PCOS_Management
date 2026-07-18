import Foundation
import ImageIO
import Testing
import UIKit
@testable import PCOS

@Suite("Meal Scan Release Contract", .serialized)
@MainActor
struct MealScanReleaseContractTests {
    private func source(at relativePath: String) throws -> String {
        let projectRoot = try TestHelpers.projectRoot(from: #filePath)
        return try String(
            contentsOf: projectRoot.appendingPathComponent(relativePath),
            encoding: .utf8
        )
    }

    private func sourceSlice(
        _ source: String,
        from startMarker: String,
        to endMarker: String
    ) throws -> Substring {
        guard let start = source.range(of: startMarker),
              let end = source.range(of: endMarker, range: start.upperBound..<source.endIndex) else {
            throw NSError(
                domain: "MealScanReleaseContractTests",
                code: 1,
                userInfo: [NSLocalizedDescriptionKey: "Unable to locate source slice from \(startMarker) to \(endMarker)."]
            )
        }
        return source[start.lowerBound..<end.lowerBound]
    }

    private func shareFixtureItems() -> [MealFoodItemDraft] {
        [
            MealFoodItemDraft(
                displayName: "Private chicken bowl",
                canonicalFoodId: "chicken",
                estimatedGrams: 125,
                nutrition: NutritionSnapshot(caloriesKcal: 280, proteinGrams: 32),
                confidence: .high,
                wasUserEdited: true,
                wasPortionAdjusted: true
            ),
            MealFoodItemDraft(
                displayName: "Private rice",
                canonicalFoodId: "rice",
                estimatedGrams: 140,
                nutrition: NutritionSnapshot(caloriesKcal: 180, carbsGrams: 40),
                confidence: .medium
            ),
        ]
    }

    @Test("Adjusted share count ignores name-only and unchanged edits")
    func adjustedShareCountUsesPortionSpecificTruth() {
        let nameOnlyEdit = MealFoodItemDraft(
            displayName: "Renamed bowl",
            canonicalFoodId: "bowl",
            estimatedGrams: 125,
            nutrition: NutritionSnapshot(caloriesKcal: 280),
            wasUserEdited: true
        )
        let unchangedSave = MealFoodItemDraft(
            displayName: "Rice",
            canonicalFoodId: "rice",
            estimatedGrams: 140,
            nutrition: NutritionSnapshot(caloriesKcal: 180),
            wasUserEdited: true,
            wasPortionAdjusted: false
        )
        let changedPortion = MealFoodItemDraft(
            displayName: "Greens",
            canonicalFoodId: "greens",
            estimatedGrams: 90,
            nutrition: NutritionSnapshot(caloriesKcal: 40),
            wasUserEdited: true,
            wasPortionAdjusted: true
        )

        let card = ScannerShareCard(
            items: [nameOnlyEdit, unchangedSave, changedPortion],
            nutrition: NutritionSnapshot(),
            sourcePhoto: nil
        )

        #expect(card.reviewedFoodCount == 3)
        #expect(card.adjustedPortionCount == 1)
    }

    @Test("Nutrition summary always announces Net carbs including zero")
    func nutritionSummaryAlwaysIncludesNetCarbs() {
        let label = MealNutritionSummaryView.accessibilityLabel(
            for: NutritionSnapshot(netCarbsGrams: 0)
        )

        #expect(label.contains("Net carbs, 0 g"))
    }

    @Test("Food rows expose one contextual VoiceOver label while warnings stay collapsed")
    func foodRowsUseOneContextualAccessibilityElement() throws {
        let item = MealFoodItemDraft(
            displayName: "Rice bowl",
            canonicalFoodId: "rice-bowl",
            estimatedGrams: 140,
            nutrition: NutritionSnapshot(caloriesKcal: 220),
            confidence: .medium,
            warning: "Sauce amount is uncertain."
        )
        let label = MealScanFoodItemRow.accessibilityLabel(for: item)
        let flowSource = try source(
            at: "PCOS/PCOS/Features/Meals/MealScan/Views/MealScanFlowView.swift"
        )
        let rowSource = try sourceSlice(
            flowSource,
            from: "struct MealScanFoodItemRow: View",
            to: "struct MealScanFailureView: View"
        )
        let reviewSource = try sourceSlice(
            flowSource,
            from: "struct MealScanReviewView: View",
            to: "struct MealFoodItemEditView: View"
        )

        #expect(label.localizedCaseInsensitiveContains("rice bowl"))
        #expect(label.contains("140"))
        #expect(label.contains("220"))
        #expect(label.localizedCaseInsensitiveContains("review suggested"))
        #expect(!label.localizedCaseInsensitiveContains("sauce amount is uncertain"))
        #expect(rowSource.contains(".accessibilityElement(children: .ignore)"))
        #expect(rowSource.contains(".accessibilityLabel(Self.accessibilityLabel(for: item))"))
        #expect(!reviewSource.contains(".accessibilityLabel(MealScanFoodItemRow.accessibilityLabel(for: item))"))
        #expect(reviewSource.contains("private var reviewWarnings: [String]"))
        #expect(reviewSource.contains("DisclosureGroup"))
    }

    @Test("Scanner semantic headings use the existing branded heading font")
    func scannerHeadingsUseAppHeadingFont() throws {
        let flowSource = try source(
            at: "PCOS/PCOS/Features/Meals/MealScan/Views/MealScanFlowView.swift"
        )
        let repeatSource = try source(
            at: "PCOS/PCOS/Features/Meals/MealScan/RepeatMeal/RepeatMealSuggestionView.swift"
        )
        let shellSource = try sourceSlice(
            flowSource,
            from: "struct MealScanPhaseShell<Content: View>: View",
            to: "struct MealScanRemoteConsentView: View"
        )
        let nutritionSource = try sourceSlice(
            flowSource,
            from: "struct MealNutritionSummaryView: View",
            to: "struct MealScanFoodItemRow: View"
        )

        #expect(shellSource.contains("dynamicTypeSize.isAccessibilitySize ? .caption2 : .title3"))
        #expect(flowSource.components(separatedBy: ".appHeadingFont(").count - 1 >= 16)
        #expect(repeatSource.components(separatedBy: ".appHeadingFont(").count - 1 >= 2)
        #expect(!nutritionSource.contains(".appHeadingFont("))
        #expect(nutritionSource.contains(".appFont(.subheadline, weight: .semibold)"))
    }

    @Test("Default scanner share card contains only privacy-safe reviewed counts and branding")
    func defaultScannerShareCardIsRedacted() {
        let card = ScannerShareCard(
            items: shareFixtureItems(),
            nutrition: NutritionSnapshot(
                caloriesKcal: 460,
                proteinGrams: 32,
                carbsGrams: 40,
                fiberGrams: 4,
                sugarGrams: 2,
                sodiumMg: 530
            ),
            sourcePhoto: UIImage(systemName: "fork.knife")
        )

        #expect(card.headline == "Photo estimate — reviewed by me")
        #expect(card.reviewedFoodCount == 2)
        #expect(card.adjustedPortionCount == 1)
        #expect(card.brandName == "CycleBalance")
        #expect(card.foodNames == nil)
        #expect(card.flattenedPhotoPNGData == nil)
        #expect(card.macros == nil)
        #expect(!card.visibleText.contains("Private chicken bowl"))
        #expect(!card.visibleText.contains("Private rice"))
        #expect(!card.visibleText.contains("460"))
        #expect(!card.visibleText.localizedCaseInsensitiveContains("calorie"))
        #expect(!card.visibleText.localizedCaseInsensitiveContains("glucose"))
        #expect(!card.visibleText.localizedCaseInsensitiveContains("symptom"))
        #expect(!card.visibleText.localizedCaseInsensitiveContains("cycle phase"))
        #expect(!card.visibleText.localizedCaseInsensitiveContains("Alex Huggler"))
        #expect(!card.visibleText.contains("2026-07-14"))
    }

    @Test("Scanner share card includes food photo and macros only after explicit opt in")
    func scannerShareCardOptionalFieldsRequireExplicitOptions() {
        let sourcePhoto = UIGraphicsImageRenderer(size: CGSize(width: 24, height: 24)).image { context in
            UIColor.systemGreen.setFill()
            context.fill(CGRect(origin: .zero, size: CGSize(width: 24, height: 24)))
        }
        let card = ScannerShareCard(
            items: shareFixtureItems(),
            nutrition: NutritionSnapshot(
                caloriesKcal: 460,
                proteinGrams: 32,
                carbsGrams: 40,
                fatGrams: 14
            ),
            sourcePhoto: sourcePhoto,
            options: ScannerShareCard.Options(
                includeFoodNames: true,
                includePhoto: true,
                includeMacros: true
            )
        )

        #expect(card.foodNames == ["Private chicken bowl", "Private rice"])
        #expect(card.flattenedPhotoPNGData?.starts(with: [0x89, 0x50, 0x4E, 0x47]) == true)
        #expect(card.macros == ScannerShareCard.Macros(proteinGrams: 32, carbsGrams: 40, fatGrams: 14))
        for privateValue in ["Alex Huggler", "2026-07-14", "symptom", "glucose", "cycle phase", "luteal"] {
            #expect(!card.visibleText.localizedCaseInsensitiveContains(privateValue))
        }
    }

    @Test("Flattened scanner share photo strips EXIF TIFF and GPS metadata")
    func flattenedScannerSharePhotoStripsMetadata() throws {
        let renderedPhoto = UIGraphicsImageRenderer(size: CGSize(width: 32, height: 32)).image { context in
            UIColor.systemPurple.setFill()
            context.fill(CGRect(origin: .zero, size: CGSize(width: 32, height: 32)))
        }
        let jpegData = NSMutableData()
        let destination = try #require(
            CGImageDestinationCreateWithData(jpegData, "public.jpeg" as CFString, 1, nil)
        )
        let sourceMetadata: [CFString: Any] = [
            kCGImagePropertyExifDictionary: [
                kCGImagePropertyExifUserComment: "PRIVATE_EXIF_MARKER",
                kCGImagePropertyExifDateTimeOriginal: "2026:07:14 12:34:56",
            ],
            kCGImagePropertyTIFFDictionary: [
                kCGImagePropertyTIFFMake: "PRIVATE_TIFF_MARKER",
                kCGImagePropertyTIFFModel: "PRIVATE_DEVICE",
            ],
            kCGImagePropertyGPSDictionary: [
                kCGImagePropertyGPSLatitude: 30.2672,
                kCGImagePropertyGPSLongitude: 97.7431,
            ],
        ]
        CGImageDestinationAddImage(
            destination,
            try #require(renderedPhoto.cgImage),
            sourceMetadata as CFDictionary
        )
        #expect(CGImageDestinationFinalize(destination))
        let sourcePhoto = try #require(UIImage(data: jpegData as Data))
        let card = ScannerShareCard(
            items: shareFixtureItems(),
            nutrition: NutritionSnapshot(),
            sourcePhoto: sourcePhoto,
            options: ScannerShareCard.Options(includePhoto: true)
        )
        let data = try #require(card.flattenedPhotoPNGData)
        let source = try #require(CGImageSourceCreateWithData(data as CFData, nil))
        let properties = try #require(CGImageSourceCopyPropertiesAtIndex(source, 0, nil) as NSDictionary?)
        let exif = properties[kCGImagePropertyExifDictionary] as? NSDictionary
        let tiff = properties[kCGImagePropertyTIFFDictionary] as? NSDictionary
        let gps = properties[kCGImagePropertyGPSDictionary] as? NSDictionary

        #expect(exif?[kCGImagePropertyExifUserComment] == nil)
        #expect(exif?[kCGImagePropertyExifDateTimeOriginal] == nil)
        #expect(tiff?[kCGImagePropertyTIFFMake] == nil)
        #expect(tiff?[kCGImagePropertyTIFFModel] == nil)
        #expect(gps == nil || gps?.count == 0)
        #expect(!String(describing: properties).contains("PRIVATE"))
    }

    @Test("Scanner share payload forms a campaign URL only with a validated provider token")
    func scannerShareCampaignURLFailsClosedWithoutProviderToken() {
        #expect(
            ScannerShareCard.campaignURL(providerToken: "123456789")?.absoluteString
                == "https://apps.apple.com/us/app/cyclebalance/id6760353511?pt=123456789&ct=meal_scan_share&mt=8"
        )
        #expect(ScannerShareCard.campaignURL(providerToken: nil) == nil)
        #expect(ScannerShareCard.campaignURL(providerToken: "not-a-provider-token") == nil)
        #expect(
            ScannerShareCard.destinationURL(providerToken: nil).absoluteString
                == "https://cyclebalance.app/meal-scan"
        )
    }

    @Test("Scanner share provider token is an optional non-secret build configuration")
    func scannerShareProviderTokenIsOptionalBuildConfiguration() throws {
        let debugPlist = try source(at: "PCOS/PCOS/Info.plist")
        let releasePlist = try source(at: "PCOS/PCOS/Info.Release.plist")
        let productionSetup = try source(at: "docs/meal_scan_flash_lite_production_setup.md")

        for plist in [debugPlist, releasePlist] {
            #expect(plist.contains("<key>APP_STORE_PROVIDER_TOKEN</key>"))
            #expect(plist.contains("<string>$(APP_STORE_PROVIDER_TOKEN)</string>"))
        }
        #expect(productionSetup.contains("APP_STORE_PROVIDER_TOKEN"))
        #expect(productionSetup.contains("https://cyclebalance.app/meal-scan"))
        #expect(productionSetup.localizedCaseInsensitiveContains("publication gate"))
    }

    @Test("Cancelling scanner sharing has no completed-share side effect")
    func scannerShareCancellationIsSideEffectFree() {
        let savedItems = shareFixtureItems()
        let savedItemsSnapshot = savedItems
        let savedNavigationPhase = "saved"
        var state = ScannerSharePresentationState()
        state.begin()
        state.finish(completed: false)

        #expect(!state.isPresented)
        #expect(state.completedShareCount == 0)
        #expect(savedItems == savedItemsSnapshot)
        #expect(savedNavigationPhase == "saved")
    }

    @Test("Share sheet cancellation cannot mutate the saved meal or scanner navigation")
    func shareSheetCancellationHasNoViewModelMutationPath() throws {
        let flowSource = try source(at: "PCOS/PCOS/Features/Meals/MealScan/Views/MealScanFlowView.swift")
        let composer = try sourceSlice(
            flowSource,
            from: "private struct ScannerShareComposerView",
            to: "private struct ScannerShareCardArtwork"
        )

        #expect(composer.contains("shareState.finish(completed: completed)"))
        #expect(!composer.contains("viewModel.phase ="))
        #expect(!composer.contains("viewModel.save("))
        #expect(!composer.contains("modelContext"))
    }

    @Test("Scanner phases share the branded shell and avoid generic Form layouts")
    func scannerPhasesUseSharedShellAndBrandedLayouts() throws {
        let flowSource = try source(at: "PCOS/PCOS/Features/Meals/MealScan/Views/MealScanFlowView.swift")
        let repeatSource = try source(at: "PCOS/PCOS/Features/Meals/MealScan/RepeatMeal/RepeatMealSuggestionView.swift")

        #expect(flowSource.contains("struct MealScanPhaseShell<Content: View>: View"))
        #expect(flowSource.contains("title: viewModel.phase.localizedTitle"))
        #expect(flowSource.contains(".accessibilityFocused($isHeadingFocused)"))
        #expect(flowSource.contains(".task(id: title)"))
        #expect(flowSource.contains("MealScanPhaseShell(\n            title: L10n.string(\"Edit food\""))

        let phaseRouter = try sourceSlice(
            flowSource,
            from: "private func phaseContent(for viewModel: MealScanViewModel)",
            to: "private func chooseBarcode()"
        )
        for phase in [
            ".photoChoice", ".processing", ".repeatSuggestion", ".remoteConsent",
            ".failure", ".review", ".saved",
        ] {
            #expect(phaseRouter.contains("case \(phase):"), "Shared scanner routing must cover \(phase).")
        }
        for obsoletePhase in [
            ".entry", ".camera", ".ambiguousOutcome", ".newAttemptConfirmation", ".manualFallback",
        ] {
            #expect(!phaseRouter.contains("case \(obsoletePhase):"), "Scanner routing must not retain \(obsoletePhase).")
        }

        let photoChoice = try sourceSlice(flowSource, from: "struct MealPhotoChoiceView", to: "struct MealScanProcessingView")
        let review = try sourceSlice(flowSource, from: "struct MealScanReviewView", to: "struct MealScanReviewActionPanel")
        let editor = try sourceSlice(flowSource, from: "struct MealFoodItemEditView", to: "struct MealNutritionSummaryView")
        #expect(!photoChoice.contains("Form {"))
        #expect(!review.contains("Form {"))
        #expect(!editor.contains("Form {"))
        #expect(review.contains("adjustPortion(id: item.id, byGrams: -25)"))
        #expect(review.contains("MealNutritionSummaryView(nutrition: viewModel.totalNutrition, mode: .core)"))
        #expect(review.contains("DisclosureGroup(isExpanded: $isShowingMoreDetails)"))
        #expect(review.contains("viewModel.newManualFoodDraft()"))
        #expect(!review.contains("mealBalanceScore"))
        #expect(!repeatSource.contains("BotanicalScreenBackground"), "Repeat content should inherit the shared shell.")

        for legacyView in [
            "struct MealScanEntryView: View",
            "private struct LegacyMealScanReviewView: View",
            "struct MealScanAmbiguousOutcomeView: View",
            "struct MealScanNewAttemptConfirmationView: View",
            "struct MealCameraView: View",
            "struct MealScanManualFallbackView: View",
        ] {
            #expect(!flowSource.contains(legacyView), "Dead legacy scanner view must be removed: \(legacyView).")
        }
    }

    @Test("Debug sample scan uses bundled meal artwork instead of an empty image")
    func debugSampleScanUsesBundledMealArtwork() throws {
        let viewModelSource = try source(
            at: "PCOS/PCOS/Features/Meals/MealScan/ViewModels/MealScanViewModel.swift"
        )

        #expect(viewModelSource.contains("UIImage(named: \"botanical-meal-bowl\")"))
        #expect(!viewModelSource.contains("await scanWithFallback(image: UIImage())"))
    }

    @Test("Scanner nutrient and food accessibility summaries include numeric values and units")
    func scannerAccessibilitySummariesIncludeValuesAndUnits() {
        let nutrition = NutritionSnapshot(
            caloriesKcal: 460,
            proteinGrams: 32,
            carbsGrams: 40,
            fiberGrams: 4,
            sugarGrams: 2,
            sodiumMg: 530
        )
        let nutrientLabel = MealNutritionSummaryView.accessibilityLabel(for: nutrition)
        let foodLabel = MealScanFoodItemRow.accessibilityLabel(for: shareFixtureItems()[0])

        for expected in ["32", "g", "4", "40", "2", "530", "mg"] {
            #expect(nutrientLabel.contains(expected), "Nutrient accessibility label must contain \(expected).")
        }
        for expected in ["Private chicken bowl", "125", "g", "280", "kcal", "Good estimate"] {
            #expect(foodLabel.contains(expected), "Food accessibility label must contain \(expected).")
        }
    }

    @Test("Scanner status and actions remain understandable without color")
    func scannerStatusAndActionsUseTextAndSymbolCues() throws {
        let flowSource = try source(at: "PCOS/PCOS/Features/Meals/MealScan/Views/MealScanFlowView.swift")
        let photoChoice = try sourceSlice(flowSource, from: "struct MealPhotoChoiceView", to: "struct MealScanProcessingView")
        let review = try sourceSlice(flowSource, from: "struct MealScanReviewView", to: "struct MealScanReviewActionPanel")
        let saved = try sourceSlice(flowSource, from: "struct MealScanSavedView", to: "private struct MealScanSavedMealDetailView")

        #expect(photoChoice.contains("cameraPermissionSystemImage"))
        #expect(photoChoice.contains("shouldShowCameraPermissionHelp"))
        for status in ["Camera needs attention", "The camera permission was denied.", "The camera is restricted on this device."] {
            #expect(photoChoice.contains(status))
        }
        #expect(review.contains("viewModel.confidence.displayName"))
        #expect(review.contains("Nutrition and glycemic context are estimates, not a diagnosis or medical advice."))
        for action in ["View Meal", "Add Context", "Share"] {
            #expect(saved.contains("L10n.string(\"\(action)\""))
        }
        #expect(saved.contains("systemImage:"))
    }

    @Test("Scanner-facing onboarding and paywall copy describes an editable draft without cycle-aware claims")
    func scannerCopyAvoidsUnsupportedCycleAwareNutritionClaim() throws {
        let onboardingSource = try source(at: "PCOS/PCOS/Features/Onboarding/Views/OnboardingMealScanDemoView.swift")
        let paywallSource = try source(at: "PCOS/PCOS/Core/StoreKit/PaywallView.swift")

        #expect(!onboardingSource.localizedCaseInsensitiveContains("Cycle note:"))
        #expect(!paywallSource.localizedCaseInsensitiveContains("cycle-aware nutrition"))
        #expect(onboardingSource.contains("Editable draft: check foods, portions, and hidden ingredients before saving."))
        #expect(paywallSource.contains("Turn meal photos into editable nutrition drafts you review before saving."))
    }

    @Test("Tracking Hub scanner fallbacks wait for dismissal and launch the requested meal flow")
    func trackingHubScannerFallbacksRouteThroughMealLog() throws {
        let contentSource = try source(at: "PCOS/PCOS/App/ContentView.swift")
        let mealLogSource = try source(at: "PCOS/PCOS/Features/Meals/Views/MealLogView.swift")

        #expect(contentSource.contains("@State private var pendingMealLogDestinationAfterScan: MealLogInitialDestination?"))
        #expect(contentSource.contains("@State private var activeMealLogDestination: MealLogInitialDestination = .form"))
        #expect(contentSource.contains("onDismiss: presentPendingMealLogDestinationAfterScan"))
        #expect(contentSource.contains("onDismiss: resetMealLogPresentationState"))
        #expect(contentSource.contains("routeMealScanFallback(to: .barcode)"))
        #expect(contentSource.contains("routeMealScanFallback(to: .form)"))
        #expect(contentSource.contains("initialDestination: activeMealLogDestination"))
        #expect(contentSource.contains("pendingMealLogDestinationAfterScan = nil"))
        #expect(contentSource.contains("onDismiss: (() -> Void)? = nil"))
        #expect(!contentSource.contains("MealScanFlowView(mealType: .lunch)"))

        #expect(mealLogSource.contains("enum MealLogInitialDestination: Sendable"))
        #expect(mealLogSource.contains("@State private var pendingInitialDestination: MealLogInitialDestination?"))
        #expect(mealLogSource.contains("_pendingInitialDestination = State(initialValue: initialDestination)"))
        #expect(mealLogSource.contains("consumeInitialDestinationIfNeeded()"))
        #expect(mealLogSource.contains("pendingInitialDestination = nil"))
        #expect(mealLogSource.contains("case .barcode:"))
        #expect(mealLogSource.contains("showingBarcodeImport = true"))
    }

    @Test("Saved meal Add Context routes by saved identity and never opens a blank meal form")
    func savedMealAddContextRoutesBySavedMealIdentity() throws {
        let contentSource = try source(at: "PCOS/PCOS/App/ContentView.swift")
        let mealLogSource = try source(at: "PCOS/PCOS/Features/Meals/Views/MealLogView.swift")
        let flowSource = try source(
            at: "PCOS/PCOS/Features/Meals/MealScan/Views/MealScanFlowView.swift"
        )
        let viewModelSource = try source(
            at: "PCOS/PCOS/Features/Meals/MealScan/ViewModels/MealScanViewModel.swift"
        )

        #expect(flowSource.contains("MealScanSavedContextView(viewModel: viewModel)"))
        #expect(flowSource.contains("guard viewModel.savedMealID != nil"))
        #expect(flowSource.contains("meal_scan.saved_context"))
        #expect(flowSource.contains("meal_scan.context.meal_name"))
        #expect(flowSource.contains("MealAfterMealContextEditor("))
        #expect(flowSource.contains("BloodSugarLogView(prefillContext: glucosePrefillContext)"))
        #expect(flowSource.contains("meal_scan.context.log_glucose"))
        #expect(viewModelSource.contains("private(set) var savedMealID: UUID?"))
        #expect(viewModelSource.contains("savedMealID = confirmedMeal.id"))
        #expect(viewModelSource.contains("func updateSavedMealContext("))
        #expect(viewModelSource.contains("func savedMealGlucosePrefillContext()"))
        #expect(viewModelSource.contains("L10n.format("))
        #expect(viewModelSource.contains("\"After %@\""))
        #expect(!viewModelSource.contains("mealContext: \"After \\(meal.mealDescription)\""))
        #expect(viewModelSource.contains("entry.id == targetMealID"))
        #expect(!contentSource.contains("routeMealScanFallback(to: .afterMealContext)"))
        #expect(!mealLogSource.contains("case afterMealContext"))
        #expect(mealLogSource.contains("struct MealAfterMealContextEditor: View"))
        #expect(mealLogSource.contains("focusNoteRequest: focusedField == .postMealNote"))
        #expect(mealLogSource.contains(".focused($isNoteFocused)"))
        #expect(mealLogSource.contains("onNoteFocusChanged"))
    }

    @Test("After-meal context intensity controls meet the minimum touch target")
    func afterMealContextIntensityControlsAreAtLeast44Points() throws {
        let mealLogSource = try source(
            at: "PCOS/PCOS/Features/Meals/Views/MealLogView.swift"
        )
        let editorSource = try sourceSlice(
            mealLogSource,
            from: "struct MealAfterMealContextEditor: View",
            to: "private extension View"
        )

        #expect(editorSource.contains(".frame(height: 44)"))
        #expect(!editorSource.contains(".frame(height: 38)"))
    }

    @Test("Release hard-locks similarity while Debug keeps the override seam")
    func releaseSimilarityGateIsHardLocked() throws {
        let flagsSource = try source(
            at: "PCOS/PCOS/Features/Meals/MealScan/MealScanFeatureFlags.swift"
        )

        #expect(flagsSource.contains(
            "enableSimilarMealSuggestions: releaseLockedFalseValue(key: \"mealScan.enableSimilarMealSuggestions\", launchArgument: \"enableSimilarMealSuggestions\", debugDefault: false)"
        ))
        #expect(!flagsSource.contains("enableSimilarMealSuggestions: boolValue("))
        #expect(flagsSource.contains("#if DEBUG\n        boolValue("))
        #expect(flagsSource.contains("#else\n        false\n#endif"))
    }

    @Test("Release reads only UI and Gemini gates from signed build-time booleans")
    func releaseBuildGatesAreSignedAndFailClosed() throws {
        let flagsSource = try source(
            at: "PCOS/PCOS/Features/Meals/MealScan/MealScanFeatureFlags.swift"
        )
        let projectSource = try source(at: "project.yml")
        let releasePlistSource = try source(at: "PCOS/PCOS/Info.Release.plist")
        let setupSource = try source(at: "docs/meal_scan_flash_lite_production_setup.md")

        #expect(projectSource.contains("MEAL_SCAN_RELEASE_UI_ENABLED: \"NO\""))
        #expect(projectSource.contains("MEAL_SCAN_RELEASE_GEMINI_ENABLED: \"NO\""))
        #expect(projectSource.contains("INFOPLIST_FILE: PCOS/PCOS/Info.Release.plist"))
        #expect(projectSource.contains("MEAL_SCAN_RELEASE_UI_ENABLED_$(MEAL_SCAN_RELEASE_UI_ENABLED)=1"))
        #expect(projectSource.contains("MEAL_SCAN_RELEASE_GEMINI_ENABLED_$(MEAL_SCAN_RELEASE_GEMINI_ENABLED)=1"))

        #expect(releasePlistSource.contains("<key>MealScanReleaseUIEnabled</key>"))
        #expect(releasePlistSource.contains("#if MEAL_SCAN_RELEASE_UI_ENABLED_YES"))
        #expect(releasePlistSource.contains("<key>MealScanReleaseGeminiEnabled</key>"))
        #expect(releasePlistSource.contains("#if MEAL_SCAN_RELEASE_GEMINI_ENABLED_YES"))
        #expect(releasePlistSource.contains("<true/>"))
        #expect(releasePlistSource.contains("<false/>"))

        #expect(flagsSource.contains(
            "enableMealScanV2: releaseBuildConfiguredValue(infoKey: releaseUIInfoKey"
        ))
        #expect(flagsSource.contains(
            "enableGeminiMealScan: releaseBuildConfiguredValue(infoKey: releaseGeminiInfoKey"
        ))

        for lockedFlag in [
            "enableMockMealScanData",
            "enableGeminiMealScanDebugDirect",
            "enableGeminiFallbackModel",
            "enableSimilarMealSuggestions",
        ] {
            #expect(
                flagsSource.contains("\(lockedFlag): releaseLockedFalseValue("),
                "\(lockedFlag) must remain hard-false in Release"
            )
        }

        #expect(MealScanFeatureFlags.releaseBuildBoolean(
            infoDictionary: ["Gate": true],
            key: "Gate"
        ))
        #expect(!MealScanFeatureFlags.releaseBuildBoolean(
            infoDictionary: ["Gate": false],
            key: "Gate"
        ))
        #expect(!MealScanFeatureFlags.releaseBuildBoolean(
            infoDictionary: ["Gate": "YES"],
            key: "Gate"
        ))
        #expect(!MealScanFeatureFlags.releaseBuildBoolean(infoDictionary: nil, key: "Gate"))

        #expect(setupSource.contains(
            "Change only `MEAL_SCAN_RELEASE_UI_ENABLED` and `MEAL_SCAN_RELEASE_GEMINI_ENABLED` from `NO` to `YES`"
        ))
        #expect(setupSource.contains(
            "Mock data, debug-direct transport, fallback-model routing, and visual similarity remain hard-disabled in Release"
        ))
    }
}
