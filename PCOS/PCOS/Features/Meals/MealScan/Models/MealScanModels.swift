import Foundation
import CoreGraphics
import UIKit

enum MealScanFailureKind: CaseIterable, Equatable, Sendable {
    case serviceDisabled
    case offlineBeforeDispatch
    case connectionInterruptedAfterDispatch
    case appIntegrity
    case entitlement
    case quotaExhausted
    case unreadableMeal
    case ambiguousResult
    case saveFailed
}

enum MealScanConsumptionState: CaseIterable, Equatable, Sendable {
    case notUsed
    case used
    case unknown

    func preservingStrongestTruth(with other: Self) -> Self {
        if self == .used || other == .used {
            return .used
        }
        if self == .unknown || other == .unknown {
            return .unknown
        }
        return .notUsed
    }
}

enum MealScanFailureCause: CaseIterable, Equatable, Sendable {
    case featureDisabled
    case serviceControlUnavailable
    case budgetDispatchDisabled
    case offline
    case transportOutcomeUnknown
    case appIntegrityRejected
    case appIntegrityEvidenceUnavailable
    case entitlementRejected
    case entitlementEvidenceUnavailable
    case requestRateLimited
    case quotaExhausted
    case invalidImage
    case invalidRequest
    case idempotencyConflict
    case requestPending
    case serverOutcomeUnknown
    case providerResponseInvalid
    case providerRequestFailed
    case providerTimeout
    case providerDispatchOutcomeUnknown
    case saveFailed
    case unclassified
}

enum MealScanRetryBehavior: CaseIterable, Equatable, Sendable {
    case none
    case retrySameRequest
    case checkSameRequest
    case retrySave
}

enum MealScanRecovery: Equatable, Sendable {
    case none
    case retrySameRequest(afterSeconds: Int?)
    case checkSameRequest(afterSeconds: Int?)
    case retrySave

    var retryBehavior: MealScanRetryBehavior {
        switch self {
        case .none: .none
        case .retrySameRequest: .retrySameRequest
        case .checkSameRequest: .checkSameRequest
        case .retrySave: .retrySave
        }
    }

    var retryAfterSeconds: Int? {
        switch self {
        case .retrySameRequest(let afterSeconds), .checkSameRequest(let afterSeconds):
            afterSeconds
        case .none, .retrySave:
            nil
        }
    }

    init(retryBehavior: MealScanRetryBehavior, retryAfterSeconds: Int?) {
        switch retryBehavior {
        case .none:
            self = .none
        case .retrySameRequest:
            self = .retrySameRequest(afterSeconds: retryAfterSeconds)
        case .checkSameRequest:
            self = .checkSameRequest(afterSeconds: retryAfterSeconds)
        case .retrySave:
            self = .retrySave
        }
    }
}

enum MealScanAnalysisSource: CaseIterable, Equatable, Sendable {
    case exactPrevious
    case localCache
    case serverCache
    case fresh

    var consumption: MealScanConsumptionState {
        switch self {
        case .exactPrevious, .localCache, .serverCache:
            .notUsed
        case .fresh:
            .used
        }
    }
}

struct MealScanFailure: Error, Equatable, Sendable {
    var kind: MealScanFailureKind
    var cause: MealScanFailureCause
    var consumption: MealScanConsumptionState
    var recovery: MealScanRecovery
    var quota: MealScanQuota?
    var retryAfterSeconds: Int?

    var retryBehavior: MealScanRetryBehavior {
        recovery.retryBehavior
    }

    init(
        kind: MealScanFailureKind,
        cause: MealScanFailureCause = .unclassified,
        consumption: MealScanConsumptionState,
        recovery: MealScanRecovery,
        quota: MealScanQuota? = nil
    ) {
        self.kind = kind
        self.cause = cause
        self.consumption = consumption
        self.recovery = recovery
        self.quota = quota
        retryAfterSeconds = recovery.retryAfterSeconds ?? quota?.retryAfterSeconds
    }

    init(
        kind: MealScanFailureKind,
        cause: MealScanFailureCause = .unclassified,
        consumption: MealScanConsumptionState,
        retryBehavior: MealScanRetryBehavior,
        quota: MealScanQuota? = nil,
        retryAfterSeconds: Int? = nil
    ) {
        self.kind = kind
        self.cause = cause
        self.consumption = consumption
        recovery = MealScanRecovery(
            retryBehavior: retryBehavior,
            retryAfterSeconds: retryAfterSeconds
        )
        self.quota = quota
        self.retryAfterSeconds = retryAfterSeconds
    }
}

protocol MealScanFailureProviding: Error, Sendable {
    var mealScanFailure: MealScanFailure { get }
}

extension MealScanFailure: MealScanFailureProviding {
    var mealScanFailure: MealScanFailure { self }
}

enum NutritionDataSource: String, Codable, CaseIterable, Sendable {
    case usda
    case openFoodFacts
    case nutritionLabelOCR
    case userManual
    case appFixture
    case aiEstimate = "ai_estimate"
}

enum NutritionConfidence: String, Codable, CaseIterable, Sendable {
    case low
    case medium
    case high
    case unknown

    var score: Double {
        switch self {
        case .high: 0.9
        case .medium: 0.65
        case .low: 0.35
        case .unknown: 0.2
        }
    }

    var displayName: String {
        switch self {
        case .high: L10n.string("Good estimate", defaultValue: "Good estimate")
        case .medium: L10n.string("Review suggested", defaultValue: "Review suggested")
        case .low: L10n.string("Needs confirmation", defaultValue: "Needs confirmation")
        case .unknown: L10n.string("Manual estimate", defaultValue: "Manual estimate")
        }
    }

    var rank: Int {
        switch self {
        case .unknown: 0
        case .low: 1
        case .medium: 2
        case .high: 3
        }
    }

    func lowered(by steps: Int = 1) -> NutritionConfidence {
        let nextRank = max(0, rank - steps)
        return Self.allCases.first { $0.rank == nextRank } ?? .unknown
    }
}

enum HiddenIngredientEstimate: String, Codable, CaseIterable, Identifiable, Sendable {
    case no
    case aLittle
    case moderate
    case aLot
    case notSure

    var id: String { rawValue }

    var displayName: String {
        switch self {
        case .no: L10n.string("No", defaultValue: "No")
        case .aLittle: L10n.string("A little", defaultValue: "A little")
        case .moderate: L10n.string("Moderate", defaultValue: "Moderate")
        case .aLot: L10n.string("A lot", defaultValue: "A lot")
        case .notSure: L10n.string("Not sure", defaultValue: "Not sure")
        }
    }

    var addedOilGrams: Double {
        switch self {
        case .no: 0
        case .aLittle: 5
        case .moderate: 14
        case .aLot: 28
        case .notSure: 7
        }
    }
}

enum GlycemicImpactLevel: String, Codable, CaseIterable, Sendable {
    case low
    case moderate
    case moderateHigh
    case high
    case unknown

    var displayName: String {
        switch self {
        case .low: L10n.string("Low", defaultValue: "Low")
        case .moderate: L10n.string("Moderate", defaultValue: "Moderate")
        case .moderateHigh: L10n.string("Moderate-high", defaultValue: "Moderate-high")
        case .high: L10n.string("High", defaultValue: "High")
        case .unknown: L10n.string("Unknown", defaultValue: "Unknown")
        }
    }

    var mealEntryImpact: GlycemicImpact {
        switch self {
        case .low: .low
        case .moderate, .unknown: .medium
        case .moderateHigh, .high: .high
        }
    }
}

enum MealScanCarbLoadCategory: String, Codable, CaseIterable, Sendable {
    case low
    case moderate
    case high
    case veryHigh
}

enum MealScanAdequacy: String, Codable, CaseIterable, Sendable {
    case low
    case moderate
    case strong
}

enum MealScanFatLevel: String, Codable, CaseIterable, Sendable {
    case low
    case moderate
    case high
}

enum PortionEstimationMethod: String, Codable, CaseIterable, Sendable {
    case lidarDepth
    case monocularDepth
    case plateReference
    case servingSizeHeuristic
    case manualUserInput
    case mockFixture
}

enum FoodCategory: String, Codable, CaseIterable, Sendable {
    case cookedRice
    case pasta
    case chicken
    case beef
    case fish
    case eggs
    case yogurt
    case oatmeal
    case bread
    case fruit
    case vegetables
    case salad
    case beans
    case soup
    case sauce
    case oilDressing
    case mixedDish
}

struct NutritionSnapshot: Codable, Equatable, Sendable {
    var caloriesKcal: Double = 0
    var proteinGrams: Double = 0
    var carbsGrams: Double = 0
    var netCarbsGrams: Double = 0
    var fatGrams: Double = 0
    var fiberGrams: Double = 0
    var sugarGrams: Double = 0
    var sodiumMg: Double = 0
    var saturatedFatGrams: Double = 0
    var cholesterolMg: Double = 0
    var potassiumMg: Double = 0
    var calciumMg: Double = 0
    var ironMg: Double = 0

    init(
        caloriesKcal: Double = 0,
        proteinGrams: Double = 0,
        carbsGrams: Double = 0,
        netCarbsGrams: Double? = nil,
        fatGrams: Double = 0,
        fiberGrams: Double = 0,
        sugarGrams: Double = 0,
        sodiumMg: Double = 0,
        saturatedFatGrams: Double = 0,
        cholesterolMg: Double = 0,
        potassiumMg: Double = 0,
        calciumMg: Double = 0,
        ironMg: Double = 0
    ) {
        self.caloriesKcal = caloriesKcal
        self.proteinGrams = proteinGrams
        self.carbsGrams = carbsGrams
        self.netCarbsGrams = netCarbsGrams ?? max(carbsGrams - fiberGrams, 0)
        self.fatGrams = fatGrams
        self.fiberGrams = fiberGrams
        self.sugarGrams = sugarGrams
        self.sodiumMg = sodiumMg
        self.saturatedFatGrams = saturatedFatGrams
        self.cholesterolMg = cholesterolMg
        self.potassiumMg = potassiumMg
        self.calciumMg = calciumMg
        self.ironMg = ironMg
    }

    func adding(_ other: NutritionSnapshot) -> NutritionSnapshot {
        NutritionSnapshot(
            caloriesKcal: caloriesKcal + other.caloriesKcal,
            proteinGrams: proteinGrams + other.proteinGrams,
            carbsGrams: carbsGrams + other.carbsGrams,
            netCarbsGrams: netCarbsGrams + other.netCarbsGrams,
            fatGrams: fatGrams + other.fatGrams,
            fiberGrams: fiberGrams + other.fiberGrams,
            sugarGrams: sugarGrams + other.sugarGrams,
            sodiumMg: sodiumMg + other.sodiumMg,
            saturatedFatGrams: saturatedFatGrams + other.saturatedFatGrams,
            cholesterolMg: cholesterolMg + other.cholesterolMg,
            potassiumMg: potassiumMg + other.potassiumMg,
            calciumMg: calciumMg + other.calciumMg,
            ironMg: ironMg + other.ironMg
        )
    }

    func scaled(by factor: Double) -> NutritionSnapshot {
        guard factor.isFinite, factor >= 0 else { return self }
        return NutritionSnapshot(
            caloriesKcal: caloriesKcal * factor,
            proteinGrams: proteinGrams * factor,
            carbsGrams: carbsGrams * factor,
            netCarbsGrams: netCarbsGrams * factor,
            fatGrams: fatGrams * factor,
            fiberGrams: fiberGrams * factor,
            sugarGrams: sugarGrams * factor,
            sodiumMg: sodiumMg * factor,
            saturatedFatGrams: saturatedFatGrams * factor,
            cholesterolMg: cholesterolMg * factor,
            potassiumMg: potassiumMg * factor,
            calciumMg: calciumMg * factor,
            ironMg: ironMg * factor
        )
    }
}

struct FoodNutritionRecord: Codable, Equatable, Identifiable, Sendable {
    var id: String
    var source: NutritionDataSource
    var displayName: String
    var canonicalName: String
    var brandName: String? = nil
    var servingDescription: String? = nil
    var servingGrams: Double? = nil
    var caloriesPer100g: Double? = nil
    var proteinPer100g: Double? = nil
    var carbsPer100g: Double? = nil
    var fatPer100g: Double? = nil
    var fiberPer100g: Double? = nil
    var sugarPer100g: Double? = nil
    var addedSugarPer100g: Double? = nil
    var sodiumMgPer100g: Double? = nil
    var saturatedFatPer100g: Double? = nil
    var cholesterolMgPer100g: Double? = nil
    var potassiumMgPer100g: Double? = nil
    var calciumMgPer100g: Double? = nil
    var ironMgPer100g: Double? = nil
    var category: FoodCategory? = nil
    var aliases: [String] = []
}

struct FoodClassificationCandidate: Identifiable, Equatable, Sendable {
    var id: UUID = UUID()
    var label: String
    var canonicalFoodId: String?
    var confidence: Double
}

struct MealScanRect: Codable, Equatable, Sendable {
    var x: Double
    var y: Double
    var width: Double
    var height: Double

    init(_ rect: CGRect) {
        x = rect.origin.x
        y = rect.origin.y
        width = rect.width
        height = rect.height
    }

    var cgRect: CGRect {
        CGRect(x: x, y: y, width: width, height: height)
    }
}

struct FoodSegmentationResult: Identifiable, Equatable, Sendable {
    var id: UUID = UUID()
    var label: String
    var boundingBox: MealScanRect?
    var confidence: Double
    var maskIdentifier: String?
}

struct MealDepthData: Equatable, Sendable {
    var sourceDescription: String
}

struct PortionEstimate: Identifiable, Equatable, Sendable {
    var id: UUID { foodItemId }
    var foodItemId: UUID
    var estimatedGrams: Double?
    var estimatedVolumeMl: Double?
    var servingDescription: String?
    var method: PortionEstimationMethod
    var confidence: NutritionConfidence
    var warning: String?
}

struct DetectedFoodItem: Identifiable, Equatable, Codable, Sendable {
    var id: UUID = UUID()
    var displayName: String
    var canonicalFoodId: String
    var estimatedGrams: Double
    var estimatedVolumeMl: Double? = nil
    var servingDescription: String?
    var nutrition: NutritionSnapshot
    var confidence: NutritionConfidence
    var warning: String?
    var detectionSource: String = "mock_fixture"
    var portionEstimationMethod: PortionEstimationMethod = .mockFixture
    var isMixedDish: Bool = false
}

struct MealFoodItemDraft: Identifiable, Equatable, Codable, Sendable {
    var id: UUID = UUID()
    var displayName: String
    var canonicalFoodId: String
    var nutritionSource: NutritionDataSource = .appFixture
    var estimatedGrams: Double
    var estimatedVolumeMl: Double? = nil
    var servingDescription: String? = nil
    var nutrition: NutritionSnapshot = NutritionSnapshot()
    var confidence: NutritionConfidence = .medium
    var warning: String? = nil
    var detectionSource: String = "mock_fixture"
    var portionEstimationMethod: PortionEstimationMethod = .mockFixture
    var wasUserEdited: Bool = false
    /// Optional backing keeps older cached/backup JSON decodable while exposing
    /// a default-false Boolean to scanner and share-card code.
    private var persistedWasPortionAdjusted: Bool?
    var isMixedDish: Bool = false

    var wasPortionAdjusted: Bool {
        get { persistedWasPortionAdjusted == true }
        set { persistedWasPortionAdjusted = newValue ? true : nil }
    }

    init(
        id: UUID = UUID(),
        displayName: String,
        canonicalFoodId: String,
        nutritionSource: NutritionDataSource = .appFixture,
        estimatedGrams: Double,
        estimatedVolumeMl: Double? = nil,
        servingDescription: String? = nil,
        nutrition: NutritionSnapshot = NutritionSnapshot(),
        confidence: NutritionConfidence = .medium,
        warning: String? = nil,
        detectionSource: String = "mock_fixture",
        portionEstimationMethod: PortionEstimationMethod = .mockFixture,
        wasUserEdited: Bool = false,
        wasPortionAdjusted: Bool = false,
        isMixedDish: Bool = false
    ) {
        self.id = id
        self.displayName = displayName
        self.canonicalFoodId = canonicalFoodId
        self.nutritionSource = nutritionSource
        self.estimatedGrams = estimatedGrams
        self.estimatedVolumeMl = estimatedVolumeMl
        self.servingDescription = servingDescription
        self.nutrition = nutrition
        self.confidence = confidence
        self.warning = warning
        self.detectionSource = detectionSource
        self.portionEstimationMethod = portionEstimationMethod
        self.wasUserEdited = wasUserEdited
        persistedWasPortionAdjusted = wasPortionAdjusted ? true : nil
        self.isMixedDish = isMixedDish
    }

    mutating func recordUserEdit(previousEstimatedGrams: Double) {
        wasUserEdited = true
        guard previousEstimatedGrams.isFinite, estimatedGrams.isFinite else { return }
        if abs(previousEstimatedGrams - estimatedGrams) > 0.001 {
            wasPortionAdjusted = true
        }
    }
}

/// Privacy-first content for the post-save scanner share card.
/// Optional meal details are absent unless the user explicitly enables them.
struct ScannerShareCard: Equatable, Sendable {
    struct Options: Equatable, Sendable {
        var includeFoodNames = false
        var includePhoto = false
        var includeMacros = false
    }

    struct Macros: Equatable, Sendable {
        var proteinGrams: Double
        var carbsGrams: Double
        var fatGrams: Double
    }

    static let canonicalMealScanURL = URL(string: "https://cyclebalance.app/meal-scan")!
    private static let appStoreURL = URL(string: "https://apps.apple.com/us/app/cyclebalance/id6760353511")!

    let headline: String
    let reviewedFoodCount: Int
    let adjustedPortionCount: Int
    let brandName: String
    let destinationURL: URL
    let foodNames: [String]?
    let flattenedPhotoPNGData: Data?
    let macros: Macros?

    @MainActor
    init(
        items: [MealFoodItemDraft],
        nutrition: NutritionSnapshot,
        sourcePhoto: UIImage?,
        options: Options = Options(),
        providerToken: String? = ScannerShareCard.configuredProviderToken
    ) {
        headline = L10n.string(
            "Photo estimate — reviewed by me",
            defaultValue: "Photo estimate — reviewed by me"
        )
        reviewedFoodCount = items.count
        adjustedPortionCount = items.filter(\.wasPortionAdjusted).count
        brandName = "CycleBalance"
        destinationURL = Self.destinationURL(providerToken: providerToken)
        foodNames = options.includeFoodNames ? items.map(\.displayName) : nil
        flattenedPhotoPNGData = options.includePhoto
            ? Self.flattenedPNGData(from: sourcePhoto)
            : nil
        macros = options.includeMacros
            ? Macros(
                proteinGrams: nutrition.proteinGrams,
                carbsGrams: nutrition.carbsGrams,
                fatGrams: nutrition.fatGrams
            )
            : nil
    }

    static func campaignURL(providerToken: String?) -> URL? {
        guard let providerToken = validatedProviderToken(providerToken) else {
            return nil
        }
        var components = URLComponents(url: appStoreURL, resolvingAgainstBaseURL: false)
        components?.queryItems = [
            URLQueryItem(name: "pt", value: providerToken),
            URLQueryItem(name: "ct", value: "meal_scan_share"),
            URLQueryItem(name: "mt", value: "8"),
        ]
        return components?.url
    }

    static func destinationURL(providerToken: String?) -> URL {
        campaignURL(providerToken: providerToken) ?? canonicalMealScanURL
    }

    private static var configuredProviderToken: String? {
        Bundle.main.object(forInfoDictionaryKey: "APP_STORE_PROVIDER_TOKEN") as? String
    }

    private static func validatedProviderToken(_ candidate: String?) -> String? {
        guard let candidate else { return nil }
        let trimmed = candidate.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty,
              trimmed.count <= 20,
              trimmed.allSatisfy(\.isNumber) else {
            return nil
        }
        return trimmed
    }

    var visibleText: String {
        var lines = [
            headline,
            "\(reviewedFoodCount) \(L10n.string("Foods reviewed", defaultValue: "Foods reviewed"))",
            "\(adjustedPortionCount) \(L10n.string("Adjusted portions", defaultValue: "Adjusted portions"))",
            brandName,
        ]
        if let foodNames {
            lines.append(contentsOf: foodNames)
        }
        if let macros {
            lines.append(
                "\(L10n.string("Protein", defaultValue: "Protein")) \(MealNutritionCalculator.displayMacro(macros.proteinGrams)) g"
            )
            lines.append(
                "\(L10n.string("Carbs", defaultValue: "Carbs")) \(MealNutritionCalculator.displayMacro(macros.carbsGrams)) g"
            )
            lines.append(
                "\(L10n.string("Fat", defaultValue: "Fat")) \(MealNutritionCalculator.displayMacro(macros.fatGrams)) g"
            )
        }
        return lines.joined(separator: "\n")
    }

    @MainActor
    private static func flattenedPNGData(from sourcePhoto: UIImage?) -> Data? {
        guard let sourcePhoto, sourcePhoto.size.width > 0, sourcePhoto.size.height > 0 else {
            return nil
        }
        let format = UIGraphicsImageRendererFormat()
        format.scale = 1
        format.opaque = true
        return UIGraphicsImageRenderer(size: sourcePhoto.size, format: format)
            .image { _ in
                UIColor.systemBackground.setFill()
                UIRectFill(CGRect(origin: .zero, size: sourcePhoto.size))
                sourcePhoto.draw(in: CGRect(origin: .zero, size: sourcePhoto.size))
            }
            .pngData()
    }
}

/// Presentation-only state. A cancelled share never mutates the saved meal or
/// increments completion state.
struct ScannerSharePresentationState: Equatable, Sendable {
    private(set) var isPresented = false
    private(set) var completedShareCount = 0

    mutating func begin() {
        isPresented = true
    }

    mutating func finish(completed: Bool) {
        guard isPresented else { return }
        isPresented = false
        if completed {
            completedShareCount += 1
        }
    }
}

struct MealMetabolicProfile: Codable, Equatable, Sendable {
    var carbLoadCategory: MealScanCarbLoadCategory
    var proteinAdequacy: MealScanAdequacy
    var fiberAdequacy: MealScanAdequacy
    var fatLevel: MealScanFatLevel
    var estimatedGlycemicImpact: GlycemicImpactLevel
    var mealBalanceScore: Int
    var explanation: String
    var caution: String?
}

struct MealScanResult: Identifiable, Equatable, Sendable {
    var id: UUID = UUID()
    var mealName: String
    var mealType: MealType
    var detectedItems: [MealFoodItemDraft]
    var nutrition: NutritionSnapshot
    var metabolicProfile: MealMetabolicProfile
    var confidence: NutritionConfidence
    var warnings: [String]
    var originalPredictionJSON: String
    var modelVersion: String
    var pipelineVersion: String
}

struct ConfirmedMealScan: Equatable, Sendable {
    var id: UUID = UUID()
    var scanResult: MealScanResult
    var loggedAt: Date = Date()
    var mealType: MealType
    var userConfirmed: Bool
    var hasUserEdits: Bool
    var finalUserConfirmedJSON: String
    var photoData: Data?
    var photoLocalPath: String?
    var notes: String?
    var repeatSourceRecordID: UUID?

    init(
        id: UUID = UUID(),
        scanResult: MealScanResult,
        loggedAt: Date = Date(),
        mealType: MealType? = nil,
        userConfirmed: Bool,
        hasUserEdits: Bool = false,
        finalUserConfirmedJSON: String? = nil,
        photoData: Data? = nil,
        photoLocalPath: String? = nil,
        notes: String? = nil,
        repeatSourceRecordID: UUID? = nil
    ) {
        self.id = id
        self.scanResult = scanResult
        self.loggedAt = loggedAt
        self.mealType = mealType ?? scanResult.mealType
        self.userConfirmed = userConfirmed
        self.hasUserEdits = hasUserEdits
        self.finalUserConfirmedJSON = finalUserConfirmedJSON ?? scanResult.originalPredictionJSON
        self.photoData = photoData
        self.photoLocalPath = photoLocalPath
        self.notes = notes
        self.repeatSourceRecordID = repeatSourceRecordID
    }
}

struct SavedMealContextDraft: Equatable, Sendable {
    let mealID: UUID
    let mealName: String
    var severity: Int
    var note: String
}

struct FoodAlias: Codable, Equatable, Sendable {
    var inputName: String
    var canonicalFoodName: String
    var defaultFoodId: String?
    var category: FoodCategory
}

struct FoodDensityDefaults: Equatable, Sendable {
    var gramsPerMlByCategory: [FoodCategory: Double]

    static let fixture = FoodDensityDefaults(gramsPerMlByCategory: [
        .cookedRice: 0.85,
        .pasta: 0.65,
        .chicken: 0.95,
        .beef: 0.95,
        .fish: 0.9,
        .eggs: 1.03,
        .yogurt: 1.03,
        .oatmeal: 0.8,
        .bread: 0.27,
        .fruit: 0.65,
        .vegetables: 0.55,
        .salad: 0.25,
        .beans: 0.75,
        .soup: 1.0,
        .sauce: 1.05,
        .oilDressing: 0.9,
        .mixedDish: 0.8,
    ])

    func grams(forVolumeMl volumeMl: Double, category: FoodCategory) -> Double {
        let density = gramsPerMlByCategory[category] ?? 1
        return volumeMl * density
    }
}
