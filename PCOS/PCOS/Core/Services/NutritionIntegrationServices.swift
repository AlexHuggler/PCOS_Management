import Foundation
import SwiftData

struct FoodProductCandidate: Equatable, Sendable {
    var sourceKind: NutritionImportSourceKind
    var sourceLabel: String
    var sourceName: String?
    var externalIdentifier: String?
    var barcode: String?
    var productName: String
    var brandName: String?
    var servingText: String?
    var calories: Double?
    var carbsGrams: Double?
    var proteinGrams: Double?
    var fatGrams: Double?
    var fiberGrams: Double?
    var sugarGrams: Double?
    var waterOz: Double?
    var confidence: Double
    var completeness: Double

    init(
        sourceKind: NutritionImportSourceKind,
        sourceLabel: String,
        sourceName: String? = nil,
        externalIdentifier: String? = nil,
        barcode: String? = nil,
        productName: String,
        brandName: String? = nil,
        servingText: String? = nil,
        calories: Double? = nil,
        carbsGrams: Double? = nil,
        proteinGrams: Double? = nil,
        fatGrams: Double? = nil,
        fiberGrams: Double? = nil,
        sugarGrams: Double? = nil,
        waterOz: Double? = nil,
        confidence: Double = 0.75,
        completeness: Double? = nil
    ) {
        self.sourceKind = sourceKind
        self.sourceLabel = sourceLabel
        self.sourceName = sourceName
        self.externalIdentifier = externalIdentifier
        self.barcode = barcode
        self.productName = productName
        self.brandName = brandName
        self.servingText = servingText
        self.calories = calories
        self.carbsGrams = carbsGrams
        self.proteinGrams = proteinGrams
        self.fatGrams = fatGrams
        self.fiberGrams = fiberGrams
        self.sugarGrams = sugarGrams
        self.waterOz = waterOz
        self.confidence = confidence
        self.completeness = completeness ?? Self.estimatedCompleteness(
            productName: productName,
            calories: calories,
            carbsGrams: carbsGrams,
            proteinGrams: proteinGrams,
            fatGrams: fatGrams,
            fiberGrams: fiberGrams,
            sugarGrams: sugarGrams
        )
    }

    init?(record: NutritionImportRecord) {
        guard let barcode = record.barcode, let productName = record.productName else {
            return nil
        }

        self.init(
            sourceKind: record.sourceKind,
            sourceLabel: record.sourceLabel,
            sourceName: record.sourceName,
            externalIdentifier: record.externalIdentifier,
            barcode: barcode,
            productName: productName,
            brandName: record.brandName,
            servingText: record.servingText,
            calories: record.calories,
            carbsGrams: record.carbsGrams,
            proteinGrams: record.proteinGrams,
            fatGrams: record.fatGrams,
            fiberGrams: record.fiberGrams,
            sugarGrams: record.sugarGrams,
            waterOz: record.waterOz,
            confidence: record.confidence,
            completeness: record.completeness
        )
    }

    static func estimatedCompleteness(
        productName: String?,
        calories: Double?,
        carbsGrams: Double?,
        proteinGrams: Double?,
        fatGrams: Double?,
        fiberGrams: Double?,
        sugarGrams: Double?
    ) -> Double {
        let slots: [Bool] = [
            productName?.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty == false,
            calories != nil,
            carbsGrams != nil,
            proteinGrams != nil,
            fatGrams != nil,
            fiberGrams != nil,
            sugarGrams != nil,
        ]
        return Double(slots.filter { $0 }.count) / Double(slots.count)
    }

    func makeNutritionImportRecord(importedAt: Date, reviewStatus: NutritionImportReviewStatus = .needsReview) -> NutritionImportRecord {
        NutritionImportRecord(
            sourceKind: sourceKind,
            sourceName: sourceName ?? sourceLabel,
            externalIdentifier: externalIdentifier,
            startDate: importedAt,
            barcode: barcode,
            productName: productName,
            brandName: brandName,
            servingText: servingText,
            calories: calories,
            carbsGrams: carbsGrams,
            proteinGrams: proteinGrams,
            fatGrams: fatGrams,
            fiberGrams: fiberGrams,
            sugarGrams: sugarGrams,
            waterOz: waterOz,
            confidence: confidence,
            completeness: completeness,
            importedAt: importedAt,
            reviewStatus: reviewStatus,
            userReviewed: reviewStatus == .reviewed
        )
    }
}

struct NutritionImportDraftSummary: Equatable, Sendable {
    var sourceLabel: String
    var productName: String
    var brandName: String?
    var servingText: String?
    var completeness: Double
}

enum FoodLookupError: LocalizedError, Equatable {
    case invalidBarcode
    case productNotFound
    case invalidResponse
    case apiKeyMissing
    case requestFailed(String)

    var errorDescription: String? {
        switch self {
        case .invalidBarcode:
            "Enter a valid UPC or EAN barcode."
        case .productNotFound:
            "No matching product was found."
        case .invalidResponse:
            "The food database returned an unreadable response."
        case .apiKeyMissing:
            "USDA FoodData Central fallback is disabled until an API key is added locally."
        case .requestFailed(let message):
            message
        }
    }
}

protocol FoodProductLookupProviding: Sendable {
    func lookupBarcode(_ barcode: String) async throws -> FoodProductCandidate
}

enum OpenFoodFactsProductNormalizer {
    private struct Response: Decodable {
        var code: String?
        var status: Int?
        var product: Product?
    }

    private struct Product: Decodable {
        var productName: String?
        var brands: String?
        var servingSize: String?
        var nutriments: [String: Double]

        private enum CodingKeys: String, CodingKey {
            case productName = "product_name"
            case brands
            case servingSize = "serving_size"
            case nutriments
        }

        init(from decoder: Decoder) throws {
            let container = try decoder.container(keyedBy: CodingKeys.self)
            productName = try container.decodeIfPresent(String.self, forKey: .productName)
            brands = try container.decodeIfPresent(String.self, forKey: .brands)
            servingSize = try container.decodeIfPresent(String.self, forKey: .servingSize)
            nutriments = try container.decodeIfPresent(LenientDoubleDictionary.self, forKey: .nutriments)?.values ?? [:]
        }
    }

    private struct LenientDoubleDictionary: Decodable {
        var values: [String: Double]

        init(from decoder: Decoder) throws {
            let container = try decoder.container(keyedBy: DynamicCodingKey.self)
            var values: [String: Double] = [:]
            for key in container.allKeys {
                if let number = try? container.decode(Double.self, forKey: key) {
                    values[key.stringValue] = number
                } else if let string = try? container.decode(String.self, forKey: key),
                          let number = Double(string) {
                    values[key.stringValue] = number
                }
            }
            self.values = values
        }
    }

    private struct DynamicCodingKey: CodingKey {
        var stringValue: String
        var intValue: Int?

        init?(stringValue: String) {
            self.stringValue = stringValue
        }

        init?(intValue: Int) {
            self.stringValue = String(intValue)
            self.intValue = intValue
        }
    }

    static func normalizedProduct(from data: Data, barcode: String) throws -> FoodProductCandidate {
        let response = try JSONDecoder().decode(Response.self, from: data)
        guard response.status == 1, let product = response.product else {
            throw FoodLookupError.productNotFound
        }

        let productName = cleaned(product.productName) ?? "Scanned product"
        let nutriments = product.nutriments
        return FoodProductCandidate(
            sourceKind: .barcodeOpenFoodFacts,
            sourceLabel: "Open Food Facts",
            sourceName: "Open Food Facts",
            externalIdentifier: response.code ?? barcode,
            barcode: response.code ?? barcode,
            productName: productName,
            brandName: cleaned(product.brands),
            servingText: cleaned(product.servingSize),
            calories: firstNumber(in: nutriments, keys: ["energy-kcal_serving", "energy-kcal", "energy-kcal_100g"]),
            carbsGrams: firstNumber(in: nutriments, keys: ["carbohydrates_serving", "carbohydrates", "carbohydrates_100g"]),
            proteinGrams: firstNumber(in: nutriments, keys: ["proteins_serving", "proteins", "proteins_100g"]),
            fatGrams: firstNumber(in: nutriments, keys: ["fat_serving", "fat", "fat_100g"]),
            fiberGrams: firstNumber(in: nutriments, keys: ["fiber_serving", "fiber", "fiber_100g"]),
            sugarGrams: firstNumber(in: nutriments, keys: ["sugars_serving", "sugars", "sugars_100g"]),
            confidence: 0.82
        )
    }

    private static func firstNumber(in values: [String: Double], keys: [String]) -> Double? {
        for key in keys {
            if let value = values[key], value.isFinite {
                return value
            }
        }
        return nil
    }

    private static func cleaned(_ value: String?) -> String? {
        guard let value else { return nil }
        let trimmed = value.trimmingCharacters(in: .whitespacesAndNewlines)
        return trimmed.isEmpty ? nil : trimmed
    }
}

struct OpenFoodFactsLookupService: FoodProductLookupProviding {
    var session: URLSession = .shared

    func lookupBarcode(_ barcode: String) async throws -> FoodProductCandidate {
        let cleanedBarcode = Self.cleanedBarcode(barcode)
        guard !cleanedBarcode.isEmpty else {
            throw FoodLookupError.invalidBarcode
        }

        var components = URLComponents()
        components.scheme = "https"
        components.host = "world.openfoodfacts.org"
        components.path = "/api/v2/product/\(cleanedBarcode).json"
        components.queryItems = [
            URLQueryItem(
                name: "fields",
                value: "code,product_name,brands,serving_size,nutriments"
            ),
        ]

        guard let url = components.url else {
            throw FoodLookupError.invalidBarcode
        }

        var request = URLRequest(url: url)
        request.setValue("CycleBalance/1.0 (https://cyclebalance.app)", forHTTPHeaderField: "User-Agent")

        do {
            let (data, response) = try await session.data(for: request)
            guard let httpResponse = response as? HTTPURLResponse,
                  (200..<300).contains(httpResponse.statusCode) else {
                throw FoodLookupError.requestFailed("Open Food Facts lookup failed.")
            }
            return try OpenFoodFactsProductNormalizer.normalizedProduct(from: data, barcode: cleanedBarcode)
        } catch let lookupError as FoodLookupError {
            throw lookupError
        } catch {
            throw FoodLookupError.requestFailed(error.localizedDescription)
        }
    }

    static func cleanedBarcode(_ barcode: String) -> String {
        barcode.filter(\.isNumber)
    }
}

struct USDAFoodDataCentralLookupService: FoodProductLookupProviding {
    var apiKey: String?
    var session: URLSession = .shared

    var isEnabled: Bool {
        guard let key = sanitized(apiKey) else { return false }
        return !key.isEmpty
    }

    init(apiKey: String? = nil, session: URLSession = .shared) {
        self.apiKey = apiKey
        self.session = session
    }

    func lookupBarcode(_ barcode: String) async throws -> FoodProductCandidate {
        guard let apiKey = sanitized(apiKey), !apiKey.isEmpty else {
            throw FoodLookupError.apiKeyMissing
        }

        let cleanedBarcode = OpenFoodFactsLookupService.cleanedBarcode(barcode)
        guard !cleanedBarcode.isEmpty else {
            throw FoodLookupError.invalidBarcode
        }

        var components = URLComponents()
        components.scheme = "https"
        components.host = "api.nal.usda.gov"
        components.path = "/fdc/v1/foods/search"
        components.queryItems = [
            URLQueryItem(name: "api_key", value: apiKey),
            URLQueryItem(name: "query", value: cleanedBarcode),
            URLQueryItem(name: "dataType", value: "Branded"),
            URLQueryItem(name: "pageSize", value: "1"),
        ]

        guard let url = components.url else {
            throw FoodLookupError.invalidBarcode
        }

        do {
            let (data, response) = try await session.data(from: url)
            guard let httpResponse = response as? HTTPURLResponse,
                  (200..<300).contains(httpResponse.statusCode) else {
                throw FoodLookupError.requestFailed("USDA FoodData Central lookup failed.")
            }
            return try USDAFoodDataCentralNormalizer.normalizedProduct(from: data, barcode: cleanedBarcode)
        } catch let lookupError as FoodLookupError {
            throw lookupError
        } catch {
            throw FoodLookupError.requestFailed(error.localizedDescription)
        }
    }

    private func sanitized(_ value: String?) -> String? {
        guard let value else { return nil }
        let trimmed = value.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty, !trimmed.contains("$(") else { return nil }
        return trimmed
    }
}

enum USDAFoodDataCentralNormalizer {
    private struct Response: Decodable {
        var foods: [Food]
    }

    private struct Food: Decodable {
        var fdcId: Int?
        var description: String?
        var brandOwner: String?
        var gtinUpc: String?
        var servingSize: Double?
        var servingSizeUnit: String?
        var foodNutrients: [Nutrient]
    }

    private struct Nutrient: Decodable {
        var nutrientName: String?
        var nutrientNumber: String?
        var value: Double?
    }

    static func normalizedProduct(from data: Data, barcode: String) throws -> FoodProductCandidate {
        let response = try JSONDecoder().decode(Response.self, from: data)
        guard let food = response.foods.first else {
            throw FoodLookupError.productNotFound
        }

        let nutrients = Dictionary(uniqueKeysWithValues: food.foodNutrients.compactMap { nutrient -> (String, Double)? in
            guard let key = nutrient.nutrientNumber ?? nutrient.nutrientName,
                  let value = nutrient.value else {
                return nil
            }
            return (key.lowercased(), value)
        })

        let servingText: String?
        if let servingSize = food.servingSize, let unit = food.servingSizeUnit {
            servingText = "\(servingSize.formatted()) \(unit)"
        } else {
            servingText = nil
        }

        return FoodProductCandidate(
            sourceKind: .barcodeUSDA,
            sourceLabel: "USDA FoodData Central",
            sourceName: "USDA FoodData Central",
            externalIdentifier: food.fdcId.map(String.init),
            barcode: food.gtinUpc ?? barcode,
            productName: food.description ?? "USDA food product",
            brandName: food.brandOwner,
            servingText: servingText,
            calories: number(in: nutrients, keys: ["208", "energy"]),
            carbsGrams: number(in: nutrients, keys: ["205", "carbohydrate, by difference"]),
            proteinGrams: number(in: nutrients, keys: ["203", "protein"]),
            fatGrams: number(in: nutrients, keys: ["204", "total lipid (fat)"]),
            fiberGrams: number(in: nutrients, keys: ["291", "fiber, total dietary"]),
            sugarGrams: number(in: nutrients, keys: ["269", "sugars, total including nlea"]),
            confidence: 0.78
        )
    }

    private static func number(in nutrients: [String: Double], keys: [String]) -> Double? {
        for key in keys {
            if let value = nutrients[key.lowercased()] {
                return value
            }
        }
        return nil
    }
}

@MainActor
struct BarcodeProductLookupCoordinator {
    private let modelContext: ModelContext
    private let openFoodFactsLookup: any FoodProductLookupProviding
    private let usdaLookup: USDAFoodDataCentralLookupService

    init(
        modelContext: ModelContext,
        openFoodFactsLookup: any FoodProductLookupProviding = OpenFoodFactsLookupService(),
        usdaLookup: USDAFoodDataCentralLookupService = USDAFoodDataCentralLookupService()
    ) {
        self.modelContext = modelContext
        self.openFoodFactsLookup = openFoodFactsLookup
        self.usdaLookup = usdaLookup
    }

    func lookupBarcode(_ barcode: String) async throws -> FoodProductCandidate {
        let cleanedBarcode = OpenFoodFactsLookupService.cleanedBarcode(barcode)
        guard !cleanedBarcode.isEmpty else {
            throw FoodLookupError.invalidBarcode
        }

        if let cached = try cachedCandidate(for: cleanedBarcode) {
            return cached
        }

        do {
            return try await openFoodFactsLookup.lookupBarcode(cleanedBarcode)
        } catch FoodLookupError.productNotFound where usdaLookup.isEnabled {
            return try await usdaLookup.lookupBarcode(cleanedBarcode)
        } catch {
            throw error
        }
    }

    private func cachedCandidate(for barcode: String) throws -> FoodProductCandidate? {
        let descriptor = FetchDescriptor<NutritionImportRecord>(
            predicate: #Predicate<NutritionImportRecord> { record in
                record.barcode == barcode
            },
            sortBy: [SortDescriptor(\.importedAt, order: .reverse)]
        )
        return try modelContext.fetch(descriptor).compactMap(FoodProductCandidate.init(record:)).first
    }
}

protocol MealPhotoNutritionParsingProviding: Sendable {
    func makeNutritionCandidate(from imageData: Data) async throws -> FoodProductCandidate?
}

struct LocalOnlyMealPhotoNutritionParser: MealPhotoNutritionParsingProviding {
    func makeNutritionCandidate(from imageData: Data) async throws -> FoodProductCandidate? {
        nil
    }
}

struct AhaMoment: Equatable, Identifiable, Sendable {
    enum Kind: String, Sendable {
        case healthKitNutrition
        case healthKitContext
        case barcodeMeal
        case mealGlucoseReady
        case scannedSnack
        case quizStarter
        case starter
    }

    var id: String { kind.rawValue }
    var kind: Kind
    var title: String
    var body: String
    var nextAction: String
    var premiumDetail: String?
}

@MainActor
struct AhaMomentService {
    private let modelContext: ModelContext
    private let calendar: Calendar

    init(modelContext: ModelContext, calendar: Calendar = .current) {
        self.modelContext = modelContext
        self.calendar = calendar
    }

    func topMoment(isPremium: Bool, now: Date = Date()) throws -> AhaMoment? {
        if let healthMoment = try healthKitNutritionMoment(isPremium: isPremium, now: now) {
            return healthMoment
        }
        if let scannedSnackMoment = try scannedSnackMoment(isPremium: isPremium, now: now) {
            return scannedSnackMoment
        }
        if let glucoseMoment = try mealGlucoseMoment(isPremium: isPremium, now: now) {
            return glucoseMoment
        }
        return starterMoment()
    }

    func onboardingMoment(isPremium: Bool, profile: OnboardingProfile, now: Date = Date()) throws -> AhaMoment {
        if let sourceMoment = try sourceRichHealthKitMoment(isPremium: isPremium, now: now) {
            return sourceMoment
        }
        if let healthMoment = try healthKitNutritionMoment(isPremium: isPremium, now: now) {
            return healthMoment
        }
        return quizStarterMoment(profile: profile)
    }

    private func sourceRichHealthKitMoment(isPremium: Bool, now: Date) throws -> AhaMoment? {
        let startDate = calendar.date(byAdding: .day, value: -30, to: calendar.startOfDay(for: now)) ?? .distantPast
        let records = try modelContext.fetch(FetchDescriptor<HealthKitImportedSampleRecord>())
            .filter { $0.startDate >= startDate && $0.startDate <= now }
        guard !records.isEmpty else { return nil }

        let groupedBySource = Dictionary(grouping: records, by: \.sourceLabel)
        let topSources = groupedBySource
            .sorted { lhs, rhs in lhs.value.count > rhs.value.count }
            .prefix(2)
            .map(\.key)
        let sourceText: String
        if topSources.count == 2 {
            sourceText = L10n.format(
                "%@ and %@",
                defaultValue: "%@ and %@",
                topSources[0],
                topSources[1]
            )
        } else {
            sourceText = topSources.first ?? ""
        }

        let cycleCount = records.filter { $0.derivedRecordKind == .cycleEntry || $0.derivedRecordKind == .ovulationObservation }.count
        let symptomCount = records.filter { $0.derivedRecordKind == .symptomEntry }.count
        let nutritionCount = records.filter { $0.derivedRecordKind == .nutritionImport }.count

        let body: String
        if nutritionCount > 0 {
            body = L10n.string(
                "Apple Health shared nutrition context that can help compare meals with glucose, energy, sleep, and symptoms without retyping every macro.",
                defaultValue: "Apple Health shared nutrition context that can help compare meals with glucose, energy, sleep, and symptoms without retyping every macro."
            )
        } else if cycleCount > 0 {
            body = L10n.string(
                "Apple Health shared cycle or ovulation context that can help prefill your timeline and make future symptom comparisons easier to review.",
                defaultValue: "Apple Health shared cycle or ovulation context that can help prefill your timeline and make future symptom comparisons easier to review."
            )
        } else if symptomCount > 0 {
            body = L10n.string(
                "Apple Health shared symptom context that can help CycleBalance organize what compatible apps already captured.",
                defaultValue: "Apple Health shared symptom context that can help CycleBalance organize what compatible apps already captured."
            )
        } else {
            body = L10n.string(
                "Apple Health shared recent body, activity, recovery, or reproductive context that can help CycleBalance start with less manual entry.",
                defaultValue: "Apple Health shared recent body, activity, recovery, or reproductive context that can help CycleBalance start with less manual entry."
            )
        }

        return AhaMoment(
            kind: .healthKitContext,
            title: L10n.format(
                "%@ added useful context",
                defaultValue: "%@ added useful context",
                sourceText.isEmpty
                    ? L10n.string("Apple Health", defaultValue: "Apple Health")
                    : sourceText
            ),
            body: body,
            nextAction: L10n.string(
                "Review the source notes, then scan a barcode or log your next meal to see how new entries fit in.",
                defaultValue: "Review the source notes, then scan a barcode or log your next meal to see how new entries fit in."
            ),
            premiumDetail: isPremium
                ? L10n.string(
                    "Premium depth can compare these imported signals with future meals, symptoms, cycle phases, and glucose readings.",
                    defaultValue: "Premium depth can compare these imported signals with future meals, symptoms, cycle phases, and glucose readings."
                )
                : nil
        )
    }

    private func healthKitNutritionMoment(isPremium: Bool, now: Date) throws -> AhaMoment? {
        let startDate = calendar.date(byAdding: .day, value: -14, to: calendar.startOfDay(for: now)) ?? .distantPast
        let imports = try modelContext.fetch(FetchDescriptor<NutritionImportRecord>())
            .filter { record in
                record.sourceKind == .healthKit
                    && record.startDate >= startDate
                    && record.startDate <= now
            }
        guard !imports.isEmpty else { return nil }

        let fallbackSourceName = L10n.string("Apple Health", defaultValue: "Apple Health")
        let grouped = Dictionary(grouping: imports) { record in
            record.sourceName?.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty == false
                ? record.sourceName ?? fallbackSourceName
                : fallbackSourceName
        }
        guard let best = grouped.max(by: { lhs, rhs in lhs.value.count < rhs.value.count }) else {
            return nil
        }

        let dayCount = Set(best.value.map { calendar.startOfDay(for: $0.startDate) }).count
        let titleKey = dayCount == 1
            ? "%@ added %lld nutrition day"
            : "%@ added %lld nutrition days"
        let title = L10n.format(
            titleKey,
            defaultValue: titleKey,
            best.key,
            Int64(dayCount)
        )
        return AhaMoment(
            kind: .healthKitNutrition,
            title: title,
            body: L10n.string(
                "Apple Health nutrition can now enrich your meal patterns without retyping every macro.",
                defaultValue: "Apple Health nutrition can now enrich your meal patterns without retyping every macro."
            ),
            nextAction: L10n.string(
                "Review one imported day before logging your next meal.",
                defaultValue: "Review one imported day before logging your next meal."
            ),
            premiumDetail: isPremium
                ? L10n.string(
                    "Premium depth can compare those nutrition windows with glucose, energy, sleep, and symptom timing.",
                    defaultValue: "Premium depth can compare those nutrition windows with glucose, energy, sleep, and symptom timing."
                )
                : nil
        )
    }

    private func scannedSnackMoment(isPremium: Bool, now: Date) throws -> AhaMoment? {
        let startDate = calendar.date(byAdding: .day, value: -7, to: now) ?? .distantPast
        let imports = try modelContext.fetch(
            FetchDescriptor<NutritionImportRecord>(sortBy: [SortDescriptor(\.importedAt, order: .reverse)])
        )
        .filter { record in
            record.sourceKind == .barcodeOpenFoodFacts
                && record.importedAt >= startDate
        }
        guard let product = imports.first else { return nil }

        let carbs = product.carbsGrams ?? 0
        let protein = product.proteinGrams ?? 0
        let fiber = product.fiberGrams ?? 0
        guard carbs > 0, carbs >= (protein + fiber) * 2 else {
            return nil
        }

        return AhaMoment(
            kind: .scannedSnack,
            title: L10n.string(
                "This scanned snack is mostly carbs",
                defaultValue: "This scanned snack is mostly carbs"
            ),
            body: L10n.string(
                "Pairing it with protein or fiber can make your next glucose reflection easier to interpret.",
                defaultValue: "Pairing it with protein or fiber can make your next glucose reflection easier to interpret."
            ),
            nextAction: L10n.string(
                "Log an after-meal glucose reading if you are testing your response.",
                defaultValue: "Log an after-meal glucose reading if you are testing your response."
            ),
            premiumDetail: isPremium
                ? L10n.string(
                    "Premium depth can compare this snack against your own post-meal glucose and symptom notes.",
                    defaultValue: "Premium depth can compare this snack against your own post-meal glucose and symptom notes."
                )
                : nil
        )
    }

    private func mealGlucoseMoment(isPremium: Bool, now: Date) throws -> AhaMoment? {
        let readiness = try MealGlucoseContextService(modelContext: modelContext, calendar: calendar)
            .readiness(days: 14, now: now)
        guard readiness.state == .ready else { return nil }

        return AhaMoment(
            kind: .mealGlucoseReady,
            title: L10n.string(
                "Your post-meal glucose context is ready",
                defaultValue: "Your post-meal glucose context is ready"
            ),
            body: L10n.string(
                "You have enough paired meals, glucose readings, and check-ins for a first reflection.",
                defaultValue: "You have enough paired meals, glucose readings, and check-ins for a first reflection."
            ),
            nextAction: L10n.string(
                "Open Insights after your next paired meal to compare the pattern.",
                defaultValue: "Open Insights after your next paired meal to compare the pattern."
            ),
            premiumDetail: isPremium ? readiness.message : nil
        )
    }

    private func starterMoment() -> AhaMoment? {
        AhaMoment(
            kind: .starter,
            title: L10n.string(
                "Start with one useful signal",
                defaultValue: "Start with one useful signal"
            ),
            body: L10n.string(
                "A meal, symptom, period, glucose, or Apple Health sync can unlock your first personal pattern.",
                defaultValue: "A meal, symptom, period, glucose, or Apple Health sync can unlock your first personal pattern."
            ),
            nextAction: L10n.string(
                "Log the easiest thing you already know from today.",
                defaultValue: "Log the easiest thing you already know from today."
            ),
            premiumDetail: nil
        )
    }

    private func quizStarterMoment(profile: OnboardingProfile) -> AhaMoment {
        let focus = profile.symptomFocusAreas.first?.displayName
            ?? profile.primaryGoal?.displayName
            ?? L10n.string("today's", defaultValue: "today's")
        return AhaMoment(
            kind: .quizStarter,
            title: L10n.format(
                "Start with your %@ context",
                defaultValue: "Start with your %@ context",
                focus.lowercased()
            ),
            body: L10n.string(
                "Even without Apple Health data yet, a meal, symptom, sleep note, or period day can become the first comparison point for your personal pattern.",
                defaultValue: "Even without Apple Health data yet, a meal, symptom, sleep note, or period day can become the first comparison point for your personal pattern."
            ),
            nextAction: L10n.string(
                "Choose one quick log, scan a barcode, or enter your next meal manually.",
                defaultValue: "Choose one quick log, scan a barcode, or enter your next meal manually."
            ),
            premiumDetail: nil
        )
    }
}
