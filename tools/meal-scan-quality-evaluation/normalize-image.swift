import CoreGraphics
import Foundation
import ImageIO
import UniformTypeIdentifiers

guard CommandLine.arguments.count == 3 else {
    FileHandle.standardError.write(Data("usage: normalize-image <source> <output>\n".utf8))
    exit(2)
}

let sourceURL = URL(fileURLWithPath: CommandLine.arguments[1])
let outputURL = URL(fileURLWithPath: CommandLine.arguments[2])
guard let source = CGImageSourceCreateWithURL(sourceURL as CFURL, nil) else {
    FileHandle.standardError.write(Data("unable to decode source image\n".utf8))
    exit(1)
}

let thumbnailOptions: [CFString: Any] = [
    kCGImageSourceCreateThumbnailFromImageAlways: true,
    kCGImageSourceCreateThumbnailWithTransform: true,
    kCGImageSourceThumbnailMaxPixelSize: 960,
    kCGImageSourceShouldCacheImmediately: true,
]
guard let image = CGImageSourceCreateThumbnailAtIndex(source, 0, thumbnailOptions as CFDictionary) else {
    FileHandle.standardError.write(Data("unable to render source image\n".utf8))
    exit(1)
}

let colorSpace = CGColorSpaceCreateDeviceRGB()
let bitmapInfo = CGImageAlphaInfo.noneSkipLast.rawValue
guard let context = CGContext(
    data: nil,
    width: max(1, image.width),
    height: max(1, image.height),
    bitsPerComponent: 8,
    bytesPerRow: 0,
    space: colorSpace,
    bitmapInfo: bitmapInfo
) else {
    FileHandle.standardError.write(Data("unable to create image context\n".utf8))
    exit(1)
}

context.setFillColor(CGColor(gray: 1, alpha: 1))
context.fill(CGRect(x: 0, y: 0, width: image.width, height: image.height))
context.interpolationQuality = .high
context.draw(image, in: CGRect(x: 0, y: 0, width: image.width, height: image.height))
guard let renderedImage = context.makeImage() else {
    FileHandle.standardError.write(Data("unable to create normalized image\n".utf8))
    exit(1)
}

let outputData = NSMutableData()
guard let destination = CGImageDestinationCreateWithData(
    outputData,
    UTType.jpeg.identifier as CFString,
    1,
    nil
) else {
    FileHandle.standardError.write(Data("unable to create JPEG destination\n".utf8))
    exit(1)
}
CGImageDestinationAddImage(
    destination,
    renderedImage,
    [kCGImageDestinationLossyCompressionQuality: 0.78] as CFDictionary
)
guard CGImageDestinationFinalize(destination) else {
    FileHandle.standardError.write(Data("unable to encode normalized JPEG\n".utf8))
    exit(1)
}

do {
    try (outputData as Data).write(to: outputURL, options: .atomic)
    try FileManager.default.setAttributes([.posixPermissions: 0o600], ofItemAtPath: outputURL.path)
} catch {
    FileHandle.standardError.write(Data("unable to write normalized JPEG\n".utf8))
    exit(1)
}
