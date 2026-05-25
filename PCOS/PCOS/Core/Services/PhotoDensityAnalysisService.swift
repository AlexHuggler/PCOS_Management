import Foundation
import UIKit
import CoreML
import CoreVideo

protocol PhotoDensityAnalyzing {
    func analyze(photoData: Data, photoType: HairPhotoType) -> String?
}

protocol PhotoDensityCoreMLModelLoading {
    func loadPhotoDensityModel() -> Any?
}

protocol PhotoDensityCoreMLPredicting {
    func predictDensityScore(photoData: Data, photoType: HairPhotoType) -> Double?
}

struct DeferredPhotoDensityModelLoader: PhotoDensityCoreMLModelLoading {
    private let bundle: Bundle

    init(bundle: Bundle = .main) {
        self.bundle = bundle
    }

    func loadPhotoDensityModel() -> Any? {
        let candidates = [
            "PhotoDensityEstimator",
            "HairDensityEstimator",
        ]

        for name in candidates {
            guard let url = bundle.url(forResource: name, withExtension: "mlmodelc") else { continue }
            if let model = try? MLModel(contentsOf: url) {
                return model
            }
        }
        return nil
    }
}

struct PhotoDensityCoreMLPredictor: PhotoDensityCoreMLPredicting {
    private let modelLoader: PhotoDensityCoreMLModelLoading

    init(modelLoader: PhotoDensityCoreMLModelLoading = DeferredPhotoDensityModelLoader()) {
        self.modelLoader = modelLoader
    }

    func predictDensityScore(photoData: Data, photoType: HairPhotoType) -> Double? {
        guard let model = modelLoader.loadPhotoDensityModel() as? MLModel else {
            return nil
        }
        guard let image = UIImage(data: photoData), let cgImage = image.cgImage else {
            return nil
        }

        guard let (inputName, imageConstraint) = model.modelDescription.inputDescriptionsByName
            .first(where: { $0.value.type == .image })
            .map({ ($0.key, $0.value.imageConstraint) }) else {
            return nil
        }

        let width = imageConstraint?.pixelsWide ?? 224
        let height = imageConstraint?.pixelsHigh ?? 224
        guard let pixelBuffer = makePixelBuffer(from: cgImage, width: width, height: height) else {
            return nil
        }

        let featureValue = MLFeatureValue(pixelBuffer: pixelBuffer)

        do {
            let provider = try MLDictionaryFeatureProvider(dictionary: [inputName: featureValue])
            let output = try model.prediction(from: provider)
            guard let rawValue = extractRawScore(from: output) else { return nil }
            return normalizedScore(from: rawValue)
        } catch {
            return nil
        }
    }

    private func extractRawScore(from output: MLFeatureProvider) -> Double? {
        let candidateKeys = ["densityScore", "score", "output", "prediction"]
        for key in candidateKeys {
            guard let value = output.featureValue(for: key) else { continue }
            if value.type == .double { return value.doubleValue }
            if value.type == .int64 { return Double(value.int64Value) }
            if value.type == .multiArray, let array = value.multiArrayValue, array.count > 0 {
                return array[0].doubleValue
            }
        }

        for name in output.featureNames.sorted() {
            guard let value = output.featureValue(for: name) else { continue }
            if value.type == .double { return value.doubleValue }
            if value.type == .int64 { return Double(value.int64Value) }
            if value.type == .multiArray, let array = value.multiArrayValue, array.count > 0 {
                return array[0].doubleValue
            }
        }

        return nil
    }

    private func normalizedScore(from rawValue: Double) -> Double {
        let normalized: Double
        if rawValue <= 1 {
            normalized = rawValue * 100
        } else if rawValue <= 5 {
            normalized = rawValue * 20
        } else {
            normalized = rawValue
        }
        return min(max(normalized, 0), 100)
    }

    private func makePixelBuffer(from image: CGImage, width: Int, height: Int) -> CVPixelBuffer? {
        let attributes: [CFString: Any] = [
            kCVPixelBufferCGImageCompatibilityKey: true,
            kCVPixelBufferCGBitmapContextCompatibilityKey: true,
        ]

        var pixelBuffer: CVPixelBuffer?
        let status = CVPixelBufferCreate(
            kCFAllocatorDefault,
            width,
            height,
            kCVPixelFormatType_32BGRA,
            attributes as CFDictionary,
            &pixelBuffer
        )
        guard status == kCVReturnSuccess, let pixelBuffer else {
            return nil
        }

        CVPixelBufferLockBaseAddress(pixelBuffer, [])
        defer { CVPixelBufferUnlockBaseAddress(pixelBuffer, []) }

        guard let baseAddress = CVPixelBufferGetBaseAddress(pixelBuffer) else {
            return nil
        }

        let bytesPerRow = CVPixelBufferGetBytesPerRow(pixelBuffer)
        guard let colorSpace = CGColorSpace(name: CGColorSpace.sRGB) else {
            return nil
        }
        guard let context = CGContext(
            data: baseAddress,
            width: width,
            height: height,
            bitsPerComponent: 8,
            bytesPerRow: bytesPerRow,
            space: colorSpace,
            bitmapInfo: CGImageAlphaInfo.premultipliedFirst.rawValue
        ) else {
            return nil
        }

        context.interpolationQuality = .high
        context.draw(image, in: CGRect(x: 0, y: 0, width: width, height: height))
        return pixelBuffer
    }
}

struct PhotoDensityAnalysisService: PhotoDensityAnalyzing {
    private let coreMLPredictor: PhotoDensityCoreMLPredicting

    init(coreMLPredictor: PhotoDensityCoreMLPredicting = PhotoDensityCoreMLPredictor()) {
        self.coreMLPredictor = coreMLPredictor
    }

    func analyze(photoData: Data, photoType: HairPhotoType) -> String? {
        if let coreMLScore = coreMLPredictor.predictDensityScore(photoData: photoData, photoType: photoType) {
            let rounded = Int(coreMLScore.rounded())
            return String(
                localized: "Estimated density score: \(rounded)/100 (\(photoType.displayName), Core ML).",
                comment: "Photo density analysis summary text shown when the optional Core ML model is available."
            )
        }

        guard let image = UIImage(data: photoData), let cgImage = image.cgImage else {
            return nil
        }

        guard let pixelStats = samplePixelStats(cgImage: cgImage) else {
            return nil
        }

        let normalizedContrast = min(max(pixelStats.standardDeviation / 70.0, 0), 1)
        let normalizedDarkPixelRatio = min(max(pixelStats.darkPixelRatio, 0), 1)
        let densityScore = ((normalizedContrast * 0.6) + (normalizedDarkPixelRatio * 0.4)) * 100

        let rounded = Int(densityScore.rounded())
        return String(
            localized: "Estimated density score: \(rounded)/100 (\(photoType.displayName), heuristic).",
            comment: "Photo density analysis summary text shown for an optional heuristic analysis."
        )
    }

    private func samplePixelStats(cgImage: CGImage) -> (standardDeviation: Double, darkPixelRatio: Double)? {
        let targetSize = CGSize(width: 48, height: 48)
        let bytesPerPixel = 4
        let bytesPerRow = Int(targetSize.width) * bytesPerPixel
        let totalBytes = Int(targetSize.height) * bytesPerRow
        var bytes = [UInt8](repeating: 0, count: totalBytes)

        guard let colorSpace = CGColorSpace(name: CGColorSpace.sRGB) else {
            return nil
        }

        guard let context = CGContext(
            data: &bytes,
            width: Int(targetSize.width),
            height: Int(targetSize.height),
            bitsPerComponent: 8,
            bytesPerRow: bytesPerRow,
            space: colorSpace,
            bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue
        ) else {
            return nil
        }

        context.interpolationQuality = .low
        context.draw(cgImage, in: CGRect(origin: .zero, size: targetSize))

        var luminances: [Double] = []
        luminances.reserveCapacity(Int(targetSize.width * targetSize.height))

        var darkPixels = 0

        for index in stride(from: 0, to: totalBytes, by: bytesPerPixel) {
            let red = Double(bytes[index])
            let green = Double(bytes[index + 1])
            let blue = Double(bytes[index + 2])
            let alpha = Double(bytes[index + 3]) / 255.0

            guard alpha > 0 else { continue }

            let luminance = (0.2126 * red) + (0.7152 * green) + (0.0722 * blue)
            luminances.append(luminance)
            if luminance < 95 {
                darkPixels += 1
            }
        }

        guard !luminances.isEmpty else { return nil }

        let mean = luminances.reduce(0, +) / Double(luminances.count)
        let variance = luminances.reduce(0) { partial, value in
            partial + pow(value - mean, 2)
        } / Double(luminances.count)
        let standardDeviation = sqrt(variance)
        let darkPixelRatio = Double(darkPixels) / Double(luminances.count)

        return (standardDeviation, darkPixelRatio)
    }
}
