import Foundation
import QRCode
import SwiftUI

@MainActor
public struct QRSDisplayView: View {
    private static let recoveryFactor = 1.3

    @Environment(\.dismiss) private var dismiss
    @Environment(\.openURL) private var openURL
    private let data: Data
    private let filename: String?

    @State private var generator: QRSImageGenerator?
    @State private var fps: Double = 10
    @State private var sliceSize: Double = 500
    @State private var generationTask: Task<Void, Never>?
    #if os(tvOS)
        @State private var showQRSInfoQRCode = false
    #endif

    public init(data: Data, filename: String? = nil) {
        self.data = data
        self.filename = filename
    }

    public var body: some View {
        VStack(spacing: 16) {
            TimelineView(.periodic(from: .now, by: 1.0 / fps)) { context in
                Group {
                    if let image = generator?.currentImage {
                        Image(decorative: image, scale: 1.0)
                            .resizable()
                            .interpolation(.none)
                            .aspectRatio(1, contentMode: .fit)
                    } else {
                        ProgressView()
                            .frame(width: 280, height: 280)
                    }
                }
                .onChange(of: context.date) { _ in
                    generator?.advanceFrame()
                }
            }

            VStack(spacing: 8) {
                HStack {
                    Text(String(localized: "FPS"))
                    Spacer()
                    #if os(tvOS)
                        Button {
                            fps = max(1, fps - 1)
                        } label: {
                            Image(systemName: "minus")
                        }
                        Text(verbatim: "\(Int(fps))")
                            .foregroundStyle(.secondary)
                            .frame(minWidth: 50)
                        Button {
                            fps = min(60, fps + 1)
                        } label: {
                            Image(systemName: "plus")
                        }
                    #else
                        Text(verbatim: "\(Int(fps))")
                            .foregroundStyle(.secondary)
                    #endif
                }

                #if !os(tvOS)
                    Slider(value: $fps, in: 1 ... 60, step: 1)
                #endif

                HStack {
                    Text(String(localized: "Slice Size"))
                    Spacer()
                    #if os(tvOS)
                        Button {
                            sliceSize = max(100, sliceSize - 100)
                        } label: {
                            Image(systemName: "minus")
                        }
                        Text("\(Int(sliceSize))")
                            .foregroundStyle(.secondary)
                            .frame(minWidth: 50)
                        Button {
                            sliceSize = min(1500, sliceSize + 100)
                        } label: {
                            Image(systemName: "plus")
                        }
                    #else
                        Text("\(Int(sliceSize))")
                            .foregroundStyle(.secondary)
                    #endif
                }

                #if !os(tvOS)
                    Slider(value: $sliceSize, in: 100 ... 1500, step: 100)
                #endif
            }
            .padding(.horizontal)

            HStack(spacing: 12) {
                Button {
                    #if os(tvOS)
                        showQRSInfoQRCode = true
                    #else
                        openURL(URL(string: "https://github.com/qifi-dev/qrs")!)
                    #endif
                } label: {
                    HStack(spacing: 4) {
                        Image(systemName: "info.circle")
                        Text(String(localized: "What is QRS"))
                    }
                    .frame(maxWidth: .infinity)
                }
                .buttonStyle(.bordered)

                Button {
                    dismiss()
                } label: {
                    HStack(spacing: 4) {
                        Image(systemName: "xmark")
                        Text(String(localized: "Close"))
                    }
                    .frame(maxWidth: .infinity)
                }
                .buttonStyle(.borderedProminent)
            }
            .padding(.horizontal)
        }
        #if os(macOS)
        .padding()
        #else
        .padding([.horizontal, .bottom])
        #endif
        .onAppear {
            setupGenerator()
        }
        .onDisappear {
            generator?.cancel()
            generationTask?.cancel()
        }
        .onChange(of: sliceSize) { _ in
            setupGenerator()
        }
        #if os(tvOS)
        .sheet(isPresented: $showQRSInfoQRCode) {
            URLQRCodeSheet(url: "https://github.com/qifi-dev/qrs", title: String(localized: "What is QRS"))
        }
        #endif
    }

    private func setupGenerator() {
        generator?.cancel()
        generationTask?.cancel()

        let newGenerator = QRSImageGenerator(
            foregroundColor: CGColor(gray: 0.0, alpha: 1.0),
            bufferSize: 30
        )
        generator = newGenerator

        generationTask = Task {
            let (encoder, requiredFrames) = await createEncoder()
            if Task.isCancelled { return }

            newGenerator.setExpectedFrames(requiredFrames)

            let fountain = encoder.fountain()
            for _ in 0 ..< requiredFrames {
                if Task.isCancelled { return }
                guard let block = fountain.next() else { continue }
                await newGenerator.addFrame(block)
            }
        }
    }

    private nonisolated func createEncoder() async -> (LubyTransformEncoder, Int) {
        await Task.detached(priority: .userInitiated) { [data, filename, sliceSize] in
            let wrappedData = BinaryMeta.appendFileHeaderMeta(
                data: data,
                filename: filename,
                contentType: "application/octet-stream"
            )
            let sliceSizeInt = Int(sliceSize)
            let encoder = LubyTransformEncoder(data: wrappedData, sliceSize: sliceSizeInt, compress: true)
            let requiredFrames = Self.calculateRequiredFrames(dataSize: wrappedData.count, sliceSize: sliceSizeInt)
            return (encoder, requiredFrames)
        }.value
    }

    private nonisolated static func calculateRequiredFrames(dataSize: Int, sliceSize: Int) -> Int {
        let k = (dataSize + sliceSize - 1) / sliceSize
        if k == 0 { return 1 }
        return max(Int(Double(k) * recoveryFactor), k + 5)
    }
}

@MainActor
public struct QRSSheet: View {
    private let profileName: String
    private let profileData: Data

    public init(profileName: String, profileData: Data) {
        self.profileName = profileName
        self.profileData = profileData
    }

    public var body: some View {
        #if os(macOS)
            QRSDisplayView(data: profileData, filename: "\(profileName).bpf")
                .frame(minWidth: 400, minHeight: 520)
        #elseif os(iOS) || os(tvOS)
            QRSDisplayView(data: profileData, filename: "\(profileName).bpf")
                .modifier(LargeSheetModifier())
        #endif
    }
}

#if os(iOS) || os(tvOS)
    private struct LargeSheetModifier: ViewModifier {
        func body(content: Content) -> some View {
            if #available(iOS 16.0, tvOS 17.0, *) {
                content
                    .presentationDetents([.large])
                    .presentationDragIndicator(.visible)
            } else {
                content
            }
        }
    }
#endif
