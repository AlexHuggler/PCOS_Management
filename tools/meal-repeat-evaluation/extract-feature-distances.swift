import Darwin
import Foundation
import Vision

private let productionImageCount = 100
private let smokeImageCount = 5
private let toolkitDirectoryURL = URL(fileURLWithPath: #filePath)
    .deletingLastPathComponent()
    .standardizedFileURL
private let outputDirectoryURL = toolkitDirectoryURL
    .appendingPathComponent("output", isDirectory: true)
    .standardizedFileURL

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
    case invalidReleaseTopology
    case missingImageFile(Int)
    case failedFeaturePrint(Int)
    case unsafeReportDestination

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
        case .invalidReleaseTopology:
            return "invalid manifest: production runs require exactly 20 labels with four images each and 20 single-image negative labels"
        case let .missingImageFile(index):
            return "manifest image at index \(index) does not reference a readable local file"
        case let .failedFeaturePrint(index):
            return "Vision could not create a feature print for manifest image at index \(index)"
        case .unsafeReportDestination:
            return "report must be written inside \(outputDirectoryURL.path)"
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

private func validateReleaseDatasetTopology(_ images: [ManifestImage]) throws {
    var labelCounts = [String: Int]()
    for image in images {
        labelCounts[image.label, default: 0] += 1
    }
    let fourImageLabels = labelCounts.values.filter { $0 == 4 }.count
    let singleImageLabels = labelCounts.values.filter { $0 == 1 }.count
    guard labelCounts.count == 40, fourImageLabels == 20, singleImageLabels == 20 else {
        throw ExtractorError.invalidReleaseTopology
    }
}

private func resolveReportDestination(_ requestedURL: URL) throws -> URL {
    let fileManager = FileManager.default
    try fileManager.createDirectory(at: outputDirectoryURL, withIntermediateDirectories: true)
    guard outputDirectoryURL.resolvingSymlinksInPath() == outputDirectoryURL else {
        throw ExtractorError.unsafeReportDestination
    }
    try fileManager.setAttributes(
        [.posixPermissions: 0o700],
        ofItemAtPath: outputDirectoryURL.path
    )

    let destinationURL = requestedURL.standardizedFileURL
    guard destinationURL.deletingLastPathComponent() == outputDirectoryURL else {
        throw ExtractorError.unsafeReportDestination
    }
    if let fileType = try? fileManager.attributesOfItem(atPath: destinationURL.path)[.type] as? FileAttributeType,
       fileType == .typeSymbolicLink {
        throw ExtractorError.unsafeReportDestination
    }
    return destinationURL
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
    if !smoke {
        try validateReleaseDatasetTopology(manifest.images)
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

private func buildReport(records: [FeatureRecord], startedAt: Date) throws -> DistanceReport {
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
            nearestNeighborID: nearest.id,
            nearestNeighborDistance: rounded(nearest.distance),
            nearestNeighborMargin: rounded(neighbors[1].distance - nearest.distance),
            featurePrintMilliseconds: rounded(record.featurePrintMilliseconds)
        )
    }

    return DistanceReport(
        version: 1,
        evaluatedImageCount: records.count,
        images: images,
        pairs: pairs,
        totalMilliseconds: rounded(Date().timeIntervalSince(startedAt) * 1_000)
    )
}

private func main() throws {
    let options = try parseArguments()
    let reportURL = try resolveReportDestination(options.reportURL)
    let startedAt = Date()
    let images = try loadManifest(at: options.manifestURL, smoke: options.smoke)
    let report = try buildReport(records: makeFeatureRecords(for: images), startedAt: startedAt)
    let data = try JSONEncoder().encode(report)
    try data.write(to: reportURL, options: .atomic)
    FileHandle.standardOutput.write(Data("feature distance report created for \(report.evaluatedImageCount) images\n".utf8))
}

do {
    try main()
} catch {
    FileHandle.standardError.write(Data("\(error.localizedDescription)\n".utf8))
    exit(EXIT_FAILURE)
}
