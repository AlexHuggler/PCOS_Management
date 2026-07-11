import Darwin
import Foundation
import Vision

private let productionImageCount = 100
private let smokeImageCount = 5

private struct EvaluationManifest: Decodable {
    let version: Int
    let images: [ManifestImage]
}

private struct ManifestImage: Decodable {
    let id: String
    let label: String
    let file: String
    let highRisk: Bool?
}

private struct ReportImage: Encodable {
    let id: String
    let label: String
    let highRisk: Bool
    let nearestNeighborID: String
    let nearestNeighborDistance: Double
    let nearestNeighborMargin: Double
    let featurePrintMilliseconds: Double
}

private struct PairDistance: Encodable {
    let firstID: String
    let secondID: String
    let distance: Double
}

private struct DistanceReport: Encodable {
    let version: Int
    let mode: String
    let evaluatedImageCount: Int
    let images: [ReportImage]
    let pairs: [PairDistance]
    let totalMilliseconds: Double
}

private struct FeatureRecord {
    let manifest: ManifestImage
    let featurePrint: VNFeaturePrintObservation
    let featurePrintMilliseconds: Double
}

private enum ExtractorError: LocalizedError {
    case usage
    case invalidManifest
    case invalidImageMetadata(Int)
    case duplicateID
    case missingImageFile(Int)
    case failedFeaturePrint(Int)

    var errorDescription: String? {
        switch self {
        case .usage:
            return "usage: extract-feature-distances --manifest <file> --report <file> [--smoke]"
        case .invalidManifest:
            return "invalid manifest: production runs require exactly 100 images; --smoke requires exactly 5"
        case let .invalidImageMetadata(index):
            return "invalid image metadata at manifest index \(index)"
        case .duplicateID:
            return "manifest IDs must be unique opaque values"
        case let .missingImageFile(index):
            return "manifest image at index \(index) does not reference a readable local file"
        case let .failedFeaturePrint(index):
            return "Vision could not create a feature print for manifest image at index \(index)"
        }
    }
}

private func parseArguments() throws -> (manifestURL: URL, reportURL: URL, smoke: Bool) {
    var manifestPath: String?
    var reportPath: String?
    var smoke = false
    var arguments = Array(CommandLine.arguments.dropFirst())

    while !arguments.isEmpty {
        let argument = arguments.removeFirst()
        switch argument {
        case "--smoke":
            guard !smoke else { throw ExtractorError.usage }
            smoke = true
        case "--manifest", "--report":
            guard let value = arguments.first else { throw ExtractorError.usage }
            arguments.removeFirst()
            if argument == "--manifest", manifestPath == nil {
                manifestPath = value
            } else if argument == "--report", reportPath == nil {
                reportPath = value
            } else {
                throw ExtractorError.usage
            }
        default:
            throw ExtractorError.usage
        }
    }

    guard let manifestPath, let reportPath else { throw ExtractorError.usage }
    return (URL(fileURLWithPath: manifestPath), URL(fileURLWithPath: reportPath), smoke)
}

private func isOpaqueID(_ value: String) -> Bool {
    let expression = "^[A-Za-z0-9][A-Za-z0-9_-]{7,127}$"
    return value.range(of: expression, options: .regularExpression) != nil
}

private func loadManifest(at url: URL, smoke: Bool) throws -> [ManifestImage] {
    let manifest = try JSONDecoder().decode(EvaluationManifest.self, from: Data(contentsOf: url))
    let requiredCount = smoke ? smokeImageCount : productionImageCount
    guard manifest.version == 1, manifest.images.count == requiredCount else {
        throw ExtractorError.invalidManifest
    }

    var IDs = Set<String>()
    for (index, image) in manifest.images.enumerated() {
        guard isOpaqueID(image.id), !image.label.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else {
            throw ExtractorError.invalidImageMetadata(index)
        }
        guard IDs.insert(image.id).inserted else { throw ExtractorError.duplicateID }
        guard FileManager.default.isReadableFile(atPath: image.file) else {
            throw ExtractorError.missingImageFile(index)
        }
    }
    return manifest.images
}

private func makeFeatureRecords(for images: [ManifestImage]) throws -> [FeatureRecord] {
    try images.enumerated().map { index, image in
        let request = VNGenerateImageFeaturePrintRequest()
        request.revision = VNGenerateImageFeaturePrintRequestRevision2
        let startedAt = Date()
        let handler = VNImageRequestHandler(url: URL(fileURLWithPath: image.file), options: [:])
        try handler.perform([request])
        guard let featurePrint = request.results?.first as? VNFeaturePrintObservation else {
            throw ExtractorError.failedFeaturePrint(index)
        }
        return FeatureRecord(
            manifest: image,
            featurePrint: featurePrint,
            featurePrintMilliseconds: Date().timeIntervalSince(startedAt) * 1_000
        )
    }
}

private func pairKey(_ first: String, _ second: String) -> String {
    first < second ? "\(first)\u{0}\(second)" : "\(second)\u{0}\(first)"
}

private func rounded(_ value: Double) -> Double {
    (value * 1_000_000).rounded() / 1_000_000
}

private func buildReport(records: [FeatureRecord], smoke: Bool, startedAt: Date) throws -> DistanceReport {
    var pairs = [PairDistance]()
    var distances = [String: Double]()
    for firstIndex in records.indices {
        for secondIndex in records.indices.dropFirst(firstIndex + 1) {
            var distance: Float = 0
            try records[firstIndex].featurePrint.computeDistance(&distance, to: records[secondIndex].featurePrint)
            let measuredDistance = Double(distance)
            pairs.append(PairDistance(
                firstID: records[firstIndex].manifest.id,
                secondID: records[secondIndex].manifest.id,
                distance: measuredDistance
            ))
            distances[pairKey(records[firstIndex].manifest.id, records[secondIndex].manifest.id)] = measuredDistance
        }
    }

    let images = try records.map { record -> ReportImage in
        let neighbors = records.compactMap { other -> (id: String, distance: Double)? in
            guard other.manifest.id != record.manifest.id,
                  let distance = distances[pairKey(record.manifest.id, other.manifest.id)] else {
                return nil
            }
            return (other.manifest.id, distance)
        }.sorted { left, right in
            left.distance == right.distance ? left.id < right.id : left.distance < right.distance
        }
        guard let nearest = neighbors.first, neighbors.count > 1 else { throw ExtractorError.invalidManifest }
        return ReportImage(
            id: record.manifest.id,
            label: record.manifest.label,
            highRisk: record.manifest.highRisk ?? false,
            nearestNeighborID: nearest.id,
            nearestNeighborDistance: rounded(nearest.distance),
            nearestNeighborMargin: rounded(neighbors[1].distance - nearest.distance),
            featurePrintMilliseconds: rounded(record.featurePrintMilliseconds)
        )
    }

    return DistanceReport(
        version: 1,
        mode: smoke ? "smoke" : "production",
        evaluatedImageCount: records.count,
        images: images,
        pairs: pairs,
        totalMilliseconds: rounded(Date().timeIntervalSince(startedAt) * 1_000)
    )
}

private func main() throws {
    let options = try parseArguments()
    let startedAt = Date()
    let images = try loadManifest(at: options.manifestURL, smoke: options.smoke)
    let report = try buildReport(records: makeFeatureRecords(for: images), smoke: options.smoke, startedAt: startedAt)
    let data = try JSONEncoder().encode(report)
    try data.write(to: options.reportURL, options: .atomic)
    FileHandle.standardOutput.write(Data("feature distance report created for \(report.evaluatedImageCount) images\n".utf8))
}

do {
    try main()
} catch {
    FileHandle.standardError.write(Data("\(error.localizedDescription)\n".utf8))
    exit(EXIT_FAILURE)
}
