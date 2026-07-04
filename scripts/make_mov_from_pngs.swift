import AppKit
import AVFoundation
import Foundation

struct Arguments {
    var inputDirectory: URL
    var outputURL: URL
    var fps: Int
}

func value(after flag: String, in arguments: [String]) -> String? {
    guard let index = arguments.firstIndex(of: flag), arguments.indices.contains(index + 1) else {
        return nil
    }
    return arguments[index + 1]
}

let arguments = CommandLine.arguments
guard
    let inputPath = value(after: "--input-dir", in: arguments),
    let outputPath = value(after: "--output", in: arguments)
else {
    fputs("Usage: swift make_mov_from_pngs.swift --input-dir <frames> --output <movie.mov> [--fps 12]\n", stderr)
    exit(2)
}

let parsed = Arguments(
    inputDirectory: URL(fileURLWithPath: inputPath),
    outputURL: URL(fileURLWithPath: outputPath),
    fps: Int(value(after: "--fps", in: arguments) ?? "12") ?? 12
)

let frameURLs = (try FileManager.default.contentsOfDirectory(
    at: parsed.inputDirectory,
    includingPropertiesForKeys: [.isRegularFileKey],
    options: [.skipsHiddenFiles]
) as [URL])
    .filter { $0.pathExtension.lowercased() == "png" }
    .sorted { $0.lastPathComponent.localizedStandardCompare($1.lastPathComponent) == .orderedAscending }

guard let firstFrameURL = frameURLs.first,
      let firstImage = NSImage(contentsOf: firstFrameURL),
      let firstCGImage = firstImage.cgImage(forProposedRect: nil, context: nil, hints: nil)
else {
    fputs("No readable PNG frames found in \(parsed.inputDirectory.path)\n", stderr)
    exit(1)
}

let width = firstCGImage.width
let height = firstCGImage.height
try? FileManager.default.removeItem(at: parsed.outputURL)

let writer = try AVAssetWriter(outputURL: parsed.outputURL, fileType: .mov)
let input = AVAssetWriterInput(
    mediaType: .video,
    outputSettings: [
        AVVideoCodecKey: AVVideoCodecType.h264,
        AVVideoWidthKey: width,
        AVVideoHeightKey: height
    ]
)
input.expectsMediaDataInRealTime = false

let adaptor = AVAssetWriterInputPixelBufferAdaptor(
    assetWriterInput: input,
    sourcePixelBufferAttributes: [
        kCVPixelBufferPixelFormatTypeKey as String: Int(kCVPixelFormatType_32ARGB),
        kCVPixelBufferWidthKey as String: width,
        kCVPixelBufferHeightKey as String: height
    ]
)

guard writer.canAdd(input) else {
    fputs("Cannot add video input to AVAssetWriter.\n", stderr)
    exit(1)
}
writer.add(input)
writer.startWriting()
writer.startSession(atSourceTime: .zero)

func makePixelBuffer(from cgImage: CGImage, width: Int, height: Int) -> CVPixelBuffer? {
    var pixelBuffer: CVPixelBuffer?
    let status = CVPixelBufferCreate(
        kCFAllocatorDefault,
        width,
        height,
        kCVPixelFormatType_32ARGB,
        [
            kCVPixelBufferCGImageCompatibilityKey: true,
            kCVPixelBufferCGBitmapContextCompatibilityKey: true
        ] as CFDictionary,
        &pixelBuffer
    )
    guard status == kCVReturnSuccess, let pixelBuffer else { return nil }

    CVPixelBufferLockBaseAddress(pixelBuffer, [])
    defer { CVPixelBufferUnlockBaseAddress(pixelBuffer, []) }

    guard let baseAddress = CVPixelBufferGetBaseAddress(pixelBuffer) else { return nil }
    let colorSpace = CGColorSpaceCreateDeviceRGB()
    let context = CGContext(
        data: baseAddress,
        width: width,
        height: height,
        bitsPerComponent: 8,
        bytesPerRow: CVPixelBufferGetBytesPerRow(pixelBuffer),
        space: colorSpace,
        bitmapInfo: CGImageAlphaInfo.noneSkipFirst.rawValue
    )
    context?.draw(cgImage, in: CGRect(x: 0, y: 0, width: width, height: height))
    return pixelBuffer
}

let frameDuration = CMTime(value: 1, timescale: CMTimeScale(max(1, parsed.fps)))
for (index, frameURL) in frameURLs.enumerated() {
    while !input.isReadyForMoreMediaData {
        Thread.sleep(forTimeInterval: 0.005)
    }
    guard let image = NSImage(contentsOf: frameURL),
          let cgImage = image.cgImage(forProposedRect: nil, context: nil, hints: nil),
          let pixelBuffer = makePixelBuffer(from: cgImage, width: width, height: height)
    else {
        fputs("Failed to read frame \(frameURL.path)\n", stderr)
        exit(1)
    }
    let time = CMTimeMultiply(frameDuration, multiplier: Int32(index))
    adaptor.append(pixelBuffer, withPresentationTime: time)
}

input.markAsFinished()
writer.finishWriting {
    switch writer.status {
    case .completed:
        print("movie=\(parsed.outputURL.path)")
        print("frames=\(frameURLs.count)")
        print("size=\(width)x\(height)")
        exit(0)
    default:
        fputs("Movie writing failed: \(writer.error?.localizedDescription ?? "unknown error")\n", stderr)
        exit(1)
    }
}

RunLoop.current.run()
