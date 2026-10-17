import Foundation
import ImageIO
import Vision

// One image per process. No application initialization, clipboard access, or network.
func recognize() throws -> String {
    guard CommandLine.arguments.count == 1 else { throw CocoaError(.fileReadInvalidFileName) }
    var input = Data()
    while let bytes = try FileHandle.standardInput.read(upToCount: 65536), !bytes.isEmpty {
        guard input.count + bytes.count <= 20 * 1_048_576 else { throw CocoaError(.fileReadTooLarge) }
        input.append(bytes)
    }
    guard let source = CGImageSourceCreateWithData(input as CFData, [kCGImageSourceShouldCache: false] as CFDictionary),
          let properties = CGImageSourceCopyPropertiesAtIndex(source, 0, nil) as? [CFString: Any],
          let width = properties[kCGImagePropertyPixelWidth] as? Int,
          let height = properties[kCGImagePropertyPixelHeight] as? Int,
          width > 0, height > 0, height <= 40_000_000, width <= 40_000_000 / height else {
        throw CocoaError(.fileReadCorruptFile)
    }
    let options: [CFString: Any] = [kCGImageSourceCreateThumbnailFromImageAlways: true,
        kCGImageSourceCreateThumbnailWithTransform: true, kCGImageSourceThumbnailMaxPixelSize: 4096]
    guard let image = CGImageSourceCreateThumbnailAtIndex(source, 0, options as CFDictionary) else {
        throw CocoaError(.fileReadCorruptFile)
    }
    let request = VNRecognizeTextRequest()
    request.recognitionLevel = .accurate
    let supported = try request.supportedRecognitionLanguages()
    request.recognitionLanguages = ["zh-Hans", "zh-Hant", "en-US"].filter { supported.contains($0) }
    guard !request.recognitionLanguages.isEmpty else { throw CocoaError(.featureUnsupported) }
    request.usesLanguageCorrection = true
    try VNImageRequestHandler(cgImage: image).perform([request])
    let text = (request.results ?? []).compactMap { $0.topCandidates(1).first?.string }.joined(separator: "\n")
    guard text.utf8.count <= 32_768 else { throw CocoaError(.fileReadTooLarge) }
    return text
}

do {
    let text = try autoreleasepool { try recognize() }
    FileHandle.standardOutput.write(Data(text.utf8))
} catch {
    // Do not print paths, images, or recognized text on failure.
    exit(1)
}
