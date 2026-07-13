import CryptoKit
import Foundation
import UIKit

struct NormalizedMealScanImage: Equatable, Sendable {
    var jpegData: Data
    var sourceImageHash: String
    var width: Int
    var height: Int
}

protocol MealScanImageNormalizing: Sendable {
    func normalizeJPEGData(from image: UIImage) throws -> NormalizedMealScanImage
}

enum MealScanImageNormalizationError: LocalizedError, Equatable {
    case cannotRender
    case exceedsMaximumBytes(actualBytes: Int, maximumBytes: Int)

    var errorDescription: String? {
        switch self {
        case .cannotRender:
            L10n.string(
                "CycleBalance could not prepare this meal photo for a cloud estimate.",
                defaultValue: "CycleBalance could not prepare this meal photo for a cloud estimate."
            )
        case .exceedsMaximumBytes:
            L10n.string(
                "CycleBalance could not reduce this photo to the secure upload limit.",
                defaultValue: "CycleBalance could not reduce this photo to the secure upload limit."
            )
        }
    }
}

struct MealScanImageNormalizer: MealScanImageNormalizing {
    static let maximumJPEGBytes = 1_500_000

    var maxLongEdge: CGFloat = 960
    var compressionQuality: CGFloat = 0.78
    var maximumJPEGBytes: Int = Self.maximumJPEGBytes

    func normalizeJPEGData(from image: UIImage) throws -> NormalizedMealScanImage {
        let sourceSize = image.size.width > 0 && image.size.height > 0
            ? image.size
            : CGSize(width: 1, height: 1)
        let scale = min(1, maxLongEdge / max(sourceSize.width, sourceSize.height))
        let targetSize = CGSize(
            width: max(1, (sourceSize.width * scale).rounded()),
            height: max(1, (sourceSize.height * scale).rounded())
        )

        let format = UIGraphicsImageRendererFormat.default()
        format.scale = 1
        format.opaque = true
        let rendered = UIGraphicsImageRenderer(size: targetSize, format: format).image { _ in
            UIColor.white.setFill()
            UIBezierPath(rect: CGRect(origin: .zero, size: targetSize)).fill()
            image.draw(in: CGRect(origin: .zero, size: targetSize))
        }

        guard var jpegData = rendered.jpegData(compressionQuality: compressionQuality) else {
            throw MealScanImageNormalizationError.cannotRender
        }
        if jpegData.count > maximumJPEGBytes {
            for quality in [CGFloat(0.65), 0.5, 0.4, 0.3] where quality < compressionQuality {
                guard let candidate = rendered.jpegData(compressionQuality: quality) else {
                    throw MealScanImageNormalizationError.cannotRender
                }
                jpegData = candidate
                if jpegData.count <= maximumJPEGBytes { break }
            }
        }
        guard jpegData.count <= maximumJPEGBytes else {
            throw MealScanImageNormalizationError.exceedsMaximumBytes(
                actualBytes: jpegData.count,
                maximumBytes: maximumJPEGBytes
            )
        }

        return NormalizedMealScanImage(
            jpegData: jpegData,
            sourceImageHash: Self.sha256Hex(jpegData),
            width: Int(targetSize.width),
            height: Int(targetSize.height)
        )
    }

    static func sha256Hex(_ data: Data) -> String {
        SHA256.hash(data: data).map { String(format: "%02x", $0) }.joined()
    }
}
