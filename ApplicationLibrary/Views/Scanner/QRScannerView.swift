#if !os(tvOS)

    import AVFoundation
    import Library
    import SwiftUI

    #if os(macOS)
        import AppKit
    #endif

    @MainActor
    public struct QRScannerView: View {
        @Environment(\.dismiss) private var dismiss
        @State private var alert: AlertState?
        @StateObject private var controller = QRScannerController()

        private let onScan: (QRScanResult) -> Void

        public init(onScan: @escaping (QRScanResult) -> Void) {
            self.onScan = onScan
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
                        QRScannerControllerView(controller: controller)
                            .ignoresSafeArea()

                        if controller.qrsMode {
                            qrsProgressOverlay
                        }
                    }
                    .navigationTitle("Scan QR Code")
                    .navigationBarTitleDisplayMode(.inline)
                    .toolbar {
                        ToolbarItem(placement: .cancellationAction) {
                            Button("Cancel") { dismiss() }
                        }
                        ToolbarItem(placement: .primaryAction) {
                            Menu {
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
                    controller.onScan = handleScanResult
                }
            }
        #endif

        #if os(macOS)
            private var macOSBody: some View {
                VStack(spacing: 0) {
                    ZStack {
                        QRScannerControllerView(controller: controller)

                        if controller.qrsMode {
                            qrsProgressOverlay
                        }
                    }
                    .frame(minWidth: 400, minHeight: 300)

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
                            .frame(maxWidth: 250)
                        }
                        Spacer()
                        Button("Cancel") { dismiss() }
                            .keyboardShortcut(.cancelAction)
                    }
                    .padding()
                }
                .alert($alert)
                .onAppear {
                    controller.onScan = handleScanResult
                }
            }
        #endif

        private var qrsProgressOverlay: some View {
            ZStack {
                Color.black.opacity(0.5)
                    .ignoresSafeArea()

                let k = controller.decoder?.k ?? 0
                let framesScanned = controller.framesScanned
                let scanProgress = k > 0 ? min(1.0, Double(framesScanned) / Double(k) / 1.2) : 0

                CircularProgressView(
                    progress: scanProgress,
                    total: k
                )
            }
        }

        private func handleScanResult(_ result: Result<QRScanResult, QRScanError>) {
            switch result {
            case let .success(scanResult):
                dismiss()
                Task { @MainActor in
                    onScan(scanResult)
                }
            case let .failure(error):
                switch error {
                case .permissionDenied:
                    #if os(macOS)
                        alert = AlertState(
                            title: String(localized: "Camera Access Denied"),
                            message: String(localized: "Please enable camera access in Settings to scan QR codes."),
                            primaryButton: .default(String(localized: "Open Settings")) {
                                openCameraPrivacySettings()
                            },
                            secondaryButton: .cancel()
                        )
                    #else
                        alert = AlertState(
                            title: String(localized: "Camera Access Denied"),
                            message: String(localized: "Please enable camera access in Settings to scan QR codes.")
                        )
                    #endif
                default:
                    alert = AlertState(action: "scan QR code", error: error)
                }
            }
        }

        #if os(macOS)
            private func openCameraPrivacySettings() {
                if let url = URL(string: "x-apple.systempreferences:com.apple.preference.security?Privacy_Camera") {
                    NSWorkspace.shared.open(url)
                }
            }
        #endif
    }

    private struct CircularProgressView: View {
        let progress: Double
        let total: Int

        private let size: CGFloat = 96
        private let lineWidth: CGFloat = 8

        var body: some View {
            ZStack {
                Circle()
                    .stroke(Color.white.opacity(0.3), lineWidth: lineWidth)
                    .frame(width: size, height: size)

                Circle()
                    .trim(from: 0, to: progress)
                    .stroke(Color.white, style: StrokeStyle(lineWidth: lineWidth, lineCap: .round))
                    .frame(width: size, height: size)
                    .rotationEffect(.degrees(-90))
                    .animation(.easeInOut(duration: 0.2), value: progress)

                if total > 0 {
                    Text("\(min(99, Int(progress * 100)))%")
                        .font(.system(size: 20, weight: .semibold))
                        .foregroundStyle(.white)
                }

                Text("QRS")
                    .font(.system(size: 32, weight: .bold))
                    .foregroundStyle(.white)
                    .offset(y: -size / 2 - 40)
            }
        }
    }

#endif
