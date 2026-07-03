import Foundation
import UIKit
import Vision
import CoreML

struct MealScanModelRegistry: Equatable, Sendable {
    var foodClassifierModelName: String?
    var foodSegmentationModelName: String?
    var depthModelName: String?
    var modelVersion: String

    var hasAnyModel: Bool {
        foodClassifierModelName != nil || foodSegmentationModelName != nil || depthModelName != nil
    }
}

struct CoreMLFoodClassificationService: FoodClassificationService {
    var registry: MealScanModelRegistry
    var fallback: any FoodClassificationService

    func classifyFood(in image: UIImage) async throws -> [FoodClassificationCandidate] {
        guard let modelName = registry.foodClassifierModelName,
              let modelURL = Bundle.main.url(forResource: modelName, withExtension: "mlmodelc"),
              let cgImage = image.cgImage
        else {
            return try await fallback.classifyFood(in: image)
        }

        do {
            let model = try MLModel(contentsOf: modelURL)
            let visionModel = try VNCoreMLModel(for: model)
            let request = VNCoreMLRequest(model: visionModel)
            request.imageCropAndScaleOption = .centerCrop
            let handler = VNImageRequestHandler(
                cgImage: cgImage,
                orientation: CGImagePropertyOrientation(image.imageOrientation),
                options: [:]
            )
            try handler.perform([request])
            let observations = (request.results ?? []).compactMap { $0 as? VNClassificationObservation }
            let candidates = observations.prefix(10).map { observation in
                FoodClassificationCandidate(
                    label: observation.identifier,
                    canonicalFoodId: nil,
                    confidence: Double(observation.confidence)
                )
            }
            return candidates.isEmpty ? try await fallback.classifyFood(in: image) : candidates
        } catch {
            return try await fallback.classifyFood(in: image)
        }
    }
}

struct CoreMLFoodSegmentationService: FoodSegmentationService {
    var registry: MealScanModelRegistry
    var fallback: any FoodSegmentationService

    func segmentFood(in image: UIImage) async throws -> [FoodSegmentationResult] {
        guard let modelName = registry.foodSegmentationModelName,
              let modelURL = Bundle.main.url(forResource: modelName, withExtension: "mlmodelc"),
              let cgImage = image.cgImage
        else {
            return try await fallback.segmentFood(in: image)
        }

        do {
            let model = try MLModel(contentsOf: modelURL)
            let visionModel = try VNCoreMLModel(for: model)
            let request = VNCoreMLRequest(model: visionModel)
            request.imageCropAndScaleOption = .scaleFit
            let handler = VNImageRequestHandler(
                cgImage: cgImage,
                orientation: CGImagePropertyOrientation(image.imageOrientation),
                options: [:]
            )
            try handler.perform([request])

            let objectObservations = (request.results ?? []).compactMap { $0 as? VNRecognizedObjectObservation }
            let segments = objectObservations.compactMap { observation -> FoodSegmentationResult? in
                guard let label = observation.labels.first else { return nil }
                return FoodSegmentationResult(
                    label: label.identifier,
                    boundingBox: MealScanRect(observation.boundingBox),
                    confidence: Double(label.confidence),
                    maskIdentifier: nil
                )
            }

            // Pixel-mask model outputs vary by architecture, so final mask parsing stays model-contract specific.
            return segments.isEmpty ? try await fallback.segmentFood(in: image) : segments
        } catch {
            return try await fallback.segmentFood(in: image)
        }
    }
}

private extension CGImagePropertyOrientation {
    init(_ orientation: UIImage.Orientation) {
        switch orientation {
        case .up:
            self = .up
        case .upMirrored:
            self = .upMirrored
        case .down:
            self = .down
        case .downMirrored:
            self = .downMirrored
        case .left:
            self = .left
        case .leftMirrored:
            self = .leftMirrored
        case .right:
            self = .right
        case .rightMirrored:
            self = .rightMirrored
        @unknown default:
            self = .up
        }
    }
}

struct DepthAwarePortionEstimationService: PortionEstimationService {
    var fallback: any PortionEstimationService

    func estimatePortions(
        image: UIImage,
        detectedItems: [DetectedFoodItem],
        segmentationResults: [FoodSegmentationResult],
        depthData: MealDepthData?
    ) async throws -> [PortionEstimate] {
        try await fallback.estimatePortions(
            image: image,
            detectedItems: detectedItems,
            segmentationResults: segmentationResults,
            depthData: depthData
        )
    }
}

struct LocalUSDANutritionRepository: NutritionLookupService {
    var fallback: any NutritionLookupService

    func searchFood(query: String) async throws -> [FoodNutritionRecord] {
        // A bundled compact USDA SQLite store can replace this fallback when the asset is present.
        try await fallback.searchFood(query: query)
    }

    func nutrition(forFoodId foodId: String) async throws -> FoodNutritionRecord? {
        try await fallback.nutrition(forFoodId: foodId)
    }
}

protocol IngredientIntelligenceService {
    func canonicalFoodID(for inputName: String) -> String?
    func templateItems(for inputName: String) -> [String]
}

struct AliasIngredientIntelligenceService: IngredientIntelligenceService {
    var aliases: [FoodAlias] = SampleNutritionFixtures.aliases

    func canonicalFoodID(for inputName: String) -> String? {
        let normalized = inputName.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        return aliases.first { $0.inputName.lowercased() == normalized }?.defaultFoodId
    }

    func templateItems(for inputName: String) -> [String] {
        let normalized = inputName.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        if normalized.contains("avocado toast") {
            return ["white-bread", "avocado"]
        }
        if normalized.contains("burrito bowl") {
            return ["rice-white-cooked", "black-beans", "chicken-breast-cooked"]
        }
        if normalized.contains("smoothie") {
            return ["smoothie-generic"]
        }
        return canonicalFoodID(for: inputName).map { [$0] } ?? []
    }
}

protocol BarcodeNutritionLookupService {
    func lookupBarcode(_ barcode: String) async throws -> FoodNutritionRecord?
}

protocol NutritionLabelOCRService {
    func nutritionRecord(from image: UIImage) async throws -> FoodNutritionRecord?
}

protocol PackagedFoodCacheRepository {
    func cachedFood(for barcode: String) async throws -> FoodNutritionRecord?
    func save(food: FoodNutritionRecord, barcode: String) async throws
}

struct MealNutritionQueryService {
    var meals: [MealEntry]

    func totalProtein(on date: Date, calendar: Calendar = .current) -> Double {
        meals(on: date, calendar: calendar).compactMap(\.proteinGrams).reduce(0, +)
    }

    func totalCarbs(on date: Date, calendar: Calendar = .current) -> Double {
        meals(on: date, calendar: calendar).compactMap(\.carbsGrams).reduce(0, +)
    }

    func totalCalories(on date: Date, calendar: Calendar = .current) -> Double {
        meals(on: date, calendar: calendar).compactMap(\.calories).reduce(0, +)
    }

    func highCarbMeals(in dateRange: ClosedRange<Date>) -> [MealEntry] {
        meals.filter { dateRange.contains($0.timestamp) && ($0.carbsGrams ?? 0) >= 55 }
    }

    func highProteinMeals(in dateRange: ClosedRange<Date>) -> [MealEntry] {
        meals.filter { dateRange.contains($0.timestamp) && ($0.proteinGrams ?? 0) >= 25 }
    }

    func mealsWithLowFiber(in dateRange: ClosedRange<Date>) -> [MealEntry] {
        meals.filter { dateRange.contains($0.timestamp) && ($0.fiberGrams ?? 0) < 4 }
    }

    func mealsInCyclePhase(_ phase: CyclePhase, cycles: [Cycle]) -> [MealEntry] {
        let policy = CyclePhaseInferencePolicy()
        return meals.filter { meal in
            policy.approximatePhase(for: meal.timestamp, cycles: cycles) == phase
        }
    }

    func mealsNearSymptoms(_ symptom: SymptomType, symptoms: [SymptomEntry], windowHours: Double) -> [MealEntry] {
        let matchingSymptoms = symptoms.filter { $0.symptomType == symptom }
        let window = windowHours * 3_600
        return meals.filter { meal in
            matchingSymptoms.contains { abs($0.date.timeIntervalSince(meal.timestamp)) <= window }
        }
    }

    private func meals(on date: Date, calendar: Calendar) -> [MealEntry] {
        meals.filter { calendar.isDate($0.timestamp, inSameDayAs: date) }
    }
}
