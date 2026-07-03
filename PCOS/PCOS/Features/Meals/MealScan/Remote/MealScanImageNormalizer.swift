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

enum MealScanImageNormalizationError: LocalizedError {
    case cannotRender

    var errorDescription: String? {
        "CycleBalance could not prepare this meal photo for a cloud estimate."
    }
}

struct MealScanImageNormalizer: MealScanImageNormalizing {
    var maxLongEdge: CGFloat = 960
    var compressionQuality: CGFloat = 0.78

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

        guard let jpegData = rendered.jpegData(compressionQuality: compressionQuality) else {
            throw MealScanImageNormalizationError.cannotRender
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
