#if !os(tvOS)

    import AVFoundation
    import Library
    import SwiftUI

    @MainActor
    public struct QRSScannerView: View {
        @Environment(\.dismiss) private var dismiss
        @State private var alert: AlertState?
        @StateObject private var controller = QRSScannerController()

        private let onComplete: (Data) -> Void

        public init(onComplete: @escaping (Data) -> Void) {
            self.onComplete = onComplete
        }

        public var body: some View {
            #if os(iOS)
                iOSBody
            #elseif os(macOS)
                macOSBody
            #endif
        }

        #if os(iOS)
            private var iOSBody: some View {
                NavigationStackCompat {
                    ZStack {
                        QRSScannerControllerView(controller: controller)
                            .ignoresSafeArea()

                        VStack {
                            Spacer()
                            progressOverlay
                                .padding()
                        }
                    }
                    .navigationTitle("Scan QRS")
                    .navigationBarTitleDisplayMode(.inline)
                    .toolbar {
                        ToolbarItem(placement: .cancellationAction) {
                            Button("Cancel") { dismiss() }
                        }
                        ToolbarItem(placement: .primaryAction) {
                            Menu {
                                Button {
                                    controller.reset()
                                    controller.startScanning()
                                } label: {
                                    Label("Reset", systemImage: "arrow.counterclockwise")
                                }

                                if controller.availableCameras.count > 1 {
                                    Menu("Camera") {
                                        ForEach(controller.availableCameras, id: \.uniqueID) { camera in
                                            Button {
                                                controller.selectCamera(camera)
                                            } label: {
                                                if camera.uniqueID == controller.selectedCamera?.uniqueID {
                                                    Label(camera.localizedName, systemImage: "checkmark")
                                                } else {
                                                    Text(camera.localizedName)
                                                }
                                            }
                                        }
                                    }
                                }
                            } label: {
                                Image(systemName: "ellipsis.circle")
                            }
                        }
                    }
                }
                .alert($alert)
                .onAppear {
                    controller.onComplete = { data in
                        dismiss()
                        onComplete(data)
                    }
                }
            }
        #endif

        #if os(macOS)
            private var macOSBody: some View {
                VStack(spacing: 0) {
                    ZStack {
                        QRSScannerControllerView(controller: controller)
                            .frame(minWidth: 400, minHeight: 300)

                        VStack {
                            Spacer()
                            progressOverlay
                                .padding()
                        }
                    }

                    Divider()

                    HStack {
                        if controller.availableCameras.count > 1 {
                            Picker("Camera", selection: Binding(
                                get: { controller.selectedCamera },
                                set: { camera in
                                    if let camera {
                                        controller.selectCamera(camera)
                                    }
                                }
                            )) {
                                ForEach(controller.availableCameras, id: \.uniqueID) { camera in
                                    Text(camera.localizedName).tag(camera as AVCaptureDevice?)
                                }
                            }
                            .frame(maxWidth: 200)
                        }

                        Button("Reset") {
                            controller.reset()
                            controller.startScanning()
                        }

                        Spacer()

                        Button("Cancel") { dismiss() }
                            .keyboardShortcut(.cancelAction)
                    }
                    .padding()
                }
                .alert($alert)
                .onAppear {
                    controller.onComplete = { data in
                        dismiss()
                        onComplete(data)
                    }
                }
            }
        #endif

        private var progressOverlay: some View {
            VStack(spacing: 8) {
                ProgressView(value: controller.progress)
                    .progressViewStyle(.linear)
                    .frame(maxWidth: 200)

                Text("Decoded: \(Int(controller.progress * 100))%")
                    .font(.headline)

                if controller.decoder.k > 0 {
                    Text("\(controller.decoder.decodedCount)/\(controller.decoder.k) blocks")
                        .font(.caption)
                }

                Text("Frames scanned: \(controller.framesScanned)")
                    .font(.caption)

                if let error = controller.lastError {
                    Text(error)
                        .font(.caption)
                        .foregroundStyle(.red)
                }
            }
            .padding()
            .background(.ultraThinMaterial, in: RoundedRectangle(cornerRadius: 12))
        }
    }

#endif
