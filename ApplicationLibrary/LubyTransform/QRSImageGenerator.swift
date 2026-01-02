import CoreGraphics
import Foundation
import QRCode

#if canImport(UIKit)
    import UIKit
#elseif canImport(AppKit)
    import AppKit
#endif

@MainActor
final class QRSImageGenerator: ObservableObject {
    @Published private(set) var currentImage: CGImage?

    private let bufferSize: Int
    private let foregroundColor: CGColor
    private let backgroundColor: CGColor
    private let imageDimension: Int

    private var frames: [EncodedBlock] = []
    private var imageBuffer: [CGImage?]
    private var generatedUpTo: Int = -1
    private var currentFrameIndex: Int = 0
    private var expectedTotalFrames: Int = 0

    init(
        foregroundColor: CGColor,
        backgroundColor: CGColor = CGColor(gray: 1.0, alpha: 1.0),
        bufferSize: Int = 30,
        imageDimension: Int = 512
    ) {
        self.foregroundColor = foregroundColor
        self.backgroundColor = backgroundColor
        self.bufferSize = bufferSize
        self.imageDimension = imageDimension
        imageBuffer = Array(repeating: nil, count: bufferSize)
    }

    func setExpectedFrames(_ count: Int) {
        expectedTotalFrames = count
    }

    func addFrame(_ block: EncodedBlock) async {
        let image = await generateImage(for: block)

        let index = frames.count
        frames.append(block)

        let bufferIndex = index % bufferSize
        imageBuffer[bufferIndex] = image
        generatedUpTo = index

        if index == 0 {
            currentImage = image
        }
    }

    func advanceFrame() {
        guard generatedUpTo >= 0 else { return }

        let totalFrames = expectedTotalFrames > 0 ? expectedTotalFrames : frames.count
        guard totalFrames > 0 else { return }

        let nextIndex = (currentFrameIndex + 1) % totalFrames
        if nextIndex <= generatedUpTo || generatedUpTo == totalFrames - 1 {
            currentFrameIndex = nextIndex
        }

        let bufferIndex = currentFrameIndex % bufferSize
        currentImage = imageBuffer[bufferIndex]
    }

    func cancel() {}

    private nonisolated func generateImage(for block: EncodedBlock) async -> CGImage? {
        let content = block.toQRSString()
        let foregroundColor = foregroundColor
        let backgroundColor = backgroundColor
        let dimension = imageDimension

        return await Task.detached(priority: .userInitiated) {
            do {
                let document = try QRCode.Document(
                    utf8String: content,
                    errorCorrection: .low
                )
                document.design.foregroundColor(foregroundColor)
                document.design.backgroundColor(backgroundColor)
                document.design.additionalQuietZonePixels = 4
                return try document.cgImage(dimension: dimension)
            } catch {
                return nil
            }
        }.value
    }
}
