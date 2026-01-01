import Foundation
import QRCode
import SwiftUI

private extension CGColor {
    static var labelColor: CGColor {
        #if canImport(UIKit)
            UIColor.label.cgColor
        #elseif canImport(AppKit)
            NSColor.labelColor.cgColor
        #endif
    }
}

@MainActor
public struct QRSDisplayView: View {
    private let data: Data

    @State private var encoder: LubyTransformEncoder?
    @State private var currentBlock: EncodedBlock?
    @State private var frameCount = 0
    @State private var isPlaying = true
    @State private var fps: Double = 10
    @State private var sliceSize: Int = 500
    @State private var timer: Timer?

    public init(data: Data) {
        self.data = data
    }

    public var body: some View {
        VStack(spacing: 16) {
            if let block = currentBlock {
                QRCodeViewUI(
                    content: block.toBase64(),
                    errorCorrection: .low,
                    foregroundColor: .labelColor,
                    backgroundColor: CGColor(gray: 1.0, alpha: 0.0)
                )
                .aspectRatio(1, contentMode: .fit)
                #if os(macOS)
                    .frame(minWidth: 280, minHeight: 280)
                #else
                    .frame(maxWidth: 300, maxHeight: 300)
                #endif
            } else {
                ProgressView()
                    .frame(width: 280, height: 280)
            }

            VStack(spacing: 4) {
                Text("Frame: \(frameCount)")
                    .font(.caption)
                if let encoder {
                    Text("Source blocks: \(encoder.k)")
                        .font(.caption)
                    Text("Data size: \(encoder.bytes) bytes")
                        .font(.caption)
                }
            }
            .foregroundStyle(.secondary)

            VStack(spacing: 12) {
                HStack {
                    Button {
                        isPlaying.toggle()
                    } label: {
                        Image(systemName: isPlaying ? "pause.fill" : "play.fill")
                    }
                    #if os(macOS)
                    .buttonStyle(.bordered)
                    #endif

                    Spacer()

                    Text(String(localized: "Ideal FPS"))
                        .font(.caption)

                    Slider(value: $fps, in: 1 ... 30, step: 1)
                        .frame(maxWidth: 120)

                    Text("\(Int(fps))")
                        .font(.caption)
                        .frame(width: 24, alignment: .trailing)
                }

                HStack {
                    Text(String(localized: "Slice Size"))
                        .font(.caption)

                    Picker("", selection: $sliceSize) {
                        Text("200").tag(200)
                        Text("500").tag(500)
                        Text("1000").tag(1000)
                    }
                    .pickerStyle(.segmented)
                    .frame(maxWidth: 200)
                }
            }
            .padding(.horizontal)
        }
        .padding()
        .onAppear {
            setupEncoder()
            startAnimation()
        }
        .onDisappear {
            stopAnimation()
        }
        .onChange(of: fps) { _ in
            if isPlaying {
                restartTimer()
            }
        }
        .onChange(of: isPlaying) { playing in
            if playing {
                startAnimation()
            } else {
                stopAnimation()
            }
        }
        .onChange(of: sliceSize) { _ in
            setupEncoder()
            frameCount = 0
        }
    }

    private func setupEncoder() {
        encoder = LubyTransformEncoder(data: data, sliceSize: sliceSize, compress: true)
    }

    private func startAnimation() {
        nextFrame()
        restartTimer()
    }

    private func restartTimer() {
        timer?.invalidate()
        timer = Timer.scheduledTimer(withTimeInterval: 1.0 / fps, repeats: true) { _ in
            Task { @MainActor in
                nextFrame()
            }
        }
    }

    private func stopAnimation() {
        timer?.invalidate()
        timer = nil
    }

    private func nextFrame() {
        guard let encoder else { return }
        currentBlock = encoder.fountain().next()
        frameCount += 1
    }
}

@MainActor
public struct QRSSheet: View {
    @Environment(\.dismiss) private var dismiss
    private let profileName: String
    private let profileData: Data

    public init(profileName: String, profileData: Data) {
        self.profileName = profileName
        self.profileData = profileData
    }

    public var body: some View {
        #if os(macOS)
            NavigationSheet(title: String(localized: "Share as QRS")) {
                VStack {
                    QRSDisplayView(data: profileData)
                    Text("Ask the receiver to scan continuously until complete.")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .padding(.bottom)
                }
            }
            .frame(minWidth: 400, minHeight: 520)
        #elseif os(iOS) || os(tvOS)
            NavigationSheet(title: String(localized: "Share as QRS"), size: .large) {
                VStack {
                    QRSDisplayView(data: profileData)
                    Text("Ask the receiver to scan continuously until complete.")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .padding(.bottom)
                }
            }
        #endif
    }
}
