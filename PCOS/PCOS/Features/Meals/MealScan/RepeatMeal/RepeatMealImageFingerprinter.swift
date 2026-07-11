import Foundation
import Vision

protocol MealImageFingerprinting: Sendable {
    func makeFingerprint(for normalizedJPEGData: Data) async throws -> MealImageFingerprint
    func distance(between lhs: MealImageFingerprint, and rhs: MealImageFingerprint) async throws -> Float
}

enum RepeatMealFingerprintError: LocalizedError, Equatable, Sendable {
    case noObservation
    case featurePrintGenerationFailed
    case archiveFailed
    case missingArchive
    case invalidArchive
    case incompatibleVisionRevision
    case distanceCalculationFailed

    var errorDescription: String? {
        switch self {
        case .noObservation, .featurePrintGenerationFailed:
            "CycleBalance could not analyze this meal photo locally."
        case .archiveFailed, .missingArchive, .invalidArchive:
            "CycleBalance could not read a saved meal-photo comparison."
        case .incompatibleVisionRevision:
            "CycleBalance cannot compare meal photos created by different Vision versions."
        case .distanceCalculationFailed:
            "CycleBalance could not compare these meal photos."
        }
    }
}

actor VisionRepeatMealImageFingerprinter: MealImageFingerprinting {
    private static let visionRevision = Int(VNGenerateImageFeaturePrintRequestRevision2)

    func makeFingerprint(for normalizedJPEGData: Data) async throws -> MealImageFingerprint {
        let request = VNGenerateImageFeaturePrintRequest()
        request.revision = VNGenerateImageFeaturePrintRequestRevision2

        do {
            try VNImageRequestHandler(data: normalizedJPEGData).perform([request])
        } catch {
            throw RepeatMealFingerprintError.featurePrintGenerationFailed
        }

        guard let observation = request.results?.first else {
            throw RepeatMealFingerprintError.noObservation
        }

        let archive: Data
        do {
            archive = try NSKeyedArchiver.archivedData(
                withRootObject: observation,
                requiringSecureCoding: true
            )
        } catch {
            throw RepeatMealFingerprintError.archiveFailed
        }

        return MealImageFingerprint(
            sourceImageHash: MealScanImageNormalizer.sha256Hex(normalizedJPEGData),
            featurePrintArchive: archive,
            visionRevision: Self.visionRevision
        )
    }

    func distance(between lhs: MealImageFingerprint, and rhs: MealImageFingerprint) async throws -> Float {
        guard lhs.visionRevision == Self.visionRevision,
              rhs.visionRevision == Self.visionRevision else {
            throw RepeatMealFingerprintError.incompatibleVisionRevision
        }

        let lhsObservation = try featurePrintObservation(from: lhs)
        let rhsObservation = try featurePrintObservation(from: rhs)
        var distance: Float = 0

        do {
            try lhsObservation.computeDistance(&distance, to: rhsObservation)
            return distance
        } catch {
            throw RepeatMealFingerprintError.distanceCalculationFailed
        }
    }

    private func featurePrintObservation(
        from fingerprint: MealImageFingerprint
    ) throws -> VNFeaturePrintObservation {
        guard let archive = fingerprint.featurePrintArchive else {
            throw RepeatMealFingerprintError.missingArchive
        }

        do {
            guard let observation = try NSKeyedUnarchiver.unarchivedObject(
                ofClass: VNFeaturePrintObservation.self,
                from: archive
            ) else {
                throw RepeatMealFingerprintError.invalidArchive
            }
            return observation
        } catch let error as RepeatMealFingerprintError {
            throw error
        } catch {
            throw RepeatMealFingerprintError.invalidArchive
        }
    }
}
