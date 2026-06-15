import CoreGraphics
import QRCode
import SwiftUI

#if JAILBREAK
    // The QRCode library's default engine (QRCode.DefaultEngine on non-watchOS) is
    // QRCodeGenerator_CoreImage, which holds a `CIContext()`. Constructing any QRCode /
    // QRCode.Document / QRCodeViewUI eagerly builds that engine as a stored-property default,
    // and creating the CIContext spins up an EAGL/OpenGL context that crashes in this app
    // process (SIGSEGV in CI::GLContext) — the `generator:` override happens too late to help.
    // So we never touch the QRCode object types: we take the boolean module matrix straight
    // from the pure-Swift engine and rasterize it ourselves with CoreGraphics.

    public func makeExternalQRCodeImage(
        content: String,
        dimension: Int,
        foregroundColor: CGColor,
        backgroundColor: CGColor,
        quietZone: Int = 4
    ) -> CGImage? {
        guard let matrix = QRCodeGenerator_External().generate(text: content, errorCorrection: .low) else {
            return nil
        }
        let moduleCount = matrix.dimension
        guard moduleCount > 0 else { return nil }
        let totalModules = moduleCount + quietZone * 2
        let scale = max(1, dimension / totalModules)
        let pixelDimension = totalModules * scale

        let colorSpace = CGColorSpaceCreateDeviceRGB()
        guard let context = CGContext(
            data: nil,
            width: pixelDimension,
            height: pixelDimension,
            bitsPerComponent: 8,
            bytesPerRow: 0,
            space: colorSpace,
            bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue
        ) else {
            return nil
        }

        context.setFillColor(backgroundColor)
        context.fill(CGRect(x: 0, y: 0, width: pixelDimension, height: pixelDimension))
        context.setFillColor(foregroundColor)
        // QRCodeGenerator_External's matrix has row 0 at the top, not the bottom.
        for row in 0 ..< moduleCount {
            for column in 0 ..< moduleCount {
                guard matrix[row, column] else { continue }
                let x = (column + quietZone) * scale
                let y = (totalModules - 1 - (row + quietZone)) * scale
                context.fill(CGRect(x: x, y: y, width: scale, height: scale))
            }
        }
        return context.makeImage()
    }
#endif

@MainActor
public struct ExternalQRCodeView: View {
    private let content: String
    private let foregroundColor: CGColor
    private let backgroundColor: CGColor
    private let quietZone: Int

    public init(
        content: String,
        foregroundColor: CGColor,
        backgroundColor: CGColor,
        quietZone: Int = 4
    ) {
        self.content = content
        self.foregroundColor = foregroundColor
        self.backgroundColor = backgroundColor
        self.quietZone = quietZone
    }

    public var body: some View {
        #if JAILBREAK
            if let image = makeExternalQRCodeImage(
                content: content,
                dimension: 1024,
                foregroundColor: foregroundColor,
                backgroundColor: backgroundColor,
                quietZone: quietZone
            ) {
                Image(decorative: image, scale: 1)
                    .resizable()
                    .interpolation(.none)
                    .aspectRatio(1, contentMode: .fit)
            } else {
                Color.clear
            }
        #else
            QRCodeViewUI(
                content: content,
                errorCorrection: .low,
                foregroundColor: foregroundColor,
                backgroundColor: backgroundColor,
                additionalQuietZonePixels: UInt(quietZone)
            )
        #endif
    }
}
